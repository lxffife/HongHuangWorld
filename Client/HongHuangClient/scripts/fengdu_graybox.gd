extends Node3D
## Walkable Fengdu capital graybox. All dimensions in meters.
## This is a client-side art/navigation prototype; gates and permissions are not authoritative.

const CITY_HALF := 96.0
const MOAT_HALF := 108.0
const WALL_HEIGHT := 13.0
const WALL_THICKNESS := 5.0
const GATE_WIDTH := 16.0
const PLAYER_SPEED := 8.0
const MOUSE_SENSITIVITY := 0.0025

var player: CharacterBody3D
var camera: Camera3D
var camera_pitch := deg_to_rad(-18.0)
var mouse_captured := false
var status_label: Label
var district_markers: Dictionary = {}

var mats: Dictionary = {}


func _ready() -> void:
	_create_materials()
	_build_environment()
	_build_outer_landscape()
	_build_ground_and_roads()
	_build_moat_and_bridges()
	_build_city_walls()
	_build_gate_complexes()
	_build_districts()
	_build_palace_axis()
	_build_street_furnishings()
	_build_player()
	_build_hud()


func _process(delta: float) -> void:
	if player == null:
		return
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var move_dir := (right * input_dir.x + forward * -input_dir.y)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()
	player.velocity.x = move_dir.x * PLAYER_SPEED
	player.velocity.z = move_dir.z * PLAYER_SPEED
	if not player.is_on_floor():
		player.velocity.y -= 24.0 * delta
	elif Input.is_key_pressed(KEY_SPACE):
		player.velocity.y = 8.5
	player.move_and_slide()
	_update_camera()
	_update_hud()


func _update_camera() -> void:
	if camera == null or player == null:
		return
	var orbit_offset := Vector3(0, 0, 8.0).rotated(Vector3.RIGHT, camera_pitch) + Vector3(0, 1.8, 0)
	var offset := orbit_offset.rotated(Vector3.UP, player.rotation.y)
	camera.global_position = player.global_position + offset
	camera.look_at(player.global_position + Vector3(0, 1.25, 0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_capture_mouse()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_release_mouse()
	elif event is InputEventMouseMotion and mouse_captured:
		var motion := event as InputEventMouseMotion
		player.rotation.y -= motion.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clampf(camera_pitch - motion.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-55.0), deg_to_rad(8.0))


func _capture_mouse() -> void:
	mouse_captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _create_materials() -> void:
	mats = {
		"ground": _mat(Color("#242b32"), 0.96),
		"stone": _mat(Color("#59616a"), 0.88),
		"dark_stone": _mat(Color("#303941"), 0.9),
		"road": _mat(Color("#77736d"), 0.92),
		"road_edge": _mat(Color("#a18d73"), 0.82),
		"wall": _mat(Color("#4b5661"), 0.88),
		"roof": _mat(Color("#252d3a"), 0.72),
		"roof_edge": _mat(Color("#9a754e"), 0.7),
		"gold": _mat(Color("#c39a5b"), 0.55),
		"water": _mat(Color("#172f45", 0.82), 0.24, true),
		"lantern": _mat(Color("#e8ad5d"), 0.3, true),
		"palace": _mat(Color("#75604d"), 0.72),
		"district": _mat(Color("#48545d"), 0.9),
		"bridge": _mat(Color("#81715e"), 0.88)
	}


func _mat(color: Color, roughness: float = 0.8, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.45
	return material


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#101b2b")
	sky_material.sky_horizon_color = Color("#59606b")
	sky_material.ground_bottom_color = Color("#111923")
	sky_material.ground_horizon_color = Color("#353b45")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#78849a")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#424b59")
	environment.fog_density = 0.0028
	environment.fog_sky_affect = 0.7
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	sun.light_color = Color("#9aa9c0")
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	add_child(sun)
	var moon := OmniLight3D.new()
	moon.position = Vector3(0, 24, 0)
	moon.light_color = Color("#6c91c7")
	moon.light_energy = 1.4
	moon.omni_range = 120.0
	add_child(moon)


func _build_outer_landscape() -> void:
	# Broad approach plain and distant stepped mountain silhouettes frame the capital.
	_box("FengduOuterPlain", Vector3(0, -1.15, 0), Vector3(580, 0.8, 580), "ground", true)
	for i in range(7):
		var angle := TAU * float(i) / 7.0
		var radius := 205.0 + float(i % 3) * 18.0
		var center := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var width := 42.0 + float(i % 2) * 18.0
		_box("DistantMountainFoot", center + Vector3(0, 7, 0), Vector3(width, 14, width * 0.8), "dark_stone", false)
		_box("DistantMountainRidge", center + Vector3(0, 19, 0), Vector3(width * 0.68, 12, width * 0.55), "stone", false)
		_box("DistantMountainPeak", center + Vector3(0, 29, 0), Vector3(width * 0.36, 10, width * 0.3), "dark_stone", false)
	# Four processional causeways extend beyond the moat toward the outer roads.
	_box("NorthApproachRoad", Vector3(0, 0.02, 151), Vector3(11, 0.12, 72), "road", false)
	_box("SouthApproachRoad", Vector3(0, 0.02, -151), Vector3(11, 0.12, 72), "road", false)
	_box("EastApproachRoad", Vector3(151, 0.02, 0), Vector3(72, 0.12, 11), "road", false)
	_box("WestApproachRoad", Vector3(-151, 0.02, 0), Vector3(72, 0.12, 11), "road", false)


func _build_street_furnishings() -> void:
	# Lantern posts provide a readable night-time rhythm without expensive real lights.
	for z in range(-84, 85, 14):
		_lantern_post(Vector3(-10.5, 0, float(z)))
		_lantern_post(Vector3(10.5, 0, float(z)))
	for x in range(-84, 85, 14):
		if absf(float(x)) > 15.0:
			_lantern_post(Vector3(float(x), 0, -10.5))
			_lantern_post(Vector3(float(x), 0, 10.5))
	# Stone balustrades mark bridge edges and keep the causeway silhouette legible.
	for sign in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box("NorthSouthBridgeRail", Vector3(sign * 7.2, 1.0, z * (CITY_HALF + 7.5)), Vector3(0.7, 1.8, 17), "stone", true)
			_box("EastWestBridgeRail", Vector3(z * (CITY_HALF + 7.5), 1.0, sign * 7.2), Vector3(17, 1.8, 0.7), "stone", true)
	# Small paved squares create breathing space at district entrances.
	for center in [Vector3(-55, 0, -36), Vector3(55, 0, -36), Vector3(-52, 0, 20), Vector3(52, 0, 20)]:
		_box("DistrictForecourt", center + Vector3(0, 0.06, 0), Vector3(15, 0.12, 8), "road_edge", false)


func _lantern_post(position: Vector3) -> void:
	_box("LanternStoneBase", position + Vector3(0, 0.45, 0), Vector3(0.8, 0.9, 0.8), "dark_stone", true)
	_box("LanternPost", position + Vector3(0, 2.0, 0), Vector3(0.28, 2.4, 0.28), "gold", true)
	_box("LanternHousing", position + Vector3(0, 3.55, 0), Vector3(1.0, 1.0, 1.0), "lantern", false)
	_box("LanternCap", position + Vector3(0, 4.15, 0), Vector3(1.35, 0.25, 1.35), "roof", false)


func _build_ground_and_roads() -> void:
	_box("CityGround", Vector3(0, -0.55, 0), Vector3(600, 1, 600), "ground", true)
	_box("NorthSouthMainRoad", Vector3(0, 0.03, 0), Vector3(13, 0.12, 190), "road", false)
	_box("EastWestMainRoad", Vector3(0, 0.04, 0), Vector3(190, 0.12, 13), "road", false)
	_box("CentralProcessionalWay", Vector3(0, 0.06, 38), Vector3(20, 0.14, 100), "road_edge", false)
	for x in [-27.0, 27.0]:
		_box("PalaceApproach", Vector3(x, 0.035, 34), Vector3(5, 0.1, 90), "road", false)
	for z in [-32.0, 32.0]:
		_box("DistrictCrossStreet", Vector3(0, 0.035, z), Vector3(150, 0.1, 7), "road", false)


func _build_moat_and_bridges() -> void:
	var width := 7.0
	var center := MOAT_HALF - width * 0.5
	_box("NorthMoat", Vector3(0, -0.12, center), Vector3(MOAT_HALF * 2.0, 0.22, width), "water", false)
	_box("SouthMoat", Vector3(0, -0.12, -center), Vector3(MOAT_HALF * 2.0, 0.22, width), "water", false)
	_box("EastMoat", Vector3(center, -0.12, 0), Vector3(width, 0.22, MOAT_HALF * 2.0), "water", false)
	_box("WestMoat", Vector3(-center, -0.12, 0), Vector3(width, 0.22, MOAT_HALF * 2.0), "water", false)
	_box("NorthBridge", Vector3(0, 0.12, CITY_HALF + 7.5), Vector3(GATE_WIDTH, 0.45, 17), "bridge", true)
	_box("SouthBridge", Vector3(0, 0.12, -CITY_HALF - 7.5), Vector3(GATE_WIDTH, 0.45, 17), "bridge", true)
	_box("EastBridge", Vector3(CITY_HALF + 7.5, 0.12, 0), Vector3(17, 0.45, GATE_WIDTH), "bridge", true)
	_box("WestBridge", Vector3(-CITY_HALF - 7.5, 0.12, 0), Vector3(17, 0.45, GATE_WIDTH), "bridge", true)


func _build_city_walls() -> void:
	var half := CITY_HALF
	var side_len := half * 2.0
	var segment := (side_len - GATE_WIDTH) * 0.5
	for sign in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			var z := sign * half
			var x := side * (GATE_WIDTH * 0.5 + segment * 0.5)
			_box("NorthSouthWall", Vector3(x, WALL_HEIGHT * 0.5, z), Vector3(segment, WALL_HEIGHT, WALL_THICKNESS), "wall", true)
			var x2 := sign * half
			var z2 := side * (GATE_WIDTH * 0.5 + segment * 0.5)
			_box("EastWestWall", Vector3(x2, WALL_HEIGHT * 0.5, z2), Vector3(WALL_THICKNESS, WALL_HEIGHT, segment), "wall", true)
	for x in [-half, half]:
		for z in [-half, half]:
			_box("CornerTower", Vector3(x, 10.0, z), Vector3(10, 20, 10), "dark_stone", true)
			_roof_tier(Vector3(x, 20.4, z), 12.0, 4.0)
	for side in [-1.0, 1.0]:
		for i in range(1, 8):
			var p := -half + float(i) * (side_len / 8.0)
			_box("WallMerlon", Vector3(p, WALL_HEIGHT + 1.1, side * half), Vector3(2.0, 2.2, 5.8), "stone", true)
			_box("WallMerlon", Vector3(side * half, WALL_HEIGHT + 1.1, p), Vector3(5.8, 2.2, 2.0), "stone", true)


func _build_gate_complexes() -> void:
	_gate("北天门", Vector3(0, 0, CITY_HALF), Vector3(0, 0, 1), "罗酆山古道")
	_gate("南幽门", Vector3(0, 0, -CITY_HALF), Vector3(0, 0, -1), "忘川与轮回渡口")
	_gate("东玄门", Vector3(CITY_HALF, 0, 0), Vector3(1, 0, 0), "幽冥荒原远域官道")
	_gate("西冥门", Vector3(-CITY_HALF, 0, 0), Vector3(-1, 0, 0), "阴司军屯与古战场")


func _gate(title: String, center: Vector3, outward: Vector3, destination: String) -> void:
	var axis_x := absf(outward.x) < 0.5
	var post_size := Vector3(5, 17, 7) if axis_x else Vector3(7, 17, 5)
	for side in [-1.0, 1.0]:
		var offset := Vector3(8.5 * side, 0, 0) if axis_x else Vector3(0, 0, 8.5 * side)
		_box(title + "GatePier", center + offset + Vector3(0, 8.5, 0), post_size, "dark_stone", true)
		_roof_tier(center + offset + Vector3(0, 17.5, 0), 10.0, 3.0)
	_box(title + "GateLintel", center + Vector3(0, 16.5, 0), Vector3(23, 3.5, 7), "gold", true)
	_box(title + "GateRoad", center + outward * 8.0 + Vector3(0, 0.2, 0), Vector3(17, 0.4, 17), "bridge", true)
	_label(title, center + Vector3(0, 23, 0), 34, Color("#e6c58d"))
	_label("通往：" + destination, center + Vector3(0, 20.5, 0), 18, Color("#c4cbd4"))


func _build_districts() -> void:
	_district("万家魂坊", Vector3(-55, 0, -53), Vector2(34, 26), "居住 · 工匠 · 社区", 5, Color("#a9b9c4"))
	_district("万魂鬼市", Vector3(55, 0, -53), Vector2(34, 26), "交易 · 拍卖 · 情报", 6, Color("#d7b47b"))
	_district("鬼籍司", Vector3(-52, 0, 4), Vector2(27, 24), "新魂登记 · 身份凭籍", 4, Color("#9cb8c8"))
	_district("功过司", Vector3(52, 0, 4), Vector2(27, 24), "功德 · 罪业 · 因果", 4, Color("#c4b28e"))
	_district("十王府", Vector3(-51, 0, 48), Vector2(30, 23), "十殿审判 · 刑狱协调", 5, Color("#b9a4a4"))
	_district("判官司", Vector3(51, 0, 48), Vector2(30, 23), "案卷复核 · 司法文书", 5, Color("#b9a4a4"))
	_district("巡城司", Vector3(0, 0, 12), Vector2(23, 20), "治安 · 巡逻 · 夜禁", 4, Color("#a5b2c0"))
	_district("轮回司", Vector3(0, 0, -68), Vector2(32, 20), "轮回文牒 · 忘川通道", 5, Color("#b6a5d0"))
	_district("阴兵大营", Vector3(-77, 0, 0), Vector2(18, 27), "城防 · 军需 · 驻军", 3, Color("#9ba6b2"))
	_district("引魂驿站", Vector3(77, 0, 0), Vector2(18, 27), "接引 · 分流 · 远途驿传", 3, Color("#a8b7c3"))


func _district(title: String, center: Vector3, footprint: Vector2, subtitle: String, building_count: int, accent: Color) -> void:
	var base_size := Vector3(footprint.x, 0.45, footprint.y)
	_box(title + "Foundation", center + Vector3(0, 0.22, 0), base_size, "district", false)
	var count := maxi(building_count, 1)
	var columns := ceili(sqrt(float(count)))
	for i in range(count):
		var col := i % columns
		var row := i / columns
		var spacing_x := footprint.x / float(columns + 1)
		var spacing_z := footprint.y / float(columns + 1)
		var pos := center + Vector3((float(col) - float(columns - 1) * 0.5) * spacing_x, 0, (float(row) - float(columns - 1) * 0.5) * spacing_z)
		var scale_factor := 1.0 if i == 0 else 0.68
		var w := (5.0 if i == 0 else 3.8) * scale_factor
		var h := (7.0 if i == 0 else 4.5) * scale_factor
		_box(title + "Hall", pos + Vector3(0, h * 0.5, 0), Vector3(w, h, w * 0.8), "palace", true)
		_roof_tier(pos + Vector3(0, h + 0.7, 0), w * 1.45, 2.2)
		_box(title + "Sign", pos + Vector3(0, h + 3.0, 0), Vector3(0.24, 1.0, 0.24), "gold", false)
	_label(title, center + Vector3(0, 13, 0), 26, accent)
	_label(subtitle, center + Vector3(0, 10.5, 0), 15, Color("#d2d6dc"))
	district_markers[title] = center


func _build_palace_axis() -> void:
	# The palace is the city's visual anchor, intentionally larger than every bureau.
	var center := Vector3(0, 0, 72)
	district_markers["酆都皇城"] = center
	_label("酆都皇城", center + Vector3(0, 34, 0), 30, Color("#e0c08b"))
	_box("ImperialPalaceTerrace", center + Vector3(0, 0.55, 0), Vector3(43, 1.1, 28), "gold", false)
	_box("ImperialMainHall", center + Vector3(0, 9, 0), Vector3(23, 17, 15), "palace", true)
	for x in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		_box("PalacePillar", center + Vector3(x, 7.0, 8.0), Vector3(0.9, 14, 0.9), "gold", true)
	_roof_tier(center + Vector3(0, 19, 0), 31, 5)
	_roof_tier(center + Vector3(0, 25, 0), 23, 4)
	_label("酆都大帝 · 皇城正殿", center + Vector3(0, 32, 0), 38, Color("#f1d49d"))
	for z in [48.0, 34.0, 20.0, 6.0]:
		_box("PalaceProcessionStep", Vector3(0, 0.35, z), Vector3(20, 0.7, 3), "road_edge", true)


func _roof_tier(center: Vector3, width: float, height: float) -> void:
	_box("RoofTierBase", center + Vector3(0, height * 0.25, 0), Vector3(width, height * 0.5, width * 0.72), "roof", false)
	_box("RoofTierEave", center + Vector3(0, height * 0.52, 0), Vector3(width * 1.18, 0.32, width * 0.9), "roof_edge", false)
	_box("RoofTierCap", center + Vector3(0, height * 0.75, 0), Vector3(width * 0.72, height * 0.42, width * 0.55), "roof", false)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "GrayboxPlayer"
	player.position = Vector3(0, 1.4, -20)
	add_child(player)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	player.add_child(collision)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.48
	body_mesh.height = 1.8
	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _mat(Color("#6c9bb5"), 0.5)
	player.add_child(body)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.4, 0)
	player.add_child(pivot)
	camera = Camera3D.new()
	camera.position = Vector3(0, 3.2, 8.0)
	camera.rotation.x = camera_pitch
	camera.current = true
	pivot.add_child(camera)
	# Keep camera yaw aligned with the player, but pitch independently.
	camera.set_as_top_level(true)
	camera.position = player.global_position + Vector3(0, 4.6, 8.0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(390, 96)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "酆都天城 · 3D 灰盒漫游"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	status_label = Label.new()
	column.add_child(status_label)
	var help := Label.new()
	help.text = "WASD 移动 · 空格跳跃 · 鼠标左键捕获视角 · ESC 释放鼠标"
	column.add_child(help)


func _update_hud() -> void:
	if status_label == null or player == null:
		return
	var p := player.global_position
	var nearest := "城中主街"
	var nearest_distance := INF
	for district_name in district_markers.keys():
		var distance: float = Vector2(p.x, p.z).distance_to(Vector2(district_markers[district_name].x, district_markers[district_name].z))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = str(district_name)
	status_label.text = "位置 %.1f, %.1f  ·  附近：%s" % [p.x, p.z, nearest]


func _box(node_name: String, center: Vector3, size: Vector3, material_key: String, collision: bool) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = center
	add_child(root)
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mats.get(material_key, mats["stone"])
	root.add_child(instance)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		root.add_child(body)
	return root


func _label(text_value: String, position: Vector3, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = position
	label.font_size = font_size
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color("#101722")
	add_child(label)
