BEGIN;

ALTER TABLE economy_treasury_ledger_entries
    DROP CONSTRAINT IF EXISTS economy_treasury_ledger_entries_entry_type_check;
ALTER TABLE economy_treasury_ledger_entries
    ADD CONSTRAINT economy_treasury_ledger_entries_entry_type_check
    CHECK (entry_type IN ('tax','listing_fee','exchange_fee','issuance','subsidy','system_adjustment','bounty_lock','bounty_refund','contribution'));

CREATE TABLE bounty_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    world_id VARCHAR(64) NOT NULL,
    publisher_type VARCHAR(24) NOT NULL CHECK (publisher_type IN ('faction','city_government','official_agency')),
    publisher_id UUID NOT NULL REFERENCES factions(id),
    title VARCHAR(96) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    reward_amount BIGINT NOT NULL CHECK (reward_amount > 0),
    escrow_amount BIGINT NOT NULL CHECK (escrow_amount > 0),
    difficulty_tier SMALLINT NOT NULL DEFAULT 1 CHECK (difficulty_tier BETWEEN 1 AND 10),
    required_realm_level INTEGER NOT NULL DEFAULT 0 CHECK (required_realm_level >= 0),
    max_assignees SMALLINT NOT NULL DEFAULT 1 CHECK (max_assignees BETWEEN 1 AND 20),
    status VARCHAR(16) NOT NULL DEFAULT 'open' CHECK (status IN ('open','full','in_progress','completed','cancelled','expired')),
    expires_at TIMESTAMPTZ,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (escrow_amount = reward_amount * max_assignees)
);
CREATE INDEX idx_bounty_tasks_world_status ON bounty_tasks(world_id,status,created_at DESC);
CREATE INDEX idx_bounty_tasks_publisher ON bounty_tasks(publisher_id,created_at DESC);

CREATE TABLE bounty_task_escrows (
    task_id UUID PRIMARY KEY REFERENCES bounty_tasks(id) ON DELETE RESTRICT,
    treasury_account_id UUID NOT NULL REFERENCES economy_treasury_accounts(id),
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    amount BIGINT NOT NULL CHECK (amount > 0),
    status VARCHAR(16) NOT NULL DEFAULT 'locked' CHECK (status IN ('locked','refunded','paid')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE bounty_task_participants (
    task_id UUID NOT NULL REFERENCES bounty_tasks(id) ON DELETE CASCADE,
    account_id UUID NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'accepted' CHECK (status IN ('accepted','withdrawn','completed','failed')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(task_id,account_id)
);
CREATE INDEX idx_bounty_participants_account ON bounty_task_participants(account_id,status);

COMMIT;
