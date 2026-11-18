BEGIN;
-- Rollback restores the legacy local-account FK. This is only safe after every
-- account that owns a soul has been backfilled into the legacy accounts table.
ALTER TABLE souls
    ADD CONSTRAINT souls_account_id_fkey
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
    NOT VALID;
COMMIT;
