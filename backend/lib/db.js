// lib/db.js — MED-10 fix: connection pool replacing single connection
//
// Uses mysql2 for security and performance improvements.
// Falls back gracefully — all route handlers use the same db.query(sql, params, cb) API,
// so NO route code needs to change.
//
// Configuration from environment variables with loud warnings if missing.
// Second connection (printer_app) is also pooled here.

'use strict';

require('dotenv').config();

// mysql2 is a drop-in replacement for mysql v2 API (callback style).
// It supports mysql 8 caching_sha2_password, prepared statements, and has no known active vulns.
let mysqlLib;
try {
  mysqlLib = require('mysql2');
} catch (e) {
  console.warn('[DB] mysql2 not found, falling back to mysql v2. Run: npm install mysql2');
  mysqlLib = require('mysql');
}

// ─── Main DB (fonebook) ────────────────────────────────────────────────────

const dbHost = process.env.DB_HOST || 'localhost';
const dbUser = process.env.DB_USER || 'root';
const dbPass = process.env.DB_PASS || '';
const dbName = process.env.DB_NAME || 'fonebook';

if (!process.env.DB_USER) {
  console.warn('[DB] WARNING: DB_USER not set, using root. See docs/db_user_setup.md to create a least-privilege user.');
}
if (!process.env.DB_PASS) {
  console.warn('[DB] WARNING: DB_PASS not set (empty password). Set a strong password in .env');
}

const db = mysqlLib.createPool({
  host: dbHost,
  user: dbUser,
  password: dbPass,
  database: dbName,
  connectionLimit: 10,
  waitForConnections: true,
  queueLimit: 0,
  // mysql2 specific — keeps alive connections
  enableKeepAlive: true,
  keepAliveInitialDelay: 10000,
});

// Verify connectivity at startup
db.getConnection((err, connection) => {
  if (err) {
    console.error('[DB] Error connecting to fonebook MySQL:', err.message);
    // Don't exit — allow the server to start so health-check endpoints respond
  } else {
    connection.release();
    // console.log('[DB] Connected to fonebook MySQL pool');
  }
});

// ─── Secondary DB (printer_app) ───────────────────────────────────────────

const db1Host = process.env.DB1_HOST || 'localhost';
const db1User = process.env.DB1_USER || 'root';
const db1Pass = process.env.DB1_PASS || '';
const db1Name = process.env.DB1_NAME || 'printer_app';

const db1 = mysqlLib.createPool({
  host: db1Host,
  user: db1User,
  password: db1Pass,
  database: db1Name,
  connectionLimit: 5,
  waitForConnections: true,
  queueLimit: 0,
});

db1.getConnection((err, connection) => {
  if (err) {
    // printer_app is optional — warn but don't crash
    // console.warn('[DB] printer_app DB not available:', err.message);
  } else {
    connection.release();
  }
});

module.exports = { db, db1 };
