BEGIN;

-- Backfill the account's current-character projection for souls that were
-- created or assigned before migration 000043 installed the outbox trigger.
-- The migration runs once, and the normal trigger handles all future changes.
DO $$
DECLARE
    soul_row RECORD;
BEGIN
    FOR soul_row IN
        SELECT account_id, current_character_id
        FROM souls
        WHERE current_character_id IS NOT NULL
        ORDER BY account_id
    LOOP
        PERFORM emit_game_domain_event(
            'game.account.current_character_changed.v1',
            soul_row.account_id::text,
            jsonb_build_object(
                'account_id', soul_row.account_id,
                'current_character_id', soul_row.current_character_id
            )
        );
    END LOOP;
END;
$$;

COMMIT;
