BEGIN;

-- Remove only the attribute points granted by this progression ledger.
UPDATE soul_inheritance_attributes inheritance
SET strength = GREATEST(0, inheritance.strength - progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'strength';

UPDATE soul_inheritance_attributes inheritance
SET constitution = GREATEST(0, inheritance.constitution - progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'constitution';

UPDATE soul_inheritance_attributes inheritance
SET agility = GREATEST(0, inheritance.agility - progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'agility';

UPDATE soul_inheritance_attributes inheritance
SET spirit = GREATEST(0, inheritance.spirit - progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'spirit';

UPDATE soul_inheritance_attributes inheritance
SET vitality = GREATEST(0, inheritance.vitality - progress.applied_points),
    updated_at = now()
FROM soul_absorption_attribute_progress progress
WHERE progress.soul_id = inheritance.soul_id AND progress.attribute = 'vitality';

ALTER TABLE soul_absorption_records
    DROP COLUMN IF EXISTS attribute_points_awarded;

ALTER TABLE soul_inheritance_attributes
    DROP CONSTRAINT IF EXISTS chk_soul_inheritance_attribute_caps;

DROP TABLE IF EXISTS soul_absorption_attribute_progress;

COMMIT;
