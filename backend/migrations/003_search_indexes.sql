-- Migration: 003_search_indexes.sql
-- Adds indexes for common query patterns to improve search performance (A6)
-- Run: mysql -u root -p fonebook < migrations/003_search_indexes.sql
-- Rollback: see 003_search_indexes.rollback.sql
-- NOTE: These are additive only. IF NOT EXISTS prevents failures if run twice.
-- NOTE: Ask your DBA to run EXPLAIN on busy queries before adding all of these at once.

-- owner_email is used heavily in /check_search_type1, /save_my_contact
ALTER TABLE `contacts`
  ADD INDEX IF NOT EXISTS `idx_contacts_owner_email` (`owner_email`(100));

-- publish + deleted_contact is the most common filter pair in search queries  
ALTER TABLE `contacts`
  ADD INDEX IF NOT EXISTS `idx_contacts_publish_deleted` (`publish`, `deleted_contact`);

-- priority + priority_balance used in ad selection
ALTER TABLE `contacts`
  ADD INDEX IF NOT EXISTS `idx_contacts_priority` (`priority`, `priority_balance`);

-- phone_no is used as a lookup key in many routes
ALTER TABLE `contacts`
  ADD INDEX IF NOT EXISTS `idx_contacts_phone_no` (`phone_no`(30));

-- call_count table: phone_no queries are very frequent
ALTER TABLE `call_count`
  ADD INDEX IF NOT EXISTS `idx_cc_phone_no` (`phone_no`(30));

-- my_contacts: owner_email lookup
ALTER TABLE `my_contacts`
  ADD INDEX IF NOT EXISTS `idx_mc_owner_email` (`owner_email`(100));
