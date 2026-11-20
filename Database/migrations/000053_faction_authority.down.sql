BEGIN;
DROP TABLE IF EXISTS faction_membership_applications;
DROP TABLE IF EXISTS faction_members;
DROP TABLE IF EXISTS factions;
DELETE FROM economy_treasury_accounts t
WHERE t.account_type = 'faction_treasury'
  AND t.account_key LIKE 'faction:%'
  AND NOT EXISTS (SELECT 1 FROM economy_treasury_balances b WHERE b.treasury_account_id=t.id)
  AND NOT EXISTS (SELECT 1 FROM economy_treasury_ledger_entries l WHERE l.treasury_account_id=t.id);
COMMIT;
