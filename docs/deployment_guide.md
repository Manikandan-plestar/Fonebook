# Deploying the Security Hardening Branch

> **Branch:** `security-hardening`  
> **Status:** Ready for production deployment  
> **Backward compatible:** ✅ All existing client versions continue to work

---

## Pre-Deployment Checklist

### 1. Create and configure .env

```bash
# On the production server
cp backend/.env.example backend/.env
nano backend/.env    # Fill in real values — see comments in the file
```

**Required values to set:**
- `GMAIL_USER` — your OTP email address
- `GMAIL_PASS` — rotate the Gmail App Password immediately (old one is in git history)
- `DB_USER` — see docs/db_user_setup.md to create a least-privilege user
- `DB_PASS` — strong password
- `JWT_SECRET` — generate with: `node -e "require('crypto').randomBytes(64).toString('hex')"`
- `ALLOWED_ORIGINS` — your production web origin(s), comma-separated

### 2. Rotate the Gmail App Password (URGENT)

The old password `bueh rpwu zvxd goky` is in the git history for `otp@tpdirectory.com`.

1. Go to https://myaccount.google.com/apppasswords
2. Delete the old app password
3. Create a new one
4. Set `GMAIL_PASS=<new_password>` in `backend/.env`

### 3. Run database migrations

```bash
# Connect to production MySQL as root
mysql -u root -p fonebook < backend/migrations/001_otp_store.sql
mysql -u root -p fonebook < backend/migrations/002_verified_purchases.sql
mysql -u root -p fonebook < backend/migrations/003_search_indexes.sql
```

> **Note:** All migrations are additive (IF NOT EXISTS). Safe to run on a live DB.  
> Index creation (`003_`) may take a few minutes on large tables — run during off-peak hours.

### 4. Create least-privilege DB user (optional but recommended)

See [docs/db_user_setup.md](db_user_setup.md).

### 5. Install new npm packages

```bash
cd backend
npm install  # Installs dotenv, express-rate-limit, mysql2, express-validator, jsonwebtoken
```

### 6. Restart the backend

```bash
# Example (adjust to your process manager)
pm2 restart fonebook
# or
systemctl restart fonebook
```

### 7. Watch startup logs

Expected output includes:
```
[ENV] WARNING: DB_USER is "root". Create a least-privilege DB user...   ← if not done yet
[DB] Connected to fonebook MySQL pool
```

If you see `FATAL: Missing required environment variables: GMAIL_USER, GMAIL_PASS` → check your `.env` file.

### 8. Build and release Flutter app

```bash
flutter build appbundle --release
# Upload to Play Store
```

---

## Phase 2 Activation (After New App Has Rolled Out)

Once the new Flutter app version is at ≥80% of active sessions:

```env
# In backend/.env — flip these flags:
ENFORCE_AUTH=true   # Start enforcing JWT on routes (all new clients send tokens)
```

Restart the backend. Monitor logs for `[AUTH-MONITOR]` entries — any remaining old clients will be logged (not blocked).

---

## Deferred Fixes (Cannot Be Done Without Breaking Old Clients)

The following were identified but deferred until `ENFORCE_AUTH=true`:

| ID | Issue | Why Deferred | Next Step |
|----|-------|-------------|-----------|
| CRIT-01 | No auth on mutation endpoints | Old clients have no token | Enable ENFORCE_AUTH after full rollout |
| CRIT-07 | IDOR on contact edits | Requires auth token to check ownership | Same as above |
| HIGH-02 | Google Play credentials in IAP responses | Requires v1/payments/verify adoption | Migrate in-app flow to call verifyPurchaseOnServer() |
| MED-08 | Path traversal in /uploads | Needs server-side image serving with validated filenames | Future PR |

---

## Quick Reference — What Changed

### Backend (`backend/FoneBook.js` + new files)

| Change | Finding | What Was Done |
|--------|---------|---------------|
| Gmail credentials → .env | CRIT-02 | `process.env.GMAIL_USER/PASS` |
| DB `root` → env vars | CRIT-06 | `lib/db.js` with mysql2 pool |
| Wildcard CORS → allowlist | CRIT-05 | `middleware/cors.js` |
| OTP rate limiting | HIGH-04 | `otpLimiterByIp` on `/send-verification-code` |
| Global rate limiting | HIGH-04 | `globalLimiter` on all routes |
| ReDoS in phrase search | HIGH-03 | `buildSafePhraseRegex()` escapes metacharacters |
| Unbounded fallback query | A3 | Added `LIMIT 200` cap |
| Error info leakage | MED-04 | Removed SQL/values from error logs |
| HTML injection in email | MED-07 | `escapeHtml()` on all interpolated values |
| Input length validation | MED-03 | `fieldLengthValidator` middleware |
| Single connection → pool | MED-10 | mysql2 createPool |
| New v1 OTP endpoints | CRIT-03 | `routes/v1/auth.js` |
| New payment verification | CRIT-04 | `routes/v1/payments.js` |
| Auth monitor middleware | CRIT-01 | `middleware/auth.js` (monitor mode) |

### Flutter

| Change | Finding | What Was Done |
|--------|---------|---------------|
| HTTP → HTTPS in release | HIGH-05, MED-01 | `kDebugMode` conditional URL |
| Backdoor credentials removed | CRIT-03 | Removed from `login_screen.dart` |
| Client-side OTP → server-side | CRIT-03 | `/v1/auth/send-otp` + `/v1/auth/verify-otp` |
| Payment stub → server verify | CRIT-04 | `verifyPurchaseOnServer()` in `payment_service.dart` |
| guest@ fallback removed | LOW-05 | Empty string → backend skips write |
| X-App-Version header | monitoring | Added to all requests |
| `usesCleartextTraffic=false` | HIGH-05 | Android manifest + network_security_config.xml |
