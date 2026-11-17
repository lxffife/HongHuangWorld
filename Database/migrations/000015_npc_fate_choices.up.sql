BEGIN;

-- A soul may resolve each authored NPC moral choice only once. This prevents
-- clients from farming fate by replaying the request with fresh event IDs.
CREATE TABLE soul_fate_choice_claims (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    soul_id UUID NOT NULL REFERENCES souls(id) ON DELETE CASCADE,
    npc_id VARCHAR(64) NOT NULL REFERENCES world_npc_definitions(id) ON DELETE CASCADE,
    choice_id VARCHAR(64) NOT NULL,
    fate_event_id UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (soul_id, npc_id, choice_id)
);

CREATE INDEX idx_soul_fate_choice_claims_soul
    ON soul_fate_choice_claims(soul_id, created_at DESC);

-- The Judge's first branching encounter is intentionally small and data-driven.
-- Effect keys are resolved by trusted backend code; no deltas are sent by clients.
UPDATE world_npc_definitions
SET dialogue = jsonb_set(
    dialogue,
    '{choices}',
    '[
      {"id":"review_evidence","text":"复核证词，还亡魂清白","description":"你决定查明真相，不让无辜者蒙冤。","effect_key":"judge_mercy","result":"判官翻阅卷宗，确认亡魂无罪。此举记入你的功德簿。"},
      {"id":"accept_bribe","text":"收下贿赂，草草定罪","description":"你选择以私利换取一时便利。","effect_key":"judge_corruption","result":"判官冷冷合上卷宗。此事已记入你的因果簿。"}
    ]'::jsonb,
    TRUE
),
updated_at = now()
WHERE id = 'fengdu_judge';

COMMIT;
