// middleware/auth.js — Phase 2, CRIT-01 / CRIT-07 fix
// Auth middleware with MONITOR MODE (ENFORCE_AUTH=false by default).
//
// While ENFORCE_AUTH=false:
//   - Valid tokens set req.user (so new code can use it)
//   - Missing/invalid tokens are ALLOWED but logged as [AUTH-MONITOR]
//   - Ownership violations are LOGGED but not blocked ([AUTHZ-MONITOR])
//
// Once ENFORCE_AUTH=true (flip after new app version has rolled out):
//   - Missing/invalid tokens return 401
//   - Ownership violations return 403
//
// Usage:
//   const { requireAuth, requireOwnership } = require('./middleware/auth');
//   app.post('/someRoute', requireAuth, requireOwnership('contacts', 'owner_email'), handler);

'use strict';

const jwt = require('jsonwebtoken');

const ENFORCE = () => process.env.ENFORCE_AUTH === 'true';
const JWT_SECRET = () => process.env.JWT_SECRET || '';

/**
 * Extracts a Bearer token from the Authorization header.
 */
function extractToken(req) {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7);
  return null;
}

/**
 * requireAuth middleware.
 * In monitor mode: always calls next(), logs unauthenticated calls.
 * In enforce mode: returns 401 if no valid token.
 */
function requireAuth(req, res, next) {
  const token = extractToken(req);
  const appVersion = req.headers['x-app-version'] || 'unknown';

  if (token) {
    try {
      req.user = jwt.verify(token, JWT_SECRET());
    } catch (err) {
      req.user = null;
      if (ENFORCE()) {
        return res.status(401).json({ error: 'Invalid or expired token.' });
      }
      console.warn(`[AUTH-MONITOR] Invalid token on ${req.method} ${req.path} | app-version=${appVersion} | ip=${req.ip}`);
    }
  } else {
    req.user = null;
    if (ENFORCE()) {
      return res.status(401).json({ error: 'Authentication required.' });
    }
    console.warn(`[AUTH-MONITOR] Unauthenticated call to ${req.method} ${req.path} | app-version=${appVersion} | ip=${req.ip}`);
  }
  next();
}

/**
 * requireOwnership(table, emailField)
 * Checks that the authenticated user matches the record's owner.
 * In monitor mode: logs would-be violations. In enforce mode: returns 403.
 *
 * @param {object} db - mysql pool/connection
 * @param {string} table - table name
 * @param {string} idField - field used to look up the record ('id' or 'phone_no')
 * @param {string} ownerField - field in the record that holds the owner email
 */
function makeOwnershipChecker(db) {
  return function requireOwnership(table, idField, ownerField) {
    return function (req, res, next) {
      const idValue = req.body[idField] || req.query[idField];
      const userEmail = req.user ? req.user.email : null;

      if (!idValue) return next(); // No record ID — skip ownership check (new record creation)

      db.query(`SELECT ${ownerField} FROM \`${table}\` WHERE \`${idField}\` = ? LIMIT 1`, [idValue], (err, rows) => {
        if (err || !rows || rows.length === 0) return next(); // Record not found — let the route handle it

        const owner = rows[0][ownerField];
        const matches = userEmail && owner && owner.toLowerCase() === userEmail.toLowerCase();

        if (!matches) {
          if (ENFORCE()) {
            return res.status(403).json({ error: 'Forbidden: you do not own this record.' });
          }
          console.warn(`[AUTHZ-MONITOR] Ownership violation | table=${table} | id=${idValue} | claimedUser=${userEmail} | actualOwner=${owner} | route=${req.path}`);
        }
        next();
      });
    };
  };
}

module.exports = { requireAuth, makeOwnershipChecker, extractToken };
