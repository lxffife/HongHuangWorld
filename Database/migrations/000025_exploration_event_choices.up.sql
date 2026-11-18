BEGIN;

-- Authored branch choices are public narrative metadata. The backend maps
-- effect_key to trusted reward rules; clients only submit a choice identifier.
ALTER TABLE world_exploration_events
    ADD COLUMN choices JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE world_exploration_events SET choices = '[
  {"id":"keep_soul_flame","text":"留下魂灯，照亮后来者","description":"你愿意让这盏灯继续为迷途新魂指路。","result":"魂灯火光稳定下来，灯芯深处留下你的善念。","effect_key":"lantern_keep"},
  {"id":"take_soul_flame","text":"收取灯火，追寻自己的来路","description":"你将灯火收于掌心，试图从中寻找自己的前尘。","result":"灯火映出一缕旧影，你得到线索，也沾染了些许执念。","effect_key":"lantern_take"}
]'::jsonb WHERE id='fengdu_lantern_memory';

UPDATE world_exploration_events SET choices = '[
  {"id":"accept_memory","text":"接纳回音，记住这段前尘","description":"你选择正视记忆，不让它被河水彻底吞没。","result":"回音化作清晰的心念，你从中获得了力量。","effect_key":"river_accept"},
  {"id":"release_memory","text":"放下回音，让往事归于忘川","description":"你不再追问过去，任由回音随水远去。","result":"心境暂时轻松下来，但一丝遗憾仍留在心底。","effect_key":"river_release"}
]'::jsonb WHERE id='wangchuan_past_echo';

UPDATE world_exploration_events SET choices = '[
  {"id":"honor_old_oath","text":"修复誓纹，承接引渡之责","description":"你愿意承担古誓留下的责任。","result":"古誓重新亮起，一缕沉寂的善念回应了你。","effect_key":"bridge_honor"},
  {"id":"break_old_oath","text":"斩断旧誓，不受前人约束","description":"你决定不让古老誓约束缚自己的轮回。","result":"誓纹碎裂，你挣脱了旧约，却留下新的因果。","effect_key":"bridge_break"}
]'::jsonb WHERE id='naihe_bridge_ancient_oath';

UPDATE world_exploration_events SET choices = '[
  {"id":"record_truth","text":"如实刻录碑文，留给后来者","description":"你选择保存轮回秩序的真相。","result":"碑文补全了一角，后来者将能读到这段真相。","effect_key":"tablet_record"},
  {"id":"conceal_truth","text":"抹去隐秘文字，守住轮回秘密","description":"你认为有些真相不应轻易示人。","result":"碑文重归沉寂，秘密暂时被封存。","effect_key":"tablet_conceal"}
]'::jsonb WHERE id='reincarnation_hall_cycle';

COMMIT;
