extends RefCounted
## Visual-only exploration roads around Fengdu. WorldServer remains authoritative.

const ROUTES := [
	{
		"id": "south_marsh",
		"name": "南郊引魂道",
		"destination": "南郊游魂泽",
		"color": Color("#77716a"),
		"points": [Vector3(0.0, 0.0, -15.0), Vector3(0.0, 0.0, 4.0), Vector3(2.0, 0.0, 28.0), Vector3(0.0, 0.0, 52.0), Vector3(0.0, 0.0, 70.0)]
	},
	{
		"id": "west_bone",
		"name": "西郊白骨道",
		"destination": "西郊白骨荒原",
		"color": Color("#81786c"),
		"points": [Vector3(-54.0, 0.0, -60.0), Vector3(-64.0, 0.0, -60.0), Vector3(-78.0, 0.0, -58.0)]
	},
	{
		"id": "east_ferry",
		"name": "东郊古渡道",
		"destination": "东郊忘川古渡",
		"color": Color("#667c7c"),
		"points": [Vector3(54.0, 0.0, -60.0), Vector3(65.0, 0.0, -60.0), Vector3(78.0, 0.0, -58.0)]
	},
	{
		"id": "southwest_battlefield",
		"name": "古战场征魂道",
		"destination": "西南古战场",
		"color": Color("#776c68"),
		"points": [Vector3(-54.0, 0.0, -60.0), Vector3(-57.0, 0.0, -28.0), Vector3(-63.0, 0.0, 2.0), Vector3(-70.0, 0.0, 30.0)]
	}
]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "FengduOuterRoadNetwork"
	for route_variant in ROUTES:
		var route: Dictionary = route_variant
		_add_route(root, route)
	return root


static func get_routes() -> Array:
	return ROUTES.duplicate(true)


static func _add_route(root: Node3D, route: Dictionary) -> void:
	var route_root := Node3D.new()
	route_root.name = "OuterRoad_" + str(route["id"])
	route_root.set_meta("destination_region", str(route["destination"]))
	root.add_child(route_root)
	var points: Array = route["points"]
	var road_color: Color = route["color"]
	var road_material := _material(road_color, 0.98)
	var edge_material := _material(road_color.darkened(0.32), 1.0)
	var marker_material := _material(Color("#37333d"), 0.95)
	for index in range(points.size() - 1):
		var start_point: Vector3 = points[index]
		var end_point: Vector3 = points[index + 1]
		var delta := end_point - start_point
		var length := Vector2(delta.x, delta.z).length()
		if length < 0.1:
			continue
		var road := MeshInstance3D.new()
		road.name = "RoadSegment_%02d" % index
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(3.6 if str(route["id"]) == "south_marsh" else 3.0, 0.09, length)
		road.mesh = road_mesh
		road.position = (start_point + end_point) * 0.5 + Vector3(0.0, 0.07, 0.0)
		road.rotation.y = atan2(delta.x, delta.z)
		road.material_override = road_material
		route_root.add_child(road)
		_add_edge_stones(route_root, index, start_point, end_point, edge_material)
	_add_waystone(route_root, "OriginWaystone", points[0], marker_material, str(route["name"]))
	_add_waystone(route_root, "DestinationWaystone", points[points.size() - 1], marker_material, str(route["destination"]))


static func _add_edge_stones(parent: Node3D, segment_index: int, from: Vector3, to: Vector3, material: Material) -> void:
	var delta := to - from
	var flat_length := Vector2(delta.x, delta.z).length()
	var direction := Vector3(delta.x, 0.0, delta.z).normalized()
	var side := Vector3(-direction.z, 0.0, direction.x)
	var count := maxi(int(floor(flat_length / 10.0)), 1)
	for index in range(1, count):
		var center := from.lerp(to, float(index) / float(count))
		for side_sign in [-1.0, 1.0]:
			var stone := MeshInstance3D.new()
			stone.name = "RoadEdgeStone_%02d_%02d_%s" % [segment_index, index, "L" if side_sign < 0.0 else "R"]
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.42, 0.22, 0.58)
			stone.mesh = mesh
			stone.position = center + side * side_sign * 2.05 + Vector3(0.0, 0.16, 0.0)
			stone.rotation.y = atan2(direction.x, direction.z)
			stone.material_override = material
			parent.add_child(stone)


static func _add_waystone(parent: Node3D, node_name: String, position: Vector3, material: Material, title_text: String) -> void:
	var stone := MeshInstance3D.new()
	stone.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.85, 1.55, 0.5)
	stone.mesh = mesh
	stone.position = position + Vector3(0.0, 0.78, 0.0)
	stone.material_override = material
	parent.add_child(stone)
	var title := Label3D.new()
	title.name = node_name + "Label"
	title.text = title_text
	title.position = position + Vector3(0.0, 2.0, 0.0)
	title.font_size = 18
	title.outline_size = 4
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color("#d7c9a9")
	parent.add_child(title)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
