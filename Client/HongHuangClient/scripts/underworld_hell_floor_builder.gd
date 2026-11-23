extends RefCounted
## Procedural blockout for an individual underworld hell instance.
## Visual hazards are placeholders only; damage, objectives and guardian AI remain server-owned.

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")

static func build(floor_number: int) -> Node3D:
	var data := WorldMapCatalog.get_hell_floor_data(floor_number)
	if data.is_empty():
		return Node3D.new()
	var root := Node3D.new()
	root.name = "HellFloor_%02d" % floor_number
	var palette := _palette(floor_number)
	_add_arena_floor(root, palette["floor"])
	_add_arena_walls(root, palette["wall"])
	_add_pillars(root, palette["pillar"])
	_add_hazard_blockout(root, floor_number, palette["hazard"])
	_add_guardian_platform(root, str(data.get("guardian", "守狱者")), palette["accent"])
	_add_portal(root, "EntrancePortal", "来路 · 返回阴司", Vector3(0.0, 0.0, 27.0), palette["accent"])
	_add_portal(root, "TrialExitPortal", "下一层入口（待服务端开放）", Vector3(0.0, 0.0, -27.0), palette["accent"])
	_add_label(root, "FloorTitle", "第 %02d 层 · %s" % [floor_number, str(data.get("name", "地狱"))], Vector3(0.0, 15.0, 0.0), palette["accent"], 42)
	_add_label(root, "FloorObjective", "试炼目标：" + str(data.get("objective", "")), Vector3(0.0, 12.0, 0.0), Color("#d7d0c6"), 22)
	_add_label(root, "GuardianName", "守狱者：" + str(data.get("guardian", "")), Vector3(0.0, 5.0, -9.0), palette["accent"], 24)
	root.set_meta("hell_floor_number", floor_number)
	root.set_meta("hell_floor_id", str(data.get("id", "")))
	root.set_meta("trial_objective", str(data.get("objective", "")))
	root.set_meta("hazard_visual_only", true)
	return root


static func _palette(floor_number: int) -> Dictionary:
	var palettes := [
		{"floor": "#34313b", "wall": "#51434b", "pillar": "#78616c", "hazard": "#b67d91", "accent": "#e2b7c7"},
		{"floor": "#34303a", "wall": "#4e4358", "pillar": "#77657f", "hazard": "#bd9bd1", "accent": "#ddc3eb"},
		{"floor": "#343238", "wall": "#4a4547", "pillar": "#75645a", "hazard": "#a98c76", "accent": "#e0c6a2"},
		{"floor": "#292d3a", "wall": "#41485c", "pillar": "#66728e", "hazard": "#8ba8d6", "accent": "#c9d8f2"},
		{"floor": "#3a2d2b", "wall": "#5c4039", "pillar": "#8a5c4c", "hazard": "#d88b59", "accent": "#f0bd83"},
		{"floor": "#3b2c29", "wall": "#5d3d34", "pillar": "#8b5a44", "hazard": "#e17a4d", "accent": "#f3bd82"},
		{"floor": "#33313b", "wall": "#51495c", "pillar": "#796d8d", "hazard": "#b9a3d9", "accent": "#e0d2f5"},
		{"floor": "#283342", "wall": "#3c5269", "pillar": "#67839d", "hazard": "#81c4e6", "accent": "#d0efff"},
		{"floor": "#392b2b", "wall": "#5b3b35", "pillar": "#86584b", "hazard": "#e18c55", "accent": "#f1c18d"},
		{"floor": "#34302b", "wall": "#514b3d", "pillar": "#7c725b", "hazard": "#c4a46d", "accent": "#e6d1a3"},
		{"floor": "#343238", "wall": "#514b50", "pillar": "#766a70", "hazard": "#b7a7a0", "accent": "#e2d3c9"},
		{"floor": "#33302d", "wall": "#51483d", "pillar": "#786b56", "hazard": "#c4a46d", "accent": "#e7d4a7"},
		{"floor": "#39272f", "wall": "#5b3446", "pillar": "#865067", "hazard": "#d85b83", "accent": "#f3a9c1"},
		{"floor": "#34303a", "wall": "#51475c", "pillar": "#786d8a", "hazard": "#a98fd2", "accent": "#ded0f5"},
		{"floor": "#353036", "wall": "#59424d", "pillar": "#815d69", "hazard": "#c47a8e", "accent": "#e9b4c2"},
		{"floor": "#3a2926", "wall": "#5d3c32", "pillar": "#8a5544", "hazard": "#e87545", "accent": "#f6b17b"},
		{"floor": "#302c31", "wall": "#50474c", "pillar": "#75666c", "hazard": "#aa8d9a", "accent": "#ddc2ce"},
		{"floor": "#211d2c", "wall": "#3a2b48", "pillar": "#665078", "hazard": "#9c65d0", "accent": "#e0b8ff"}
	]
	var selected: Dictionary = palettes[clampi(floor_number - 1, 0, 17)]
	var result: Dictionary = {}
	for key in selected.keys():
		result[key] = Color(str(selected[key]))
	return result


static func _add_arena_floor(root: Node3D, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "TrialArenaFloor"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(58.0, 58.0)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(58.0, 0.2, 58.0)
	collision.shape = shape
	collision.position.y = -0.1
	body.add_child(collision)
	root.add_child(body)


static func _add_arena_walls(root: Node3D, color: Color) -> void:
	for side in [-1.0, 1.0]:
		_add_wall(root, "ArenaWallX_" + str(side), Vector3(1.8, 8.0, 58.0), Vector3(side * 29.0, 4.0, 0.0), color)
		_add_wall(root, "ArenaWallZ_" + str(side), Vector3(58.0, 8.0, 1.8), Vector3(0.0, 4.0, side * 29.0), color)


static func _add_pillars(root: Node3D, color: Color) -> void:
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			var pillar := CylinderMesh.new()
			pillar.top_radius = 0.75
			pillar.bottom_radius = 1.0
			pillar.height = 9.0
			pillar.radial_segments = 12
			var instance := MeshInstance3D.new()
			instance.name = "TrialPillar"
			instance.mesh = pillar
			instance.position = Vector3(x_side * 23.0, 4.5, z_side * 23.0)
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.86
			instance.material_override = material
			root.add_child(instance)


static func _add_hazard_blockout(root: Node3D, floor_number: int, color: Color) -> void:
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var position := Vector3(cos(angle) * 15.0, 0.8, sin(angle) * 15.0)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "HazardMarker_%02d" % index
		if floor_number == 8:
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = 0.75
			spike.height = 2.8
			mesh_instance.mesh = spike
		elif floor_number in [6, 9, 16, 18]:
			var flame := SphereMesh.new()
			flame.radius = 0.9
			flame.height = 1.8
			mesh_instance.mesh = flame
		else:
			var marker := BoxMesh.new()
			marker.size = Vector3(1.8, 1.2, 1.8)
			mesh_instance.mesh = marker
		mesh_instance.position = position
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.5
		mesh_instance.material_override = material
		root.add_child(mesh_instance)


static func _add_guardian_platform(root: Node3D, guardian_name: String, color: Color) -> void:
	var platform := MeshInstance3D.new()
	platform.name = "GuardianDais"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 4.8
	cylinder.bottom_radius = 5.5
	cylinder.height = 0.9
	cylinder.radial_segments = 32
	platform.mesh = cylinder
	platform.position = Vector3(0.0, 0.45, -9.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#4a3e4e")
	material.metallic = 0.18
	platform.material_override = material
	root.add_child(platform)
	_add_label(root, "GuardianMarker", "守狱者 · " + guardian_name, Vector3(0.0, 2.0, -9.0), color, 20)


static func _add_portal(root: Node3D, node_name: String, label_text: String, position: Vector3, color: Color) -> void:
	var portal := Node3D.new()
	portal.name = node_name
	portal.position = position
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.65, 5.0, 0.8)
		var post_node := MeshInstance3D.new()
		post_node.mesh = post
		post_node.position = Vector3(side * 2.1, 2.5, 0.0)
		var post_material := StandardMaterial3D.new()
		post_material.albedo_color = color.darkened(0.25)
		post_node.material_override = post_material
		portal.add_child(post_node)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(5.0, 0.7, 0.9)
	var lintel_node := MeshInstance3D.new()
	lintel_node.mesh = lintel
	lintel_node.position = Vector3(0.0, 5.0, 0.0)
	var lintel_material := StandardMaterial3D.new()
	lintel_material.albedo_color = color
	lintel_material.emission_enabled = true
	lintel_material.emission = color
	lintel_material.emission_energy_multiplier = 1.1
	lintel_node.material_override = lintel_material
	portal.add_child(lintel_node)
	root.add_child(portal)
	_add_label(root, node_name + "Label", label_text, position + Vector3(0.0, 6.2, 0.0), color, 18)


static func _add_wall(root: Node3D, node_name: String, dimensions: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)


static func _add_label(root: Node3D, node_name: String, text_value: String, position: Vector3, color: Color, font_size: int) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text_value
	label.position = position
	label.font_size = font_size
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	root.add_child(label)
