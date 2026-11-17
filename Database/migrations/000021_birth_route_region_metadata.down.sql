BEGIN;

DROP INDEX IF EXISTS idx_reincarnation_birth_routes_region;
ALTER TABLE reincarnation_birth_routes
    DROP COLUMN IF EXISTS race_affinity,
    DROP COLUMN IF EXISTS exploration_points,
    DROP COLUMN IF EXISTS resource_tags,
    DROP COLUMN IF EXISTS danger_level,
    DROP COLUMN IF EXISTS region_description,
    DROP COLUMN IF EXISTS region_name,
    DROP COLUMN IF EXISTS region_id;

COMMIT;
