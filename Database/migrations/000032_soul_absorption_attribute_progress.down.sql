BEGIN;

ALTER TABLE soul_absorption_records
    DROP COLUMN IF EXISTS attribute_points_awarded;

ALTER TABLE soul_inheritance_attributes
    DROP CONSTRAINT IF EXISTS chk_soul_inheritance_attribute_caps;

DROP TABLE IF EXISTS soul_absorption_attribute_progress;

COMMIT;
