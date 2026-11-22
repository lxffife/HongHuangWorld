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
const NPC_DAY_SECONDS_PER_MINUTE := 1.0
const NPC_NEAR_UPDATE_DISTANCE := 60.0
const NPC_FAR_UPDATE_DISTANCE := 110.0
const NPC_VERY_FAR_DISTANCE := 220.0

var player: CharacterBody3D
var camera: Camera3D
var camera_pitch := deg_to_rad(-18.0)
var mouse_captured := false
var status_label: Label
var district_markers: Dictionary = {}
var npc_spawn_points: Dictionary = {}
var activity_points: Array[Dictionary] = []
var patrol_route: Array[Vector3] = []
var activity_debug_root: Node3D
var activity_debug_visible := false
var npc_agents: Array[Dictionary] = []
var npc_population_by_district: Dictionary = {}
var npc_region_lod: Dictionary = {}
var npc_region_distance: Dictionary = {}
var npc_focus_agent: Dictionary = {}
var npc_hint_label: Label
var npc_detail_label: Label
var npc_simulation_time := 0.0
var npc_world_minutes := 18.0 * 60.0
var npc_schedule_bucket := -1
var npc_schedule_night := true
var market_ambience_time := 0.0
var market_orbs: Array[MeshInstance3D] = []
var market_lights: Array[OmniLight3D] = []
var market_customers: Array[Node3D] = []

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
	_build_activity_registry()
	_build_npc_population()
	_build_market_ambience()
	_apply_npc_schedules()
	_build_palace_axis()
	_build_street_furnishings()
	_build_player()
	_build_hud()



func _process(delta: float) -> void:
	_update_npc_agents(delta)
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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_activity_debug()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_E:
		_interact_with_focused_npc()
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
	# Tier 1: ceremonial north-south and east-west axes.
	_box("NorthSouthMainRoad", Vector3(0, 0.03, 0), Vector3(13, 0.12, 190), "road", false)
	_box("EastWestMainRoad", Vector3(0, 0.04, 0), Vector3(190, 0.12, 13), "road", false)
	_box("CentralProcessionalWay", Vector3(0, 0.06, 38), Vector3(20, 0.14, 100), "road_edge", false)
	# Tier 2: district distributors. Their alignment follows the compound edges.
	for x in [-34.0, 34.0]:
		_box("DistrictNorthSouthStreet", Vector3(x, 0.025, 0), Vector3(6.0, 0.1, 176.0), "road", false)
	for z in [-32.0, 32.0]:
		_box("DistrictCrossStreet", Vector3(0, 0.035, z), Vector3(176.0, 0.1, 6.0), "road", false)
	# Tier 3: quieter perimeter lanes connecting the residential and service quarters.
	for z in [-78.0, 78.0]:
		_box("PerimeterLane", Vector3(0, 0.02, z), Vector3(160.0, 0.08, 4.0), "bridge", false)
	# Palace approach remains a pedestrian-scale pair of parallel stone paths.
	for x in [-27.0, 27.0]:
		_box("PalaceApproach", Vector3(x, 0.035, 34), Vector3(5, 0.1, 90), "road", false)


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
		_dougong_band(center + offset + Vector3(0, 15.0, 0), 8.0, 6.0)
		_roof_tier(center + offset + Vector3(0, 17.5, 0), 10.0, 3.0)
	_box(title + "GateLintel", center + Vector3(0, 16.5, 0), Vector3(23, 3.5, 7), "gold", true)
	# Two opened leaves make the gate read as a real fortified passage without blocking traversal.
	var door_size := Vector3(7.4, 8.5, 0.7) if axis_x else Vector3(0.7, 8.5, 7.4)
	for side in [-1.0, 1.0]:
		var door_offset := Vector3(side * 4.2, 4.5, 0) if axis_x else Vector3(0, 4.5, side * 4.2)
		var leaf := _box(title + "OpenGateLeaf", center + door_offset, door_size, "dark_stone", false)
		leaf.rotation.y = deg_to_rad(-side * 58.0)
		for row in range(4):
			var stud_offset := Vector3(side * (1.8 + float(row) * 0.9), 0, -0.42) if axis_x else Vector3(-0.42, 0, side * (1.8 + float(row) * 0.9))
			var stud := _box(title + "GateDoorStud", center + door_offset + stud_offset, Vector3(0.22, 0.22, 0.22), "gold", false)
			remove_child(stud)
			leaf.add_child(stud)
			stud.position = stud_offset
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
	_build_district_compound(title, center, footprint)
	# Market and residential quarters use their own spatial layouts instead of generic bureau halls.
	if title not in ["万魂鬼市", "万家魂坊", "阴兵大营", "引魂驿站", "巡城司"]:
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
	_build_district_landmark(title, center, footprint)
	_label(title, center + Vector3(0, 13, 0), 26, accent)
	_label(subtitle, center + Vector3(0, 10.5, 0), 15, Color("#d2d6dc"))
	district_markers[title] = center


func _build_district_compound(title: String, center: Vector3, footprint: Vector2) -> void:
	# Low compound walls frame each functional quarter while leaving a wide southern entrance.
	var half_x := footprint.x * 0.5
	var half_z := footprint.y * 0.5
	var wall_h := 2.4
	var wall_t := 0.65
	var gate_w := clampf(footprint.x * 0.32, 5.0, 7.0)
	var side_len := maxf(1.0, half_x - gate_w * 0.5)
	_box(title + "NorthCompoundWall", center + Vector3(0, wall_h * 0.5, half_z), Vector3(footprint.x, wall_h, wall_t), "dark_stone", true)
	_box(title + "WestCompoundWall", center + Vector3(-half_x, wall_h * 0.5, 0), Vector3(wall_t, wall_h, footprint.y), "dark_stone", true)
	_box(title + "EastCompoundWall", center + Vector3(half_x, wall_h * 0.5, 0), Vector3(wall_t, wall_h, footprint.y), "dark_stone", true)
	for side in [-1.0, 1.0]:
		_box(title + "SouthCompoundWall", center + Vector3(side * (gate_w * 0.5 + side_len * 0.5), wall_h * 0.5, -half_z), Vector3(side_len, wall_h, wall_t), "dark_stone", true)
		_box(title + "CompoundGatePost", center + Vector3(side * gate_w * 0.5, 1.65, -half_z), Vector3(0.9, 3.3, 1.0), "stone", true)
	_box(title + "CompoundGateLintel", center + Vector3(0, 3.25, -half_z), Vector3(gate_w + 1.2, 0.65, 1.15), "gold", false)
	# Paved inner path leads from the gate toward the central hall; it is visual only.
	_box(title + "CourtyardEntryPath", center + Vector3(0, 0.49, -half_z * 0.42), Vector3(minf(gate_w * 0.72, 4.2), 0.08, half_z * 1.08), "road_edge", false)
	_box(title + "GateThreshold", center + Vector3(0, 0.52, -half_z), Vector3(gate_w, 0.12, 1.6), "gold", false)


func _build_district_landmark(title: String, center: Vector3, footprint: Vector2) -> void:
	# Each bureau receives one unmistakable silhouette beyond the shared hall grammar.
	match title:
		"十王府":
			# A formal ten-court axis: paired judgment courts flank the central hall.
			for side in [-1.0, 1.0]:
				for i in range(3):
					var z := center.z + float(i - 1) * 5.2
					_box("TenKingsCourtWall", Vector3(center.x + side * 11.0, 1.1, z), Vector3(0.8, 2.2, 4.2), "stone", false)
					_box("TenKingsCourtPavilion", Vector3(center.x + side * 11.0, 3.5, z), Vector3(4.0, 5.0, 3.6), "palace", false)
					_roof_tier(Vector3(center.x + side * 11.0, 6.4, z), 5.2, 1.8)
			_box("TenKingsJudgmentSteps", center + Vector3(0, 0.35, -8.0), Vector3(15, 0.7, 2.0), "road_edge", false)
		"判官司":
			# Archive tower and side galleries distinguish the civil judicial bureau.
			_box("JudgeArchiveTower", center + Vector3(-9.0, 6.0, 2.0), Vector3(5.0, 12.0, 5.0), "dark_stone", false)
			for level in range(3):
				_roof_tier(center + Vector3(-9.0, 12.5 + float(level) * 3.0, 2.0), 6.2 - float(level) * 0.8, 1.5)
			for side in [-1.0, 1.0]:
				_box("JudgeGallery", center + Vector3(side * 9.0, 2.0, -7.0), Vector3(7.0, 4.0, 3.0), "palace", false)
		"鬼籍司":
			# Tall register library with repeated horizontal archive floors.
			_box("SoulRegisterLibrary", center + Vector3(0, 7.0, 2.0), Vector3(8.0, 14.0, 7.0), "dark_stone", false)
			for level in range(1, 4):
				_box("SoulRegisterFloorBand", center + Vector3(0, float(level) * 3.5, 2.0), Vector3(9.0, 0.42, 8.0), "gold", false)
				_roof_tier(center + Vector3(0, 14.5 + float(level) * 0.4, 2.0), 9.0 - float(level) * 0.8, 1.5)
		"功过司":
			# Two balanced halls represent merit and transgression records.
			for side in [-1.0, 1.0]:
				_box("MeritAndFaultHall", center + Vector3(side * 9.0, 3.5, 1.0), Vector3(7.0, 7.0, 7.0), "palace", false)
				_roof_tier(center + Vector3(side * 9.0, 7.8, 1.0), 9.0, 2.4)
			_box("MeritFaultBalanceBeam", center + Vector3(0, 5.0, -7.0), Vector3(15.0, 0.5, 0.5), "gold", false)
			_box("MeritFaultBalancePost", center + Vector3(0, 2.8, -7.0), Vector3(0.6, 4.5, 0.6), "gold", false)
		"轮回司":
			# A monumental gate marks the transition toward the reincarnation route.
			for side in [-1.0, 1.0]:
				_box("ReincarnationPortalPillar", center + Vector3(side * 8.0, 6.0, 4.0), Vector3(2.0, 12.0, 2.0), "dark_stone", false)
			_roof_tier(center + Vector3(0, 12.0, 4.0), 21.0, 3.5)
			_box("ReincarnationThreshold", center + Vector3(0, 0.22, 4.0), Vector3(17.0, 0.44, 2.5), "gold", false)
		"万魂鬼市":
			# A broad central trading aisle runs from the southern compound gate to the auction dais.
			_box("GhostMarketMainAisle", center + Vector3(0, 0.12, 0), Vector3(9.0, 0.18, 21.0), "road_edge", false)
			_box("GhostMarketAuctionDais", center + Vector3(0, 0.55, 8.0), Vector3(7.0, 1.1, 4.5), "dark_stone", false)
			_box("GhostMarketAuctionDesk", center + Vector3(0, 1.45, 8.0), Vector3(4.2, 0.7, 1.2), "gold", false)
			_roof_tier(center + Vector3(0, 3.1, 8.0), 8.0, 2.0)
			for side in [-1.0, 1.0]:
				for z in [-6.5, 0.0, 6.5]:
					_market_stall(center + Vector3(side * 10.5, 0, z), -side)
				_box("GhostMarketBackLane", center + Vector3(side * 15.0, 0.08, 0), Vector3(2.0, 0.16, 20.0), "bridge", false)
			_notice_board(center + Vector3(-5.5, 0, -9.5), "鬼市告示")
			_notice_board(center + Vector3(5.5, 0, -9.5), "悬赏榜")
			for z in [-8.0, 0.0, 8.0]:
				_hanging_lantern(center + Vector3(-4.5, 0, z))
				_hanging_lantern(center + Vector3(4.5, 0, z))
			npc_spawn_points["万魂鬼市"] = [
				center + Vector3(-10.5, 0, -6.5), center + Vector3(-10.5, 0, 0),
				center + Vector3(10.5, 0, 0), center + Vector3(10.5, 0, 6.5),
				center + Vector3(0, 0, -10.0), center + Vector3(0, 0, 5.0)
			]
		"万家魂坊":
			# Four irregular family courtyards leave a shared lane and a public gathering square.
			for data in [
				{"offset": Vector3(-10.0, 0, -6.0), "turn": -1.0},
				{"offset": Vector3(10.0, 0, -6.0), "turn": 1.0},
				{"offset": Vector3(-10.0, 0, 7.0), "turn": 1.0},
				{"offset": Vector3(10.0, 0, 7.0), "turn": -1.0}
			]:
				_soulward_house(center + data["offset"], float(data["turn"]))
			_box("SoulWardCommonSquare", center + Vector3(0, 0.12, 0), Vector3(9.0, 0.18, 8.0), "road_edge", false)
			_box("SoulWardOldWellRim", center + Vector3(0, 0.65, 0), Vector3(1.8, 1.3, 1.8), "stone", false)
			_box("SoulWardWellOpening", center + Vector3(0, 1.32, 0), Vector3(0.9, 0.08, 0.9), "dark_stone", false)
			# A small tea pavilion is the neighborhood's social anchor, not a blocking building.
			_box("SoulWardTeaPavilionFloor", center + Vector3(0, 0.3, 8.5), Vector3(7.0, 0.6, 4.0), "stone", false)
			for x in [-3.0, 3.0]:
				for z in [7.0, 10.0]:
					_box("SoulWardTeaPavilionPost", center + Vector3(x, 2.0, z), Vector3(0.35, 3.4, 0.35), "gold", false)
			_roof_tier(center + Vector3(0, 4.0, 8.5), 9.0, 2.0)
			_hanging_lantern(center + Vector3(-3.2, 0, 4.5))
			_hanging_lantern(center + Vector3(3.2, 0, 4.5))
			npc_spawn_points["万家魂坊"] = [
				center + Vector3(-4.0, 0, -2.0), center + Vector3(4.0, 0, -2.0),
				center + Vector3(-4.0, 0, 3.0), center + Vector3(4.0, 0, 3.0),
				center + Vector3(0, 0, 10.5)
			]
		"阴兵大营":
			# The parade yard stays open; barracks and equipment line the perimeter.
			_box("UnderworldDrillYard", center + Vector3(0, 0.12, -1.0), Vector3(9.0, 0.18, 11.0), "road_edge", false)
			for side in [-1.0, 1.0]:
				_box("UnderworldBarracks", center + Vector3(side * 5.7, 2.0, 8.0), Vector3(5.0, 4.0, 7.0), "dark_stone", true)
				_roof_tier(center + Vector3(side * 5.7, 4.8, 8.0), 6.2, 1.8)
				_box("BarracksWatchPost", center + Vector3(side * 7.0, 3.5, -9.0), Vector3(2.6, 7.0, 2.6), "stone", true)
				_roof_tier(center + Vector3(side * 7.0, 7.5, -9.0), 4.0, 1.6)
				_weapon_rack(center + Vector3(side * 5.7, 0, -2.0))
			for i in range(3):
				_training_dummy(center + Vector3(float(i - 1) * 2.5, 0, 4.0))
			_box("UnderworldCommandTable", center + Vector3(0, 0.75, 10.8), Vector3(3.8, 1.5, 1.1), "gold", false)
			npc_spawn_points["阴兵大营"] = [
				center + Vector3(-3.0, 0, -5.5), center + Vector3(3.0, 0, -5.5),
				center + Vector3(-3.0, 0, 2.0), center + Vector3(3.0, 0, 2.0),
				center + Vector3(0, 0, 7.0)
			]
		"引魂驿站":
			# A clear arrival-to-registration-to-dispatch sequence guides newly arrived souls.
			_box("SoulWaystationArrivalLane", center + Vector3(0, 0.1, -7.0), Vector3(7.0, 0.16, 11.0), "road_edge", false)
			_box("SoulWaystationCanopy", center + Vector3(0, 4.0, -2.0), Vector3(12.0, 0.8, 6.0), "gold", false)
			_roof_tier(center + Vector3(0, 5.0, -2.0), 15.0, 2.6)
			_box("SoulRegistrationDesk", center + Vector3(0, 1.0, 0.5), Vector3(5.0, 1.8, 1.2), "palace", false)
			_box("SoulRegistrationLedger", center + Vector3(0, 2.05, 0.5), Vector3(2.4, 0.18, 0.8), "gold", false)
			for side in [-1.0, 1.0]:
				_box("WaystationWaitingPavilion", center + Vector3(side * 6.5, 1.8, 8.0), Vector3(4.0, 3.6, 4.0), "palace", false)
				_roof_tier(center + Vector3(side * 6.5, 4.3, 8.0), 5.5, 1.7)
				_box("WaystationQueueRail", center + Vector3(side * 3.5, 0.8, -7.0), Vector3(0.22, 1.6, 8.0), "gold", false)
			_box("SoulDispatchGateLeft", center + Vector3(-3.5, 2.8, 10.5), Vector3(0.7, 5.6, 0.7), "dark_stone", false)
			_box("SoulDispatchGateRight", center + Vector3(3.5, 2.8, 10.5), Vector3(0.7, 5.6, 0.7), "dark_stone", false)
			_box("SoulDispatchGateLintel", center + Vector3(0, 5.3, 10.5), Vector3(7.5, 0.8, 0.8), "gold", false)
			_label("分流通道", center + Vector3(0, 6.3, 10.5), 16, Color("#d7bd98"))
			npc_spawn_points["引魂驿站"] = [
				center + Vector3(-2.0, 0, -9.0), center + Vector3(2.0, 0, -9.0),
				center + Vector3(-2.0, 0, 3.0), center + Vector3(2.0, 0, 3.0),
				center + Vector3(0, 0, 8.5)
			]
		"巡城司":
			# Patrol headquarters combines a dispatch room, route table and three visible street posts.
			_box("PatrolSignalTower", center + Vector3(0, 5.0, 5.5), Vector3(4.5, 10.0, 4.5), "dark_stone", true)
			_roof_tier(center + Vector3(0, 10.8, 5.5), 6.5, 2.0)
			_box("PatrolDispatchHall", center + Vector3(0, 2.0, -6.0), Vector3(9.0, 4.0, 5.0), "palace", true)
			_roof_tier(center + Vector3(0, 4.8, -6.0), 11.0, 2.0)
			_box("PatrolRouteTable", center + Vector3(0, 1.0, -2.0), Vector3(4.0, 1.8, 2.2), "gold", false)
			for side in [-1.0, 1.0]:
				_box("PatrolGatePost", center + Vector3(side * 8.5, 1.8, -2.0), Vector3(2.0, 3.6, 2.0), "stone", true)
				_roof_tier(center + Vector3(side * 8.5, 4.2, -2.0), 3.5, 1.4)
			_box("PatrolNoticePillar", center + Vector3(0, 1.5, -9.5), Vector3(1.0, 3.0, 1.0), "gold", false)
			npc_spawn_points["巡城司"] = [
				center + Vector3(-7.0, 0, 0), center + Vector3(7.0, 0, 0),
				center + Vector3(0, 0, -9.0), center + Vector3(0, 0, 3.0)
			]


func _build_activity_registry() -> void:
	# Convert legacy district coordinate lists into semantic, client-local activity records.
	activity_points.clear()
	for district_name in npc_spawn_points.keys():
		var role := "resident"
		var activity := "social_idle"
		var schedule_tag := "day_night"
		match str(district_name):
			"万魂鬼市":
				role = "merchant"
				activity = "trade_idle"
				schedule_tag = "night"
			"万家魂坊":
				role = "resident"
				activity = "social_idle"
			"阴兵大营":
				role = "soldier"
				activity = "drill"
				schedule_tag = "always"
			"引魂驿站":
				role = "guide"
				activity = "registration"
				schedule_tag = "always"
			"巡城司":
				role = "patrol_guard"
				activity = "patrol_watch"
				schedule_tag = "always"
		var positions: Array = npc_spawn_points[district_name]
		for index in range(positions.size()):
			var district_key := _district_key(str(district_name))
			var point: Dictionary = {
				"point_id": "%s.%s.%02d" % [district_key, role, index + 1],
				"district": str(district_name),
				"role": role,
				"activity": activity,
				"position": positions[index],
				"facing": _activity_facing(str(district_name), positions[index], index),
				"schedule_tag": schedule_tag,
				"capacity": 1,
				"radius": 1.4
			}
			if str(district_name) == "万家魂坊" and index < 4:
				point["waypoints"] = _soulward_resident_waypoints()
			activity_points.append(point)

	# Three arrivals wait between the entrance rails before reaching the registration desk.
	var waystation_center := Vector3(77.0, 0.0, 0.0)
	for queue_index in range(3):
		var queue_position := waystation_center + Vector3(0.0, 0.0, -6.0 + float(queue_index) * 2.5)
		activity_points.append({
			"point_id": "waystation.waiting_soul.%02d" % (queue_index + 1),
			"district": "引魂驿站",
			"role": "waiting_soul",
			"activity": "queue_wait",
			"position": queue_position,
			"facing": PI,
			"schedule_tag": "always",
			"capacity": 1,
			"radius": 0.8
		})

	# Patrol route follows the existing north-south/east-west distributor roads.
	# This is a visualization/planning path, not a NavigationAgent path.
	patrol_route = [
		Vector3(0, 0, 12),
		Vector3(0, 0, 32),
		Vector3(0, 0, 78),
		Vector3(34, 0, 78),
		Vector3(34, 0, 32),
		Vector3(34, 0, -32),
		Vector3(34, 0, -78),
		Vector3(0, 0, -78),
		Vector3(-34, 0, -78),
		Vector3(-34, 0, -32),
		Vector3(-34, 0, 32),
		Vector3(-34, 0, 78),
		Vector3(0, 0, 78),
		Vector3(0, 0, 32),
		Vector3(0, 0, 12)
	]
	for route_index in range(patrol_route.size()):
		var route_position: Vector3 = patrol_route[route_index]
		activity_points.append({
			"point_id": "patrol.route.%02d" % (route_index + 1),
			"district": "巡城司",
			"role": "patrol_guard",
			"activity": "patrol_route",
			"position": route_position,
			"facing": 0.0,
			"schedule_tag": "night",
			"capacity": 1,
			"radius": 1.0
		})


func _district_key(district_name: String) -> String:
	match district_name:
		"万魂鬼市": return "ghost_market"
		"万家魂坊": return "soul_ward"
		"阴兵大营": return "barracks"
		"引魂驿站": return "waystation"
		"巡城司": return "patrol_office"
		_: return "bureau"


func _npc_display_name(role: String, index: int) -> String:
	var names: Array = []
	match role:
		"merchant": names = ["孟掌柜", "铁算盘", "柳娘子", "百宝翁", "铁算盘", "阿福"]
		"resident": names = ["沈阿婆", "小石头", "顾裁缝", "青禾", "老陶", "阿宁"]
		"soldier": names = ["阴兵校尉", "持戟卫", "巡营兵", "守垒兵"]
		"guide": names = ["引魂使·无咎", "引魂使·青灯", "引魂使·渡厄"]
		"waiting_soul": names = ["新魂·甲", "新魂·乙", "新魂·丙"]
		"patrol_guard": names = ["巡城卫·陈肃", "巡城卫·陆衡"]
		_: names = ["无名阴差"]
	return str(names[index % names.size()])


func _interaction_type_for_role(role: String) -> String:
	match role:
		"merchant": return "trade"
		"guide": return "registration"
		"waiting_soul": return "queue_info"
		"soldier", "patrol_guard": return "dispatch"
		"resident": return "talk"
	return "none"


func _activity_facing(district_name: String, point_position: Vector3, index: int) -> float:
	# Godot's local forward is -Z. Face each post toward its actual work area.
	match district_name:
		"阴兵大营":
			return -PI * 0.5
		"引魂驿站":
			return PI * 0.5
		"万魂鬼市":
			return PI * 0.5 if index % 2 == 0 else -PI * 0.5
		"万家魂坊":
			var toward_square := Vector3(-55.0, 0.0, -53.0) - point_position
			return atan2(-toward_square.x, -toward_square.z)
		"巡城司":
			return PI if index % 2 == 0 else 0.0
	return 0.0


func _soulward_resident_waypoints() -> Array[Vector3]:
	# Four clear corners of the public square; the central well and tea pavilion stay clear.
	var center := Vector3(-55.0, 0.0, -53.0)
	return [
		center + Vector3(-4.0, 0.0, -2.0),
		center + Vector3(4.0, 0.0, -2.0),
		center + Vector3(4.0, 0.0, 3.0),
		center + Vector3(-4.0, 0.0, 3.0)
	]


func _build_npc_population() -> void:
	# These local stand-ins now have stable prototype identities and interaction metadata.
	# They remain client-only and must later be reconciled with server-owned actor IDs.
	npc_agents.clear()
	var role_counts: Dictionary = {}
	for point in activity_points:
		if str(point["activity"]) == "patrol_route":
			continue
		var npc_root := Node3D.new()
		npc_root.name = "LocalNPC_" + str(point["role"])
		npc_root.position = point["position"]
		add_child(npc_root)
		var role := str(point["role"])
		var role_index := int(role_counts.get(role, 0))
		role_counts[role] = role_index + 1
		var agent := _create_npc_figure(npc_root, role)
		agent["npc_id"] = str(point["point_id"])
		agent["display_name"] = _npc_display_name(role, role_index)
		agent["district"] = str(point["district"])
		agent["interaction_type"] = _interaction_type_for_role(role)
		agent["importance"] = "critical" if role == "guide" else ("regional" if role in ["merchant", "soldier", "patrol_guard"] else "ambient")
		agent["root"] = npc_root
		agent["role"] = role
		if role == "soldier":
			agent["formation_slot"] = role_index
		if role == "waiting_soul":
			agent["queue_order"] = role_index
		elif role == "guide" and role_index == 2:
			# This guide stands beside the registration desk and shares the call cycle with the front soul.
			agent["waystation_desk_guide"] = true
		agent["activity"] = str(point["activity"])
		agent["schedule_tag"] = str(point["schedule_tag"])
		agent["phase"] = float(npc_agents.size()) * 1.37
		var npc_waypoints: Array = point.get("waypoints", [])
		agent["moving"] = role == "resident" and npc_waypoints.size() > 1
		agent["base_position"] = point["position"]
		if bool(agent["moving"]):
			agent["waypoints"] = npc_waypoints
			agent["route_index"] = role_index % npc_waypoints.size()
			agent["route_progress"] = 0.0
			agent["move_speed"] = 1.05
		agent["facing"] = float(point["facing"])
		agent["gesture_rate"] = 0.72 + float(npc_agents.size() % 5) * 0.13
		agent["update_accumulator"] = 0.0
		_initialize_npc_behavior(agent)
		npc_root.rotation.y = float(point["facing"])
		npc_agents.append(agent)

	# A few non-interactive customers browse from the aisle side of selected stalls.
	_build_market_customers()

	# One visible patrol guard follows the closed route; the other guards remain at posts.
	if patrol_route.size() > 1:
		var patrol_root := Node3D.new()
		patrol_root.name = "LocalNPC_PatrolWalker"
		patrol_root.position = patrol_route[0]
		add_child(patrol_root)
		var patrol_agent := _create_npc_figure(patrol_root, "patrol_guard")
		patrol_agent["npc_id"] = "patrol.guard.walker.01"
		patrol_agent["display_name"] = "巡城卫·巡夜"
		patrol_agent["district"] = "巡城司"
		patrol_agent["interaction_type"] = "dispatch"
		patrol_agent["importance"] = "regional"
		patrol_agent["root"] = patrol_root
		patrol_agent["role"] = "patrol_guard"
		patrol_agent["activity"] = "patrol_route"
		patrol_agent["phase"] = 0.0
		patrol_agent["moving"] = true
		patrol_agent["route_index"] = 0
		patrol_agent["route_progress"] = 0.0
		patrol_agent["move_speed"] = 2.6
		patrol_agent["update_accumulator"] = 0.0
		_initialize_npc_behavior(patrol_agent)
		npc_agents.append(patrol_agent)
	_rebuild_npc_population_index()
	_apply_npc_schedules()



func _build_market_customers() -> void:
	# Keep only two customers so the central aisle remains visibly open.
	# Static ambient props only: they are not server-owned or interactive NPC agents.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	var customer_stalls: Array[Dictionary] = [
		{"position": market_center + Vector3(-7.1, 0.0, -6.5), "yaw": PI * 0.5},
		{"position": market_center + Vector3(7.1, 0.0, 6.5), "yaw": -PI * 0.5}
	]
	for index in range(customer_stalls.size()):
		var customer_root := Node3D.new()
		customer_root.name = "AmbientMarketCustomer_%02d" % (index + 1)
		customer_root.position = customer_stalls[index]["position"]
		customer_root.rotation.y = float(customer_stalls[index]["yaw"])
		add_child(customer_root)
		_create_npc_figure(customer_root, "market_customer")
		var parcel := MeshInstance3D.new()
		var parcel_mesh := BoxMesh.new()
		parcel_mesh.size = Vector3(0.34, 0.32, 0.34)
		parcel.mesh = parcel_mesh
		var parcel_material := StandardMaterial3D.new()
		parcel_material.albedo_color = Color("#9a8063")
		parcel_material.roughness = 0.9
		parcel.material_override = parcel_material
		parcel.position = Vector3(0.42, 0.42, 0.12)
		customer_root.add_child(parcel)
		market_customers.append(customer_root)


func _build_market_ambience() -> void:
	# Three shared, shadowless lights illuminate the six stalls without one light per stall.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	for offset_x in [-8.0, 0.0, 8.0]:
		var light := OmniLight3D.new()
		light.name = "GhostMarketSharedLanternLight"
		light.position = market_center + Vector3(offset_x, 4.0, 0.0)
		light.light_color = Color("#e9b879")
		light.light_energy = 0.0
		light.omni_range = 12.0
		light.shadow_enabled = false
		add_child(light)
		market_lights.append(light)
	_update_market_ambience(0.0)


func _update_market_ambience(delta: float) -> void:
	market_ambience_time += delta
	var night_factor := 1.0 if npc_schedule_night else 0.0
	for index in range(market_lights.size()):
		var pulse := 0.5 + 0.5 * sin(market_ambience_time * 1.35 + float(index) * 1.7)
		market_lights[index].light_energy = night_factor * (0.48 + pulse * 0.16)
	for index in range(market_orbs.size()):
		var orb := market_orbs[index]
		var material := orb.material_override as StandardMaterial3D
		if material != null:
			var pulse := 0.5 + 0.5 * sin(market_ambience_time * 1.8 + float(index) * 0.83)
			material.emission_energy_multiplier = 0.16 + night_factor * (0.42 + pulse * 0.38)
	for customer in market_customers:
		customer.visible = npc_schedule_night


func _initialize_npc_behavior(agent: Dictionary) -> void:
	var role := str(agent.get("role", ""))
	var states: Array = _npc_behavior_states(role)
	if role == "resident" and not bool(agent.get("moving", false)):
		states = ["tea_social", "well_idle", "home_idle"]
	elif role == "waiting_soul":
		states = ["queue_wait", "queue_glance"]
	agent["behavior_states"] = states
	agent["state_cycle_index"] = 0
	agent["state"] = str(states[0]) if not states.is_empty() else "idle"
	agent["state_elapsed"] = fposmod(float(agent.get("phase", 0.0)), 3.0)
	agent["state_duration"] = _npc_behavior_duration(role, str(agent["state"]), float(agent.get("phase", 0.0)))


func _npc_behavior_states(role: String) -> Array:
	match role:
		"merchant":
			return ["trade_idle", "greet", "arrange_goods", "trade_idle", "close_shop"]
		"resident":
			return ["square_walk", "square_chat", "tea_social", "well_idle", "home_idle"]
		"soldier":
			return ["formation_ready", "drill", "formation_ready", "rest"]
		"guide":
			return ["check_ledger", "direct_souls", "registration"]
		"waiting_soul":
			return ["queue_wait", "queue_glance"]
		"patrol_guard":
			return ["patrol_walk", "patrol_watch"]
	return ["idle"]


func _npc_behavior_duration(role: String, state: String, phase: float) -> float:
	var base := 5.0
	match state:
		"greet", "direct_souls", "queue_glance":
			base = 3.2
		"arrange_goods", "check_ledger", "well_idle":
			base = 6.0
		"close_shop", "rest", "home_idle":
			base = 8.0
		"queue_called":
			base = 3.8
		"tea_social", "square_chat", "square_walk", "trade_idle", "drill":
			base = 5.5
		"patrol_walk", "patrol_watch":
			base = 10.0
	return base + fposmod(phase * 1.73, 2.2)


func _advance_npc_behavior(agent: Dictionary, elapsed: float) -> void:
	var states: Array = agent.get("behavior_states", [])
	if states.is_empty():
		return
	var state_elapsed := float(agent.get("state_elapsed", 0.0)) + elapsed
	var duration := float(agent.get("state_duration", 5.0))
	var cycle_index := int(agent.get("state_cycle_index", 0))
	var role := str(agent.get("role", ""))
	if role == "soldier" and str(agent.get("activity", "")) == "rest":
		agent["state"] = "rest"
		agent["state_elapsed"] = state_elapsed
		return
	if role == "soldier" and str(agent.get("state", "")) == "rest":
		agent["state_cycle_index"] = 0
		agent["state"] = "formation_ready"
		state_elapsed = 0.0
		duration = _npc_behavior_duration(role, "formation_ready", float(agent.get("phase", 0.0)))
	while state_elapsed >= duration:
		state_elapsed -= duration
		cycle_index = (cycle_index + 1) % states.size()
		var next_state := str(states[cycle_index])
		duration = _npc_behavior_duration(role, next_state, float(agent.get("phase", 0.0)) + float(cycle_index))
		agent["state"] = next_state
	agent["state_elapsed"] = state_elapsed
	agent["state_duration"] = duration
	agent["state_cycle_index"] = cycle_index


func _sync_waystation_call(agent: Dictionary) -> void:
	# Three fixed queue slots are processed front-to-back on a shared local demo clock.
	# This is presentation-only: the narrow rail/desk geometry is not safe for fake locomotion.
	var role := str(agent.get("role", ""))
	var cycle_index := int(npc_simulation_time / 28.0)
	var call_phase := fposmod(npc_simulation_time, 28.0)
	var served_count := mini(cycle_index, 3)
	var active_queue_order := 2 - served_count
	if bool(agent.get("waystation_desk_guide", false)):
		if served_count >= 3:
			agent["state"] = "check_ledger"
		elif call_phase < 9.0:
			agent["state"] = "check_ledger"
		elif call_phase < 13.0:
			agent["state"] = "direct_souls"
		elif call_phase < 18.0:
			agent["state"] = "registration"
		else:
			agent["state"] = "check_ledger"
	elif role == "waiting_soul":
		var queue_order := int(agent.get("queue_order", -1))
		if queue_order > active_queue_order:
			agent["state"] = "queue_registered"
		elif queue_order == active_queue_order:
			if call_phase < 9.0:
				agent["state"] = "queue_wait"
			elif call_phase < 13.0:
				agent["state"] = "queue_called"
			elif call_phase < 16.0:
				agent["state"] = "queue_glance"
			else:
				agent["state"] = "queue_registering"
		elif queue_order < active_queue_order:
			agent["state"] = "queue_wait"


func _apply_npc_behavior_pose(agent: Dictionary, phase: float) -> void:
	var state := str(agent.get("state", "idle"))
	var root: Node3D = agent["root"]
	var left_arm: MeshInstance3D = agent["left_arm"]
	var right_arm: MeshInstance3D = agent["right_arm"]
	var body: MeshInstance3D = agent["body"]
	var facing := float(agent.get("facing", 0.0))
	var gesture := sin(phase * 1.25)
	match state:
		"trade_idle":
			left_arm.rotation.z = deg_to_rad(-18.0) + gesture * 0.07
			right_arm.rotation.z = deg_to_rad(18.0) + sin(phase * 0.9) * 0.1
		"greet":
			root.rotation.y = facing + sin(phase * 0.22) * 0.08
			left_arm.rotation.z = deg_to_rad(-18.0)
			right_arm.rotation.z = deg_to_rad(-52.0) + sin(phase * 2.2) * 0.28
		"arrange_goods":
			body.rotation.x = deg_to_rad(7.0) + absf(gesture) * 0.035
			left_arm.rotation.z = deg_to_rad(-42.0) + gesture * 0.08
			right_arm.rotation.z = deg_to_rad(42.0) - gesture * 0.08
		"close_shop":
			left_arm.rotation.z = deg_to_rad(-12.0) + gesture * 0.04
			right_arm.rotation.z = deg_to_rad(12.0) - gesture * 0.04
		"square_walk":
			left_arm.rotation.z = deg_to_rad(-24.0) + sin(phase * 2.4) * 0.14
			right_arm.rotation.z = deg_to_rad(24.0) - sin(phase * 2.4) * 0.14
		"square_chat", "tea_social":
			if not bool(agent.get("moving", false)):
				root.rotation.y = facing + sin(phase * 0.38) * (0.24 if state == "square_chat" else 0.12)
			left_arm.rotation.z = deg_to_rad(-28.0) + gesture * 0.08
			right_arm.rotation.z = deg_to_rad(28.0) - sin(phase * 0.85 + 0.7) * 0.09
		"well_idle", "home_idle":
			if not bool(agent.get("moving", false)):
				root.rotation.y = facing + sin(phase * 0.2) * 0.1
			left_arm.rotation.z = deg_to_rad(-18.0) + gesture * 0.025
			right_arm.rotation.z = deg_to_rad(18.0) - gesture * 0.025
		"formation_ready":
			left_arm.rotation.z = deg_to_rad(-10.0)
			right_arm.rotation.z = deg_to_rad(10.0)
		"drill":
			var drill_swing := sin(phase * 2.0) * 0.28
			left_arm.rotation.z = deg_to_rad(-18.0) + drill_swing
			right_arm.rotation.z = deg_to_rad(18.0) - drill_swing
		"drill_recover":
			left_arm.rotation.z = deg_to_rad(-10.0) + sin(phase * 0.45) * 0.025
			right_arm.rotation.z = deg_to_rad(10.0) - sin(phase * 0.45) * 0.025
		"rest":
			left_arm.rotation.z = deg_to_rad(-18.0) + sin(phase * 0.35) * 0.025
			right_arm.rotation.z = deg_to_rad(18.0) - sin(phase * 0.35) * 0.025
		"check_ledger":
			left_arm.rotation.z = deg_to_rad(-30.0)
			right_arm.rotation.z = deg_to_rad(42.0) + sin(phase * 0.7) * 0.05
			var ledger: MeshInstance3D = agent.get("ledger")
			if ledger != null:
				ledger.rotation.x = deg_to_rad(-28.0) + sin(phase * 0.5) * 0.04
		"direct_souls", "registration":
			left_arm.rotation.z = deg_to_rad(-18.0) + maxf(gesture, 0.0) * 0.18
			right_arm.rotation.z = deg_to_rad(18.0) - maxf(-gesture, 0.0) * 0.34
		"patrol_walk":
			left_arm.rotation.z = deg_to_rad(-28.0) + sin(phase * 2.4) * 0.18
			right_arm.rotation.z = deg_to_rad(28.0) - sin(phase * 2.4) * 0.18
		"patrol_watch":
			if not bool(agent.get("moving", false)):
				root.rotation.y = facing + sin(phase * 0.25) * 0.12
		"queue_wait", "queue_glance":
			root.rotation.y = facing + (sin(phase * 0.28) * 0.08 if state == "queue_glance" else 0.0)
			left_arm.rotation.z = deg_to_rad(-18.0)
			right_arm.rotation.z = deg_to_rad(18.0) + sin(phase * 0.4) * 0.035
		"queue_called":
			# A restrained acknowledgement gesture keeps the front position clear of the desk.
			root.rotation.y = facing + sin(phase * 0.45) * 0.035
			left_arm.rotation.z = deg_to_rad(-25.0) + sin(phase * 0.8) * 0.025
			right_arm.rotation.z = deg_to_rad(34.0) + sin(phase * 1.1) * 0.045
			body.rotation.x = deg_to_rad(5.0) + absf(sin(phase * 0.7)) * 0.025
		"queue_registered":
			# The soul remains in its slot; registration is acknowledged without crossing the rails.
			root.rotation.y = facing
			left_arm.rotation.z = deg_to_rad(-12.0)
			right_arm.rotation.z = deg_to_rad(12.0)
			body.rotation.x = deg_to_rad(3.0)
		"queue_registering":
			# A short, restrained bow communicates desk-side processing without moving position.
			root.rotation.y = facing
			left_arm.rotation.z = deg_to_rad(-20.0)
			right_arm.rotation.z = deg_to_rad(20.0)
			body.rotation.x = deg_to_rad(7.0)
		_:
			left_arm.rotation.z = deg_to_rad(-18.0)
			right_arm.rotation.z = deg_to_rad(18.0)
	if state not in ["arrange_goods", "queue_called", "queue_registering", "queue_registered"]:
		body.rotation.x = 0.0


func _rebuild_npc_population_index() -> void:
	npc_population_by_district.clear()
	npc_region_lod.clear()
	npc_region_distance.clear()
	for agent_index in range(npc_agents.size()):
		var district := str(npc_agents[agent_index].get("district", "未归类"))
		if not npc_population_by_district.has(district):
			npc_population_by_district[district] = []
			npc_region_lod[district] = "far"
			npc_region_distance[district] = INF
		npc_population_by_district[district].append(agent_index)


func _update_npc_population_manager() -> void:
	# One regional pass assigns a shared LOD tier; individual NPCs do not run independent AI.
	for district in npc_population_by_district.keys():
		var nearest_distance := INF
		for agent_index in npc_population_by_district[district]:
			var root: Node3D = npc_agents[agent_index].get("root")
			if root == null or not root.visible or player == null:
				continue
			nearest_distance = minf(nearest_distance, root.global_position.distance_to(player.global_position))
		npc_region_distance[district] = nearest_distance
		if nearest_distance <= NPC_NEAR_UPDATE_DISTANCE:
			npc_region_lod[district] = "near"
		elif nearest_distance <= NPC_FAR_UPDATE_DISTANCE:
			npc_region_lod[district] = "mid"
		else:
			npc_region_lod[district] = "far"


func _npc_lod_interval(agent: Dictionary, distance_to_player: float, region_lod: String) -> float:
	# The region tier is shared, while exact distance keeps far-edge NPCs from
	# inheriting the near player's full update rate.
	var interval := 0.0
	if distance_to_player > NPC_FAR_UPDATE_DISTANCE:
		interval = 0.8
	elif distance_to_player > NPC_NEAR_UPDATE_DISTANCE:
		interval = 0.32
	if region_lod == "far" and distance_to_player > NPC_FAR_UPDATE_DISTANCE:
		interval = maxf(interval, 0.8)
	match str(agent.get("importance", "ambient")):
		"critical": interval *= 0.5
		"ambient": interval *= 1.5
	if distance_to_player > NPC_VERY_FAR_DISTANCE:
		interval = maxf(interval, 1.2)
	return interval


func _create_npc_figure(root: Node3D, role: String) -> Dictionary:
	var tint := Color("#b8c5cf") if role == "waiting_soul" else _activity_color(role)
	var robe_material := StandardMaterial3D.new()
	robe_material.albedo_color = tint
	robe_material.roughness = 0.82
	var dark_material := StandardMaterial3D.new()
	dark_material.albedo_color = Color("#252c36")
	dark_material.roughness = 0.9
	var accent_material := StandardMaterial3D.new()
	accent_material.albedo_color = Color("#d7b477") if role in ["merchant", "guide"] else (Color("#c49a72") if role == "market_customer" else Color("#8797a8"))
	accent_material.emission_enabled = role == "guide"
	accent_material.emission = Color("#d7b477")

	var body := MeshInstance3D.new()
	var robe := CapsuleMesh.new()
	robe.radius = 0.34
	robe.height = 1.45
	body.mesh = robe
	body.position = Vector3(0, 0.92, 0)
	body.material_override = robe_material
	root.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.24
	head_mesh.height = 0.48
	head.mesh = head_mesh
	head.position = Vector3(0, 1.82, 0)
	head.material_override = dark_material
	root.add_child(head)

	var left_arm := MeshInstance3D.new()
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.105
	arm_mesh.height = 0.78
	left_arm.mesh = arm_mesh
	left_arm.position = Vector3(-0.39, 1.12, 0)
	left_arm.rotation.z = deg_to_rad(-18.0)
	left_arm.material_override = robe_material
	root.add_child(left_arm)

	var right_arm := MeshInstance3D.new()
	right_arm.mesh = arm_mesh
	right_arm.position = Vector3(0.39, 1.12, 0)
	right_arm.rotation.z = deg_to_rad(18.0)
	right_arm.material_override = robe_material
	root.add_child(right_arm)

	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.64, 0.12, 0.38)
	belt.mesh = belt_mesh
	belt.position = Vector3(0, 0.72, 0)
	belt.material_override = accent_material
	root.add_child(belt)

	if role == "merchant":
		var canopy := MeshInstance3D.new()
		var canopy_mesh := BoxMesh.new()
		canopy_mesh.size = Vector3(0.72, 0.12, 0.58)
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(0, 2.12, 0)
		canopy.material_override = accent_material
		root.add_child(canopy)
	elif role == "soldier":
		var spear := MeshInstance3D.new()
		var spear_mesh := CylinderMesh.new()
		spear_mesh.top_radius = 0.035
		spear_mesh.bottom_radius = 0.055
		spear_mesh.height = 2.2
		spear.mesh = spear_mesh
		spear.position = Vector3(0.55, 1.25, -0.08)
		spear.rotation.z = deg_to_rad(-8.0)
		spear.material_override = accent_material
		root.add_child(spear)
	elif role == "guide":
		var lantern := MeshInstance3D.new()
		var lantern_mesh := SphereMesh.new()
		lantern_mesh.radius = 0.16
		lantern_mesh.height = 0.32
		lantern.mesh = lantern_mesh
		lantern.position = Vector3(0.58, 1.05, -0.08)
		lantern.material_override = accent_material
		root.add_child(lantern)

	var ledger: MeshInstance3D
	if role == "guide":
		ledger = MeshInstance3D.new()
		var ledger_mesh := BoxMesh.new()
		ledger_mesh.size = Vector3(0.38, 0.045, 0.28)
		ledger.mesh = ledger_mesh
		ledger.position = Vector3(0.0, 1.18, -0.28)
		ledger.rotation.x = deg_to_rad(-18.0)
		ledger.material_override = accent_material
		root.add_child(ledger)

	return {"body": body, "left_arm": left_arm, "right_arm": right_arm, "ledger": ledger}


func _update_npc_agents(delta: float) -> void:
	npc_simulation_time += delta
	_update_npc_population_manager()
	npc_world_minutes = fposmod(npc_world_minutes + delta / NPC_DAY_SECONDS_PER_MINUTE, 1440.0)
	_update_market_ambience(delta)
	var schedule_bucket := int(npc_world_minutes / 5.0)
	if schedule_bucket != npc_schedule_bucket:
		npc_schedule_bucket = schedule_bucket
		_apply_npc_schedules()

	for agent in npc_agents:
		var root: Node3D = agent["root"]
		if not root.visible:
			continue
		var distance_to_player := 0.0
		if player != null:
			distance_to_player = root.global_position.distance_to(player.global_position)
		var district := str(agent.get("district", "未归类"))
		var region_lod := str(npc_region_lod.get(district, "far"))
		var update_interval := _npc_lod_interval(agent, distance_to_player, region_lod)
		var elapsed := delta
		if update_interval > 0.0:
			var accumulated := float(agent.get("update_accumulator", 0.0)) + delta
			if accumulated < update_interval:
				agent["update_accumulator"] = accumulated
				continue
			elapsed = accumulated
			agent["update_accumulator"] = 0.0

		var body: MeshInstance3D = agent["body"]
		var left_arm: MeshInstance3D = agent["left_arm"]
		var right_arm: MeshInstance3D = agent["right_arm"]
		var phase := npc_simulation_time * 1.8 * float(agent.get("gesture_rate", 1.0)) + float(agent["phase"])
		var activity := str(agent["activity"])
		_advance_npc_behavior(agent, elapsed)
		_sync_waystation_call(agent)
		if str(agent.get("role", "")) == "soldier":
			_sync_soldier_formation(agent)
		if str(agent.get("role", "")) == "merchant":
			_update_merchant_proximity_behavior(agent, distance_to_player)
		if bool(agent["moving"]):
			var route_index := int(agent["route_index"])
			var route_progress := float(agent["route_progress"])
			var route: Array = agent.get("waypoints", patrol_route)
			var start: Vector3 = route[route_index]
			var next_index := (route_index + 1) % route.size()
			var finish: Vector3 = route[next_index]
			var segment_length := maxf(start.distance_to(finish), 0.01)
			route_progress += float(agent["move_speed"]) * elapsed / segment_length
			while route_progress >= 1.0:
				route_progress -= 1.0
				route_index = next_index
				next_index = (route_index + 1) % route.size()
				start = route[route_index]
				finish = route[next_index]
				segment_length = maxf(start.distance_to(finish), 0.01)
			root.position = start.lerp(finish, route_progress)
			var direction := finish - start
			if direction.length_squared() > 0.01:
				root.rotation.y = atan2(-direction.x, -direction.z)
			agent["route_index"] = route_index
			agent["route_progress"] = route_progress
			body.position.y = 0.92 + absf(sin(phase * 2.4)) * 0.07
			left_arm.rotation.z = deg_to_rad(-28.0) + sin(phase * 2.4) * 0.18
			right_arm.rotation.z = deg_to_rad(28.0) - sin(phase * 2.4) * 0.18
		else:
			var base_position: Vector3 = agent["base_position"]
			root.position = base_position + Vector3(0, absf(sin(phase)) * 0.035, 0)
			body.position.y = 0.92 + sin(phase) * 0.025
			root.rotation.y = float(agent["facing"])
			if activity == "drill":
				var drill_swing := sin(phase * 2.0) * 0.28
				left_arm.rotation.z = deg_to_rad(-18.0) + drill_swing
				right_arm.rotation.z = deg_to_rad(18.0) - drill_swing
			elif activity == "rest":
				left_arm.rotation.z = deg_to_rad(-18.0) + sin(phase * 0.35) * 0.025
				right_arm.rotation.z = deg_to_rad(18.0) - sin(phase * 0.35) * 0.025
			elif activity == "trade_idle":
				left_arm.rotation.z = deg_to_rad(-18.0) + sin(phase * 0.8) * 0.08
				right_arm.rotation.z = deg_to_rad(18.0) + sin(phase * 0.8 + float(agent["phase"])) * 0.13
			elif activity == "social_idle":
				root.rotation.y = float(agent["facing"]) + sin(phase * 0.45) * 0.22
				left_arm.rotation.z = deg_to_rad(-18.0) + sin(phase * 0.9) * 0.06
				right_arm.rotation.z = deg_to_rad(18.0) - sin(phase * 0.9 + 0.8) * 0.06
			elif activity == "registration":
				var gesture := sin(phase * 0.62)
				left_arm.rotation.z = deg_to_rad(-18.0) + maxf(gesture, 0.0) * 0.18
				right_arm.rotation.z = deg_to_rad(18.0) - maxf(-gesture, 0.0) * 0.34
				var ledger: MeshInstance3D = agent.get("ledger")
				if ledger != null:
					ledger.rotation.x = deg_to_rad(-18.0) + maxf(gesture, 0.0) * 0.24
			elif activity == "queue_wait":
				# Waiting souls keep their place, occasionally glance toward the desk.
				root.rotation.y = float(agent["facing"]) + sin(phase * 0.28) * 0.08
				left_arm.rotation.z = deg_to_rad(-18.0)
				right_arm.rotation.z = deg_to_rad(18.0) + sin(phase * 0.4) * 0.035
			else:
				left_arm.rotation.z = deg_to_rad(-18.0)
				right_arm.rotation.z = deg_to_rad(18.0)
		_apply_npc_behavior_pose(agent, phase)


func _sync_soldier_formation(agent: Dictionary) -> void:
	# All visible soldiers sample one shared drill cadence; the server will own combat orders later.
	if str(agent.get("activity", "")) == "rest":
		agent["state"] = "rest"
		return
	var formation_phase := fposmod(npc_simulation_time, 18.0)
	if formation_phase < 4.0:
		agent["state"] = "formation_ready"
	elif formation_phase < 11.0:
		agent["state"] = "drill"
	elif formation_phase < 14.0:
		agent["state"] = "drill_recover"
	else:
		agent["state"] = "formation_ready"


func _update_merchant_proximity_behavior(agent: Dictionary, distance_to_player: float) -> void:
	# Merchants greet nearby players but remain rooted behind their own stall.
	var should_greet := distance_to_player <= 5.0 and player != null
	var was_greeting := bool(agent.get("player_greeting", false))
	if should_greet:
		agent["player_greeting"] = true
		agent["state"] = "greet"
		return
	if was_greeting:
		agent["player_greeting"] = false
		var states: Array = agent.get("behavior_states", [])
		var idle_index := states.find("trade_idle")
		if idle_index < 0:
			idle_index = 0
		agent["state_cycle_index"] = idle_index
		agent["state"] = str(states[idle_index]) if not states.is_empty() else "trade_idle"
		agent["state_elapsed"] = 0.0
		agent["state_duration"] = _npc_behavior_duration("merchant", str(agent["state"]), float(agent.get("phase", 0.0)))


func _apply_npc_schedules() -> void:
	var hour := int(npc_world_minutes / 60.0)
	npc_schedule_night = hour >= 18 or hour < 6
	for agent in npc_agents:
		var role := str(agent.get("role", ""))
		var root: Node3D = agent["root"]
		if str(agent.get("schedule_tag", "")) == "night":
			root.visible = npc_schedule_night
		if role == "soldier":
			agent["activity"] = "drill" if hour >= 6 and hour < 22 else "rest"
		elif role == "merchant":
			agent["activity"] = "trade_idle"
		elif role == "waiting_soul":
			agent["activity"] = "queue_wait"
		elif role == "guide":
			agent["activity"] = "registration"
		elif role == "resident":
			agent["activity"] = "social_idle"
	for customer in market_customers:
		customer.visible = npc_schedule_night
	_update_market_ambience(0.0)
	# Clock display is intentionally local to this graybox, not a server-authoritative world clock.


func _format_npc_clock() -> String:
	var hour := int(npc_world_minutes / 60.0)
	var minute := int(fposmod(npc_world_minutes, 60.0))
	return "%02d:%02d" % [hour, minute]


func _toggle_activity_debug() -> void:
	activity_debug_visible = not activity_debug_visible
	if activity_debug_visible:
		_build_activity_debug()
	elif activity_debug_root != null:
		activity_debug_root.queue_free()
		activity_debug_root = null


func _build_activity_debug() -> void:
	if activity_debug_root != null:
		activity_debug_root.queue_free()
	activity_debug_root = Node3D.new()
	activity_debug_root.name = "ActivityPointDebug"
	add_child(activity_debug_root)

	for point in activity_points:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.38 if str(point["activity"]) != "patrol_route" else 0.25
		sphere.height = sphere.radius * 2.0
		marker.mesh = sphere
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = _activity_color(str(point["role"]))
		marker_material.emission_enabled = true
		marker_material.emission = marker_material.albedo_color
		marker_material.emission_energy_multiplier = 0.65
		marker.material_override = marker_material
		marker.position = point["position"] + Vector3(0, 0.55, 0)
		activity_debug_root.add_child(marker)

		var label := Label3D.new()
		label.text = "%s · %s" % [str(point["district"]), str(point["activity"])]
		label.position = marker.position + Vector3(0, 0.65, 0)
		label.font_size = 14
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = _activity_color(str(point["role"]))
		activity_debug_root.add_child(label)

	for index in range(patrol_route.size() - 1):
		var start := patrol_route[index] + Vector3(0, 0.18, 0)
		var finish := patrol_route[index + 1] + Vector3(0, 0.18, 0)
		var segment_length := start.distance_to(finish)
		if segment_length <= 0.1:
			continue
		var segment := MeshInstance3D.new()
		var segment_mesh := BoxMesh.new()
		segment_mesh.size = Vector3(0.12, 0.12, segment_length)
		segment.mesh = segment_mesh
		var route_material := StandardMaterial3D.new()
		route_material.albedo_color = Color("#d9b56f")
		route_material.emission_enabled = true
		route_material.emission = Color("#d9b56f")
		route_material.emission_energy_multiplier = 0.8
		segment.material_override = route_material
		segment.position = (start + finish) * 0.5
		segment.look_at(finish, Vector3.UP)
		activity_debug_root.add_child(segment)


func _activity_color(role: String) -> Color:
	match role:
		"merchant":
			return Color("#e5b56e")
		"resident":
			return Color("#91c4d8")
		"soldier":
			return Color("#c77e75")
		"guide":
			return Color("#b5a1dc")
		"patrol_guard":
			return Color("#a7c18a")
		"waiting_soul":
			return Color("#b8c5cf")
		"market_customer":
			return Color("#9cabb5")
	return Color("#d0d0d0")


func _weapon_rack(center: Vector3) -> void:
	_box("UnderworldWeaponRackBase", center + Vector3(0, 0.75, 0), Vector3(2.8, 0.25, 0.8), "dark_stone", false)
	for x in [-1.0, 1.0]:
		_box("UnderworldWeaponRackPost", center + Vector3(x, 1.55, 0), Vector3(0.18, 1.6, 0.18), "gold", false)
	for i in range(3):
		var weapon := _box("TrainingSpear", center + Vector3(float(i - 1) * 0.65, 2.0, 0), Vector3(0.12, 2.2, 0.12), "stone", false)
		weapon.rotation.z = deg_to_rad(-8.0 + float(i) * 8.0)


func _training_dummy(center: Vector3) -> void:
	_box("TrainingDummyPost", center + Vector3(0, 1.0, 0), Vector3(0.3, 2.0, 0.3), "dark_stone", false)
	_box("TrainingDummyCrossbar", center + Vector3(0, 1.55, 0), Vector3(1.2, 0.18, 0.18), "gold", false)
	_box("TrainingDummyTarget", center + Vector3(0, 2.0, 0), Vector3(0.55, 0.55, 0.55), "palace", false)


func _market_stall(center: Vector3, facing: float) -> void:
	# Stall front faces the central aisle; rear stock remains tucked against the compound edge.
	_box("GhostMarketStallCounter", center + Vector3(facing * 0.85, 0.72, 0), Vector3(1.25, 1.05, 3.8), "palace", false)
	_box("GhostMarketStallStock", center + Vector3(-facing * 0.9, 1.05, 0), Vector3(1.7, 2.1, 3.8), "dark_stone", false)
	_box("GhostMarketStallAwning", center + Vector3(0, 3.0, 0), Vector3(4.8, 0.28, 4.8), "roof", false)
	for side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			_box("GhostMarketStallPost", center + Vector3(side * 2.0, 1.55, z_side * 2.0), Vector3(0.22, 3.0, 0.22), "gold", false)
	_box("GhostMarketStallSign", center + Vector3(facing * 2.15, 2.55, 0), Vector3(0.18, 0.9, 1.6), "gold", false)
	# Three small display groups sit on the aisle-facing counter; the center aisle remains clear.
	var counter_front := center + Vector3(facing * 0.85, 1.26, 0)
	_market_display_orb(counter_front + Vector3(0, 0.22, -1.22), 0.22, Color("#83b9d2"))
	_market_display_orb(counter_front + Vector3(0, 0.22, 1.22), 0.22, Color("#b99bdc"))
	_box("GhostMarketScrollDisplay", counter_front + Vector3(0, 0.10, 0), Vector3(0.48, 0.16, 0.78), "gold", false)
	_box("GhostMarketHerbBundleDisplay", counter_front + Vector3(-facing * 0.30, 0.14, 0.58), Vector3(0.32, 0.22, 0.42), "district", false)


func _market_display_orb(position: Vector3, radius: float, tint: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.28
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.7
	var instance := MeshInstance3D.new()
	instance.name = "GhostMarketSoulOrbDisplay"
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)
	market_orbs.append(instance)


func _soulward_house(center: Vector3, entrance_side: float) -> void:
	_box("SoulWardHouseBody", center + Vector3(0, 2.0, 0), Vector3(5.6, 4.0, 4.8), "stone", false)
	_roof_tier(center + Vector3(0, 4.6, 0), 7.0, 1.8)
	# Three low courtyard walls leave a deliberate doorway toward the shared lane.
	_box("SoulWardCourtyardSideWall", center + Vector3(-3.8, 0.9, 0), Vector3(0.4, 1.8, 7.2), "dark_stone", false)
	_box("SoulWardCourtyardSideWall", center + Vector3(3.8, 0.9, 0), Vector3(0.4, 1.8, 7.2), "dark_stone", false)
	_box("SoulWardCourtyardRearWall", center + Vector3(0, 0.9, 3.6), Vector3(7.6, 1.8, 0.4), "dark_stone", false)
	_box("SoulWardDoorPost", center + Vector3(entrance_side * 3.8, 1.1, -3.0), Vector3(0.45, 2.2, 0.45), "gold", false)
	_box("SoulWardHouseStep", center + Vector3(0, 0.18, -2.7), Vector3(2.2, 0.36, 1.0), "road_edge", false)


func _notice_board(center: Vector3, board_title: String) -> void:
	_box("DistrictNoticeBoardPost", center + Vector3(0, 1.35, 0), Vector3(0.24, 2.7, 0.24), "gold", false)
	_box("DistrictNoticeBoard", center + Vector3(0, 2.25, 0), Vector3(2.2, 1.5, 0.24), "palace", false)
	_label(board_title, center + Vector3(0, 3.25, 0), 14, Color("#e7c995"))


func _hanging_lantern(center: Vector3) -> void:
	_box("DistrictLanternStem", center + Vector3(0, 3.4, 0), Vector3(0.16, 1.2, 0.16), "gold", false)
	_box("DistrictHangingLantern", center + Vector3(0, 2.55, 0), Vector3(0.85, 0.95, 0.85), "lantern", false)
	_box("DistrictLanternCap", center + Vector3(0, 3.12, 0), Vector3(1.1, 0.18, 1.1), "roof", false)


func _build_palace_axis() -> void:
	# A walled northern palace precinct with two ceremonial gates and a layered court axis.
	var center := Vector3(0, 0, 72)
	district_markers["酆都皇城"] = center
	_label("酆都皇城", center + Vector3(0, 38, 0), 30, Color("#e0c08b"))
	_box("ImperialPalaceTerrace", center + Vector3(0, 0.55, 0), Vector3(43, 1.1, 28), "gold", false)

	# Outer palace wall: the southern entrance remains a broad, walkable opening.
	for side in [-1.0, 1.0]:
		_box("ImperialOuterSideWall", center + Vector3(side * 31.0, 4.0, 0), Vector3(1.8, 8.0, 48.0), "wall", true)
		_box("ImperialOuterSouthWall", center + Vector3(side * 19.5, 4.0, -24.0), Vector3(23.0, 8.0, 1.8), "wall", true)
	_box("ImperialOuterNorthWall", center + Vector3(0, 4.0, 24.0), Vector3(63.0, 8.0, 1.8), "wall", true)
	for side in [-1.0, 1.0]:
		_box("ImperialSouthGatePier", center + Vector3(side * 8.5, 5.0, -24.0), Vector3(2.2, 10.0, 2.4), "dark_stone", true)
		_roof_tier(center + Vector3(side * 8.5, 10.5, -24.0), 5.5, 2.0)
	_box("ImperialSouthGateLintel", center + Vector3(0, 10.0, -24.0), Vector3(18.0, 1.2, 2.4), "gold", false)
	_label("午门", center + Vector3(0, 13.0, -24.0), 24, Color("#f1d49d"))

	# Inner court wall and second ceremonial gate create a clear progression to the throne hall.
	for side in [-1.0, 1.0]:
		_box("ImperialInnerWall", center + Vector3(side * 25.0, 3.2, -8.0), Vector3(1.4, 6.4, 20.0), "wall", true)
		_box("ImperialInnerGatePier", center + Vector3(side * 7.0, 4.5, -8.0), Vector3(1.8, 9.0, 2.0), "dark_stone", true)
		_roof_tier(center + Vector3(side * 7.0, 9.5, -8.0), 4.8, 1.8)
	_box("ImperialInnerGateLintel", center + Vector3(0, 9.0, -8.0), Vector3(15.0, 1.0, 2.0), "gold", false)
	_label("承天门", center + Vector3(0, 12.0, -8.0), 21, Color("#e4c58e"))

	# Front court, side halls and rear residence establish a palace rather than a lone hall.
	_box("ImperialFrontCourt", center + Vector3(0, 0.12, -16.0), Vector3(35.0, 0.18, 12.0), "road_edge", false)
	for side in [-1.0, 1.0]:
		var side_center := center + Vector3(side * 20.0, 0, 5.0)
		_box("ImperialSideHall", side_center + Vector3(0, 4.0, 0), Vector3(8.0, 8.0, 9.0), "palace", true)
		_dougong_band(side_center + Vector3(0, 7.5, 0), 8.5, 9.0)
		_roof_tier(side_center + Vector3(0, 9.0, 0), 12.0, 2.8)
		_box("ImperialRearGallery", center + Vector3(side * 13.0, 2.0, 17.0), Vector3(12.0, 4.0, 3.0), "dark_stone", true)
		_box("ImperialGardenPool", center + Vector3(side * 20.0, 0.08, 17.0), Vector3(8.0, 0.16, 5.0), "water", false)
	_box("ImperialRearHall", center + Vector3(0, 4.0, 18.0), Vector3(15.0, 8.0, 9.0), "palace", true)
	_roof_tier(center + Vector3(0, 9.0, 18.0), 20.0, 3.2)
	_label("后殿", center + Vector3(0, 13.0, 18.0), 20, Color("#d7bd98"))

	# Main throne hall remains the tallest and most prominent structure.
	_box("ImperialMainHall", center + Vector3(0, 9, 0), Vector3(23, 17, 15), "palace", true)
	for x in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		_box("PalacePillar", center + Vector3(x, 7.0, 8.0), Vector3(0.9, 14, 0.9), "gold", true)
	_dougong_band(center + Vector3(0, 15.0, 0), 24.0, 15.0)
	_roof_tier(center + Vector3(0, 19, 0), 31, 5)
	_roof_tier(center + Vector3(0, 25, 0), 23, 4)
	_label("酆都大帝 · 皇城正殿", center + Vector3(0, 32, 0), 38, Color("#f1d49d"))
	for z in [42.0, 34.0, 20.0, 6.0]:
		_box("PalaceProcessionStep", Vector3(0, 0.35, z), Vector3(20, 0.7, 3), "road_edge", true)


func _roof_tier(center: Vector3, width: float, height: float) -> void:
	# Four sloped planes form a compact hip roof; raised corners suggest Chinese flying eaves.
	var roof_y := height * 0.48
	_box("RoofUnderstructure", center + Vector3(0, height * 0.18, 0), Vector3(width * 0.76, height * 0.36, width * 0.56), "dark_stone", false)
	var side_panel := Vector3(width * 0.58, maxf(0.28, height * 0.12), width * 0.88)
	var front_panel := Vector3(width * 0.82, maxf(0.28, height * 0.12), width * 0.42)
	var slope := 17.0
	var left := _box("HipRoofLeft", center + Vector3(-width * 0.22, roof_y, 0), side_panel, "roof", false)
	left.rotation_degrees.z = -slope
	var right := _box("HipRoofRight", center + Vector3(width * 0.22, roof_y, 0), side_panel, "roof", false)
	right.rotation_degrees.z = slope
	var front := _box("HipRoofFront", center + Vector3(0, roof_y, -width * 0.22), front_panel, "roof", false)
	front.rotation_degrees.x = -slope
	var back := _box("HipRoofBack", center + Vector3(0, roof_y, width * 0.22), front_panel, "roof", false)
	back.rotation_degrees.x = slope
	# Continuous eave bands and lifted corner tips make the silhouette readable at distance.
	var eave_front := _box("RoofEaveFront", center + Vector3(0, height * 0.30, -width * 0.43), Vector3(width * 1.12, 0.28, 0.48), "roof_edge", false)
	var eave_back := _box("RoofEaveBack", center + Vector3(0, height * 0.30, width * 0.43), Vector3(width * 1.12, 0.28, 0.48), "roof_edge", false)
	var eave_left := _box("RoofEaveLeft", center + Vector3(-width * 0.43, height * 0.30, 0), Vector3(0.48, 0.28, width * 0.86), "roof_edge", false)
	var eave_right := _box("RoofEaveRight", center + Vector3(width * 0.43, height * 0.30, 0), Vector3(0.48, 0.28, width * 0.86), "roof_edge", false)
	eave_front.rotation_degrees.x = -4.0
	eave_back.rotation_degrees.x = 4.0
	eave_left.rotation_degrees.z = 4.0
	eave_right.rotation_degrees.z = -4.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("FlyingEaveTip", center + Vector3(sx * width * 0.49, height * 0.39, sz * width * 0.40), Vector3(0.72, 0.34, 0.72), "gold", false)


func _dougong_band(center: Vector3, width: float, depth: float) -> void:
	# Simplified bracket-set silhouette: bearing blocks, projecting arms and tie beam.
	var y := center.y
	_box("DougongBearingBlock", Vector3(center.x, y, center.z), Vector3(width * 0.72, 0.42, depth * 0.72), "gold", false)
	for side in [-1.0, 1.0]:
		_box("DougongCrossArm", Vector3(center.x + side * width * 0.22, y - 0.12, center.z), Vector3(width * 0.38, 0.28, depth * 0.34), "roof_edge", false)
		_box("DougongProjectingArm", Vector3(center.x, y - 0.28, center.z + side * depth * 0.20), Vector3(width * 0.34, 0.24, depth * 0.42), "gold", false)
	_box("DougongTieBeam", Vector3(center.x, y - 0.48, center.z), Vector3(width, 0.32, depth * 0.62), "dark_stone", false)


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
	panel.custom_minimum_size = Vector2(440, 142)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "酆都天城 · 3D 灰盒漫游"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	status_label = Label.new()
	column.add_child(status_label)
	npc_hint_label = Label.new()
	npc_hint_label.add_theme_color_override("font_color", Color("#e8c58b"))
	column.add_child(npc_hint_label)
	npc_detail_label = Label.new()
	npc_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_detail_label.custom_minimum_size = Vector2(410, 34)
	column.add_child(npc_detail_label)
	var help := Label.new()
	help.text = "WASD 移动 · 空格跳跃 · 鼠标左键捕获视角 · ESC 释放 · E 交互 · F6 活动点"
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
	var period := "夜" if npc_schedule_night else "昼"
	status_label.text = "%s %s  ·  位置 %.1f, %.1f  ·  附近：%s" % [period, _format_npc_clock(), p.x, p.z, nearest]
	_update_npc_interaction_hint()


func _update_npc_interaction_hint() -> void:
	if npc_hint_label == null:
		return
	var nearest_agent: Dictionary = {}
	var nearest_distance := 3.8
	for agent in npc_agents:
		if str(agent.get("interaction_type", "none")) == "none":
			continue
		var root: Node3D = agent.get("root")
		if root == null or not root.visible:
			continue
		var distance := player.global_position.distance_to(root.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_agent = agent
	npc_focus_agent = nearest_agent
	if npc_focus_agent.is_empty():
		npc_hint_label.text = ""
	else:
		npc_hint_label.text = "E 交互  ·  %s（%s）" % [str(npc_focus_agent["display_name"]), str(npc_focus_agent["district"])]


func _interact_with_focused_npc() -> void:
	if npc_focus_agent.is_empty() or npc_detail_label == null:
		return
	var npc_name := str(npc_focus_agent.get("display_name", "无名阴差"))
	var npc_id := str(npc_focus_agent.get("npc_id", "unknown"))
	var message := ""
	match str(npc_focus_agent.get("interaction_type", "none")):
		"trade":
			var merchant_state := str(npc_focus_agent.get("state", "trade_idle"))
			if merchant_state == "greet":
				message = "%s：客官，夜市刚开张，来看看今日的新到魂器与冥府杂货。" % npc_name
			else:
				message = "%s：鬼市夜市已开。货物、魂钱与交易功能将在商店系统接入后开放。" % npc_name
		"registration": message = "%s：请准备好魂籍凭证，先登记来处，再按引导前往分流处。" % npc_name
		"queue_info":
			var queue_state := str(npc_focus_agent.get("state", "queue_wait"))
			match queue_state:
				"queue_registered": message = "%s：魂籍登记已完成，请留在原位等待分流引导（当前为本地演示）。" % npc_name
				"queue_called", "queue_glance": message = "%s：引魂使正在叫号，请回应并准备登记。" % npc_name
				"queue_registering": message = "%s：引魂使正在核验魂籍，请稍候。" % npc_name
				_: message = "%s：请依次候登记，不要越过前方魂灵。" % npc_name
		"dispatch": message = "%s：巡防事务请报明来意。此处暂未开放军令与治安任务。" % npc_name
		"talk": message = "%s：魂坊今日安宁，若有闲暇，不妨去茶亭坐坐。" % npc_name
		_: message = "%s 暂无可用交互。" % npc_name
	npc_detail_label.text = message
	print("[FengduNPC] interact id=%s type=%s" % [npc_id, str(npc_focus_agent.get("interaction_type", "none"))])


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
