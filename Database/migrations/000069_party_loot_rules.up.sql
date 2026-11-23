BEGIN;
ALTER TABLE parties
  ADD COLUMN material_loot_mode VARCHAR(20) NOT NULL DEFAULT 'personal'
    CHECK (material_loot_mode IN ('personal','free_for_all','round_robin','leader')),
  ADD COLUMN equipment_loot_mode VARCHAR(20) NOT NULL DEFAULT 'personal'
    CHECK (equipment_loot_mode IN ('personal','free_for_all','round_robin','leader')),
  ADD COLUMN material_loot_cursor BIGINT NOT NULL DEFAULT 0 CHECK (material_loot_cursor >= 0),
  ADD COLUMN equipment_loot_cursor BIGINT NOT NULL DEFAULT 0 CHECK (equipment_loot_cursor >= 0);
CREATE TABLE ground_drop_eligible_characters (
  drop_id UUID NOT NULL REFERENCES ground_drops(id) ON DELETE CASCADE,
  character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (drop_id, character_id)
);
CREATE INDEX idx_ground_drop_eligible_character ON ground_drop_eligible_characters(character_id, drop_id);
INSERT INTO ground_drop_eligible_characters(drop_id, character_id)
SELECT id, owner_character_id FROM ground_drops WHERE status='available'
ON CONFLICT DO NOTHING;
COMMIT;
