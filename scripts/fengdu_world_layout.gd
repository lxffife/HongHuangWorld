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
