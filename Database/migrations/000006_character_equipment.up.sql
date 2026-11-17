BEGIN;

ALTER TABLE item_definitions
    ADD COLUMN item_type VARCHAR(24) NOT NULL DEFAULT 'material'
        CHECK (item_type IN ('equipment', 'consumable', 'material', 'quest')),
    ADD COLUMN equipment_slot VARCHAR(24)
        CHECK (equipment_slot IS NULL OR equipment_slot IN ('weapon', 'head', 'chest', 'legs', 'boots', 'accessory')),
    ADD COLUMN base_stats JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN use_effect JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE item_definitions
SET item_type = category
WHERE category IN ('equipment', 'consumable', 'material', 'quest');

ALTER TABLE item_definitions
    ADD CONSTRAINT item_equipment_slot_required
    CHECK ((item_type = 'equipment' AND equipment_slot IS NOT NULL) OR
           (item_type <> 'equipment' AND equipment_slot IS NULL));

CREATE TABLE character_equipment (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot VARCHAR(24) NOT NULL CHECK (slot IN ('weapon', 'head', 'chest', 'legs', 'boots', 'accessory')),
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    equipped_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, slot),
    UNIQUE (character_id, item_id)
);

CREATE INDEX idx_character_equipment_item ON character_equipment(item_id);

-- Keep item_type aligned with the legacy category field for every catalog insert.
CREATE FUNCTION sync_item_type_from_category() RETURNS trigger
LANGUAGE plpgsql AS 'BEGIN NEW.item_type := NEW.category; RETURN NEW; END;';

CREATE TRIGGER trg_item_type_from_category
BEFORE INSERT OR UPDATE OF category ON item_definitions
FOR EACH ROW EXECUTE FUNCTION sync_item_type_from_category();

COMMIT;
