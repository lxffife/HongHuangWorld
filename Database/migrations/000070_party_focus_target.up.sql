BEGIN;
ALTER TABLE parties
  ADD COLUMN focus_target_entity_id VARCHAR(96),
  ADD COLUMN focus_by_account_id UUID REFERENCES accounts(id) ON DELETE SET NULL,
  ADD COLUMN focus_updated_at TIMESTAMPTZ;
CREATE INDEX idx_parties_focus_expiry ON parties(focus_updated_at)
  WHERE focus_target_entity_id IS NOT NULL;
COMMIT;
