BEGIN;
DROP INDEX IF EXISTS idx_parties_focus_expiry;
ALTER TABLE parties
  DROP COLUMN IF EXISTS focus_updated_at,
  DROP COLUMN IF EXISTS focus_by_account_id,
  DROP COLUMN IF EXISTS focus_target_entity_id;
COMMIT;
