BEGIN;

-- Slot capacity counts stack rows and unique equipment instances separately.
-- Existing characters default to 40 slots until an explicit capacity row is created.
CREATE TABLE character_inventory_capacity (
    character_id UUID PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    max_slots INTEGER NOT NULL DEFAULT 40 CHECK (max_slots BETWEEN 1 AND 500),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
