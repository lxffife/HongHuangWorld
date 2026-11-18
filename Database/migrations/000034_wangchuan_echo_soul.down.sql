BEGIN;
-- Preserve historical absorption rows: the kind is referenced by the audit ledger.
UPDATE soul_absorption_kinds
SET enabled=FALSE
WHERE id='wangchuan_echo_wisp';
COMMIT;
