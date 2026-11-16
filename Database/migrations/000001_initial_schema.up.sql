BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) NOT NULL UNIQUE,
    email VARCHAR(254) UNIQUE,
    password_hash TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'locked', 'disabled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (length(username) >= 3)
);

CREATE TABLE account_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    token_hash BYTEA NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_account_sessions_account ON account_sessions(account_id);
CREATE INDEX idx_account_sessions_expiry ON account_sessions(expires_at);

CREATE TABLE souls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    soul_name VARCHAR(48) NOT NULL,
    soul_origin VARCHAR(64),
    karma BIGINT NOT NULL DEFAULT 0,
    merit BIGINT NOT NULL DEFAULT 0,
    current_character_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, id)
);
CREATE INDEX idx_souls_account ON souls(account_id);

CREATE TABLE world_definitions (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(96) NOT NULL,
    world_type VARCHAR(32) NOT NULL,
    world_level SMALLINT NOT NULL DEFAULT 1 CHECK (world_level > 0),
    config JSONB NOT NULL DEFAULT '{}'::jsonb,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE world_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    instance_key VARCHAR(96) NOT NULL UNIQUE,
    status VARCHAR(16) NOT NULL DEFAULT 'starting' CHECK (status IN ('starting', 'ready', 'draining', 'offline')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_world_instances_world_status ON world_instances(world_id, status);

CREATE TABLE server_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    node_key VARCHAR(96) NOT NULL UNIQUE,
    host VARCHAR(255) NOT NULL,
    udp_port INTEGER NOT NULL CHECK (udp_port BETWEEN 1 AND 65535),
    region VARCHAR(32) NOT NULL DEFAULT 'local',
    capacity INTEGER NOT NULL DEFAULT 100 CHECK (capacity > 0),
    current_players INTEGER NOT NULL DEFAULT 0 CHECK (current_players >= 0),
    status VARCHAR(16) NOT NULL DEFAULT 'starting' CHECK (status IN ('starting', 'ready', 'draining', 'offline')),
    last_heartbeat_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (current_players <= capacity)
);
CREATE INDEX idx_server_registry_status ON server_registry(status, last_heartbeat_at);

CREATE TABLE characters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id),
    life_index INTEGER NOT NULL CHECK (life_index > 0),
    world_id VARCHAR(64) NOT NULL REFERENCES world_definitions(id),
    world_instance_id UUID REFERENCES world_instances(id),
    name VARCHAR(48) NOT NULL,
    race_id VARCHAR(64),
    level INTEGER NOT NULL DEFAULT 1 CHECK (level > 0),
    status VARCHAR(16) NOT NULL DEFAULT 'alive' CHECK (status IN ('alive', 'dead', 'retired', 'archived')),
    position_x DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    position_z DOUBLE PRECISION NOT NULL DEFAULT 0,
    rotation_y DOUBLE PRECISION NOT NULL DEFAULT 0,
    snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, life_index)
);
CREATE INDEX idx_characters_soul ON characters(soul_id, life_index DESC);
CREATE INDEX idx_characters_world ON characters(world_id, world_instance_id);

ALTER TABLE souls
    ADD CONSTRAINT fk_souls_current_character
    FOREIGN KEY (current_character_id) REFERENCES characters(id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE world_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    character_id UUID NOT NULL REFERENCES characters(id),
    instance_id UUID NOT NULL REFERENCES world_instances(id),
    server_id UUID NOT NULL REFERENCES server_registry(id),
    session_state VARCHAR(16) NOT NULL DEFAULT 'connecting' CHECK (session_state IN ('connecting', 'active', 'saving', 'closed')),
    connected_at TIMESTAMPTZ,
    disconnected_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_world_sessions_character_state ON world_sessions(character_id, session_state);
CREATE INDEX idx_world_sessions_server_state ON world_sessions(server_id, session_state);

INSERT INTO world_definitions (id, name, world_type, world_level, config)
VALUES
    ('underworld_fengdu', '冥界·酆都', 'underworld', 1, '{"starter": true}'::jsonb),
    ('qingyun_human', '青云人界', 'human', 1, '{"starter": true}'::jsonb),
    ('myriad_demon', '万妖界', 'demon', 1, '{"starter": true}'::jsonb)
ON CONFLICT (id) DO NOTHING;

COMMIT;
