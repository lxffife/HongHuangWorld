BEGIN;

ALTER TABLE reincarnation_events
    DROP COLUMN IF EXISTS birth_route_snapshot,
    DROP COLUMN IF EXISTS birth_route_description,
    DROP COLUMN IF EXISTS birth_route_name,
    DROP COLUMN IF EXISTS birth_route_id;

DROP TABLE IF EXISTS reincarnation_birth_routes;

COMMIT;
