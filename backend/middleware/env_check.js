// middleware/env_check.js
// Validates required environment variables at startup.
// Call this before anything else in the server.

'use strict';

const REQUIRED = [
  'GMAIL_USER',
  'GMAIL_PASS',
];

const RECOMMENDED = [
  'DB_USER',
  'DB_PASS',
  'ALLOWED_ORIGINS',
  'JWT_SECRET',
];

function checkEnv() {
  const missing = REQUIRED.filter(k => !process.env[k]);
  if (missing.length > 0) {
    console.error('[ENV] FATAL: Missing required environment variables:', missing.join(', '));
    console.error('[ENV] Copy backend/.env.example to backend/.env and fill in real values.');
    process.exit(1);
  }

  const defaulting = RECOMMENDED.filter(k => !process.env[k]);
  if (defaulting.length > 0) {
    console.warn('[ENV] WARNING: These recommended env vars are not set (using insecure defaults):', defaulting.join(', '));
  }

  if (!process.env.DB_USER || process.env.DB_USER === 'root') {
    console.warn('[ENV] WARNING: DB_USER is "root". Create a least-privilege DB user. See docs/db_user_setup.md');
  }
  if (!process.env.DB_PASS) {
    console.warn('[ENV] WARNING: DB_PASS is empty. Set a strong password in .env');
  }
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET === 'CHANGE_ME_LONG_RANDOM_SECRET_64_CHARS_MIN') {
    console.warn('[ENV] WARNING: JWT_SECRET is not set or is using the placeholder value. Auth will not be secure.');
  }
}

module.exports = { checkEnv };
