BEGIN;

-- Track treasury frozen balances in the immutable ledger for escrow release.
ALTER TABLE economy_treasury_ledger_entries
    ADD COLUMN frozen_delta BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN frozen_after BIGINT NOT NULL DEFAULT 0 CHECK (frozen_after >= 0);

ALTER TABLE economy_treasury_ledger_entries
    DROP CONSTRAINT IF EXISTS economy_treasury_ledger_entries_delta_check;
ALTER TABLE economy_treasury_ledger_entries
    ADD CONSTRAINT economy_treasury_ledger_entries_delta_check
    CHECK (delta <> 0 OR entry_type = 'bounty_payout');

ALTER TABLE economy_treasury_ledger_entries
    DROP CONSTRAINT IF EXISTS economy_treasury_ledger_entries_entry_type_check;
ALTER TABLE economy_treasury_ledger_entries
    ADD CONSTRAINT economy_treasury_ledger_entries_entry_type_check
    CHECK (entry_type IN ('tax','listing_fee','exchange_fee','issuance','subsidy','system_adjustment','bounty_lock','bounty_refund','bounty_payout','contribution'));

CREATE TABLE bounty_task_settlements (
    task_id UUID PRIMARY KEY REFERENCES bounty_tasks(id) ON DELETE RESTRICT,
    event_key VARCHAR(128) NOT NULL UNIQUE,
    settled_by UUID NOT NULL,
    participant_count SMALLINT NOT NULL CHECK (participant_count > 0),
    paid_amount BIGINT NOT NULL CHECK (paid_amount > 0),
    refunded_amount BIGINT NOT NULL CHECK (refunded_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (paid_amount + refunded_amount > 0)
);

COMMIT;
