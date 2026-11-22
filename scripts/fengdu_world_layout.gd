extends RefCounted
## Canonical, presentation-independent Fengdu layout data.
## Coordinates are in meters in the current city-local X/Z plane.
## Keep gameplay identities and placements here; terrain and building art are replaceable adapters.

const CITY_HALF := 96.0
const MOAT_HALF := 108.0
const WALL_HEIGHT := 13.0
const WALL_THICKNESS := 5.0
const GATE_WIDTH := 16.0
const OUTER_LANDSCAPE_EXTENT := 600.0
const MOAT_WIDTH := 7.0
const MOAT_SURFACE_Y := -0.12
const MOAT_THICKNESS := 0.22
const BRIDGE_CENTER_OFFSET := 7.5
const BRIDGE_LENGTH := 17.0
const BRIDGE_DECK_HEIGHT := 0.45

static func get_city_config() -> Dictionary:
	return {
		"city_half_extent": CITY_HALF,
		"moat_half_extent": MOAT_HALF,
		"wall_height": WALL_HEIGHT,
		"wall_thickness": WALL_THICKNESS,
		"gate_width": GATE_WIDTH,
		"imperial_palace_center": Vector3(0, 0, 72),
		"outer_landscape_extent": OUTER_LANDSCAPE_EXTENT
	}


static func get_gates() -> Array[Dictionary]:
	return [
		{"id": "north_heaven_gate", "name": "北天门", "position": Vector3(0, 0, CITY_HALF), "outward": Vector3(0, 0, 1), "destination": "罗酆山古道"},
		{"id": "south_ghost_gate", "name": "南幽门", "position": Vector3(0, 0, -CITY_HALF), "outward": Vector3(0, 0, -1), "destination": "忘川与轮回渡口"},
		{"id": "east_mystic_gate", "name": "东玄门", "position": Vector3(CITY_HALF, 0, 0), "outward": Vector3(1, 0, 0), "destination": "幽冥荒原远域官道"},
		{"id": "west_dark_gate", "name": "西冥门", "position": Vector3(-CITY_HALF, 0, 0), "outward": Vector3(-1, 0, 0), "destination": "阴司军屯与古战场"}
	]



static func get_roads() -> Array[Dictionary]:
	# Presentation-independent road footprints; surface keys are resolved by the graybox adapter.
	return [
		{"id": "north_south_main_axis", "tier": 1, "center": Vector3(0, 0.03, 0), "size": Vector3(13, 0.12, 190), "surface": "road"},
		{"id": "east_west_main_axis", "tier": 1, "center": Vector3(0, 0.04, 0), "size": Vector3(190, 0.12, 13), "surface": "road"},
		{"id": "central_processional_way", "tier": 1, "center": Vector3(0, 0.06, 38), "size": Vector3(20, 0.14, 100), "surface": "road_edge"},
		{"id": "district_street_west", "tier": 2, "center": Vector3(-34, 0.025, 0), "size": Vector3(6, 0.1, 176), "surface": "road"},
		{"id": "district_street_east", "tier": 2, "center": Vector3(34, 0.025, 0), "size": Vector3(6, 0.1, 176), "surface": "road"},
		{"id": "district_cross_street_south", "tier": 2, "center": Vector3(0, 0.035, -32), "size": Vector3(176, 0.1, 6), "surface": "road"},
		{"id": "district_cross_street_north", "tier": 2, "center": Vector3(0, 0.035, 32), "size": Vector3(176, 0.1, 6), "surface": "road"},
		{"id": "perimeter_lane_south", "tier": 3, "center": Vector3(0, 0.02, -78), "size": Vector3(160, 0.08, 4), "surface": "bridge"},
		{"id": "perimeter_lane_north", "tier": 3, "center": Vector3(0, 0.02, 78), "size": Vector3(160, 0.08, 4), "surface": "bridge"},
		{"id": "palace_approach_west", "tier": "palace", "center": Vector3(-27, 0.035, 34), "size": Vector3(5, 0.1, 90), "surface": "road"},
		{"id": "palace_approach_east", "tier": "palace", "center": Vector3(27, 0.035, 34), "size": Vector3(5, 0.1, 90), "surface": "road"}
	]


static func get_approach_roads() -> Array[Dictionary]:
	return [
		{"id": "north_approach", "center": Vector3(0, 0.02, 151), "size": Vector3(11, 0.12, 72), "surface": "road"},
		{"id": "south_approach", "center": Vector3(0, 0.02, -151), "size": Vector3(11, 0.12, 72), "surface": "road"},
		{"id": "east_approach", "center": Vector3(151, 0.02, 0), "size": Vector3(72, 0.12, 11), "surface": "road"},
		{"id": "west_approach", "center": Vector3(-151, 0.02, 0), "size": Vector3(72, 0.12, 11), "surface": "road"}
	]



static func get_moat_segments() -> Array[Dictionary]:
	var center := MOAT_HALF - MOAT_WIDTH * 0.5
	return [
		{"id": "north_moat", "center": Vector3(0, MOAT_SURFACE_Y, center), "size": Vector3(MOAT_HALF * 2.0, MOAT_THICKNESS, MOAT_WIDTH)},
		{"id": "south_moat", "center": Vector3(0, MOAT_SURFACE_Y, -center), "size": Vector3(MOAT_HALF * 2.0, MOAT_THICKNESS, MOAT_WIDTH)},
		{"id": "east_moat", "center": Vector3(center, MOAT_SURFACE_Y, 0), "size": Vector3(MOAT_WIDTH, MOAT_THICKNESS, MOAT_HALF * 2.0)},
		{"id": "west_moat", "center": Vector3(-center, MOAT_SURFACE_Y, 0), "size": Vector3(MOAT_WIDTH, MOAT_THICKNESS, MOAT_HALF * 2.0)}
	]


static func get_bridges() -> Array[Dictionary]:
	return [
		{"id": "north_bridge", "gate_id": "north_heaven_gate", "center": Vector3(0, 0.12, CITY_HALF + BRIDGE_CENTER_OFFSET), "size": Vector3(GATE_WIDTH, BRIDGE_DECK_HEIGHT, BRIDGE_LENGTH)},
		{"id": "south_bridge", "gate_id": "south_ghost_gate", "center": Vector3(0, 0.12, -CITY_HALF - BRIDGE_CENTER_OFFSET), "size": Vector3(GATE_WIDTH, BRIDGE_DECK_HEIGHT, BRIDGE_LENGTH)},
		{"id": "east_bridge", "gate_id": "east_mystic_gate", "center": Vector3(CITY_HALF + BRIDGE_CENTER_OFFSET, 0.12, 0), "size": Vector3(BRIDGE_LENGTH, BRIDGE_DECK_HEIGHT, GATE_WIDTH)},
		{"id": "west_bridge", "gate_id": "west_dark_gate", "center": Vector3(-CITY_HALF - BRIDGE_CENTER_OFFSET, 0.12, 0), "size": Vector3(BRIDGE_LENGTH, BRIDGE_DECK_HEIGHT, GATE_WIDTH)}
	]


static func get_wall_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var side_length := CITY_HALF * 2.0
	var segment_length := (side_length - GATE_WIDTH) * 0.5
	for z_sign in [-1.0, 1.0]:
		for side_sign in [-1.0, 1.0]:
			var z_side := "north" if z_sign > 0.0 else "south"
			var x_side := "east" if side_sign > 0.0 else "west"
			var x := side_sign * (GATE_WIDTH * 0.5 + segment_length * 0.5)
			result.append({
				"id": "%s_wall_%s" % [z_side, x_side],
				"center": Vector3(x, WALL_HEIGHT * 0.5, z_sign * CITY_HALF),
				"size": Vector3(segment_length, WALL_HEIGHT, WALL_THICKNESS)
			})
			var x_side_name := "east" if z_sign > 0.0 else "west"
			var z_side_name := "north" if side_sign > 0.0 else "south"
			var z := side_sign * (GATE_WIDTH * 0.5 + segment_length * 0.5)
			result.append({
				"id": "%s_wall_%s" % [x_side_name, z_side_name],
				"center": Vector3(z_sign * CITY_HALF, WALL_HEIGHT * 0.5, z),
				"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, segment_length)
			})
	return result


static func get_wall_towers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var x_side := "east" if x_sign > 0.0 else "west"
			var z_side := "north" if z_sign > 0.0 else "south"
			var center := Vector3(x_sign * CITY_HALF, 10.0, z_sign * CITY_HALF)
			result.append({
				"id": "%s_%s_corner_tower" % [z_side, x_side],
				"center": center,
				"size": Vector3(10, 20, 10),
				"roof_center": center + Vector3(0, 10.4, 0),
				"roof_width": 12.0,
				"roof_height": 4.0
			})
	return result


static func get_wall_merlons() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var side_length := CITY_HALF * 2.0
	for side_sign in [-1.0, 1.0]:
		for index in range(1, 8):
			var offset := -CITY_HALF + float(index) * (side_length / 8.0)
			var side_name := "north" if side_sign > 0.0 else "south"
			result.append({
				"id": "%s_wall_merlon_%d" % [side_name, index],
				"center": Vector3(offset, WALL_HEIGHT + 1.1, side_sign * CITY_HALF),
				"size": Vector3(2.0, 2.2, 5.8)
			})
			side_name = "east" if side_sign > 0.0 else "west"
			result.append({
				"id": "%s_wall_merlon_%d" % [side_name, index],
				"center": Vector3(side_sign * CITY_HALF, WALL_HEIGHT + 1.1, offset),
				"size": Vector3(5.8, 2.2, 2.0)
			})
	return result




static func get_market_stalls() -> Array[Dictionary]:
	# Stable stall identity and placement; stall visuals/catalogs remain adapter-owned.
	var market_center := Vector3(55.0, 0.0, -53.0)
	var types := ["魂珠铺", "魂籍铺", "药材铺", "法器铺", "魂器铺", "悬赏交易"]
	var result: Array[Dictionary] = []
	var index := 0
	for side in [-1.0, 1.0]:
		for z in [-6.5, 0.0, 6.5]:
			var stall_type: String = types[index]
			result.append({
				"stall_id": "ghost_market.stall.%02d" % (index + 1),
				"stall_type": stall_type,
				"district": "万魂鬼市",
				"position": market_center + Vector3(side * 10.5, 0.0, z),
				"facing": -side,
				"restock_group": "soul_goods" if index < 2 else ("herb_goods" if index < 4 else ""),
				"open_schedule": "18:00-06:00",
				"presentation_state": "client_visual_only"
			})
			index += 1
	return result


static func get_npc_activity_points() -> Array[Dictionary]:
	# Stable prototype placements; renderers may replace these coordinates after terrain sampling.
	var points: Array[Dictionary] = []
	var market_positions := [
		Vector3(44.5, 0, -59.5), Vector3(44.5, 0, -53.0),
		Vector3(65.5, 0, -53.0), Vector3(65.5, 0, -46.5),
		Vector3(55.0, 0, -63.0), Vector3(55.0, 0, -48.0)
	]
	for i in range(market_positions.size()):
		points.append(_npc_point("ghost_market.merchant.%02d" % (i + 1), "万魂鬼市", "merchant", "trade_idle", market_positions[i], PI * 0.5 if i % 2 == 0 else -PI * 0.5, "night", 1, 1.4))
	var soulward_positions := [
		Vector3(-59, 0, -55), Vector3(-51, 0, -55),
		Vector3(-59, 0, -50), Vector3(-51, 0, -50),
		Vector3(-55, 0, -42.5)
	]
	var resident_routines := ["square_walk", "carry_goods", "well_idle", "home_idle", "tea_social"]
	for i in range(soulward_positions.size()):
		var point := _npc_point("soul_ward.resident.%02d" % (i + 1), "万家魂坊", "resident", "social_idle", soulward_positions[i], atan2(-(Vector3(-55, 0, -53) - soulward_positions[i]).x, -(Vector3(-55, 0, -53) - soulward_positions[i]).z), "day_night", 1, 1.4)
		point["resident_activity"] = resident_routines[i]
		if i < 2:
			point["waypoints"] = [Vector3(-59, 0, -55), Vector3(-51, 0, -55), Vector3(-51, 0, -50), Vector3(-59, 0, -50)]
		points.append(point)
	var soldier_positions := [Vector3(-80, 0, -5.5), Vector3(-74, 0, -5.5), Vector3(-80, 0, 2), Vector3(-74, 0, 2), Vector3(-77, 0, 7)]
	for i in range(soldier_positions.size()):
		points.append(_npc_point("barracks.soldier.%02d" % (i + 1), "阴兵大营", "soldier", "drill", soldier_positions[i], -PI * 0.5, "always", 1, 1.4))
	var guide_positions := [Vector3(75, 0, -9), Vector3(79, 0, -9), Vector3(75, 0, 3), Vector3(79, 0, 3), Vector3(77, 0, 8.5)]
	for i in range(guide_positions.size()):
		points.append(_npc_point("waystation.guide.%02d" % (i + 1), "引魂驿站", "guide", "registration", guide_positions[i], PI * 0.5, "always", 1, 1.4))
	var patrol_positions := [Vector3(-7, 0, 12), Vector3(7, 0, 12), Vector3(0, 0, 3), Vector3(0, 0, 15)]
	for i in range(patrol_positions.size()):
		points.append(_npc_point("patrol_office.guard.%02d" % (i + 1), "巡城司", "patrol_guard", "patrol_watch", patrol_positions[i], PI if i % 2 == 0 else 0.0, "always", 1, 1.4))
	var queue_positions := [Vector3(77, 0, -6), Vector3(77, 0, -3.5), Vector3(77, 0, -1)]
	for i in range(queue_positions.size()):
		points.append(_npc_point("waystation.waiting_soul.%02d" % (i + 1), "引魂驿站", "waiting_soul", "queue_wait", queue_positions[i], PI, "always", 1, 0.8))
	return points


static func get_patrol_routes() -> Array[Dictionary]:
	var node_positions := [
		Vector3(0, 0, 12), Vector3(0, 0, 32), Vector3(0, 0, 78),
		Vector3(34, 0, 78), Vector3(34, 0, 32), Vector3(34, 0, -32),
		Vector3(34, 0, -78), Vector3(0, 0, -78), Vector3(-34, 0, -78),
		Vector3(-34, 0, -32), Vector3(-34, 0, 32), Vector3(-34, 0, 78),
		Vector3(0, 0, 78), Vector3(0, 0, 32), Vector3(0, 0, 12)
	]
	var node_ids: Array[String] = []
	for i in range(node_positions.size()):
		node_ids.append("patrol.route.node.%02d" % (i + 1))
	return [{
		"route_id": "fengdu.patrol.perimeter_loop",
		"district": "巡城司",
		"role": "patrol_guard",
		"node_ids": node_ids,
		"nodes": node_positions,
		"schedule_tag": "night",
		"client_visual_only": true
	}]


static func _npc_point(point_id: String, district: String, role: String, activity: String, position: Vector3, facing: float, schedule_tag: String, capacity: int, radius: float) -> Dictionary:
	return {
		"point_id": point_id,
		"district": district,
		"role": role,
		"activity": activity,
		"position": position,
		"facing": facing,
		"schedule_tag": schedule_tag,
		"capacity": capacity,
		"radius": radius
	}


static func get_districts() -> Array[Dictionary]:
	return [
		{"id": "soul_ward", "name": "万家魂坊", "center": Vector3(-55, 0, -53), "footprint": Vector2(34, 26), "subtitle": "居住 · 工匠 · 社区", "building_count": 5, "accent": "#a9b9c4"},
		{"id": "ghost_market", "name": "万魂鬼市", "center": Vector3(55, 0, -53), "footprint": Vector2(34, 26), "subtitle": "交易 · 拍卖 · 情报", "building_count": 6, "accent": "#d7b47b"},
		{"id": "soul_registry", "name": "鬼籍司", "center": Vector3(-52, 0, 4), "footprint": Vector2(27, 24), "subtitle": "新魂登记 · 身份凭籍", "building_count": 4, "accent": "#9cb8c8"},
		{"id": "merit_bureau", "name": "功过司", "center": Vector3(52, 0, 4), "footprint": Vector2(27, 24), "subtitle": "功德 · 罪业 · 因果", "building_count": 4, "accent": "#c4b28e"},
		{"id": "ten_kings_court", "name": "十王府", "center": Vector3(-51, 0, 48), "footprint": Vector2(30, 23), "subtitle": "十殿审判 · 刑狱协调", "building_count": 5, "accent": "#b9a4a4"},
		{"id": "judge_bureau", "name": "判官司", "center": Vector3(51, 0, 48), "footprint": Vector2(30, 23), "subtitle": "案卷复核 · 司法文书", "building_count": 5, "accent": "#b9a4a4"},
		{"id": "patrol_office", "name": "巡城司", "center": Vector3(0, 0, 12), "footprint": Vector2(23, 20), "subtitle": "治安 · 巡逻 · 夜禁", "building_count": 4, "accent": "#a5b2c0"},
		{"id": "reincarnation_bureau", "name": "轮回司", "center": Vector3(0, 0, -68), "footprint": Vector2(32, 20), "subtitle": "轮回文牒 · 忘川通道", "building_count": 5, "accent": "#b6a5d0"},
		{"id": "barracks", "name": "阴兵大营", "center": Vector3(-77, 0, 0), "footprint": Vector2(18, 27), "subtitle": "城防 · 军需 · 驻军", "building_count": 3, "accent": "#9ba6b2"},
		{"id": "waystation", "name": "引魂驿站", "center": Vector3(77, 0, 0), "footprint": Vector2(18, 27), "subtitle": "接引 · 分流 · 远途驿传", "building_count": 3, "accent": "#a8b7c3"}
	]
