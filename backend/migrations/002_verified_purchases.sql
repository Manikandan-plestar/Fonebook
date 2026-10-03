-- Migration: 002_verified_purchases.sql
-- Adds purchase replay-protection table (Phase 2 — CRIT-04)
-- Run: mysql -u root -p fonebook < migrations/002_verified_purchases.sql
-- Rollback: see 002_verified_purchases.rollback.sql

CREATE TABLE IF NOT EXISTS `verified_purchases` (
    `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `token_hash`  VARCHAR(64)     NOT NULL UNIQUE COMMENT 'SHA-256 of the purchase token — prevents replay attacks',
    `product_id`  VARCHAR(200)    NOT NULL,
    `user_email`  VARCHAR(320)    NOT NULL,
    `created_at`  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `uidx_token_hash` (`token_hash`),
    INDEX `idx_vp_email` (`user_email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Records verified IAP purchase tokens to prevent replay attacks.';
