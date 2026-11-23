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


static func get_local_connectors() -> Array[Dictionary]:
	# Short paved links connect district gates to the existing tier-2 and palace roads.
	return [
		{"id": "connector_soulward", "center": Vector3(-44.5, 0.035, -66.0), "size": Vector3(21.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_ghost_market", "center": Vector3(44.5, 0.035, -66.0), "size": Vector3(21.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_soul_registry", "center": Vector3(-43.0, 0.035, -8.0), "size": Vector3(18.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_merit_bureau", "center": Vector3(43.0, 0.035, -8.0), "size": Vector3(18.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_ten_kings", "center": Vector3(-39.0, 0.035, 36.5), "size": Vector3(24.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_judge_bureau", "center": Vector3(39.0, 0.035, 36.5), "size": Vector3(24.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_barracks", "center": Vector3(-55.5, 0.035, -13.5), "size": Vector3(43.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_waystation", "center": Vector3(55.5, 0.035, -13.5), "size": Vector3(43.0, 0.1, 4.5), "surface": "road"},
		{"id": "connector_reincarnation", "center": Vector3(0.0, 0.035, -55.0), "size": Vector3(4.5, 0.1, 46.0), "surface": "road"}
	]


static func get_navigation_network() -> Dictionary:
	# Stable topology; positions are city-local meters and can be remapped to NavigationServer later.
	return {
		"nodes": [
			{"id": "gate.north", "position": Vector3(0, 0, 96), "kind": "city_gate"},
			{"id": "gate.south", "position": Vector3(0, 0, -96), "kind": "city_gate"},
			{"id": "gate.east", "position": Vector3(96, 0, 0), "kind": "city_gate"},
			{"id": "gate.west", "position": Vector3(-96, 0, 0), "kind": "city_gate"},
			{"id": "junction.center", "position": Vector3(0, 0, 0), "kind": "junction"},
			{"id": "junction.north", "position": Vector3(0, 0, 32), "kind": "junction"},
			{"id": "junction.south", "position": Vector3(0, 0, -32), "kind": "junction"},
			{"id": "junction.west", "position": Vector3(-34, 0, 0), "kind": "junction"},
			{"id": "junction.east", "position": Vector3(34, 0, 0), "kind": "junction"},
			{"id": "junction.west.north", "position": Vector3(-34, 0, 32), "kind": "junction"},
			{"id": "junction.west.south", "position": Vector3(-34, 0, -32), "kind": "junction"},
			{"id": "junction.east.north", "position": Vector3(34, 0, 32), "kind": "junction"},
			{"id": "junction.east.south", "position": Vector3(34, 0, -32), "kind": "junction"},
			{"id": "junction.west.far_south", "position": Vector3(-34, 0, -66), "kind": "junction"},
			{"id": "junction.east.far_south", "position": Vector3(34, 0, -66), "kind": "junction"},
			{"id": "junction.west.registry", "position": Vector3(-34, 0, -8), "kind": "junction"},
			{"id": "junction.east.merit", "position": Vector3(34, 0, -8), "kind": "junction"},
			{"id": "junction.west.service", "position": Vector3(-34, 0, -13.5), "kind": "junction"},
			{"id": "junction.east.service", "position": Vector3(34, 0, -13.5), "kind": "junction"},
			{"id": "junction.palace.west", "position": Vector3(-27, 0, 32), "kind": "junction"},
			{"id": "junction.palace.east", "position": Vector3(27, 0, 32), "kind": "junction"},
			{"id": "junction.ten_kings.connector", "position": Vector3(-27, 0, 36.5), "kind": "junction"},
			{"id": "junction.judge.connector", "position": Vector3(27, 0, 36.5), "kind": "junction"},
			{"id": "district.soul_ward.entry", "position": Vector3(-55, 0, -66), "kind": "district_entry"},
			{"id": "district.ghost_market.entry", "position": Vector3(55, 0, -66), "kind": "district_entry"},
			{"id": "district.soul_registry.entry", "position": Vector3(-52, 0, -8), "kind": "district_entry"},
			{"id": "district.merit_bureau.entry", "position": Vector3(52, 0, -8), "kind": "district_entry"},
			{"id": "district.ten_kings.entry", "position": Vector3(-51, 0, 36.5), "kind": "district_entry"},
			{"id": "district.judge_bureau.entry", "position": Vector3(51, 0, 36.5), "kind": "district_entry"},
			{"id": "district.patrol_office.entry", "position": Vector3(0, 0, 2), "kind": "district_entry"},
			{"id": "district.reincarnation.entry", "position": Vector3(0, 0, -78), "kind": "district_entry"},
			{"id": "district.barracks.entry", "position": Vector3(-77, 0, -13.5), "kind": "district_entry"},
			{"id": "district.waystation.entry", "position": Vector3(77, 0, -13.5), "kind": "district_entry"},
			{"id": "patrol.route.south_gate", "position": Vector3(0, 0, 12), "kind": "patrol_waypoint"},
			{"id": "patrol.route.north_west", "position": Vector3(0, 0, 78), "kind": "patrol_waypoint"},
			{"id": "patrol.route.east_north", "position": Vector3(34, 0, 78), "kind": "patrol_waypoint"},
			{"id": "patrol.route.east_south", "position": Vector3(34, 0, -78), "kind": "patrol_waypoint"},
			{"id": "patrol.route.west_south", "position": Vector3(-34, 0, -78), "kind": "patrol_waypoint"},
			{"id": "patrol.route.west_north", "position": Vector3(-34, 0, 78), "kind": "patrol_waypoint"}
		],
		"edges": [
			{"id": "road.gate.north", "from": "gate.north", "to": "junction.north", "width": 11.0, "two_way": true, "gate_id": "north_heaven_gate"},
			{"id": "road.gate.south", "from": "gate.south", "to": "junction.south", "width": 11.0, "two_way": true, "gate_id": "south_ghost_gate"},
			{"id": "road.gate.east", "from": "gate.east", "to": "junction.east", "width": 11.0, "two_way": true, "gate_id": "east_mystic_gate"},
			{"id": "road.gate.west", "from": "gate.west", "to": "junction.west", "width": 11.0, "two_way": true, "gate_id": "west_dark_gate"},
			{"id": "road.axis.north", "from": "junction.north", "to": "junction.center", "width": 13.0, "two_way": true},
			{"id": "road.axis.south", "from": "junction.center", "to": "junction.south", "width": 13.0, "two_way": true},
			{"id": "road.cross.west", "from": "junction.west", "to": "junction.center", "width": 13.0, "two_way": true},
			{"id": "road.cross.east", "from": "junction.center", "to": "junction.east", "width": 13.0, "two_way": true},
			{"id": "road.west.north", "from": "junction.west.north", "to": "junction.north", "width": 6.0, "two_way": true},
			{"id": "road.west.vertical.north", "from": "junction.west", "to": "junction.west.north", "width": 6.0, "two_way": true},
			{"id": "road.east.vertical.north", "from": "junction.east", "to": "junction.east.north", "width": 6.0, "two_way": true},
			{"id": "road.west.south", "from": "junction.west.south", "to": "junction.south", "width": 6.0, "two_way": true},
			{"id": "road.east.north", "from": "junction.north", "to": "junction.east.north", "width": 6.0, "two_way": true},
			{"id": "road.east.south", "from": "junction.south", "to": "junction.east.south", "width": 6.0, "two_way": true},
			{"id": "road.west.south.extension", "from": "junction.west.south", "to": "junction.west.far_south", "width": 6.0, "two_way": true},
			{"id": "road.east.south.extension", "from": "junction.east.south", "to": "junction.east.far_south", "width": 6.0, "two_way": true},
			{"id": "road.west.registry.branch", "from": "junction.west", "to": "junction.west.registry", "width": 6.0, "two_way": true},
			{"id": "road.east.merit.branch", "from": "junction.east", "to": "junction.east.merit", "width": 6.0, "two_way": true},
			{"id": "road.west.service.branch", "from": "junction.west", "to": "junction.west.service", "width": 6.0, "two_way": true},
			{"id": "road.east.service.branch", "from": "junction.east", "to": "junction.east.service", "width": 6.0, "two_way": true},
			{"id": "road.palace.west", "from": "junction.palace.west", "to": "junction.north", "width": 5.0, "two_way": true},
			{"id": "road.palace.east", "from": "junction.north", "to": "junction.palace.east", "width": 5.0, "two_way": true},
			{"id": "road.ten_kings.approach", "from": "junction.palace.west", "to": "junction.ten_kings.connector", "width": 5.0, "two_way": true},
			{"id": "road.judge.approach", "from": "junction.palace.east", "to": "junction.judge.connector", "width": 5.0, "two_way": true},
			{"id": "road.soul_ward.connector", "from": "junction.west.far_south", "to": "district.soul_ward.entry", "width": 4.5, "two_way": true},
			{"id": "road.ghost_market.connector", "from": "junction.east.far_south", "to": "district.ghost_market.entry", "width": 4.5, "two_way": true},
			{"id": "road.soul_registry.connector", "from": "junction.west.registry", "to": "district.soul_registry.entry", "width": 4.5, "two_way": true},
			{"id": "road.merit_bureau.connector", "from": "junction.east.merit", "to": "district.merit_bureau.entry", "width": 4.5, "two_way": true},
			{"id": "road.ten_kings.connector", "from": "junction.ten_kings.connector", "to": "district.ten_kings.entry", "width": 4.5, "two_way": true},
			{"id": "road.judge_bureau.connector", "from": "junction.judge.connector", "to": "district.judge_bureau.entry", "width": 4.5, "two_way": true},
			{"id": "road.patrol_office.connector", "from": "junction.center", "to": "district.patrol_office.entry", "width": 5.0, "two_way": true},
			{"id": "road.reincarnation.connector", "from": "junction.south", "to": "district.reincarnation.entry", "width": 4.5, "two_way": true},
			{"id": "road.barracks.connector", "from": "junction.west.service", "to": "district.barracks.entry", "width": 4.5, "two_way": true},
			{"id": "road.waystation.connector", "from": "junction.east.service", "to": "district.waystation.entry", "width": 4.5, "two_way": true},
			{"id": "patrol.edge.01", "from": "patrol.route.south_gate", "to": "junction.north", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.02", "from": "junction.north", "to": "patrol.route.north_west", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.03", "from": "patrol.route.north_west", "to": "patrol.route.east_north", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.04", "from": "patrol.route.east_north", "to": "junction.east.north", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.05", "from": "junction.east.north", "to": "junction.east.south", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.06", "from": "junction.east.south", "to": "patrol.route.east_south", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.07", "from": "patrol.route.east_south", "to": "district.reincarnation.entry", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.08", "from": "district.reincarnation.entry", "to": "patrol.route.west_south", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.09", "from": "patrol.route.west_south", "to": "junction.west.south", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.10", "from": "junction.west.south", "to": "junction.west.north", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.11", "from": "junction.west.north", "to": "patrol.route.west_north", "width": 6.0, "two_way": true},
			{"id": "patrol.edge.12", "from": "patrol.route.west_north", "to": "patrol.route.north_west", "width": 6.0, "two_way": true},
		],
		"routes": [
			{"id": "route.south_gate_to_reincarnation", "from": "gate.south", "to": "district.reincarnation.entry", "waypoints": ["gate.south", "junction.south", "district.reincarnation.entry"], "purpose": "忘川与轮回方向"},
			{"id": "route.waystation_to_registry", "from": "district.waystation.entry", "to": "district.soul_registry.entry", "waypoints": ["district.waystation.entry", "junction.east.service", "junction.east", "junction.center", "junction.west", "junction.west.registry", "district.soul_registry.entry"], "purpose": "新魂登记"},
			{"id": "route.registry_to_judgment", "from": "district.soul_registry.entry", "to": "district.ten_kings.entry", "waypoints": ["district.soul_registry.entry", "junction.west.registry", "junction.west", "junction.west.north", "junction.north", "junction.palace.west", "junction.ten_kings.connector", "district.ten_kings.entry"], "purpose": "鬼籍核验后进入审判"},
			{"id": "route.registry_to_judge_review", "from": "district.soul_registry.entry", "to": "district.judge_bureau.entry", "waypoints": ["district.soul_registry.entry", "junction.west.registry", "junction.west", "junction.center", "junction.east", "junction.east.north", "junction.north", "junction.palace.east", "junction.judge.connector", "district.judge_bureau.entry"], "purpose": "档案复核与文书交接"},
			{"id": "route.judgment_to_reincarnation", "from": "district.ten_kings.entry", "to": "district.reincarnation.entry", "waypoints": ["district.ten_kings.entry", "junction.ten_kings.connector", "junction.palace.west", "junction.north", "junction.center", "junction.south", "district.reincarnation.entry"], "purpose": "判决后前往轮回司"},
			{"id": "route.patrol.perimeter_loop", "from": "patrol.route.south_gate", "to": "patrol.route.south_gate", "waypoints": ["patrol.route.south_gate", "junction.north", "patrol.route.north_west", "patrol.route.east_north", "junction.east.north", "junction.east.south", "patrol.route.east_south", "district.reincarnation.entry", "patrol.route.west_south", "junction.west.south", "junction.west.north", "patrol.route.west_north", "patrol.route.north_west", "junction.north", "patrol.route.south_gate"], "purpose": "巡城司闭环巡防"}
		]
	}

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





static func get_market_auction_layout() -> Dictionary:
	return {
		"district": "万魂鬼市",
		"dais_offset": Vector3(0.0, 0.55, 8.0),
		"dais_size": Vector3(7.0, 1.1, 4.5),
		"desk_offset": Vector3(0.0, 1.45, 8.0),
		"desk_size": Vector3(4.2, 0.7, 1.2),
		"roof_offset": Vector3(0.0, 3.1, 8.0),
		"roof_width": 8.0,
		"roof_height": 2.0,
		"label_offset": Vector3(0.0, 5.65, 8.0),
		"step_center_offset": Vector3(0.0, 0.0, 0.0),
		"steps": [
			{"point_id": "ghost_market.auction.step.01", "offset": Vector3(0.0, 0.09, 5.48), "size": Vector3(5.2, 0.18, 0.48)},
			{"point_id": "ghost_market.auction.step.02", "offset": Vector3(0.0, 0.18, 5.0), "size": Vector3(4.85, 0.36, 0.48)},
			{"point_id": "ghost_market.auction.step.03", "offset": Vector3(0.0, 0.27, 4.52), "size": Vector3(4.5, 0.54, 0.48)}
		],
		"step_rails": [
			{"point_id": "ghost_market.auction.step_rail.left", "offset": Vector3(-2.92, 0.32, 5.35), "base_size": Vector3(0.24, 0.64, 1.35), "cap_offset": Vector3(0.0, 0.4, 0.0), "cap_size": Vector3(0.38, 0.16, 1.45)},
			{"point_id": "ghost_market.auction.step_rail.right", "offset": Vector3(2.92, 0.32, 5.35), "base_size": Vector3(0.24, 0.64, 1.35), "cap_offset": Vector3(0.0, 0.4, 0.0), "cap_size": Vector3(0.38, 0.16, 1.45)}
		],
		"showcase_orbs": [
			{"point_id": "ghost_market.auction.showcase.01", "offset": Vector3(-1.15, 2.0, 8.0), "radius": 0.18, "tint": "#83c7e4"},
			{"point_id": "ghost_market.auction.showcase.02", "offset": Vector3(0.0, 2.0, 8.0), "radius": 0.22, "tint": "#e8c477"},
			{"point_id": "ghost_market.auction.showcase.03", "offset": Vector3(1.15, 2.0, 8.0), "radius": 0.18, "tint": "#b99bdc"}
		],
		"audience_event_points": [
			{"point_id": "ghost_market.auction.event_guest.01", "offset": Vector3(-10.8, 0.0, 4.2)},
			{"point_id": "ghost_market.auction.event_guest.02", "offset": Vector3(10.8, 0.0, 4.2)},
			{"point_id": "ghost_market.auction.event_guest.03", "offset": Vector3(-10.8, 0.0, 7.2)},
			{"point_id": "ghost_market.auction.event_guest.04", "offset": Vector3(10.8, 0.0, 7.2)}
		],
		"audience_seats": [
			{"point_id": "ghost_market.auction.seat.01", "offset": Vector3(-8.0, 0.0, 5.8), "facing": PI},
			{"point_id": "ghost_market.auction.seat.02", "offset": Vector3(-8.0, 0.0, 9.4), "facing": PI},
			{"point_id": "ghost_market.auction.seat.03", "offset": Vector3(8.0, 0.0, 5.8), "facing": 0.0},
			{"point_id": "ghost_market.auction.seat.04", "offset": Vector3(8.0, 0.0, 9.4), "facing": 0.0}
		],
		"audience_benches": [
			{"point_id": "ghost_market.auction.bench.left", "offset": Vector3(-6.25, 0.0, 7.6), "facing": 1.0},
			{"point_id": "ghost_market.auction.bench.right", "offset": Vector3(6.25, 0.0, 7.6), "facing": -1.0}
		],
		"pedestals": [
			{"point_id": "ghost_market.auction.pedestal.left", "offset": Vector3(-4.95, 0.0, 7.8), "facing": 1.0},
			{"point_id": "ghost_market.auction.pedestal.right", "offset": Vector3(4.95, 0.0, 7.8), "facing": -1.0}
		]
	}


static func get_market_caravans() -> Array[Dictionary]:
	return [
		{
			"caravan_id": "ghost_market.caravan.01",
			"cargo_type": "魂珠与魂籍",
			"cargo_palette": "#8d789e",
			"offset": Vector3(-15.3, 0.0, -7.0),
			"facing": PI,
			"route_offsets": [Vector3(0.0, 0.0, -5.0), Vector3.ZERO, Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -5.0)],
			"restock_stall_id": "ghost_market.stall.01",
			"phase": 0.0
		},
		{
			"caravan_id": "ghost_market.caravan.02",
			"cargo_type": "药材与法器",
			"cargo_palette": "#718d70",
			"offset": Vector3(15.3, 0.0, 7.0),
			"facing": 0.0,
			"route_offsets": [Vector3(0.0, 0.0, -5.0), Vector3.ZERO, Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -5.0)],
			"restock_stall_id": "ghost_market.stall.03",
			"phase": 17.0
		}
	]


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


static func get_administrative_layout() -> Dictionary:
	# Semantic service spaces for registration, judgment, records, and reincarnation.
	return {
		"ten_kings_court": {
			"hearing_courts": [
				{"point_id": "ten_kings.court.left.01", "offset": Vector3(-11.0, 3.5, -5.2), "wall_offset": Vector3(-11.0, 1.1, -5.2), "roof_offset": Vector3(-11.0, 6.4, -5.2)},
				{"point_id": "ten_kings.court.left.02", "offset": Vector3(-11.0, 3.5, 0.0), "wall_offset": Vector3(-11.0, 1.1, 0.0), "roof_offset": Vector3(-11.0, 6.4, 0.0)},
				{"point_id": "ten_kings.court.left.03", "offset": Vector3(-11.0, 3.5, 5.2), "wall_offset": Vector3(-11.0, 1.1, 5.2), "roof_offset": Vector3(-11.0, 6.4, 5.2)},
				{"point_id": "ten_kings.court.right.01", "offset": Vector3(11.0, 3.5, -5.2), "wall_offset": Vector3(11.0, 1.1, -5.2), "roof_offset": Vector3(11.0, 6.4, -5.2)},
				{"point_id": "ten_kings.court.right.02", "offset": Vector3(11.0, 3.5, 0.0), "wall_offset": Vector3(11.0, 1.1, 0.0), "roof_offset": Vector3(11.0, 6.4, 0.0)},
				{"point_id": "ten_kings.court.right.03", "offset": Vector3(11.0, 3.5, 5.2), "wall_offset": Vector3(11.0, 1.1, 5.2), "roof_offset": Vector3(11.0, 6.4, 5.2)}
			],
			"judgment_steps": {"point_id": "ten_kings.judgment.steps", "offset": Vector3(0.0, 0.35, -8.0), "size": Vector3(15.0, 0.7, 2.0)},
			"hearing_approach": {"point_id": "ten_kings.hearing.approach", "offset": Vector3(0.0, 0.0, -10.0)}
		},
		"judge_bureau": {
			"archive_tower": {"point_id": "judge.archive.tower", "offset": Vector3(-9.0, 6.0, 2.0), "size": Vector3(5.0, 12.0, 5.0), "roof_base": Vector3(-9.0, 12.5, 2.0)},
			"galleries": [
				{"point_id": "judge.gallery.left", "offset": Vector3(-9.0, 2.0, -7.0), "size": Vector3(7.0, 4.0, 3.0)},
				{"point_id": "judge.gallery.right", "offset": Vector3(9.0, 2.0, -7.0), "size": Vector3(7.0, 4.0, 3.0)}
			],
			"review_station": {"point_id": "judge.review.station", "offset": Vector3(0.0, 0.0, 0.0)},
			"document_dispatch": {"point_id": "judge.document.dispatch", "offset": Vector3(0.0, 0.0, 9.0)}
		},
		"soul_registry": {
			"archive_tower": {"point_id": "soul_registry.archive.tower", "offset": Vector3(0.0, 7.0, 2.0), "size": Vector3(8.0, 14.0, 7.0)},
			"floor_bands": [
				{"point_id": "soul_registry.archive.floor.01", "level": 1, "offset": Vector3(0.0, 3.5, 2.0)},
				{"point_id": "soul_registry.archive.floor.02", "level": 2, "offset": Vector3(0.0, 7.0, 2.0)},
				{"point_id": "soul_registry.archive.floor.03", "level": 3, "offset": Vector3(0.0, 10.5, 2.0)}
			],
			"archive_roof_base": Vector3(0.0, 14.9, 2.0),
			"identity_verification": {"point_id": "soul_registry.identity.verification", "offset": Vector3(0.0, 0.0, -8.0)},
			"record_lookup": {"point_id": "soul_registry.record.lookup", "offset": Vector3(0.0, 0.0, 7.0)}
		},
		"reincarnation_bureau": {
			"portal_pillars": [
				{"point_id": "reincarnation.portal.left", "offset": Vector3(-8.0, 6.0, 4.0), "size": Vector3(2.0, 12.0, 2.0)},
				{"point_id": "reincarnation.portal.right", "offset": Vector3(8.0, 6.0, 4.0), "size": Vector3(2.0, 12.0, 2.0)}
			],
			"portal_roof": {"point_id": "reincarnation.portal.roof", "offset": Vector3(0.0, 12.0, 4.0), "width": 21.0, "height": 3.5},
			"threshold": {"point_id": "reincarnation.portal.threshold", "offset": Vector3(0.0, 0.22, 4.0), "size": Vector3(17.0, 0.44, 2.5)},
			"document_check": {"point_id": "reincarnation.document.check", "offset": Vector3(0.0, 0.0, -7.0)},
			"departure_lane": {"point_id": "reincarnation.departure.lane", "offset": Vector3(0.0, 0.0, 10.0)}
		}
	}


static func get_waystation_layout() -> Dictionary:
	# Arrival, registration, waiting, and dispatch are authored as semantic local-space points.
	return {
		"district": "引魂驿站",
		"arrival_lane": {"point_id": "waystation.arrival.lane", "offset": Vector3(0.0, 0.1, -7.0), "size": Vector3(7.0, 0.16, 11.0)},
		"canopy": {"point_id": "waystation.registration.canopy", "offset": Vector3(0.0, 4.0, -2.0), "size": Vector3(12.0, 0.8, 6.0), "roof_offset": Vector3(0.0, 5.0, -2.0), "roof_width": 15.0, "roof_height": 2.6},
		"registration_desk": {"point_id": "waystation.registration.desk", "offset": Vector3(0.0, 1.0, 0.5), "size": Vector3(5.0, 1.8, 1.2)},
		"registration_ledger": {"point_id": "waystation.registration.ledger", "offset": Vector3(0.0, 2.05, 0.5), "size": Vector3(2.4, 0.18, 0.8)},
		"waiting_pavilions": [
			{"point_id": "waystation.waiting_pavilion.left", "offset": Vector3(-6.5, 1.8, 8.0), "size": Vector3(4.0, 3.6, 4.0), "roof_offset": Vector3(-6.5, 4.3, 8.0), "roof_width": 5.5, "roof_height": 1.7},
			{"point_id": "waystation.waiting_pavilion.right", "offset": Vector3(6.5, 1.8, 8.0), "size": Vector3(4.0, 3.6, 4.0), "roof_offset": Vector3(6.5, 4.3, 8.0), "roof_width": 5.5, "roof_height": 1.7}
		],
		"queue_rails": [
			{"point_id": "waystation.queue_rail.left", "offset": Vector3(-3.5, 0.8, -7.0), "size": Vector3(0.22, 1.6, 8.0)},
			{"point_id": "waystation.queue_rail.right", "offset": Vector3(3.5, 0.8, -7.0), "size": Vector3(0.22, 1.6, 8.0)}
		],
		"queue_positions": [Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -3.5), Vector3(0.0, 0.0, -1.0)],
		"dispatch_gate": {
			"point_id": "waystation.dispatch.gate",
			"left_post_offset": Vector3(-3.5, 2.8, 10.5), "right_post_offset": Vector3(3.5, 2.8, 10.5),
			"post_size": Vector3(0.7, 5.6, 0.7),
			"lintel_offset": Vector3(0.0, 5.3, 10.5), "lintel_size": Vector3(7.5, 0.8, 0.8),
			"label_offset": Vector3(0.0, 6.3, 10.5)
		},
		"guide_posts": [
			{"point_id": "waystation.guide.01", "offset": Vector3(-2.0, 0.0, -9.0), "facing": PI * 0.5, "activity": "arrival_assist"},
			{"point_id": "waystation.guide.02", "offset": Vector3(2.0, 0.0, -9.0), "facing": PI * 0.5, "activity": "arrival_assist"},
			{"point_id": "waystation.guide.03", "offset": Vector3(-2.0, 0.0, 3.0), "facing": PI * 0.5, "activity": "registration"},
			{"point_id": "waystation.guide.04", "offset": Vector3(2.0, 0.0, 3.0), "facing": PI * 0.5, "activity": "registration"},
			{"point_id": "waystation.guide.05", "offset": Vector3(0.0, 0.0, 8.5), "facing": PI * 0.5, "activity": "dispatch"}
		]
	}


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
	var waystation: Dictionary = get_waystation_layout()
	var waystation_center := Vector3(77.0, 0.0, 0.0)
	for guide in waystation["guide_posts"]:
		var guide_point := _npc_point(str(guide["point_id"]), "引魂驿站", "guide", str(guide["activity"]), waystation_center + guide["offset"], float(guide["facing"]), "always", 1, 1.4)
		guide_point["waystation_station_id"] = str(guide["point_id"])
		points.append(guide_point)
	var patrol_positions := [Vector3(-7, 0, 12), Vector3(7, 0, 12), Vector3(0, 0, 3), Vector3(0, 0, 15)]
	for i in range(patrol_positions.size()):
		points.append(_npc_point("patrol_office.guard.%02d" % (i + 1), "巡城司", "patrol_guard", "patrol_watch", patrol_positions[i], PI if i % 2 == 0 else 0.0, "always", 1, 1.4))
	# Each gate has a day/night relief pair. Only the active shift is rendered by the graybox.
	var gate_posts := [
		{"id": "north_heaven_gate", "name": "北天门", "center": Vector3(0, 0, 88), "inward_facing": PI},
		{"id": "south_ghost_gate", "name": "南幽门", "center": Vector3(0, 0, -88), "inward_facing": 0.0},
		{"id": "east_mystic_gate", "name": "东玄门", "center": Vector3(88, 0, 0), "inward_facing": -PI * 0.5},
		{"id": "west_dark_gate", "name": "西冥门", "center": Vector3(-88, 0, 0), "inward_facing": PI * 0.5}
	]
	for gate in gate_posts:
		for shift_tag in ["day", "night"]:
			var gate_point := _npc_point(
				"gate_guard.%s.%s" % [str(gate["id"]), shift_tag],
				"城门守备", "gate_guard", "gate_watch", gate["center"],
				float(gate["inward_facing"]), "always", 1, 1.4
			)
			gate_point["gate_id"] = str(gate["id"])
			gate_point["gate_name"] = str(gate["name"])
			gate_point["shift_tag"] = shift_tag
			points.append(gate_point)
	var queue_positions: Array = waystation["queue_positions"]
	for i in range(queue_positions.size()):
		var queue_point := _npc_point("waystation.waiting_soul.%02d" % (i + 1), "引魂驿站", "waiting_soul", "queue_wait", waystation_center + queue_positions[i], PI, "always", 1, 0.8)
		queue_point["queue_lane_id"] = "waystation.queue.main"
		queue_point["queue_slot"] = i
		points.append(queue_point)
	return points


static func get_district_service_entrances() -> Array[Dictionary]:
	# Entrance points align with the southern gate opening of each district compound.
	return [
		{"id": "service.soul_ward.main", "district_id": "soul_ward", "district_name": "万家魂坊", "navigation_node_id": "district.soul_ward.entry", "position": Vector3(-55, 0, -66), "service": "社区与居民服务"},
		{"id": "service.ghost_market.main", "district_id": "ghost_market", "district_name": "万魂鬼市", "navigation_node_id": "district.ghost_market.entry", "position": Vector3(55, 0, -66), "service": "交易与拍卖"},
		{"id": "service.soul_registry.main", "district_id": "soul_registry", "district_name": "鬼籍司", "navigation_node_id": "district.soul_registry.entry", "position": Vector3(-52, 0, -8), "service": "新魂登记与身份核验"},
		{"id": "service.merit_bureau.main", "district_id": "merit_bureau", "district_name": "功过司", "navigation_node_id": "district.merit_bureau.entry", "position": Vector3(52, 0, -8), "service": "功过与因果查询"},
		{"id": "service.ten_kings.main", "district_id": "ten_kings_court", "district_name": "十王府", "navigation_node_id": "district.ten_kings.entry", "position": Vector3(-51, 0, 36.5), "service": "十殿审判"},
		{"id": "service.judge_bureau.main", "district_id": "judge_bureau", "district_name": "判官司", "navigation_node_id": "district.judge_bureau.entry", "position": Vector3(51, 0, 36.5), "service": "案卷复核与司法文书"},
		{"id": "service.patrol_office.main", "district_id": "patrol_office", "district_name": "巡城司", "navigation_node_id": "district.patrol_office.entry", "position": Vector3(0, 0, 2), "service": "治安与巡防调度"},
		{"id": "service.reincarnation.main", "district_id": "reincarnation_bureau", "district_name": "轮回司", "navigation_node_id": "district.reincarnation.entry", "position": Vector3(0, 0, -78), "service": "轮回文牒与忘川通道"},
		{"id": "service.barracks.main", "district_id": "barracks", "district_name": "阴兵大营", "navigation_node_id": "district.barracks.entry", "position": Vector3(-77, 0, -13.5), "service": "驻军与军需"},
		{"id": "service.waystation.main", "district_id": "waystation", "district_name": "引魂驿站", "navigation_node_id": "district.waystation.entry", "position": Vector3(77, 0, -13.5), "service": "接引与分流"}
	]


static func get_spatial_binding_for_point(point: Dictionary, network: Dictionary = {}) -> Dictionary:
	if network.is_empty():
		network = get_navigation_network()
	var district_name := str(point.get("district", ""))
	var district_id := ""
	var entry_id := ""
	for entrance in get_district_service_entrances():
		if str(entrance["district_name"]) == district_name:
			district_id = str(entrance["district_id"])
			entry_id = str(entrance["navigation_node_id"])
			break
	var nearest_node_id := ""
	var nearest_distance := INF
	var point_position: Vector3 = point.get("position", Vector3.ZERO)
	for node in network["nodes"]:
		var node_position: Vector3 = node["position"]
		var distance := point_position.distance_to(node_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_node_id = str(node["id"])
	return {
		"district_id": district_id,
		"district_entry_node_id": entry_id,
		"nearest_road_node_id": nearest_node_id,
		"nearest_road_node_distance": nearest_distance,
		"navigation_profile": "pedestrian"
	}


static func get_gate_guard_roster() -> Array[Dictionary]:
	return [
		{"gate_id": "north_heaven_gate", "gate_name": "北天门", "day_shift": "06:00-18:00", "night_shift": "18:00-06:00", "guards_per_shift": 1},
		{"gate_id": "south_ghost_gate", "gate_name": "南幽门", "day_shift": "06:00-18:00", "night_shift": "18:00-06:00", "guards_per_shift": 1},
		{"gate_id": "east_mystic_gate", "gate_name": "东玄门", "day_shift": "06:00-18:00", "night_shift": "18:00-06:00", "guards_per_shift": 1},
		{"gate_id": "west_dark_gate", "gate_name": "西冥门", "day_shift": "06:00-18:00", "night_shift": "18:00-06:00", "guards_per_shift": 1}
	]


static func get_patrol_routes() -> Array[Dictionary]:
	# Patrol waypoints are stable navigation-graph node IDs, not a second coordinate-only route.
	var network := get_navigation_network()
	var positions_by_id: Dictionary = {}
	for node in network.get("nodes", []):
		positions_by_id[str(node.get("id", ""))] = node.get("position", Vector3.ZERO)
	var node_ids: Array[String] = [
		"patrol.route.south_gate", "junction.north", "patrol.route.north_west",
		"patrol.route.east_north", "junction.east.north", "junction.east.south",
		"patrol.route.east_south", "district.reincarnation.entry", "patrol.route.west_south",
		"junction.west.south", "junction.west.north", "patrol.route.west_north",
		"patrol.route.north_west", "junction.north"
	]
	var node_positions: Array[Vector3] = []
	for node_id in node_ids:
		if positions_by_id.has(node_id):
			node_positions.append(positions_by_id[node_id])
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
