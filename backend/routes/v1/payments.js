// routes/v1/payments.js — Phase 2, CRIT-04 / HIGH-01 fix
// Server-side Google Play purchase verification.
// Old /savepremium and /savepriorityamount are UNCHANGED for backward compatibility.
//
// POST /v1/payments/verify  — verify Google Play receipt server-side
// GET  /v1/me/premium       — return authoritative premium status from DB

'use strict';

const express = require('express');
const router = express.Router();
const { requireAuth } = require('../../middleware/auth');

// Product ID → credit amount mapping (server-authoritative, never trust client)
const PRODUCT_CREDIT_MAP = {
  'create_profile_499': { type: 'subscription', amountINR: 499, creditBalance: 0 },
  'promote_1':          { type: 'promotion', amountINR: 100, creditBalance: 100 },
  'promote_2':          { type: 'promotion', amountINR: 250, creditBalance: 250 },
  'promote_3':          { type: 'promotion', amountINR: 500, creditBalance: 500 },
  'promote_4':          { type: 'promotion', amountINR: 1000, creditBalance: 1000 },
};

// ─── POST /v1/payments/verify ───────────────────────────────────────────────
// Body: { product_id, purchase_token, profile_id, platform: 'google_play' | 'app_store' }
router.post('/verify', requireAuth, async (req, res) => {
  const db = req.app.get('db');
  const { product_id, purchase_token, profile_id, platform } = req.body;
  const userEmail = req.user ? req.user.email : null;

  if (!product_id || !purchase_token || !platform) {
    return res.status(400).json({ status: 'error', message: 'product_id, purchase_token, and platform are required.' });
  }

  const productInfo = PRODUCT_CREDIT_MAP[product_id];
  if (!productInfo) {
    console.warn(`[PAYMENT] Unknown product_id attempted: ${product_id} by ${userEmail}`);
    return res.status(400).json({ status: 'error', message: 'Unknown product.' });
  }

  // ── Google Play verification ──────────────────────────────────────────────
  if (platform === 'google_play') {
    const serviceAccountJson = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
    const packageName = process.env.GOOGLE_PLAY_PACKAGE_NAME || 'com.plestar.fonebook';

    if (!serviceAccountJson) {
      // Graceful degradation: service account not configured — log and grant (monitor mode)
      console.warn('[PAYMENT] GOOGLE_PLAY_SERVICE_ACCOUNT_JSON not set. Skipping server-side verification (monitor mode).');
      // TODO: set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON to enable real verification
    } else {
      try {
        // Dynamic import to avoid hard dependency if not configured
        const { google } = require('googleapis');
        const serviceAccount = JSON.parse(serviceAccountJson);
        const auth = new google.auth.GoogleAuth({
          credentials: serviceAccount,
          scopes: ['https://www.googleapis.com/auth/androidpublisher'],
        });
        const androidPublisher = google.androidpublisher({ version: 'v3', auth });

        // Determine if this is a one-time purchase or subscription
        let verifyResult;
        try {
          // Try one-time purchase first
          verifyResult = await androidPublisher.purchases.products.get({
            packageName,
            productId: product_id,
            token: purchase_token,
          });
        } catch {
          // Fall back to subscription
          verifyResult = await androidPublisher.purchases.subscriptions.get({
            packageName,
            subscriptionId: product_id,
            token: purchase_token,
          });
        }

        const purchaseState = verifyResult.data.purchaseState; // 0 = purchased
        if (purchaseState !== undefined && purchaseState !== 0) {
          return res.status(400).json({ status: 'error', message: 'Purchase not completed.' });
        }
      } catch (verifyErr) {
        console.error('[PAYMENT] Google Play verification error (details redacted)');
        return res.status(400).json({ status: 'error', message: 'Purchase verification failed.' });
      }
    }

    // ── Check for duplicate purchase token (replay protection) ───────────────
    const tokenHash = require('crypto').createHash('sha256').update(purchase_token).digest('hex');
    if (!db) {
      return res.status(503).json({ status: 'error', message: 'Service unavailable.' });
    }

    db.query('SELECT id FROM verified_purchases WHERE token_hash = ? LIMIT 1', [tokenHash], (err, rows) => {
      if (err) {
        console.error('[PAYMENT] DB error checking token hash');
        return res.status(500).json({ status: 'error', message: 'Server error.' });
      }
      if (rows && rows.length > 0) {
        return res.status(400).json({ status: 'error', message: 'This purchase has already been applied.' });
      }

      // Record the token to prevent replays
      db.query(
        'INSERT INTO verified_purchases (token_hash, product_id, user_email, created_at) VALUES (?, ?, ?, NOW())',
        [tokenHash, product_id, userEmail || 'unknown'],
        (insertErr) => {
          if (insertErr) {
            console.error('[PAYMENT] DB error recording token hash');
            // Don't block the grant — log and continue
          }
        }
      );

      // ── Apply the benefit ─────────────────────────────────────────────────
      if (productInfo.type === 'subscription' && profile_id) {
        db.query(
          "UPDATE contacts SET subscription_status='active', subscription_start=NOW(), subscription_end=DATE_ADD(NOW(), INTERVAL 1 YEAR), payment_status='completed', transaction_id=?, amount=? WHERE id=? AND (owner_email=? OR owner_email IS NULL)",
          [purchase_token.substring(0, 100), productInfo.amountINR, profile_id, userEmail || ''],
          (updateErr) => {
            if (updateErr) {
              console.error('[PAYMENT] DB error applying subscription');
              return res.status(500).json({ status: 'error', message: 'Server error applying subscription.' });
            }
            return res.status(200).json({ status: 'success', message: 'Subscription activated.', type: 'subscription' });
          }
        );
      } else if (productInfo.type === 'promotion' && profile_id) {
        db.query(
          'UPDATE contacts SET priority_balance = priority_balance + ?, priority = 0 WHERE id = ? AND (owner_email = ? OR owner_email IS NULL)',
          [productInfo.creditBalance, profile_id, userEmail || ''],
          (updateErr) => {
            if (updateErr) {
              console.error('[PAYMENT] DB error applying promotion credit');
              return res.status(500).json({ status: 'error', message: 'Server error applying credit.' });
            }
            return res.status(200).json({
              status: 'success',
              message: `Added ${productInfo.creditBalance} credits.`,
              type: 'promotion',
              credits_added: productInfo.creditBalance,
            });
          }
        );
      } else {
        return res.status(200).json({ status: 'success', message: 'Purchase recorded.' });
      }
    });
  } else {
    // Apple App Store — placeholder (implement with apple-receipt-verify if needed)
    console.warn('[PAYMENT] Apple App Store verification not yet implemented — monitor mode.');
    return res.status(200).json({ status: 'success', message: 'Purchase recorded (unverified — App Store).' });
  }
});

// ─── GET /v1/me/premium ─────────────────────────────────────────────────────
router.get('/premium', requireAuth, (req, res) => {
  const db = req.app.get('db');
  const userEmail = req.user ? req.user.email : null;
  if (!userEmail) return res.status(401).json({ error: 'Unauthorized' });

  db.query(
    "SELECT premium, premium_start, premium_end, subscription_status, subscription_end FROM contacts WHERE owner_email = ? AND deleted_contact = 0 ORDER BY premium DESC LIMIT 1",
    [userEmail],
    (err, rows) => {
      if (err) return res.status(500).json({ error: 'Server error' });
      if (!rows || rows.length === 0) return res.status(200).json({ premium: false, subscription_status: 'none' });
      const r = rows[0];
      return res.status(200).json({
        premium: r.premium === 1,
        premium_end: r.premium_end,
        subscription_status: r.subscription_status || 'none',
        subscription_end: r.subscription_end,
      });
    }
  );
});

// ─── GET /v1/app-config ─────────────────────────────────────────────────────
// Force-update support (Phase 3). Values configured via env.
router.get('/app-config', (req, res) => {
  return res.status(200).json({
    min_supported_version: process.env.APP_MIN_SUPPORTED_VERSION || '1.0.0',
    latest_version: process.env.APP_LATEST_VERSION || '1.0.14',
    play_store_url: 'https://play.google.com/store/apps/details?id=com.plestar.fonebook',
  });
});

module.exports = router;
