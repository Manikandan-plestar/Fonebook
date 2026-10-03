-- Rollback: 003_search_indexes.sql
ALTER TABLE `contacts`   DROP INDEX IF EXISTS `idx_contacts_owner_email`;
ALTER TABLE `contacts`   DROP INDEX IF EXISTS `idx_contacts_publish_deleted`;
ALTER TABLE `contacts`   DROP INDEX IF EXISTS `idx_contacts_priority`;
ALTER TABLE `contacts`   DROP INDEX IF EXISTS `idx_contacts_phone_no`;
ALTER TABLE `call_count` DROP INDEX IF EXISTS `idx_cc_phone_no`;
ALTER TABLE `my_contacts` DROP INDEX IF EXISTS `idx_mc_owner_email`;
