# Least-Privilege DB User Setup

> **Fix:** CRIT-06 — Backend was running as MySQL `root`  
> **Priority:** HIGH — run this before enabling ENFORCE_AUTH  
> **Safe to run on live server:** ✅ Yes (additive, no existing data touched)

---

## Why This Matters

The backend was connecting as `root`. If any SQL injection vulnerability exists (or is found in future), an attacker gets **full database admin access** — they can read, write, drop tables, and exfiltrate everything.

A least-privilege user can only do what the application actually needs.

---

## Step 1: Connect as root

```bash
mysql -u root -p
```

---

## Step 2: Create the application user

```sql
-- Create a dedicated app user (not root)
CREATE USER IF NOT EXISTS 'fonebook_app'@'localhost' IDENTIFIED BY 'REPLACE_WITH_STRONG_PASSWORD';

-- Grant only what the app needs on the fonebook database
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.* TO 'fonebook_app'@'localhost';

-- If the app also needs to CREATE/ALTER for runtime migrations (startup column checks):
-- GRANT CREATE, ALTER ON `fonebook`.* TO 'fonebook_app'@'localhost';
-- (Recommended: remove this grant once all startup migrations are moved to explicit migration files)

-- Flush
FLUSH PRIVILEGES;
```

---

## Step 3: Update .env

```env
DB_USER=fonebook_app
DB_PASS=REPLACE_WITH_STRONG_PASSWORD
```

---

## Step 4: Test

Restart the backend and verify it connects. Watch startup logs for:
- `[DB] Connected to fonebook MySQL pool` — success
- Any `Access denied` errors — means a missing GRANT (add it above and re-run FLUSH PRIVILEGES)

---

## Step 5: Optional — restrict to specific tables

For even tighter security, you can grant per-table instead of `*`:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.`contacts` TO 'fonebook_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.`my_contacts` TO 'fonebook_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.`reviews` TO 'fonebook_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.`call_count` TO 'fonebook_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.`otp_codes` TO 'fonebook_app'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON `fonebook`.`verified_purchases` TO 'fonebook_app'@'localhost';
-- Add other tables as needed
FLUSH PRIVILEGES;
```

---

## Rollback

If you need to revert temporarily (NOT recommended for production):

```sql
-- Revert .env to DB_USER=root, DB_PASS=
-- No SQL changes needed — root still exists
```
