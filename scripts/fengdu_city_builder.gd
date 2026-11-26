extends RefCounted
## Procedural Fengdu capital blockout derived from the city-plan catalog.
## Schematic coordinates are scaled into the current 256 m prototype; this is not the final city scale.

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const BUILDING_MODELS := {
	"wall": "res://assets/models/fengdu_wall.glb",
	"tower": "res://assets/models/fengdu_watchtower.glb",
	"hall": "res://assets/models/fengdu_hall.glb",
	"house": "res://assets/models/fengdu_house.glb",
	"east_asian_roof": "res://assets/models/fengdu_east_asian_roof.glb",
	"east_asian_wall": "res://assets/models/fengdu_east_asian_wall.glb",
	"column_base": "res://assets/models/fengdu_column_base.glb",
	"lantern": "res://assets/models/fengdu_lantern.glb",
	"bell": "res://assets/models/fengdu_bell.glb"
}

const CITY_SCALE := 0.12
const CITY_CENTER_Z := -60.0
const WALL_HALF_X := 47.0
const WALL_HALF_Z := 37.0

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "FengduCapitalBlockout"
	var plan := WorldMapCatalog.get_fengdu_city_plan()
	var nodes: Array = plan.get("nodes", [])
	var by_id: Dictionary = {}
	for entry_variant in nodes:
		var entry: Dictionary = entry_variant
		by_id[str(entry.get("id", ""))] = entry
		_add_district(root, entry)
	_add_city_walls(root)
	_add_city_corner_towers(root)
	_add_moat_and_bridges(root)
	_add_roads(root, by_id, plan.get("roads", []))
	_add_city_landmark(root, "CapitalName", "酆 都 天 城", Vector3(0.0, 19.0, CITY_CENTER_Z - 8.0), Color("#d9c7a1"))
	_add_city_landmark(root, "CapitalSubtitle", "陰司中樞 · 十王分治 · 四門通幽", Vector3(0.0, 15.0, CITY_CENTER_Z - 8.0), Color("#b8a9c9"))
	return root


static func _world_position(schematic_position: Array) -> Vector3:
	return Vector3(
		float(schematic_position[0]) * CITY_SCALE,
		0.0,
		-float(schematic_position[1]) * CITY_SCALE + CITY_CENTER_Z
	)


static func _district_color(kind: String) -> Color:
	match kind:
		"palace":
			return Color("#665044")
		"court":
			return Color("#55475d")
		"admin":
			return Color("#46505d")
		"sacred":
			return Color("#65566f")
		"market":
			return Color("#69543e")
		"residential":
			return Color("#4d5a54")
		"military":
			return Color("#454b55")
		"transport", "gate":
			return Color("#5c5362")
		_:
			return Color("#514b59")


static func _add_district(root: Node3D, entry: Dictionary) -> void:
	var position_data: Array = entry.get("position", [0.0, 0.0])
	var size_data: Array = entry.get("size", [60.0, 40.0])
	var center := _world_position(position_data)
	var footprint := Vector2(maxf(float(size_data[0]) * CITY_SCALE, 5.0), maxf(float(size_data[1]) * CITY_SCALE, 4.5))
	var kind := str(entry.get("kind", "admin"))
	var base_color := _district_color(kind)
	var district := StaticBody3D.new()
	district.name = "District_" + str(entry.get("id", "unknown"))
	district.position = center
	var foundation := _box_mesh("Foundation", Vector3(footprint.x, 0.7, footprint.y), Vector3(0.0, 0.35, 0.0), base_color.darkened(0.22))
	district.add_child(foundation)
	var building_height := 5.2
	if kind == "palace":
		building_height = 11.0
	elif kind == "sacred" or kind == "court":
		building_height = 7.2
	elif kind == "gate":
		building_height = 6.5
	elif kind == "residential" or kind == "market":
		building_height = 4.0
	var main_width := footprint.x * 0.68
	var main_depth := footprint.y * 0.66
	var building_model_key := "hall"
	if kind == "residential" or kind == "market":
		building_model_key = "house"
	elif kind == "military" or kind == "gate":
		building_model_key = "tower"
	var has_imported_building := _add_scaled_model(
		district, str(BUILDING_MODELS[building_model_key]),
		Vector3(main_width, building_height + 1.2, main_depth), Vector3(0.0, 0.7, 0.0)
	)
	if not has_imported_building:
		district.add_child(_box_mesh("MainHall", Vector3(main_width, building_height, main_depth), Vector3(0.0, 0.7 + building_height * 0.5, 0.0), base_color))
	var building_collision := CollisionShape3D.new()
	var building_shape := BoxShape3D.new()
	building_shape.size = Vector3(main_width, building_height, main_depth)
	building_collision.shape = building_shape
	building_collision.position = Vector3(0.0, 0.7 + building_height * 0.5, 0.0)
	district.add_child(building_collision)
	if not has_imported_building:
		district.add_child(_box_mesh("Roof", Vector3(main_width * 1.18, 0.85, main_depth * 1.16), Vector3(0.0, 1.1 + building_height, 0.0), Color("#282936")))
		district.add_child(_box_mesh("RoofRidge", Vector3(main_width * 0.72, 0.28, 0.5), Vector3(0.0, 1.58 + building_height, 0.0), Color("#a88b60")))
	else:
		# Transition the imported medieval shell toward Fengdu's East Asian silhouette:
		# the CC0 roof module adds broad eaves while gameplay collision stays unchanged.
		_add_scaled_model(
			district, str(BUILDING_MODELS["east_asian_roof"]),
			Vector3(main_width * 1.24, 1.65, main_depth * 1.24),
			Vector3(0.0, building_height + 1.25, 0.0)
		)
		if kind in ["palace", "court", "admin", "sacred"]:
			for side in [-1.0, 1.0]:
				for depth_side in [-1.0, 1.0]:
					_add_scaled_model(
						district, str(BUILDING_MODELS["column_base"]),
						Vector3(0.72, 0.45, 0.72),
						Vector3(side * main_width * 0.43, 0.72, depth_side * main_depth * 0.43)
					)
		if kind in ["palace", "court", "admin", "sacred", "gate"]:
			_add_scaled_model(
				district, str(BUILDING_MODELS["east_asian_wall"]),
				Vector3(main_width * 0.42, building_height * 0.54, 0.28),
				Vector3(0.0, 0.72 + building_height * 0.28, -main_depth * 0.46)
			)
			_add_scaled_model(
				district, str(BUILDING_MODELS["east_asian_wall"]),
				Vector3(main_width * 0.42, building_height * 0.54, 0.28),
				Vector3(0.0, 0.72 + building_height * 0.28, main_depth * 0.46),
				PI
			)
		if kind == "sacred":
			_add_scaled_model(
				district, str(BUILDING_MODELS["bell"]),
				Vector3(3.0, 3.6, 3.0), Vector3(footprint.x * 0.31, 0.7, footprint.y * 0.28)
			)
	if kind == "palace":
		if not _add_scaled_model(
			district, str(BUILDING_MODELS["hall"]),
			Vector3(main_width * 0.62, 4.0, main_depth * 0.58),
			Vector3(0.0, building_height + 3.0, 0.0)
		):
			district.add_child(_box_mesh("UpperHall", Vector3(main_width * 0.62, 4.0, main_depth * 0.58), Vector3(0.0, building_height + 3.0, 0.0), Color("#806044")))
		if not _add_scaled_model(
			district, str(BUILDING_MODELS["east_asian_roof"]),
			Vector3(main_width * 0.78, 1.1, main_depth * 0.76),
			Vector3(0.0, building_height + 5.35, 0.0)
		):
			district.add_child(_box_mesh("UpperRoof", Vector3(main_width * 0.76, 0.65, main_depth * 0.72), Vector3(0.0, building_height + 5.35, 0.0), Color("#332638")))
	_add_district_details(district, kind, footprint, base_color, building_height)
	_add_district_lanterns(district, footprint)
	var label := Label3D.new()
	label.name = "DistrictLabel"
	label.text = str(entry.get("name", "城区"))
	label.position = Vector3(0.0, building_height + 3.2, 0.0)
	label.font_size = 30
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#e1d2b4")
	district.add_child(label)
	root.add_child(district)


static func _add_district_details(district: Node3D, kind: String, footprint: Vector2, base_color: Color, building_height: float) -> void:
	match kind:
		"palace":
			for side in [-1.0, 1.0]:
				for depth_side in [-1.0, 1.0]:
					var pillar := CylinderMesh.new()
					pillar.top_radius = 0.34
					pillar.bottom_radius = 0.42
					pillar.height = building_height * 0.78
					pillar.radial_segments = 10
					var pillar_node := MeshInstance3D.new()
					pillar_node.name = "PalacePillar"
					pillar_node.mesh = pillar
					pillar_node.position = Vector3(side * footprint.x * 0.31, 0.7 + building_height * 0.39, depth_side * footprint.y * 0.29)
					var pillar_material := StandardMaterial3D.new()
					pillar_material.albedo_color = Color("#a88b60")
					pillar_node.material_override = pillar_material
					district.add_child(pillar_node)
		"court", "admin":
			for side in [-1.0, 1.0]:
				var wing_size := Vector3(footprint.x * 0.2, building_height * 0.58, footprint.y * 0.52)
				var wing_position := Vector3(side * footprint.x * 0.39, 0.7 + building_height * 0.29, 0.0)
				if not _add_scaled_model(district, str(BUILDING_MODELS["east_asian_wall"]), wing_size, wing_position):
					district.add_child(_box_mesh("SideWing", wing_size, wing_position, base_color.lightened(0.12)))
		"market":
			for stall_index in range(4):
				var stall_x := -footprint.x * 0.34 + float(stall_index) * footprint.x * 0.22
				district.add_child(_box_mesh("MarketCounter_" + str(stall_index), Vector3(2.0, 0.9, 1.5), Vector3(stall_x, 1.15, footprint.y * 0.28), Color("#8b704d")))
				district.add_child(_box_mesh("MarketAwning_" + str(stall_index), Vector3(2.3, 0.22, 1.9), Vector3(stall_x, 3.0, footprint.y * 0.28), Color("#6b3f4a") if stall_index % 2 == 0 else Color("#46596b")))
		"residential":
			for house_index in range(3):
				var house_x := -footprint.x * 0.28 + float(house_index) * footprint.x * 0.28
				var house_position := Vector3(house_x, 0.0, -footprint.y * 0.28)
				if not _add_scaled_model(district, str(BUILDING_MODELS["house"]), Vector3(2.8, 3.6, 2.8), house_position):
					district.add_child(_box_mesh("SoulHouse_" + str(house_index), Vector3(2.5, 2.8, 2.7), house_position + Vector3(0.0, 2.1, 0.0), Color("#59645d")))
					district.add_child(_box_mesh("SoulHouseRoof_" + str(house_index), Vector3(3.0, 0.42, 3.1), house_position + Vector3(0.0, 3.72, 0.0), Color("#30323b")))
		"military":
			for side in [-1.0, 1.0]:
				var tower_position := Vector3(side * footprint.x * 0.34, 0.0, 0.0)
				if not _add_scaled_model(district, str(BUILDING_MODELS["tower"]), Vector3(3.2, 7.5, 3.2), tower_position):
					district.add_child(_box_mesh("WatchTower", Vector3(2.0, 7.0, 2.0), tower_position + Vector3(0.0, 4.2, 0.0), Color("#414752")))
					district.add_child(_box_mesh("WatchTowerRoof", Vector3(2.8, 0.55, 2.8), tower_position + Vector3(0.0, 8.0, 0.0), Color("#292b35")))
		"gate":
			for side in [-1.0, 1.0]:
				district.add_child(_box_mesh("GateColumn", Vector3(0.8, building_height + 1.0, 0.9), Vector3(side * footprint.x * 0.34, (building_height + 1.0) * 0.5, 0.0), Color("#82705e")))
			district.add_child(_box_mesh("GateBeam", Vector3(footprint.x * 0.82, 0.8, 1.1), Vector3(0.0, building_height + 0.5, 0.0), Color("#a18a64")))
		"transport":
			district.add_child(_box_mesh("WaystationPlatform", Vector3(footprint.x * 0.86, 0.35, footprint.y * 0.82), Vector3(0.0, 0.9, 0.0), Color("#827968")))
			district.add_child(_box_mesh("WaystationCanopy", Vector3(footprint.x * 0.8, 0.35, footprint.y * 0.76), Vector3(0.0, building_height + 1.4, 0.0), Color("#343341")))


static func _add_moat_and_bridges(root: Node3D) -> void:
	# A continuous defensive moat surrounds the wall, with four deliberately
	# aligned openings. Server collision uses the same X/Z rectangles.
	var moat_color := Color("#292d45")
	var moat_y := -0.18
	var moat_depth := 6.1
	# North and south runs, split around the 12 m gate/bridge openings.
	for side in [-1.0, 1.0]:
		_add_moat_segment(root, "NorthMoat_" + str(side),
			Vector3(48.0, 0.18, moat_depth),
			Vector3(side * 30.0, moat_y, -100.95), moat_color)
		_add_moat_segment(root, "SouthMoat_" + str(side),
			Vector3(48.0, 0.18, moat_depth),
			Vector3(side * 30.0, moat_y, -19.05), moat_color)
	# East and west runs are split above/below their gate openings.
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 50.95
		var prefix := "West" if side < 0.0 else "East"
		_add_moat_segment(root, prefix + "Moat_North",
			Vector3(moat_depth, 0.18, 38.0), Vector3(x, moat_y, -85.0), moat_color)
		_add_moat_segment(root, prefix + "Moat_South",
			Vector3(moat_depth, 0.18, 38.0), Vector3(x, moat_y, -35.0), moat_color)

	# Bridge decks overlap the moat banks slightly so there are no tiny gaps
	# at the shore or wall threshold. The openings remain 12 m wide.
	_add_gate_bridge(root, "NorthGateBridge", Vector3(12.0, 0.36, 10.0), Vector3(0.0, 0.10, -101.5), false)
	_add_gate_bridge(root, "SouthGateBridge", Vector3(12.0, 0.36, 10.0), Vector3(0.0, 0.10, -18.5), false)
	_add_gate_bridge(root, "WestGateBridge", Vector3(10.0, 0.36, 12.0), Vector3(-51.0, 0.10, -60.0), true)
	_add_gate_bridge(root, "EastGateBridge", Vector3(10.0, 0.36, 12.0), Vector3(51.0, 0.10, -60.0), true)


static func _add_moat_segment(root: Node3D, node_name: String, dimensions: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var water := _box_mesh("WaterSurface", dimensions, Vector3.ZERO, color)
	var material := water.material_override as StandardMaterial3D
	material.roughness = 0.22
	material.metallic = 0.12
	body.add_child(water)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)


static func _add_gate_bridge(root: Node3D, node_name: String, dimensions: Vector3, position: Vector3, east_west: bool) -> void:
	var bridge := StaticBody3D.new()
	bridge.name = node_name
	bridge.position = position
	bridge.add_child(_box_mesh("StoneDeck", dimensions, Vector3.ZERO, Color("#6b625e")))
	var deck_collision := CollisionShape3D.new()
	var deck_shape := BoxShape3D.new()
	deck_shape.size = dimensions
	deck_collision.shape = deck_shape
	bridge.add_child(deck_collision)
	var rail_color := Color("#403b49")
	if east_west:
		for side in [-1.0, 1.0]:
			bridge.add_child(_box_mesh("BridgeRail", Vector3(10.0, 0.72, 0.28), Vector3(0.0, 0.54, side * 5.65), rail_color))
	else:
		for side in [-1.0, 1.0]:
			bridge.add_child(_box_mesh("BridgeRail", Vector3(0.28, 0.72, 10.0), Vector3(side * 5.65, 0.54, 0.0), rail_color))
	root.add_child(bridge)


static func _add_city_walls(root: Node3D) -> void:
	var wall_color := Color("#494451")
	# North and south walls are split around a 12 m gate opening.
	for side in [-1.0, 1.0]:
		_add_wall(root, "NorthWall_" + str(side), Vector3(WALL_HALF_X - 6.0, 5.0, 1.8), Vector3(side * (WALL_HALF_X * 0.5 + 3.0), 2.5, CITY_CENTER_Z - WALL_HALF_Z), wall_color)
		_add_wall(root, "SouthWall_" + str(side), Vector3(WALL_HALF_X - 6.0, 5.0, 1.8), Vector3(side * (WALL_HALF_X * 0.5 + 3.0), 2.5, CITY_CENTER_Z + WALL_HALF_Z), wall_color)
	# East and west walls also leave a 12 m gate opening, matching server collision data.
	for side in [-1.0, 1.0]:
		for depth_side in [-1.0, 1.0]:
			_add_wall(
				root,
				("WestWall_" if side < 0.0 else "EastWall_") + str(depth_side),
				Vector3(1.8, 5.0, WALL_HALF_Z - 6.0),
				Vector3(side * WALL_HALF_X, 2.5, CITY_CENTER_Z + depth_side * (WALL_HALF_Z * 0.5 + 3.0)),
				wall_color
			)
	_add_city_landmark(root, "EastGateName", "東 玄 門", Vector3(WALL_HALF_X + 1.5, 7.0, CITY_CENTER_Z), Color("#c9b9d2"))
	_add_city_landmark(root, "WestGateName", "西 冥 門", Vector3(-WALL_HALF_X - 1.5, 7.0, CITY_CENTER_Z), Color("#c9b9d2"))
	_add_city_landmark(root, "SouthGateName", "南 幽 门", Vector3(0.0, 7.0, CITY_CENTER_Z + WALL_HALF_Z + 1.5), Color("#c9b9d2"))
	_add_city_landmark(root, "NorthGateName", "北 天 门", Vector3(0.0, 7.0, CITY_CENTER_Z - WALL_HALF_Z - 1.5), Color("#c9b9d2"))

	_add_gatehouse(root, "NorthGatehouse", Vector3(0.0, 0.0, CITY_CENTER_Z - WALL_HALF_Z), false, "天门")
	_add_gatehouse(root, "SouthGatehouse", Vector3(0.0, 0.0, CITY_CENTER_Z + WALL_HALF_Z), false, "幽门")
	_add_gatehouse(root, "EastGatehouse", Vector3(WALL_HALF_X, 0.0, CITY_CENTER_Z), true, "玄门")
	_add_gatehouse(root, "WestGatehouse", Vector3(-WALL_HALF_X, 0.0, CITY_CENTER_Z), true, "冥门")


static func _add_gatehouse(root: Node3D, node_name: String, gate_position: Vector3, east_west: bool, gate_title: String) -> void:
	# Gatehouse is a decorative lintel and roof over the existing 12 m opening.
	# No collider is added: server-side gate geometry remains authoritative.
	var gate := Node3D.new()
	gate.name = node_name
	gate.position = gate_position
	var pillar_color := Color("#655b59")
	var trim_color := Color("#b49a6d")
	for side in [-1.0, 1.0]:
		var pillar_position := Vector3(0.0, 0.0, side * 6.6) if east_west else Vector3(side * 6.6, 0.0, 0.0)
		gate.add_child(_box_mesh(
			"GatePillar", Vector3(1.0, 7.0, 1.0), pillar_position + Vector3(0.0, 3.5, 0.0), pillar_color
		))
		gate.add_child(_box_mesh(
			"GatePillarCap", Vector3(1.35, 0.35, 1.35), pillar_position + Vector3(0.0, 7.15, 0.0), trim_color
		))
	var beam_size := Vector3(14.2, 1.05, 1.4) if not east_west else Vector3(1.4, 1.05, 14.2)
	gate.add_child(_box_mesh("GateLintel", beam_size, Vector3(0.0, 7.45, 0.0), pillar_color))
	var roof_size := Vector3(15.2, 1.25, 3.4) if not east_west else Vector3(3.4, 1.25, 15.2)
	var roof_added := _add_scaled_model(
		gate, str(BUILDING_MODELS["east_asian_roof"]), roof_size,
		Vector3(0.0, 8.05, 0.0), PI * 0.5 if east_west else 0.0
	)
	if not roof_added:
		gate.add_child(_box_mesh(
			"GateRoofFallback", roof_size, Vector3(0.0, 8.05, 0.0), Color("#302c3b")
		))
	gate.add_child(_box_mesh(
		"GatePlaque", Vector3(4.0, 1.15, 0.22) if not east_west else Vector3(0.22, 1.15, 4.0),
		Vector3(0.0, 6.35, -0.82) if not east_west else Vector3(-0.82, 6.35, 0.0),
		Color("#332b37")
	))
	var plaque := Label3D.new()
	plaque.name = "GateInscription"
	plaque.text = gate_title
	plaque.position = Vector3(0.0, 6.35, -0.98) if not east_west else Vector3(-0.98, 6.35, 0.0)
	plaque.font_size = 32
	plaque.outline_size = 5
	plaque.modulate = Color("#e1c58e")
	plaque.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate.add_child(plaque)
	for side in [-1.0, 1.0]:
		var lantern := Node3D.new()
		lantern.name = "GateSoulLantern"
		lantern.position = Vector3(side * 5.35, 0.0, -1.15) if not east_west else Vector3(-1.15, 0.0, side * 5.35)
		if not _add_scaled_model(lantern, str(BUILDING_MODELS["lantern"]), Vector3(0.75, 2.2, 0.75), Vector3.ZERO):
			lantern.add_child(_box_mesh("LanternFallback", Vector3(0.55, 1.8, 0.55), Vector3(0.0, 0.9, 0.0), Color("#536c91")))
		gate.add_child(lantern)
	root.add_child(gate)


static func _add_city_corner_towers(root: Node3D) -> void:
	# Four compact corner keeps visually anchor the perimeter. They are
	# deliberately visual-only until matching server-side obstacle geometry
	# is introduced; the existing wall colliders remain unchanged.
	var corners := [
		{"id": "NorthWest", "x": -1.0, "z": -1.0},
		{"id": "NorthEast", "x": 1.0, "z": -1.0},
		{"id": "SouthWest", "x": -1.0, "z": 1.0},
		{"id": "SouthEast", "x": 1.0, "z": 1.0}
	]
	for corner_variant in corners:
		var corner: Dictionary = corner_variant
		var tower := Node3D.new()
		tower.name = "CornerTower_" + str(corner["id"])
		tower.position = Vector3(
			float(corner["x"]) * (WALL_HALF_X - 0.15),
			0.0,
			CITY_CENTER_Z + float(corner["z"]) * (WALL_HALF_Z - 0.15)
		)
		var imported := _add_scaled_model(
			tower, str(BUILDING_MODELS["tower"]),
			Vector3(5.8, 8.2, 5.8), Vector3(0.0, 4.1, 0.0)
		)
		if not imported:
			tower.add_child(_box_mesh(
				"CornerKeepBody", Vector3(5.2, 6.2, 5.2),
				Vector3(0.0, 3.1, 0.0), Color("#55505b")
			))
			tower.add_child(_box_mesh(
				"CornerKeepRoof", Vector3(6.2, 0.8, 6.2),
				Vector3(0.0, 6.6, 0.0), Color("#302d3a")
			))
		tower.add_child(_box_mesh(
			"CornerKeepCrown", Vector3(6.0, 0.35, 6.0),
			Vector3(0.0, 7.0, 0.0), Color("#9a835f")
		))
		for side in [-1.0, 1.0]:
			tower.add_child(_box_mesh(
				"CornerKeepMerlon", Vector3(0.9, 0.8, 0.9),
				Vector3(side * 2.35, 7.55, 0.0), Color("#b19a70")
			))
			tower.add_child(_box_mesh(
				"CornerKeepMerlon", Vector3(0.9, 0.8, 0.9),
				Vector3(0.0, 7.55, side * 2.35), Color("#b19a70")
			))
		root.add_child(tower)


static func _add_wall(root: Node3D, node_name: String, dimensions: Vector3, position: Vector3, color: Color) -> void:
	var wall := StaticBody3D.new()
	wall.name = node_name
	wall.position = position
	var model_path := str(BUILDING_MODELS["wall"])
	if ResourceLoader.exists(model_path):
		var along_x := dimensions.x >= dimensions.z
		var total_length := dimensions.x if along_x else dimensions.z
		var segment_count := maxi(1, ceili(total_length / 4.0))
		var segment_length := total_length / float(segment_count)
		var added_segments := 0
		for index in range(segment_count):
			var segment_size := Vector3(segment_length, dimensions.y, dimensions.z) if along_x else Vector3(dimensions.x, dimensions.y, segment_length)
			var segment_position := Vector3(
				-dimensions.x * 0.5 + segment_length * (float(index) + 0.5) if along_x else 0.0,
				0.0,
				0.0 if along_x else -dimensions.z * 0.5 + segment_length * (float(index) + 0.5)
			)
			if _add_scaled_model(wall, model_path, segment_size, segment_position, 0.0 if along_x else PI * 0.5):
				added_segments += 1
				_add_scaled_model(
					wall, str(BUILDING_MODELS["east_asian_roof"]),
					Vector3(segment_length * 1.14, 0.82, maxf(dimensions.z * 1.8, 1.4)),
					segment_position + Vector3(0.0, dimensions.y * 0.5 + 0.25, 0.0),
					0.0 if along_x else PI * 0.5
				)
		if added_segments == 0:
			wall.add_child(_box_mesh("WallVisual", dimensions, Vector3.ZERO, color))
	else:
		wall.add_child(_box_mesh("WallVisual", dimensions, Vector3.ZERO, color))
	_add_wall_merlons(wall, dimensions, color)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	wall.add_child(collision)
	root.add_child(wall)


static func _add_wall_merlons(wall: Node3D, dimensions: Vector3, color: Color) -> void:
	# Repeating crenellations give the long perimeter a readable defensive
	# silhouette. They are visual-only: the existing continuous wall collider
	# remains the sole gameplay blocker and keeps its original dimensions.
	var along_x := dimensions.x >= dimensions.z
	var length := dimensions.x if along_x else dimensions.z
	var spacing := 2.4
	var merlon_count := maxi(2, int(floor(length / spacing)))
	var actual_spacing := length / float(merlon_count)
	var merlon_size := Vector3(0.82, 0.82, maxf(dimensions.z * 0.78, 0.72)) if along_x else Vector3(maxf(dimensions.x * 0.78, 0.72), 0.82, 0.82)
	var merlon_color := color.lightened(0.16)
	for index in range(merlon_count + 1):
		var along_offset := -length * 0.5 + actual_spacing * (float(index) + 0.5)
		var merlon_position := Vector3(along_offset, dimensions.y * 0.5 + 0.38, 0.0) if along_x else Vector3(0.0, dimensions.y * 0.5 + 0.38, along_offset)
		wall.add_child(_box_mesh("WallMerlon_%02d" % index, merlon_size, merlon_position, merlon_color))


static func _add_scaled_model(parent: Node3D, model_path: String, target_size: Vector3, base_position: Vector3, rotation_y: float = 0.0) -> bool:
	if not ResourceLoader.exists(model_path):
		return false
	var packed := load(model_path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.rotation.y = rotation_y
	var bounds := {"found": false, "min": Vector3.ZERO, "max": Vector3.ZERO}
	_collect_model_bounds(model, Transform3D.IDENTITY, bounds)
	if not bool(bounds["found"]):
		model.free()
		return false
	var minimum: Vector3 = bounds["min"]
	var maximum: Vector3 = bounds["max"]
	var size := maximum - minimum
	if size.x < 0.001 or size.y < 0.001 or size.z < 0.001:
		model.free()
		return false
	var scale_factor := Vector3(target_size.x / size.x, target_size.y / size.y, target_size.z / size.z)
	model.scale = scale_factor
	var center := (minimum + maximum) * 0.5
	model.position = base_position - Vector3(center.x * scale_factor.x, minimum.y * scale_factor.y, center.z * scale_factor.z)
	model.set_meta("fengdu_imported_asset", model_path)
	parent.add_child(model)
	return true


static func _collect_model_bounds(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var local_bounds := mesh_instance.mesh.get_aabb() * current_transform
			var local_min := local_bounds.position
			var local_max := local_bounds.position + local_bounds.size
			if not bool(state["found"]):
				state["min"] = local_min
				state["max"] = local_max
				state["found"] = true
			else:
				var previous_min: Vector3 = state["min"]
				var previous_max: Vector3 = state["max"]
				state["min"] = previous_min.min(local_min)
				state["max"] = previous_max.max(local_max)
	for child in node.get_children():
		_collect_model_bounds(child, current_transform, state)


static func _add_roads(root: Node3D, by_id: Dictionary, roads: Array) -> void:
	for road_variant in roads:
		var road: Dictionary = road_variant
		var from_id := str(road.get("from", ""))
		var to_id := str(road.get("to", ""))
		if not by_id.has(from_id) or not by_id.has(to_id):
			continue
		var from_entry: Dictionary = by_id[from_id]
		var to_entry: Dictionary = by_id[to_id]
		var from_pos := _world_position(from_entry.get("position", [0.0, 0.0]))
		var to_pos := _world_position(to_entry.get("position", [0.0, 0.0]))
		var delta := to_pos - from_pos
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(2.2, 0.08, delta.length())
		var road_instance := MeshInstance3D.new()
		road_instance.name = "Road_" + from_id + "_" + to_id
		road_instance.mesh = road_mesh
		road_instance.position = (from_pos + to_pos) * 0.5 + Vector3(0.0, 0.035, 0.0)
		road_instance.rotation.y = atan2(delta.x, delta.z)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#756b68")
		material.roughness = 0.98
		road_instance.material_override = material
		root.add_child(road_instance)


static func _box_mesh(node_name: String, dimensions: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	instance.material_override = material
	return instance


static func _add_city_landmark(root: Node3D, node_name: String, text_value: String, position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text_value
	label.position = position
	label.font_size = 38
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	root.add_child(label)


static func _add_district_lanterns(district: Node3D, footprint: Vector2) -> void:
	# Paired soul lanterns mark each district frontage without narrowing the
	# central street or adding new gameplay collision volumes.
	for side in [-1.0, 1.0]:
		var lantern := Node3D.new()
		lantern.name = "DistrictLanternLeft" if side < 0.0 else "DistrictLanternRight"
		lantern.position = Vector3(side * footprint.x * 0.39, 0.0, footprint.y * 0.43)
		if not _add_scaled_model(
			lantern, str(BUILDING_MODELS["lantern"]), Vector3(0.85, 2.45, 0.85), Vector3.ZERO
		):
			var pedestal := CylinderMesh.new()
			pedestal.top_radius = 0.13
			pedestal.bottom_radius = 0.22
			pedestal.height = 1.55
			pedestal.radial_segments = 8
			var pedestal_node := MeshInstance3D.new()
			pedestal_node.name = "LanternPedestal"
			pedestal_node.mesh = pedestal
			pedestal_node.position.y = 0.78
			var stone := StandardMaterial3D.new()
			stone.albedo_color = Color("#393342")
			stone.roughness = 0.9
			pedestal_node.material_override = stone
			lantern.add_child(pedestal_node)
			lantern.add_child(_box_mesh(
				"LanternHousing", Vector3(0.62, 0.48, 0.62), Vector3(0.0, 1.78, 0.0), Color("#64799d")
			))
		var flame := MeshInstance3D.new()
		flame.name = "SoulFlame"
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.16
		flame_mesh.height = 0.42
		flame.mesh = flame_mesh
		flame.position = Vector3(0.0, 2.08, 0.0)
		var flame_material := StandardMaterial3D.new()
		flame_material.albedo_color = Color("#8fb8e8")
		flame_material.emission_enabled = true
		flame_material.emission = Color("#537fc4")
		flame_material.emission_energy_multiplier = 2.0
		flame.material_override = flame_material
		lantern.add_child(flame)
		district.add_child(lantern)
