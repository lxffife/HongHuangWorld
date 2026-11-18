BEGIN;

-- Game remains the source of truth. Every domain event is inserted by a trigger
-- in the same transaction as the source row change.
CREATE SEQUENCE game_event_outbox_sequence;

CREATE TABLE game_event_outbox (
    event_sequence BIGINT PRIMARY KEY DEFAULT nextval('game_event_outbox_sequence'),
    event_id UUID NOT NULL UNIQUE,
    event_type VARCHAR(128) NOT NULL,
    aggregate_id VARCHAR(96) NOT NULL,
    aggregate_version BIGINT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_until TIMESTAMPTZ,
    locked_by VARCHAR(96),
    last_error TEXT,
    CHECK ((locked_until IS NULL) = (locked_by IS NULL))
);

CREATE INDEX idx_game_event_outbox_pending
    ON game_event_outbox(next_attempt_at, event_sequence)
    WHERE published_at IS NULL;
CREATE INDEX idx_game_event_outbox_expired_locks
    ON game_event_outbox(locked_until)
    WHERE published_at IS NULL AND locked_until IS NOT NULL;

CREATE OR REPLACE FUNCTION emit_game_domain_event(
    p_event_type VARCHAR,
    p_aggregate_id VARCHAR,
    p_data JSONB
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id UUID := gen_random_uuid();
    v_sequence BIGINT := nextval('game_event_outbox_sequence');
    v_occurred_at TIMESTAMPTZ := clock_timestamp();
BEGIN
    INSERT INTO game_event_outbox(
        event_sequence, event_id, event_type, aggregate_id,
        aggregate_version, occurred_at, payload
    ) VALUES (
        v_sequence, v_event_id, p_event_type, p_aggregate_id,
        v_sequence, v_occurred_at,
        jsonb_build_object(
            'version', 1,
            'event_id', v_event_id,
            'event_type', p_event_type,
            'aggregate_id', p_aggregate_id,
            'aggregate_version', v_sequence,
            'occurred_at', v_occurred_at,
            'data', COALESCE(p_data, '{}'::jsonb)
        )
    );
    RETURN v_sequence;
END;
$$;

CREATE OR REPLACE FUNCTION trg_game_character_projection_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_account_id UUID;
    v_event_type VARCHAR(128);
BEGIN
    SELECT account_id INTO v_account_id FROM souls WHERE id = NEW.soul_id;
    IF v_account_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_event_type := 'game.character.created.v1';
    ELSE
        v_event_type := 'game.character.updated.v1';
    END IF;

    PERFORM emit_game_domain_event(
        v_event_type,
        NEW.id::text,
        jsonb_build_object(
            'character_id', NEW.id,
            'account_id', v_account_id,
            'name', NEW.name,
            'race_id', COALESCE(NEW.race_id, ''),
            'level', NEW.level,
            'world_id', NEW.world_id,
            'status', NEW.status
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER game_characters_projection_event
AFTER INSERT OR UPDATE OF name, race_id, level, world_id, status ON characters
FOR EACH ROW EXECUTE FUNCTION trg_game_character_projection_event();

CREATE OR REPLACE FUNCTION trg_game_account_character_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.current_character_id IS DISTINCT FROM OLD.current_character_id THEN
        PERFORM emit_game_domain_event(
            'game.account.current_character_changed.v1',
            NEW.account_id::text,
            jsonb_build_object(
                'account_id', NEW.account_id,
                'current_character_id', NEW.current_character_id
            )
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER game_souls_current_character_event
AFTER INSERT OR UPDATE OF current_character_id ON souls
FOR EACH ROW EXECUTE FUNCTION trg_game_account_character_event();

CREATE OR REPLACE FUNCTION trg_game_world_instance_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_node_key VARCHAR(96);
BEGIN
    SELECT node_key INTO v_node_key FROM server_registry WHERE id = NEW.server_id;
    PERFORM emit_game_domain_event(
        'game.world_instance.upserted.v1',
        NEW.id::text,
        jsonb_build_object(
            'instance_id', NEW.id,
            'world_id', NEW.world_id,
            'node_key', COALESCE(v_node_key, ''),
            'status', NEW.status
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER game_world_instances_projection_event
AFTER INSERT OR UPDATE OF world_id, server_id, status ON world_instances
FOR EACH ROW EXECUTE FUNCTION trg_game_world_instance_event();

CREATE OR REPLACE FUNCTION trg_game_server_node_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM emit_game_domain_event(
        'game.server_node.heartbeat.v1',
        NEW.node_key,
        jsonb_build_object(
            'node_key', NEW.node_key,
            'status', NEW.status,
            'host', NEW.host,
            'udp_port', NEW.udp_port,
            'region', NEW.region,
            'last_heartbeat_at', NEW.last_heartbeat_at
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER game_server_registry_projection_event
AFTER INSERT OR UPDATE OF node_key, status, host, udp_port, region, last_heartbeat_at ON server_registry
FOR EACH ROW EXECUTE FUNCTION trg_game_server_node_event();

CREATE OR REPLACE FUNCTION trg_game_world_session_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_node_key VARCHAR(96);
    v_event_type VARCHAR(128);
BEGIN
    SELECT node_key INTO v_node_key
    FROM server_registry WHERE id = NEW.server_id;

    IF NEW.session_state = 'closed' THEN
        v_event_type := 'game.world_session.closed.v1';
    ELSIF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.session_state IS DISTINCT FROM NEW.session_state) THEN
        v_event_type := 'game.world_session.updated.v1';
        IF NEW.session_state = 'active' THEN
            v_event_type := 'game.world_session.opened.v1';
        END IF;
    ELSE
        RETURN NEW;
    END IF;

    PERFORM emit_game_domain_event(
        v_event_type,
        NEW.id::text,
        jsonb_build_object(
            'session_id', NEW.id,
            'character_id', NEW.character_id,
            'instance_id', NEW.instance_id,
            'node_key', COALESCE(v_node_key, ''),
            'session_state', NEW.session_state,
            'disconnected_at', NEW.disconnected_at
        )
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER game_world_sessions_projection_event
AFTER INSERT OR UPDATE OF character_id, instance_id, server_id, session_state, disconnected_at ON world_sessions
FOR EACH ROW EXECUTE FUNCTION trg_game_world_session_event();

COMMIT;
