BEGIN;

-- A soul may discover each authored hidden encounter only once, even across
-- reincarnations or retries. Rewards are committed with the immutable ledger.
CREATE TABLE soul_fate_encounter_claims (
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    encounter_id VARCHAR(64) NOT NULL,
    npc_id VARCHAR(64) NOT NULL REFERENCES world_npc_definitions(id),
    fate_event_id UUID NOT NULL DEFAULT gen_random_uuid(),
    claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (soul_id, encounter_id),
    UNIQUE (fate_event_id)
);

UPDATE world_npc_definitions
SET dialogue = dialogue || jsonb_build_object(
    'fate_encounters',
    jsonb_build_object(
        'blessed_fate', jsonb_build_object(
            'id', 'mengpo_blessed_lotus',
            'title', '忘川净莲',
            'description', '孟婆从忘川水中取出一枚净莲花瓣。你的福缘令它重现生机，灵魂因这份善缘获得了额外功德。',
            'merit_delta', 2,
            'karma_delta', 0
        ),
        'karmic_shadow', jsonb_build_object(
            'id', 'mengpo_karmic_lantern',
            'title', '业火引灯',
            'description', '一盏幽灯映出你未偿的旧业。你主动承认过往因果，业力因此消减。',
            'merit_delta', 1,
            'karma_delta', -2
        ),
        'entangled_fate', jsonb_build_object(
            'id', 'mengpo_entangled_ferry',
            'title', '双生渡舟',
            'description', '忘川边出现一叶双生渡舟。福祸纠缠的命格令你看见两条命运交汇的航道，因果稍得澄清。',
            'merit_delta', 2,
            'karma_delta', -1
        ),
        'unmarked_fate', jsonb_build_object(
            'id', 'mengpo_unmarked_lotus',
            'title', '无名莲种',
            'description', '孟婆赠你一枚尚未发芽的莲种。命格未定，善缘从此刻开始。',
            'merit_delta', 1,
            'karma_delta', 0
        )
    )
), updated_at = now()
WHERE id = 'fengdu_mengpo';

COMMIT;
