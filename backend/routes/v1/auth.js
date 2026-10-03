// routes/v1/auth.js — Phase 2, CRIT-03 fix
// NEW server-side OTP endpoints.
// Old /send-verification-code and /updateverify are UNCHANGED for backward compatibility.
//
// POST /v1/auth/send-otp   — generate OTP server-side, store hash, send email
// POST /v1/auth/verify-otp — validate OTP, return JWT access + refresh tokens
// POST /v1/auth/refresh    — refresh an access token

'use strict';

const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { escapeHtml } = require('../../lib/sanitize');

// ─── In-process OTP store (production: replace with Redis) ──────────────────
// Stores: { hash, expiresAt, attempts }
const _otpStore = new Map();
const _tokenBlocklist = new Set(); // For refresh token revocation

const OTP_TTL_MS = 10 * 60 * 1000; // 10 minutes
const MAX_ATTEMPTS = 5;

function generateOtp() {
  // crypto.randomInt is CSPRNG — safe for OTPs
  return crypto.randomInt(100000, 999999).toString();
}

function hashOtp(otp) {
  return crypto.createHash('sha256').update(otp).digest('hex');
}

// ─── POST /v1/auth/send-otp ─────────────────────────────────────────────────
router.post('/send-otp', async (req, res) => {
  const email = (req.body.email || '').trim().toLowerCase();
  const foneId = (req.body.fone_identification || 'fonebook').toString().toLowerCase();

  if (!email || !email.includes('@') || !email.includes('.')) {
    return res.status(400).json({ status: 'error', message: 'Valid email required.' });
  }
  if (email.length > 320) {
    return res.status(400).json({ status: 'error', message: 'Email too long.' });
  }

  // Generate and store OTP (hash only — never log or return plaintext)
  const otp = generateOtp();
  const hash = hashOtp(otp);
  _otpStore.set(email, {
    hash,
    expiresAt: Date.now() + OTP_TTL_MS,
    attempts: 0,
  });

  // Branding
  const appName = foneId === 'fonebook' ? 'Fone Book' : 'Telephone Directory App';
  const bannerUrl = foneId === 'fonebook'
    ? 'https://apps.plestarinc.com/uploads/fonebook_banner.jpg'
    : 'https://apps.plestarinc.com/uploads/tpdirectory.webp';

  // Safe values for HTML interpolation
  const safeOtp = escapeHtml(otp);
  const safeAppName = escapeHtml(appName);
  const safeBannerUrl = escapeHtml(bannerUrl);

  // Get transporter from parent scope (injected at mount time)
  const transporter = req.app.get('emailTransporter');
  if (!transporter) {
    return res.status(503).json({ status: 'error', message: 'Email service unavailable.' });
  }

  const mailOptions = {
    from: `"${safeAppName}" <${process.env.GMAIL_USER}>`,
    to: email,
    subject: `Verification Code - ${safeAppName}`,
    html: `<div>
      <p>Your Verification Code is <b>${safeOtp}</b>. This code expires in 10 minutes.</p>
      <p>If you did not request this, please ignore this email.</p>
      <br>
      <img src="${safeBannerUrl}" alt="${safeAppName}" style="width:400px;height:auto;"/>
    </div>`,
  };

  try {
    await transporter.sendMail(mailOptions);
    return res.status(200).json({ status: 'success', message: 'OTP sent to your email.' });
  } catch (err) {
    console.error('[AUTH] Error sending OTP email (id redacted)');
    return res.status(200).json({ status: 'error', message: 'Error sending OTP. Please try again.' });
  }
});

// ─── POST /v1/auth/verify-otp ───────────────────────────────────────────────
router.post('/verify-otp', (req, res) => {
  const email = (req.body.email || '').trim().toLowerCase();
  const otp = (req.body.otp || '').trim();

  if (!email || !otp) {
    return res.status(400).json({ status: 'error', message: 'Email and OTP required.' });
  }

  const record = _otpStore.get(email);
  if (!record) {
    return res.status(400).json({ status: 'error', message: 'No OTP found for this email. Please request a new one.' });
  }

  if (Date.now() > record.expiresAt) {
    _otpStore.delete(email);
    return res.status(400).json({ status: 'error', message: 'OTP expired. Please request a new one.' });
  }

  if (record.attempts >= MAX_ATTEMPTS) {
    _otpStore.delete(email);
    return res.status(400).json({ status: 'error', message: 'Too many failed attempts. Please request a new OTP.' });
  }

  const providedHash = hashOtp(otp);
  // Constant-time comparison to prevent timing attacks
  const expected = Buffer.from(record.hash, 'hex');
  const provided = Buffer.from(providedHash, 'hex');

  if (expected.length !== provided.length || !crypto.timingSafeEqual(expected, provided)) {
    record.attempts += 1;
    return res.status(400).json({ status: 'error', message: 'Incorrect OTP.' });
  }

  // OTP matched — delete it (single use)
  _otpStore.delete(email);

  // Issue tokens
  const jwtSecret = process.env.JWT_SECRET || '';
  if (!jwtSecret) {
    console.error('[AUTH] JWT_SECRET not set — cannot issue tokens');
    return res.status(500).json({ status: 'error', message: 'Auth service misconfigured.' });
  }

  const accessToken = jwt.sign(
    { email, type: 'access' },
    jwtSecret,
    { expiresIn: process.env.JWT_ACCESS_EXPIRES || '15m' }
  );

  const refreshToken = jwt.sign(
    { email, type: 'refresh' },
    jwtSecret,
    { expiresIn: process.env.JWT_REFRESH_EXPIRES || '30d' }
  );

  return res.status(200).json({
    status: 'success',
    message: 'OTP verified.',
    access_token: accessToken,
    refresh_token: refreshToken,
  });
});

// ─── POST /v1/auth/refresh ──────────────────────────────────────────────────
router.post('/refresh', (req, res) => {
  const token = req.body.refresh_token || (req.headers.authorization || '').replace('Bearer ', '');
  if (!token) return res.status(400).json({ status: 'error', message: 'refresh_token required.' });

  if (_tokenBlocklist.has(token)) {
    return res.status(401).json({ status: 'error', message: 'Token has been revoked.' });
  }

  const jwtSecret = process.env.JWT_SECRET || '';
  try {
    const payload = jwt.verify(token, jwtSecret);
    if (payload.type !== 'refresh') {
      return res.status(401).json({ status: 'error', message: 'Invalid token type.' });
    }

    const newAccessToken = jwt.sign(
      { email: payload.email, type: 'access' },
      jwtSecret,
      { expiresIn: process.env.JWT_ACCESS_EXPIRES || '15m' }
    );

    return res.status(200).json({
      status: 'success',
      access_token: newAccessToken,
    });
  } catch (err) {
    return res.status(401).json({ status: 'error', message: 'Invalid or expired refresh token.' });
  }
});

// ─── POST /v1/auth/logout ───────────────────────────────────────────────────
router.post('/logout', (req, res) => {
  const token = req.body.refresh_token;
  if (token) _tokenBlocklist.add(token);
  return res.status(200).json({ status: 'success', message: 'Logged out.' });
});

module.exports = router;
