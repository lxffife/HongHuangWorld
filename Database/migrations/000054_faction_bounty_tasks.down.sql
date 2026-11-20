BEGIN;
DROP TABLE IF EXISTS bounty_task_participants;
DROP TABLE IF EXISTS bounty_task_escrows;
DROP TABLE IF EXISTS bounty_tasks;
ALTER TABLE economy_treasury_ledger_entries
    DROP CONSTRAINT IF EXISTS economy_treasury_ledger_entries_entry_type_check;
ALTER TABLE economy_treasury_ledger_entries
    ADD CONSTRAINT economy_treasury_ledger_entries_entry_type_check
    CHECK (entry_type IN ('tax','listing_fee','exchange_fee','issuance','subsidy','system_adjustment'));
COMMIT;
