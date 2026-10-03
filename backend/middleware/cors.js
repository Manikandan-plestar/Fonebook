// middleware/cors.js  — CRIT-05 fix
// Replaces wildcard Access-Control-Allow-Origin with an allowlist.
//
// BACKWARD COMPATIBILITY NOTE:
// Native Android/iOS apps do NOT send an Origin header.
// Requests with no Origin pass through unchanged (same as before).
// Only browser-based cross-origin requests are now restricted.
//
// Set ALLOWED_ORIGINS in .env as a comma-separated list, e.g.:
//   ALLOWED_ORIGINS=https://apps.plestarinc.com,https://fonebook.app
//
// In development (NODE_ENV != production) localhost origins are also allowed.

'use strict';

function buildAllowedSet() {
  const raw = (process.env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (process.env.NODE_ENV !== 'production') {
    raw.push('http://localhost:8000', 'http://localhost:3000', 'http://10.0.2.2:8000');
  }
  return new Set(raw);
}

function corsMiddleware(req, res, next) {
  const allowedOrigins = buildAllowedSet();
  const origin = req.headers.origin;

  if (!origin) {
    // Native app (no Origin header) — pass through, same as old behavior
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-App-Version, X-User-Id');
    if (req.method === 'OPTIONS') return res.sendStatus(200);
    return next();
  }

  if (allowedOrigins.has(origin)) {
    res.header('Access-Control-Allow-Origin', origin);
    res.header('Vary', 'Origin');
  }
  // If origin is not in the allowlist, we set no ACAO header.
  // The browser will block the response. Older app clients are unaffected.

  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-App-Version, X-User-Id');

  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
}

module.exports = { corsMiddleware };
