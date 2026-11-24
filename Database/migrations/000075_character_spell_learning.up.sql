BEGIN;

-- Every living/new character starts with the common, free Nether Phosphor
-- technique. Other combat techniques require consuming their matching tome.
CREATE TABLE character_known_spells (
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    spell_id VARCHAR(64) NOT NULL CHECK (spell_id IN ('fireball','ice_bolt','taunt')),
    learned_from_item_id VARCHAR(64) REFERENCES item_definitions(id),
    learned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (character_id, spell_id)
);
CREATE INDEX idx_character_known_spells_spell ON character_known_spells(spell_id, character_id);

CREATE TABLE spell_tome_definitions (
    item_id VARCHAR(64) PRIMARY KEY REFERENCES item_definitions(id),
    spell_id VARCHAR(64) NOT NULL UNIQUE CHECK (spell_id IN ('ice_bolt','taunt')),
    display_name VARCHAR(96) NOT NULL,
    discipline_id VARCHAR(64) NOT NULL,
    required_world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE character_spell_learning_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    character_id UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    request_id UUID NOT NULL,
    item_id VARCHAR(64) NOT NULL REFERENCES item_definitions(id),
    spell_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (character_id, request_id)
);

-- Backfill all existing characters, including dead characters that may return
-- through reincarnation/history systems, with the free starter technique.
INSERT INTO character_known_spells(character_id,spell_id)
SELECT id,'fireball' FROM characters
ON CONFLICT (character_id,spell_id) DO NOTHING;

CREATE FUNCTION grant_default_character_spells() RETURNS trigger AS $$
BEGIN
    INSERT INTO character_known_spells(character_id,spell_id)
    VALUES (NEW.id,'fireball')
    ON CONFLICT (character_id,spell_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_characters_default_spell
AFTER INSERT ON characters
FOR EACH ROW EXECUTE FUNCTION grant_default_character_spells();

INSERT INTO item_definitions(id,name,category,quality,max_stack,icon_key,description)
VALUES
('tome_suppressing_talisman','《镇邪符箓初解》','material',1,10,'tome_talisman_gold','记载镇邪符的基础符诀。研读后永久掌握镇邪符。'),
('tome_ghost_gate_chain','《鬼门锁链真诀》','material',2,10,'tome_ghost_chain','记载酆都鬼门锁链的拘魂与缚敌法门。研读后永久掌握鬼门锁链。')
ON CONFLICT(id) DO NOTHING;

INSERT INTO spell_tome_definitions(item_id,spell_id,display_name,discipline_id,required_world_id)
VALUES
('tome_suppressing_talisman','ice_bolt','镇邪符','fengdu_ming司','underworld_fengdu'),
('tome_ghost_gate_chain','taunt','鬼门锁链','fengdu_ming司','underworld_fengdu')
ON CONFLICT(item_id) DO NOTHING;

INSERT INTO npc_shop_items(shop_id,item_id,unit_price,stock_quantity,sort_order,enabled)
VALUES
('fengdu_talisman_shop','tome_suppressing_talisman',90,NULL,30,TRUE),
('fengdu_talisman_shop','tome_ghost_gate_chain',180,NULL,40,TRUE)
ON CONFLICT(shop_id,item_id) DO NOTHING;

COMMIT;
