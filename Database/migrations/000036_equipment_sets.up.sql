BEGIN;
CREATE TABLE equipment_sets (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    bonus_tiers JSONB NOT NULL DEFAULT '{}'::jsonb,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT equipment_set_bonus_tiers_object CHECK (jsonb_typeof(bonus_tiers) = 'object')
);
ALTER TABLE item_definitions
    ADD COLUMN equipment_set_id VARCHAR(64) REFERENCES equipment_sets(id) ON DELETE SET NULL;
CREATE INDEX idx_item_definitions_equipment_set ON item_definitions(equipment_set_id) WHERE equipment_set_id IS NOT NULL;
-- Example: {"2":{"attack":5},"4":{"attack":12,"defense":8}}
-- This is configuration only; actual combat bonuses remain server-authoritative.
COMMIT;
