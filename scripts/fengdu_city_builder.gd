extends RefCounted
## Procedural Fengdu capital blockout derived from the city-plan catalog.
## Schematic coordinates are scaled into the current 256 m prototype; this is not the final city scale.

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")

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
	district.add_child(_box_mesh("MainHall", Vector3(main_width, building_height, main_depth), Vector3(0.0, 0.7 + building_height * 0.5, 0.0), base_color))
	var building_collision := CollisionShape3D.new()
	var building_shape := BoxShape3D.new()
	building_shape.size = Vector3(main_width, building_height, main_depth)
	building_collision.shape = building_shape
	building_collision.position = Vector3(0.0, 0.7 + building_height * 0.5, 0.0)
	district.add_child(building_collision)
	district.add_child(_box_mesh("Roof", Vector3(main_width * 1.18, 0.85, main_depth * 1.16), Vector3(0.0, 1.1 + building_height, 0.0), Color("#282936")))
	district.add_child(_box_mesh("RoofRidge", Vector3(main_width * 0.72, 0.28, 0.5), Vector3(0.0, 1.58 + building_height, 0.0), Color("#a88b60")))
	if kind == "palace":
		district.add_child(_box_mesh("UpperHall", Vector3(main_width * 0.62, 4.0, main_depth * 0.58), Vector3(0.0, building_height + 3.0, 0.0), Color("#806044")))
		district.add_child(_box_mesh("UpperRoof", Vector3(main_width * 0.76, 0.65, main_depth * 0.72), Vector3(0.0, building_height + 5.35, 0.0), Color("#332638")))
	_add_district_details(district, kind, footprint, base_color, building_height)
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
				district.add_child(_box_mesh("SideWing", Vector3(footprint.x * 0.2, building_height * 0.58, footprint.y * 0.52), Vector3(side * footprint.x * 0.39, 0.7 + building_height * 0.29, 0.0), base_color.lightened(0.12)))
		"market":
			for stall_index in range(4):
				var stall_x := -footprint.x * 0.34 + float(stall_index) * footprint.x * 0.22
				district.add_child(_box_mesh("MarketCounter_" + str(stall_index), Vector3(2.0, 0.9, 1.5), Vector3(stall_x, 1.15, footprint.y * 0.28), Color("#8b704d")))
				district.add_child(_box_mesh("MarketAwning_" + str(stall_index), Vector3(2.3, 0.22, 1.9), Vector3(stall_x, 3.0, footprint.y * 0.28), Color("#6b3f4a") if stall_index % 2 == 0 else Color("#46596b")))
		"residential":
			for house_index in range(3):
				var house_x := -footprint.x * 0.28 + float(house_index) * footprint.x * 0.28
				district.add_child(_box_mesh("SoulHouse_" + str(house_index), Vector3(2.5, 2.8, 2.7), Vector3(house_x, 2.1, -footprint.y * 0.28), Color("#59645d")))
				district.add_child(_box_mesh("SoulHouseRoof_" + str(house_index), Vector3(3.0, 0.42, 3.1), Vector3(house_x, 3.72, -footprint.y * 0.28), Color("#30323b")))
		"military":
			for side in [-1.0, 1.0]:
				district.add_child(_box_mesh("WatchTower", Vector3(2.0, 7.0, 2.0), Vector3(side * footprint.x * 0.34, 4.2, 0.0), Color("#414752")))
				district.add_child(_box_mesh("WatchTowerRoof", Vector3(2.8, 0.55, 2.8), Vector3(side * footprint.x * 0.34, 8.0, 0.0), Color("#292b35")))
		"gate":
			for side in [-1.0, 1.0]:
				district.add_child(_box_mesh("GateColumn", Vector3(0.8, building_height + 1.0, 0.9), Vector3(side * footprint.x * 0.34, (building_height + 1.0) * 0.5, 0.0), Color("#82705e")))
			district.add_child(_box_mesh("GateBeam", Vector3(footprint.x * 0.82, 0.8, 1.1), Vector3(0.0, building_height + 0.5, 0.0), Color("#a18a64")))
		"transport":
			district.add_child(_box_mesh("WaystationPlatform", Vector3(footprint.x * 0.86, 0.35, footprint.y * 0.82), Vector3(0.0, 0.9, 0.0), Color("#827968")))
			district.add_child(_box_mesh("WaystationCanopy", Vector3(footprint.x * 0.8, 0.35, footprint.y * 0.76), Vector3(0.0, building_height + 1.4, 0.0), Color("#343341")))


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


static func _add_wall(root: Node3D, node_name: String, dimensions: Vector3, position: Vector3, color: Color) -> void:
	var wall := StaticBody3D.new()
	wall.name = node_name
	wall.position = position
	wall.add_child(_box_mesh("WallVisual", dimensions, Vector3.ZERO, color))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	wall.add_child(collision)
	root.add_child(wall)


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
