BEGIN;

-- North/south inner gate sentry patrol. Coordinates follow the authored
-- Fengdu city preview: the south gate is centered at (0, 0, 36).
INSERT INTO world_npc_definitions
    (id,world_id,name,title,npc_type,interaction_type,
     position_x,position_y,position_z,rotation_y,interaction_radius,dialogue)
VALUES
    ('fengdu_south_gate_guard','underworld_fengdu','鬼门关阴兵','南城门守备','guard','world_guard',
     0,0,31.0,3.14159,4.5,
     '{"greeting":"止步。此处乃酆都南门，出入城门须遵守阴司法度。","topics":["城门巡防由阴司统领调度。","血海在酆都之外，切勿将荒原当作城内街巷。"]}'::jsonb),
    ('fengdu_ghost_market_vendor_west','underworld_fengdu','纸钱铺掌柜','鬼市 · 西市摊','guide','dialogue',
     -25,0,18,0,3.8,
     '{"greeting":"客官，纸钱、香烛、引路符都备着呢。","topics":["鬼市摊位会逐步开放更多商品。","真正的购买与库存扣减由中心服结算。"]}'::jsonb),
    ('fengdu_ghost_market_vendor_east','underworld_fengdu','魂灯摊主','鬼市 · 东市摊','guide','dialogue',
     -16,0,27,3.14159,3.8,
     '{"greeting":"魂灯照归途，夜行莫迷路。要挑一盏吗？","topics":["魂灯用于标记幽冥道路与安全区域。","商品价格和库存以中心服数据为准。"]}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    world_id=EXCLUDED.world_id,
    name=EXCLUDED.name,
    title=EXCLUDED.title,
    npc_type=EXCLUDED.npc_type,
    interaction_type=EXCLUDED.interaction_type,
    position_x=EXCLUDED.position_x,
    position_y=EXCLUDED.position_y,
    position_z=EXCLUDED.position_z,
    rotation_y=EXCLUDED.rotation_y,
    interaction_radius=EXCLUDED.interaction_radius,
    dialogue=EXCLUDED.dialogue,
    enabled=TRUE,
    updated_at=now();

UPDATE world_npc_definitions
SET behavior_profile='guard_patrol',
    patrol_route='{
      "waypoints": [
        {"x": -5.0, "y": 0.0, "z": 30.0, "wait_seconds": 3.0},
        {"x": 5.0, "y": 0.0, "z": 30.0, "wait_seconds": 2.0},
        {"x": 5.0, "y": 0.0, "z": 34.0, "wait_seconds": 3.0},
        {"x": -5.0, "y": 0.0, "z": 34.0, "wait_seconds": 2.0}
      ],
      "speed_mps": 0.95,
      "default_wait_seconds": 2.0,
      "phase_offset_seconds": 7.0,
      "loop": true
    }'::jsonb,
    updated_at=now()
WHERE id='fengdu_south_gate_guard'
  AND world_id='underworld_fengdu';

COMMIT;
