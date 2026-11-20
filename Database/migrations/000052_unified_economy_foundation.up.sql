BEGIN;

CREATE TABLE currency_definitions (
    id VARCHAR(64) PRIMARY KEY,
    display_name VARCHAR(64) NOT NULL,
    symbol VARCHAR(16) NOT NULL DEFAULT '',
    currency_class VARCHAR(24) NOT NULL CHECK (currency_class IN ('fiat', 'cultivation', 'origin')),
    home_world_id VARCHAR(64),
    energy_element VARCHAR(32) NOT NULL DEFAULT 'none',
    quality_grade SMALLINT NOT NULL DEFAULT 1 CHECK (quality_grade BETWEEN 1 AND 9),
    cultivation_usable BOOLEAN NOT NULL DEFAULT FALSE,
    tradeable BOOLEAN NOT NULL DEFAULT TRUE,
    cross_world_exchangeable BOOLEAN NOT NULL DEFAULT TRUE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    description TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((currency_class = 'fiat' AND cultivation_usable = FALSE) OR currency_class <> 'fiat')
);
CREATE INDEX idx_currency_definitions_world ON currency_definitions(home_world_id, enabled);

CREATE TABLE currency_world_rules (
    world_id VARCHAR(64) NOT NULL,
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    issue_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    exchange_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    unlock_key VARCHAR(96) NOT NULL DEFAULT 'world_entry',
    PRIMARY KEY (world_id, currency_id)
);
CREATE UNIQUE INDEX uq_currency_world_primary ON currency_world_rules(world_id) WHERE is_primary;

CREATE TABLE currency_balances (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    available_amount BIGINT NOT NULL DEFAULT 0 CHECK (available_amount >= 0),
    frozen_amount BIGINT NOT NULL DEFAULT 0 CHECK (frozen_amount >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, currency_id)
);
CREATE INDEX idx_currency_balances_currency ON currency_balances(currency_id, available_amount DESC);

CREATE TABLE economy_ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id),
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    event_key VARCHAR(128) NOT NULL,
    entry_type VARCHAR(32) NOT NULL CHECK (entry_type IN (
        'grant', 'spend', 'trade', 'cultivation', 'craft', 'exchange_in', 'exchange_out',
        'escrow_lock', 'escrow_release', 'system_adjustment'
    )),
    delta BIGINT NOT NULL CHECK (delta <> 0),
    available_after BIGINT NOT NULL CHECK (available_after >= 0),
    frozen_delta BIGINT NOT NULL DEFAULT 0,
    frozen_after BIGINT NOT NULL DEFAULT 0 CHECK (frozen_after >= 0),
    source_type VARCHAR(32) NOT NULL DEFAULT '',
    source_id VARCHAR(128) NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, event_key)
);
CREATE INDEX idx_economy_ledger_account_time ON economy_ledger_entries(account_id, created_at DESC);
CREATE INDEX idx_economy_ledger_source ON economy_ledger_entries(source_type, source_id);

CREATE TABLE economy_escrows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id),
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    reference_type VARCHAR(32) NOT NULL,
    reference_id VARCHAR(128) NOT NULL,
    amount BIGINT NOT NULL CHECK (amount > 0),
    status VARCHAR(16) NOT NULL DEFAULT 'locked' CHECK (status IN ('locked', 'released', 'refunded')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (reference_type, reference_id)
);
CREATE INDEX idx_economy_escrows_account ON economy_escrows(account_id, status);

CREATE TABLE currency_cultivation_affinities (
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    target_tag VARCHAR(96) NOT NULL,
    efficiency_bp INTEGER NOT NULL CHECK (efficiency_bp BETWEEN 0 AND 20000),
    min_quality_grade SMALLINT NOT NULL DEFAULT 1 CHECK (min_quality_grade BETWEEN 1 AND 9),
    PRIMARY KEY (currency_id, target_tag)
);

CREATE TABLE currency_cultivation_costs (
    action_key VARCHAR(96) NOT NULL,
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    amount_per_unit BIGINT NOT NULL CHECK (amount_per_unit > 0),
    PRIMARY KEY (action_key, currency_id)
);

INSERT INTO currency_cultivation_affinities (currency_id, target_tag, efficiency_bp)
VALUES
('spirit_stone', 'all', 10000),
('nether_stone', 'all', 5000),
('nether_stone', 'race:ghost', 10000),
('demon_stone', 'all', 4000),
('demon_stone', 'race:demon', 10000),
('monster_stone', 'all', 5000),
('monster_stone', 'race:monster', 10000),
('immortal_crystal', 'all', 8000),
('immortal_crystal', 'realm:immortal', 10000),
('buddhist_crystal', 'all', 5000),
('buddhist_crystal', 'path:buddhist', 10000),
('dragon_crystal', 'all', 5000),
('dragon_crystal', 'race:dragon', 10000),
('witch_crystal', 'all', 5000),
('witch_crystal', 'race:witch', 10000)
ON CONFLICT (currency_id, target_tag) DO NOTHING;

CREATE TABLE currency_exchange_pairs (
    from_currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    to_currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    official_rate_numerator BIGINT NOT NULL CHECK (official_rate_numerator > 0),
    official_rate_denominator BIGINT NOT NULL CHECK (official_rate_denominator > 0),
    market_min_deviation_bp INTEGER NOT NULL DEFAULT 1500 CHECK (market_min_deviation_bp BETWEEN 0 AND 10000),
    market_max_deviation_bp INTEGER NOT NULL DEFAULT 3000 CHECK (market_max_deviation_bp BETWEEN 0 AND 10000),
    fee_bp INTEGER NOT NULL DEFAULT 100 CHECK (fee_bp BETWEEN 0 AND 3000),
    unlock_key VARCHAR(96) NOT NULL DEFAULT 'cross_world_trade',
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (from_currency_id, to_currency_id),
    CHECK (from_currency_id <> to_currency_id),
    CHECK (market_min_deviation_bp <= market_max_deviation_bp)
);

CREATE TABLE currency_exchange_reserves (
    world_id VARCHAR(64) NOT NULL,
    currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    available_amount BIGINT NOT NULL DEFAULT 0 CHECK (available_amount >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (world_id, currency_id)
);

CREATE TABLE currency_market_quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    to_currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    rate_numerator BIGINT NOT NULL CHECK (rate_numerator > 0),
    rate_denominator BIGINT NOT NULL CHECK (rate_denominator > 0),
    volume_24h BIGINT NOT NULL DEFAULT 0 CHECK (volume_24h >= 0),
    source VARCHAR(24) NOT NULL DEFAULT 'market',
    quoted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    CHECK (from_currency_id <> to_currency_id)
);
CREATE INDEX idx_currency_market_quotes_pair_time ON currency_market_quotes(from_currency_id, to_currency_id, quoted_at DESC);

CREATE TABLE currency_exchange_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES accounts(id),
    event_key VARCHAR(128) NOT NULL,
    from_currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    to_currency_id VARCHAR(64) NOT NULL REFERENCES currency_definitions(id),
    from_amount BIGINT NOT NULL CHECK (from_amount > 0),
    to_amount BIGINT NOT NULL CHECK (to_amount > 0),
    fee_amount BIGINT NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
    rate_numerator BIGINT NOT NULL CHECK (rate_numerator > 0),
    rate_denominator BIGINT NOT NULL CHECK (rate_denominator > 0),
    rate_source VARCHAR(16) NOT NULL CHECK (rate_source IN ('official', 'market')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, event_key)
);

CREATE TABLE account_world_economy_unlocks (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    world_id VARCHAR(64) NOT NULL,
    unlock_key VARCHAR(96) NOT NULL,
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_type VARCHAR(32) NOT NULL DEFAULT 'progression',
    source_id VARCHAR(128) NOT NULL DEFAULT '',
    PRIMARY KEY (account_id, world_id, unlock_key)
);

INSERT INTO currency_definitions
(id, display_name, symbol, currency_class, home_world_id, energy_element, quality_grade, cultivation_usable, tradeable, cross_world_exchangeable, description)
VALUES
('human_gold', '金币', '金', 'fiat', 'qingyun_human', 'none', 1, FALSE, TRUE, TRUE, '人间界通用凡俗货币'),
('human_silver', '银币', '银', 'fiat', 'qingyun_human', 'none', 1, FALSE, TRUE, TRUE, '人间界常用辅币'),
('human_copper', '铜钱', '文', 'fiat', 'qingyun_human', 'none', 1, FALSE, TRUE, TRUE, '人间界日常小额货币'),
('ghost_cash', '冥钱', '冥', 'fiat', 'underworld_fengdu', 'none', 1, FALSE, TRUE, TRUE, '幽冥界凡俗交易货币，不可直接用于修炼'),
('nether_stone', '冥石', '冥石', 'cultivation', 'underworld_fengdu', 'nether', 1, TRUE, TRUE, TRUE, '蕴含幽冥之气，可交易、修炼、炼器与布阵'),
('demon_coin', '魔币', '魔', 'fiat', 'myriad_demon', 'none', 1, FALSE, TRUE, TRUE, '魔界凡俗交易货币，不可直接用于修炼'),
('demon_stone', '魔石', '魔石', 'cultivation', 'myriad_demon', 'demonic', 1, TRUE, TRUE, TRUE, '蕴含魔气，可交易、修炼、炼器与布阵'),
('spirit_stone', '灵石', '灵石', 'cultivation', NULL, 'spiritual', 1, TRUE, TRUE, TRUE, '通用灵气修炼资源，可在具备兑换渠道的世界流通'),
('monster_coin', '妖币', '妖', 'fiat', NULL, 'none', 1, FALSE, TRUE, TRUE, '妖界凡俗交易货币'),
('monster_stone', '妖石', '妖石', 'cultivation', NULL, 'demonic_nature', 1, TRUE, TRUE, TRUE, '蕴含妖气，可交易、修炼与炼器'),
('immortal_coin', '仙钱', '仙', 'fiat', NULL, 'none', 1, FALSE, TRUE, TRUE, '仙界凡俗交易货币'),
('immortal_crystal', '仙晶', '仙晶', 'cultivation', NULL, 'immortal', 1, TRUE, TRUE, TRUE, '蕴含仙灵之气的高阶修炼资源'),
('buddhist_crystal', '佛晶', '佛晶', 'cultivation', NULL, 'buddhist', 1, TRUE, TRUE, TRUE, '蕴含佛力与愿力的修炼资源'),
('dragon_crystal', '龙晶', '龙晶', 'cultivation', NULL, 'dragon', 1, TRUE, TRUE, TRUE, '蕴含龙族血脉本源的修炼资源'),
('witch_crystal', '巫晶', '巫晶', 'cultivation', NULL, 'bloodline', 1, TRUE, TRUE, TRUE, '蕴含气血与巫力的修炼资源'),
('world_origin_crystal', '世界本源晶', '源晶', 'origin', NULL, 'world_origin', 5, TRUE, FALSE, FALSE, '世界本源战略资源，默认不可自由兑换'),
('heavenly_rule_shard', '天道碎晶', '道碎', 'origin', NULL, 'heavenly_rule', 7, TRUE, FALSE, FALSE, '蕴含规则碎片的稀有战略资源'),
('chaos_origin_crystal', '混沌源晶', '混沌', 'origin', NULL, 'chaos', 9, TRUE, FALSE, FALSE, '蕴含混沌本源的极稀有战略资源')
ON CONFLICT (id) DO NOTHING;

INSERT INTO currency_world_rules (world_id, currency_id, is_primary, unlock_key)
VALUES
('qingyun_human', 'human_gold', TRUE, 'world_entry'),
('qingyun_human', 'human_silver', FALSE, 'world_entry'),
('qingyun_human', 'human_copper', FALSE, 'world_entry'),
('qingyun_human', 'spirit_stone', FALSE, 'cultivation_access'),
('underworld_fengdu', 'ghost_cash', TRUE, 'world_entry'),
('underworld_fengdu', 'nether_stone', FALSE, 'cultivation_access'),
('underworld_fengdu', 'spirit_stone', FALSE, 'cross_world_trade'),
('myriad_demon', 'demon_coin', TRUE, 'world_entry'),
('myriad_demon', 'demon_stone', FALSE, 'cultivation_access'),
('myriad_demon', 'spirit_stone', FALSE, 'cross_world_trade')
ON CONFLICT (world_id, currency_id) DO NOTHING;

INSERT INTO currency_exchange_pairs
(from_currency_id, to_currency_id, official_rate_numerator, official_rate_denominator, market_min_deviation_bp, market_max_deviation_bp, fee_bp, unlock_key)
VALUES
('nether_stone', 'spirit_stone', 4, 5, 500, 2500, 100, 'cross_world_trade'),
('spirit_stone', 'nether_stone', 5, 4, 500, 2500, 100, 'cross_world_trade'),
('demon_stone', 'spirit_stone', 3, 4, 500, 3000, 120, 'cross_world_trade'),
('spirit_stone', 'demon_stone', 4, 3, 500, 3000, 120, 'cross_world_trade'),
('human_gold', 'ghost_cash', 1, 1, 1000, 3500, 200, 'cross_world_trade'),
('ghost_cash', 'human_gold', 1, 1, 1000, 3500, 200, 'cross_world_trade')
ON CONFLICT (from_currency_id, to_currency_id) DO NOTHING;

COMMIT;
