BEGIN;

-- Monster kill currency is issued only by authenticated world-server reward
-- events. The limits are per account, currency and source type.
INSERT INTO currency_issuance_policies
(world_id, currency_id, source_type, max_per_event, daily_cap, requires_trusted_server, enabled)
VALUES
('underworld_fengdu', 'ghost_cash', 'monster_kill', 2000, 50000, TRUE, TRUE),
('underworld_fengdu', 'nether_stone', 'monster_kill', 5, 200, TRUE, TRUE)
ON CONFLICT (world_id, currency_id, source_type) DO UPDATE
SET max_per_event = EXCLUDED.max_per_event,
    daily_cap = EXCLUDED.daily_cap,
    requires_trusted_server = TRUE,
    enabled = TRUE;

-- Nether stones are now earnable from elite monster kills even before the
-- character unlocks their direct cultivation use.
UPDATE currency_world_rules
SET issue_enabled = TRUE
WHERE world_id = 'underworld_fengdu' AND currency_id = 'nether_stone';

COMMIT;
