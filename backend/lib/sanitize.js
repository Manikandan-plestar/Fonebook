// lib/sanitize.js — Input validation and sanitization helpers
// HIGH-03 (ReDoS), MED-03 (input length), MED-07 (HTML escaping)

'use strict';

/**
 * HTML-escape a string for safe interpolation into email HTML bodies.
 * Prevents XSS if user-controlled values end up in emails.
 */
function escapeHtml(str) {
  if (typeof str !== 'string') return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

/**
 * Sanitize a user-supplied string for use in a MySQL REGEXP clause.
 * Escapes all regex metacharacters to prevent ReDoS.
 */
function escapeRegex(str) {
  if (typeof str !== 'string') return '';
  // MySQL REGEXP metacharacters: . * + ? ^ $ { } [ ] | ( ) \
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Validate and cap a search query.
 * Returns null if invalid, trimmed lowercase string if valid.
 */
const MAX_SEARCH_QUERY_LEN = 100;
function validateSearchQuery(query) {
  if (typeof query !== 'string') return null;
  const q = query.toLowerCase().trim();
  if (q.length === 0) return null;
  if (q.length > MAX_SEARCH_QUERY_LEN) return null;
  return q;
}

/**
 * Build a safe REGEXP pattern from a search query for use in MySQL REGEXP ?.
 * Words are joined with .* to allow phrase matching, all metacharacters escaped.
 */
function buildSafePhraseRegex(trimmedQuery) {
  const words = trimmedQuery.split(/\s+/).map(w => escapeRegex(w));
  return words.join('.*');
}

/**
 * Field length limits (generous — based on typical DB column sizes).
 * These are used in input validation to reject obviously abusive payloads.
 */
const FIELD_LIMITS = {
  name: 200,
  service: 300,
  about: 2000,
  keyword: 1000,
  keywords: 1000,
  location: 500,
  location1: 300,
  email: 320,
  phone: 30,
  city: 200,
  state: 200,
  country_name: 200,
  title: 500,
  tag: 200,
  tags: 500,
};

/**
 * Validate POST body field lengths.
 * Returns an array of error messages (empty if all OK).
 */
function validateFieldLengths(body) {
  const errors = [];
  for (const [field, limit] of Object.entries(FIELD_LIMITS)) {
    if (body[field] !== undefined && body[field] !== null) {
      const val = String(body[field]);
      if (val.length > limit) {
        errors.push(`Field '${field}' exceeds maximum length of ${limit} characters.`);
      }
    }
  }
  return errors;
}

/**
 * Middleware: validate field lengths on any POST route.
 * Keeps the same status code (400) so the app can handle it.
 * Existing clients that don't hit the limits are completely unaffected.
 */
function fieldLengthValidator(req, res, next) {
  if (req.method !== 'POST' && req.method !== 'PUT') return next();
  const errors = validateFieldLengths(req.body);
  if (errors.length > 0) {
    return res.status(400).json({ error: 'Input validation failed', details: errors });
  }
  next();
}

module.exports = {
  escapeHtml,
  escapeRegex,
  validateSearchQuery,
  buildSafePhraseRegex,
  fieldLengthValidator,
  FIELD_LIMITS,
};
