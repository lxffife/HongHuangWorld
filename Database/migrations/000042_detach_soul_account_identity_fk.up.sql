BEGIN;
-- Account IDs are issued by the standalone Identity service. The game database
-- keeps the stable UUID on souls but must not require a local credentials row.
ALTER TABLE souls DROP CONSTRAINT IF EXISTS souls_account_id_fkey;
COMMIT;
