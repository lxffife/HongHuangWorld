extends Node3D
## Standalone, walkable Fengdu capital blockout.
## All dimensions below are gameplay-scale greybox dimensions, not final art assets.

const WorldEnvironmentBuilder = preload("res://scripts/world_environment_builder.gd")
const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")

const CITY_SCALE := 2.5
const WALL_WIDTH := 1900.0
const WALL_DEPTH := 1475.0
const MOAT_WIDTH := 60.0
const WALL_HEIGHT := 54.0
const WALL_THICKNESS := 18.0
const GATE_OPENING := 112.0

var _city_plan: Dictionary = {}
var _materials: Dictionary = {}
var _player: CharacterBody3D
var _camera_pivot: Node3D
var _camera: Camera3D
var _pitch := -0.08
var _mouse_captured := false
var _hint_label: Label


func _ready() -> void:
	_city_plan = WorldMapCatalog.get_fengdu_city_plan()
	_create_materials()
	var environment_rig := WorldEnvironmentBuilder.build("underworld_fengdu")
	var world_environment := environment_rig.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.fog_density = 0.0015
	add_child(environment_rig)
	_build_ground_and_moat()
	_build_city_walls()
	_build_gatehouses()
	_build_roads()
	_build_districts()
	_build_landmark_silhouette()
	_build_player()
	_build_hud()


func _create_materials() -> void:
	_materials = {
		"ground": _material("#252431"),
		"road": _material("#48434b"),
		"road_edge": _material("#82745f"),
		"wall": _material("#625a60"),
		"wall_top": _material("#887b76"),
		"gate": _material("#55404b"),
		"roof": _material("#493743"),
		"stone": _material("#777078"),
		"water": _material("#263d59", 0.18, true),
		"palace": _material("#8a6842"),
		"court": _material("#69534a"),
		"admin": _material("#526577"),
		"sacred": _material("#716092"),
		"market": _material("#967044"),
		"residential": _material("#596d57"),
		"military": _material("#754750"),
		"transport": _material("#4d7477"),
		"gate_district": _material("#7b705f"),
		"lantern": _emissive_material("#7aa5dc", "#416fae", 2.2)
	}


func _material(color_hex: String, transparency := 0.0, metallic := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color_hex)
	result.roughness = 0.82
	result.metallic = 0.22 if metallic else 0.0
	if transparency > 0.0:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return result


func _emissive_material(color_hex: String, glow_hex: String, energy: float) -> StandardMaterial3D:
	var result := _material(color_hex)
	result.emission_enabled = true
	result.emission = Color(glow_hex)
	result.emission_energy_multiplier = energy
	return result


func _build_ground_and_moat() -> void:
	_add_box("CityGround", Vector3(WALL_WIDTH + 700.0, 8.0, WALL_DEPTH + 700.0), Vector3(0.0, -4.0, 0.0), "ground", true)
	var outer_x := WALL_WIDTH * 0.5 + MOAT_WIDTH * 0.5 + 28.0
	var outer_z := WALL_DEPTH * 0.5 + MOAT_WIDTH * 0.5 + 28.0
	_add_box("NorthMoat", Vector3(WALL_WIDTH + MOAT_WIDTH * 2.0, 1.0, MOAT_WIDTH), Vector3(0.0, 0.15, -outer_z), "water", false)
	_add_box("SouthMoat", Vector3(WALL_WIDTH + MOAT_WIDTH * 2.0, 1.0, MOAT_WIDTH), Vector3(0.0, 0.15, outer_z), "water", false)
	_add_box("WestMoat", Vector3(MOAT_WIDTH, 1.0, WALL_DEPTH), Vector3(-outer_x, 0.15, 0.0), "water", false)
	_add_box("EastMoat", Vector3(MOAT_WIDTH, 1.0, WALL_DEPTH), Vector3(outer_x, 0.15, 0.0), "water", false)
	_add_box("SouthGateBridge", Vector3(150.0, 2.0, MOAT_WIDTH + 50.0), Vector3(0.0, 0.4, outer_z), "road_edge", true)
	_add_box("NorthGateBridge", Vector3(150.0, 2.0, MOAT_WIDTH + 50.0), Vector3(0.0, 0.4, -outer_z), "road_edge", true)
	_add_box("EastGateBridge", Vector3(MOAT_WIDTH + 50.0, 2.0, 150.0), Vector3(outer_x, 0.4, 0.0), "road_edge", true)
	_add_box("WestGateBridge", Vector3(MOAT_WIDTH + 50.0, 2.0, 150.0), Vector3(-outer_x, 0.4, 0.0), "road_edge", true)


func _build_city_walls() -> void:
	var half_x := WALL_WIDTH * 0.5
	var half_z := WALL_DEPTH * 0.5
	var side_segment := (WALL_WIDTH - GATE_OPENING) * 0.5
	var depth_segment := (WALL_DEPTH - GATE_OPENING) * 0.5
	for side in [-1.0, 1.0]:
		_add_box("NorthWall_" + str(side), Vector3(side_segment, WALL_HEIGHT, WALL_THICKNESS), Vector3(side * (GATE_OPENING * 0.5 + side_segment * 0.5), WALL_HEIGHT * 0.5, -half_z), "wall", true)
		_add_box("SouthWall_" + str(side), Vector3(side_segment, WALL_HEIGHT, WALL_THICKNESS), Vector3(side * (GATE_OPENING * 0.5 + side_segment * 0.5), WALL_HEIGHT * 0.5, half_z), "wall", true)
		_add_box("WestWall_" + str(side), Vector3(WALL_THICKNESS, WALL_HEIGHT, depth_segment), Vector3(-half_x, WALL_HEIGHT * 0.5, side * (GATE_OPENING * 0.5 + depth_segment * 0.5)), "wall", true)
		_add_box("EastWall_" + str(side), Vector3(WALL_THICKNESS, WALL_HEIGHT, depth_segment), Vector3(half_x, WALL_HEIGHT * 0.5, side * (GATE_OPENING * 0.5 + depth_segment * 0.5)), "wall", true)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			_add_box("CornerWatchtower_%s_%s" % [x_side, z_side], Vector3(42.0, 78.0, 42.0), Vector3(x_side * (half_x - 12.0), 39.0, z_side * (half_z - 12.0)), "wall_top", true)


func _build_gatehouses() -> void:
	_build_gatehouse("NorthGatehouse", Vector3(0.0, 0.0, -WALL_DEPTH * 0.5), true)
	_build_gatehouse("SouthGatehouse", Vector3(0.0, 0.0, WALL_DEPTH * 0.5), true)
	_build_gatehouse("WestGatehouse", Vector3(-WALL_WIDTH * 0.5, 0.0, 0.0), false)
	_build_gatehouse("EastGatehouse", Vector3(WALL_WIDTH * 0.5, 0.0, 0.0), false)


func _build_gatehouse(gate_name: String, center: Vector3, horizontal: bool) -> void:
	var side_offset := 76.0
	var pillar_size := Vector3(28.0, 70.0, 34.0) if horizontal else Vector3(34.0, 70.0, 28.0)
	var lintel_size := Vector3(180.0, 18.0, 34.0) if horizontal else Vector3(34.0, 18.0, 180.0)
	var left := center + (Vector3(-side_offset, 0.0, 0.0) if horizontal else Vector3(0.0, 0.0, -side_offset))
	var right := center + (Vector3(side_offset, 0.0, 0.0) if horizontal else Vector3(0.0, 0.0, side_offset))
	_add_box(gate_name + "_PillarA", pillar_size, left + Vector3.UP * 35.0, "gate", true)
	_add_box(gate_name + "_PillarB", pillar_size, right + Vector3.UP * 35.0, "gate", true)
	_add_box(gate_name + "_Lintel", lintel_size, center + Vector3.UP * 72.0, "gate", true)
	_add_box(gate_name + "_Beacon", Vector3(9.0, 14.0, 9.0), center + Vector3.UP * 90.0, "lantern", false)


func _build_roads() -> void:
	_add_box("NorthSouthImperialAvenue", Vector3(52.0, 0.6, 1050.0), Vector3(0.0, 0.25, 175.0), "road", false)
	_add_box("EastWestImperialAvenue", Vector3(WALL_WIDTH - 80.0, 0.6, 52.0), Vector3(0.0, 0.27, 0.0), "road", false)
	_add_box("NorthernPalaceApproach", Vector3(38.0, 0.5, 260.0), Vector3(0.0, 0.3, -500.0), "road_edge", false)
	_add_box("SouthernSoulAvenue", Vector3(38.0, 0.5, 270.0), Vector3(0.0, 0.3, 500.0), "road_edge", false)
	for side in [-1.0, 1.0]:
		_add_box("CrossDistrictRoad_" + str(side), Vector3(560.0, 0.5, 26.0), Vector3(side * 280.0, 0.28, side * 300.0), "road", false)
	_add_box("SouthGateToCityRoad", Vector3(44.0, 0.5, 260.0), Vector3(0.0, 0.28, 610.0), "road", false)


func _build_districts() -> void:
	var nodes: Array = _city_plan.get("nodes", [])
	for item in nodes:
		if not item is Dictionary:
			continue
		var district: Dictionary = item
		var kind := str(district.get("kind", "admin"))
		if kind == "gate":
			continue
		var p: Array = district.get("position", [0.0, 0.0])
		var center := Vector3(float(p[0]) * CITY_SCALE, 0.0, -float(p[1]) * CITY_SCALE)
		_build_district_cluster(district, center)


func _build_district_cluster(district: Dictionary, center: Vector3) -> void:
	var kind := str(district.get("kind", "admin"))
	var material_key := "gate_district" if kind == "gate" else kind
	if not _materials.has(material_key):
		material_key = "admin"
	var prefix := str(district.get("id", "District"))
	var is_palace := kind == "palace"
	var main_width := 210.0 if is_palace else 92.0
	var main_depth := 150.0 if is_palace else 68.0
	var main_height := 68.0 if is_palace else 28.0
	if kind == "court":
		main_width = 120.0
		main_depth = 88.0
		main_height = 42.0
	elif kind == "sacred":
		main_width = 140.0
		main_depth = 96.0
		main_height = 48.0
	_add_box(prefix + "_MainHall", Vector3(main_width, main_height, main_depth), center + Vector3(0.0, main_height * 0.5, 0.0), material_key, true)
	_add_roof_cap(prefix + "_MainHallRoof", Vector3(main_width + 18.0, 9.0, main_depth + 18.0), center + Vector3(0.0, main_height + 4.5, 0.0), "roof")
	var wing_offset := 92.0 if is_palace else 66.0
	var wing_size := Vector3(58.0, 20.0, 48.0) if is_palace else Vector3(42.0, 15.0, 38.0)
	for side in [-1.0, 1.0]:
		_add_box(prefix + "_SideHall_" + str(side), wing_size, center + Vector3(side * wing_offset, wing_size.y * 0.5, 82.0), material_key, true)
		_add_roof_cap(prefix + "_SideRoof_" + str(side), Vector3(wing_size.x + 10.0, 6.0, wing_size.z + 10.0), center + Vector3(side * wing_offset, wing_size.y + 3.0, 82.0), "roof")
	_add_box(prefix + "_Courtyard", Vector3(170.0, 0.3, 58.0), center + Vector3(0.0, 0.18, main_depth * 0.5 + 48.0), "road_edge", false)
	_add_box(prefix + "_FrontSteps", Vector3(main_width * 0.72, 3.0, 18.0), center + Vector3(0.0, 1.5, main_depth * 0.5 + 12.0), "stone", true)
	if kind == "market" or kind == "residential":
		for row in range(2):
			for column in range(3):
				var x := (float(column) - 1.0) * 52.0
				var z := -90.0 - float(row) * 50.0
				var stall_size := Vector3(34.0, 13.0 + float((row + column) % 2) * 4.0, 30.0)
				_add_box(prefix + "_Shop_%d_%d" % [row, column], stall_size, center + Vector3(x, stall_size.y * 0.5, z), material_key, true)
				_add_roof_cap(prefix + "_ShopRoof_%d_%d" % [row, column], Vector3(38.0, 5.0, 34.0), center + Vector3(x, stall_size.y + 2.5, z), "roof")
	if kind == "military":
		for i in range(4):
			var x := -75.0 + float(i) * 50.0
			_add_box(prefix + "_Barracks_%d" % i, Vector3(38.0, 18.0, 54.0), center + Vector3(x, 9.0, -92.0), material_key, true)
	if kind == "transport":
		_add_box(prefix + "_Stable", Vector3(90.0, 17.0, 48.0), center + Vector3(0.0, 8.5, -92.0), material_key, true)
		_add_box(prefix + "_Platform", Vector3(150.0, 1.0, 48.0), center + Vector3(0.0, 0.5, 95.0), "stone", true)


func _add_roof_cap(node_name: String, dimensions: Vector3, position: Vector3, material_key: String) -> void:
	var roof := MeshInstance3D.new()
	roof.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	roof.mesh = mesh
	roof.position = position
	roof.material_override = _materials[material_key]
	add_child(roof)


func _build_landmark_silhouette() -> void:
	# Distant skyline spires make the capital's central axis readable from the south gate.
	for i in range(7):
		var x := (float(i) - 3.0) * 82.0
		var height := 52.0 + float((i * 7) % 4) * 18.0
		_add_box("PalaceSkylineSpire_%d" % i, Vector3(8.0, height, 8.0), Vector3(x, height * 0.5, -570.0), "palace", false)
	for side in [-1.0, 1.0]:
		for i in range(8):
			var z := -640.0 + float(i) * 180.0
			var position := Vector3(side * 26.0, 11.0, z)
			_add_box("AvenueLanternStone_%s_%d" % [side, i], Vector3(3.0, 11.0, 3.0), position, "stone", true)
			_add_box("AvenueLanternGlow_%s_%d" % [side, i], Vector3(1.2, 2.0, 1.2), position + Vector3.UP * 6.2, "lantern", false)


func _add_box(node_name: String, dimensions: Vector3, position: Vector3, material_key: String, collision_enabled: bool) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.material_override = _materials.get(material_key, _materials["stone"])
	root.add_child(visual)
	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "CollisionBody"
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = dimensions
		collision.shape = shape
		body.add_child(collision)
		root.add_child(body)
	add_child(root)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "GreyboxPlayer"
	_player.position = Vector3(0.0, 1.1, 600.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.65
	shape.height = 2.0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 1.0
	_player.add_child(collision)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.9
	var body_visual := MeshInstance3D.new()
	body_visual.mesh = body_mesh
	body_visual.position.y = 1.0
	body_visual.material_override = _material("#c5ad88")
	_player.add_child(body_visual)
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_camera_pivot.position = Vector3(0.0, 1.55, 0.0)
	_player.add_child(_camera_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 74.0
	_camera_pivot.add_child(_camera)
	add_child(_player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GreyboxHUD"
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(440.0, 94.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "酆都天城 · 3D 灰盒漫游"
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	_hint_label = Label.new()
	_hint_label.text = "WASD 移动 · 鼠标观察 · Shift 奔跑 · Space 跳跃 · Esc 释放鼠标"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)
	var note := Label.new()
	note.text = "南门入城：中央御道直望皇城。当前为比例灰盒，建筑与服务尚未接入。"
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	add_child(layer)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_captured = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_mouse_captured = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_SPACE and _player != null and _player.is_on_floor():
			_player.velocity.y = 8.0
	elif event is InputEventMouseMotion and _mouse_captured:
		_player.rotate_y(-event.relative.x * 0.0024)
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -1.15, 0.9)
		_camera_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var input_vector := Vector2.ZERO
	input_vector.x = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	input_vector.y = float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	input_vector = input_vector.normalized()
	var speed := 18.0 if Input.is_key_pressed(KEY_SHIFT) else 9.0
	var direction := (_player.global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	_player.velocity.x = direction.x * speed
	_player.velocity.z = direction.z * speed
	if not _player.is_on_floor():
		_player.velocity.y -= 24.0 * delta
	else:
		_player.velocity.y = maxf(_player.velocity.y, -1.0)
	_player.move_and_slide()
