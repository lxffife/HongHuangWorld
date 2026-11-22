BEGIN;
ALTER TABLE item_instances ADD COLUMN enhancement_level SMALLINT NOT NULL DEFAULT 0 CHECK (enhancement_level BETWEEN 0 AND 12);
CREATE TABLE equipment_enhancement_rules (
 target_level SMALLINT PRIMARY KEY CHECK (target_level BETWEEN 1 AND 12),
 material_quantity INTEGER NOT NULL CHECK (material_quantity BETWEEN 1 AND 99),
 success_rate_bp INTEGER NOT NULL CHECK (success_rate_bp BETWEEN 0 AND 10000)
);
INSERT INTO equipment_enhancement_rules(target_level,material_quantity,success_rate_bp) VALUES
(1,2,10000),(2,3,8500),(3,4,7000),(4,5,6000),(5,6,5000),(6,7,4000),
(7,8,3000),(8,9,2500),(9,10,2000),(10,12,1500),(11,14,1000),(12,16,800);
CREATE TABLE equipment_enhancement_events (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
 request_id UUID NOT NULL,
 item_instance_id UUID NOT NULL,
 equipment_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
 old_level SMALLINT NOT NULL CHECK (old_level BETWEEN 0 AND 11),
 target_level SMALLINT NOT NULL CHECK (target_level BETWEEN 1 AND 12),
 material_item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
 material_quantity INTEGER NOT NULL CHECK (material_quantity > 0),
 success_rate_bp INTEGER NOT NULL CHECK (success_rate_bp BETWEEN 0 AND 10000),
 succeeded BOOLEAN NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(character_id,request_id)
);
CREATE INDEX idx_equipment_enhancement_character_time ON equipment_enhancement_events(character_id,created_at DESC);
COMMIT;
