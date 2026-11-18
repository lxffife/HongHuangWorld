BEGIN;
DELETE FROM soul_absorption_kinds
WHERE id IN ('blazing_war_soul_elite','blazing_war_soul_ancient','blazing_war_soul_mythic');
ALTER TABLE soul_absorption_records DROP CONSTRAINT IF EXISTS chk_soul_absorption_attribute_points_awarded;
UPDATE soul_absorption_records SET attribute_points_awarded=LEAST(attribute_points_awarded,1);
ALTER TABLE soul_absorption_records
    ADD CONSTRAINT soul_absorption_records_attribute_points_awarded_check
    CHECK (attribute_points_awarded BETWEEN 0 AND 1);
ALTER TABLE soul_absorption_records DROP COLUMN progress_units;
ALTER TABLE soul_absorption_kinds DROP COLUMN progress_units;
ALTER TABLE soul_absorption_kinds DROP COLUMN quality_tier;
COMMIT;
