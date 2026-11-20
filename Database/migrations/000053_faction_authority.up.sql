BEGIN;

-- Player-created organizations are sects only. City government and official
-- agencies are provisioned by trusted administration, never by client input.
CREATE TABLE factions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    world_id VARCHAR(64) NOT NULL,
    faction_type VARCHAR(24) NOT NULL CHECK (faction_type IN ('sect', 'city_government', 'official_agency')),
    name VARCHAR(48) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    level INTEGER NOT NULL DEFAULT 1 CHECK (level BETWEEN 1 AND 100),
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'disbanded')),
    treasury_account_id UUID REFERENCES economy_treasury_accounts(id),
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_factions_world_name ON factions(world_id, lower(name));
CREATE INDEX idx_factions_world_type_status ON factions(world_id, faction_type, status);

CREATE TABLE faction_members (
    faction_id UUID NOT NULL REFERENCES factions(id) ON DELETE CASCADE,
    account_id UUID NOT NULL,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'officer', 'member')),
    contribution_points BIGINT NOT NULL DEFAULT 0 CHECK (contribution_points >= 0),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (faction_id, account_id)
);
CREATE INDEX idx_faction_members_account ON faction_members(account_id, joined_at DESC);

CREATE TABLE faction_membership_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faction_id UUID NOT NULL REFERENCES factions(id) ON DELETE CASCADE,
    account_id UUID NOT NULL,
    message VARCHAR(240) NOT NULL DEFAULT '',
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (faction_id, account_id, id)
);
CREATE UNIQUE INDEX uq_faction_pending_application
    ON faction_membership_applications(faction_id, account_id) WHERE status = 'pending';
CREATE INDEX idx_faction_applications_review
    ON faction_membership_applications(faction_id, status, created_at);

COMMIT;
