BEGIN;

DELETE FROM npc_shop_items
WHERE item_id IN ('tome_suppressing_talisman','tome_ghost_gate_chain');

DROP TRIGGER IF EXISTS trg_characters_default_spell ON characters;
DROP FUNCTION IF EXISTS grant_default_character_spells();

DROP TABLE IF EXISTS character_spell_learning_events;
DROP TABLE IF EXISTS spell_tome_definitions;
DROP TABLE IF EXISTS character_known_spells;

COMMIT;
