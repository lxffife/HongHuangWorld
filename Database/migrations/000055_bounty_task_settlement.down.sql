BEGIN;

DROP TABLE IF EXISTS bounty_task_settlements;

ALTER TABLE economy_treasury_ledger_entries
    DROP CONSTRAINT IF EXISTS economy_treasury_ledger_entries_entry_type_check;
ALTER TABLE economy_treasury_ledger_entries
    ADD CONSTRAINT economy_treasury_ledger_entries_entry_type_check
    CHECK (entry_type IN ('tax','listing_fee','exchange_fee','issuance','subsidy','system_adjustment','bounty_lock','bounty_refund','contribution'));

ALTER TABLE economy_treasury_ledger_entries
    DROP CONSTRAINT IF EXISTS economy_treasury_ledger_entries_delta_check;
ALTER TABLE economy_treasury_ledger_entries
    ADD CONSTRAINT economy_treasury_ledger_entries_delta_check CHECK (delta <> 0);

ALTER TABLE economy_treasury_ledger_entries
    DROP COLUMN IF EXISTS frozen_delta,
    DROP COLUMN IF EXISTS frozen_after;

COMMIT;
