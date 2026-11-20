extends Node3D
## Standalone, walkable Fengdu capital blockout.
## All dimensions below are gameplay-scale greybox dimensions, not final art assets.

const WorldEnvironmentBuilder = preload("res://scripts/world_environment_builder.gd")
const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const CityModuleScene = preload("res://scenes/experiments/FengduCityModule.tscn")

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
var _nearby_district_data: Dictionary = {}


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
	_build_wall_defenses()
	_build_gate_signs()
	_build_patrol_guards()
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
		result.albedo_color.a = 0.72
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
			_spawn_city_module({"module_kind": "watchtower"}, Vector3(x_side * (half_x - 12.0), 0.0, z_side * (half_z - 12.0)))
	for side in [-1.0, 1.0]:
		for offset in [-320.0, 320.0]:
			_spawn_city_module({"module_kind": "watchtower"}, Vector3(offset, 0.0, side * half_z))
			_spawn_city_module({"module_kind": "watchtower"}, Vector3(side * half_x, 0.0, offset))


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
	_add_box("NorthGateProcessionalRoad", Vector3(38.0, 0.5, 180.0), Vector3(0.0, 0.3, -635.0), "road_edge", false)
	_add_box("SouthernSoulAvenue", Vector3(38.0, 0.5, 270.0), Vector3(0.0, 0.3, 500.0), "road_edge", false)
	for side in [-1.0, 1.0]:
		_add_box("CrossDistrictRoad_" + str(side), Vector3(560.0, 0.5, 26.0), Vector3(side * 280.0, 0.28, side * 300.0), "road", false)
	_add_box("SouthGateToCityRoad", Vector3(44.0, 0.5, 260.0), Vector3(0.0, 0.28, 610.0), "road", false)
	_add_box("WestInnerStreet", Vector3(26.0, 0.5, 520.0), Vector3(-260.0, 0.28, 150.0), "road", false)
	_add_box("EastInnerStreet", Vector3(26.0, 0.5, 520.0), Vector3(260.0, 0.28, 150.0), "road", false)
	_add_box("NorthernCrossStreet", Vector3(520.0, 0.5, 26.0), Vector3(0.0, 0.28, -100.0), "road", false)
	_add_box("SouthernCrossStreet", Vector3(520.0, 0.5, 26.0), Vector3(0.0, 0.28, 310.0), "road", false)
	_add_box("MarketApproachWest", Vector3(100.0, 0.5, 26.0), Vector3(-310.0, 0.28, 310.0), "road", false)
	_add_box("MarketApproachEast", Vector3(100.0, 0.5, 26.0), Vector3(310.0, 0.28, 310.0), "road", false)
	_add_box("ReincarnationApproach", Vector3(26.0, 0.5, 230.0), Vector3(380.0, 0.28, 490.0), "road", false)


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
		match str(district.get("id", "")):
			"ghost_registry", "merit_bureau":
				center.z += 125.0
			"patrol_office":
				center += Vector3(155.0, 0.0, 145.0)
			"reincarnation_bureau":
				center.x += 380.0
		_build_district_cluster(district, center)


func _build_district_cluster(district: Dictionary, center: Vector3) -> void:
	var module_data := district.duplicate(true)
	module_data["module_kind"] = "district"
	var module := _spawn_city_module(module_data, center)
	module.name = "District_" + str(district.get("id", "unknown"))
	module.connect("player_entered", Callable(self, "_on_district_entered"))
	module.connect("player_exited", Callable(self, "_on_district_exited"))


func _spawn_city_module(data: Dictionary, world_position: Vector3) -> Node3D:
	var module := CityModuleScene.instantiate() as Node3D
	module.call("configure", data)
	module.position = world_position
	add_child(module)
	return module


func _build_wall_defenses() -> void:
	var half_x := WALL_WIDTH * 0.5
	var half_z := WALL_DEPTH * 0.5
	for i in range(17):
		var x := -half_x + 70.0 + float(i) * 110.0
		if absf(x) > GATE_OPENING * 0.5 + 30.0:
			for side in [-1.0, 1.0]:
				_add_box("WallCrenel_X_%d_%s" % [i, side], Vector3(22.0, 9.0, 22.0), Vector3(x, WALL_HEIGHT + 4.0, side * half_z), "wall_top", false)
	for i in range(12):
		var z := -half_z + 70.0 + float(i) * 110.0
		if absf(z) > GATE_OPENING * 0.5 + 30.0:
			for side in [-1.0, 1.0]:
				_add_box("WallCrenel_Z_%d_%s" % [i, side], Vector3(22.0, 9.0, 22.0), Vector3(side * half_x, WALL_HEIGHT + 4.0, z), "wall_top", false)


func _build_gate_signs() -> void:
	_add_world_label("北天门 · 罗酆山方向", Vector3(0.0, 104.0, -WALL_DEPTH * 0.5 - 24.0), 0.0)
	_add_world_label("南幽门 · 忘川轮回方向", Vector3(0.0, 104.0, WALL_DEPTH * 0.5 + 24.0), 0.0)
	_add_world_label("西冥门 · 古战场方向", Vector3(-WALL_WIDTH * 0.5 - 24.0, 104.0, 0.0), -PI * 0.5)
	_add_world_label("东玄门 · 幽冥荒原方向", Vector3(WALL_WIDTH * 0.5 + 24.0, 104.0, 0.0), PI * 0.5)


func _add_world_label(value: String, p: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = p
	label.rotation.y = yaw
	label.font_size = 46
	label.pixel_size = 0.026
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("#e7d7b8")
	add_child(label)


func _build_patrol_guards() -> void:
	var guards := [
		{"name": "南门守城阴兵", "position": Vector3(-52.0, 0.0, 660.0)},
		{"name": "南门巡逻阴兵", "position": Vector3(52.0, 0.0, 660.0)},
		{"name": "北门守城阴兵", "position": Vector3(-52.0, 0.0, -660.0)},
		{"name": "北门巡逻阴兵", "position": Vector3(52.0, 0.0, -660.0)},
		{"name": "西门守城阴兵", "position": Vector3(-875.0, 0.0, -52.0)},
		{"name": "东门守城阴兵", "position": Vector3(875.0, 0.0, 52.0)},
		{"name": "皇城巡逻阴兵", "position": Vector3(-92.0, 0.0, -260.0)},
		{"name": "皇城巡逻阴兵", "position": Vector3(92.0, 0.0, -260.0)},
		{"name": "鬼市巡逻阴兵", "position": Vector3(430.0, 0.0, 420.0)},
		{"name": "魂坊巡逻阴兵", "position": Vector3(-430.0, 0.0, 420.0)}
	]
	for index in range(guards.size()):
		var guard_data: Dictionary = guards[index]
		var module := CityModuleScene.instantiate() as Node3D
		module.name = "PatrolGuard_%02d" % index
		guard_data["module_kind"] = "guard"
		module.call("configure", guard_data)
		module.position = guard_data["position"]
		add_child(module)


func _on_district_entered(data: Dictionary) -> void:
	_nearby_district_data = data.duplicate(true)
	var title := str(data.get("name", "城区"))
	_hint_label.text = "已到达：%s · 按 E 查看城区信息" % title


func _on_district_exited(data: Dictionary) -> void:
	if str(_nearby_district_data.get("id", "")) == str(data.get("id", "")):
		_nearby_district_data.clear()
		_hint_label.text = "WASD 移动 · 鼠标观察 · Shift 奔跑 · Space 跳跃 · Esc 释放鼠标"


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
	_player.add_to_group("fengdu_player")
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
		if event.keycode == KEY_E and not _nearby_district_data.is_empty():
			var data := _nearby_district_data
			_hint_label.text = "%s\n主管：%s · 开放条件：%s\n%s" % [str(data.get("name", "城区")), str(data.get("authority", "未知")), str(data.get("access", "无")), str(data.get("description", ""))]
		elif event.keycode == KEY_ESCAPE:
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
