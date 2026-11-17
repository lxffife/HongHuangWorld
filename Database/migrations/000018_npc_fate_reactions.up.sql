BEGIN;

-- Fate reactions are authored as NPC dialogue data. The center service selects
-- the response using the current body's immutable fate trait; clients never
-- calculate or submit a trait.
UPDATE world_npc_definitions
SET dialogue = dialogue || jsonb_build_object(
    'fate_reactions',
    jsonb_build_object(
        'blessed_fate', '判官翻阅因果簿，见你功德有光，语气稍缓：此世仍有善缘可续。',
        'karmic_shadow', '判官目光落在你的命格印记上：业障随身，此世行事更须谨慎。',
        'entangled_fate', '判官凝视命格：福祸纠缠，善恶一念之间，因果尚未定局。',
        'unmarked_fate', '判官合上因果簿：命格未显，且看你今生如何落笔。'
    )
), updated_at = now()
WHERE id = 'fengdu_judge';

UPDATE world_npc_definitions
SET dialogue = dialogue || jsonb_build_object(
    'fate_reactions',
    jsonb_build_object(
        'blessed_fate', '孟婆含笑递来汤盏：你身有福缘，愿这份善念伴你走过新生。',
        'karmic_shadow', '孟婆轻叹：旧业未消，莫让执念再结新因。',
        'entangled_fate', '孟婆望向忘川：福祸相依，下一世的路要由你自己走出来。',
        'unmarked_fate', '孟婆轻声道：命数尚未显露，且把今生当作新的开始。'
    )
), updated_at = now()
WHERE id = 'fengdu_mengpo';

COMMIT;
