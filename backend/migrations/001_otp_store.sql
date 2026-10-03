-- Migration: 001_otp_store.sql
-- Adds server-side OTP storage table (Phase 2 — CRIT-03)
-- Run: mysql -u root -p fonebook < migrations/001_otp_store.sql
-- Rollback: see 001_otp_store.rollback.sql

-- NOTE: This is additive only — no existing tables are modified.

CREATE TABLE IF NOT EXISTS `otp_codes` (
    `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `email`      VARCHAR(320)    NOT NULL,
    `otp_hash`   VARCHAR(64)     NOT NULL COMMENT 'SHA-256 hex of the OTP — never store plaintext',
    `expires_at` DATETIME        NOT NULL,
    `attempts`   TINYINT         NOT NULL DEFAULT 0,
    `created_at` DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_otp_email` (`email`),
    INDEX `idx_otp_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Server-side OTP storage. Rows auto-expire; clean up with event scheduler or cron.';

-- Optional: auto-delete expired OTPs (requires MySQL Event Scheduler enabled)
-- CREATE EVENT IF NOT EXISTS `cleanup_otp_codes`
--   ON SCHEDULE EVERY 1 HOUR
--   DO DELETE FROM `otp_codes` WHERE expires_at < NOW();
