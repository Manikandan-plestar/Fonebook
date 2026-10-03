// middleware/rate_limit.js  — HIGH-04 fix
// Adds rate limiting to prevent OTP bombing, scraping, and DoS.
//
// Global limit is generous (defaults to 120/min) so normal usage is never hit.
// OTP-specific limit is strict (3 per 10 min per IP — configurable via env).
//
// Trust proxy setting: needed on Google Cloud so the limiter sees the real
// client IP (X-Forwarded-For), not the load balancer IP.
// Set app.set('trust proxy', 1) in your main server file.
//
// Env vars:
//   OTP_RATE_LIMIT_MAX   (default: 3 per 10 min per IP)
//   GLOBAL_RATE_LIMIT_MAX (default: 120 per min per IP)

'use strict';

const rateLimit = require('express-rate-limit');

// Global limiter — generous cap, mainly protects against floods
const globalLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: parseInt(process.env.GLOBAL_RATE_LIMIT_MAX, 10) || 120,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
  skip: (req) => {
    // Skip rate limiting for OPTIONS (preflight)
    return req.method === 'OPTIONS';
  },
});

// OTP limiter — strict, per IP
const otpLimiterByIp = rateLimit({
  windowMs: 10 * 60 * 1000, // 10 minutes
  max: parseInt(process.env.OTP_RATE_LIMIT_MAX, 10) || 3,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.ip,
  message: { error: 'Too many OTP requests. Please wait 10 minutes before trying again.' },
});

module.exports = { globalLimiter, otpLimiterByIp };
