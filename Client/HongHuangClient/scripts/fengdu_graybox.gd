extends Node3D

const WORLD_LAYOUT = preload("res://scripts/fengdu_world_layout.gd")
const WORLD_NAVIGATION = preload("res://scripts/fengdu_navigation.gd")
## Walkable Fengdu capital graybox. All dimensions in meters.
## This is a client-side art/navigation prototype; gates and permissions are not authoritative.

const CITY_HALF := WORLD_LAYOUT.CITY_HALF
const MOAT_HALF := WORLD_LAYOUT.MOAT_HALF
const WALL_HEIGHT := WORLD_LAYOUT.WALL_HEIGHT
const WALL_THICKNESS := WORLD_LAYOUT.WALL_THICKNESS
const GATE_WIDTH := WORLD_LAYOUT.GATE_WIDTH
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
var navigation_network_data: Dictionary = {}
var last_navigation_route: Dictionary = {}
var patrol_route: Array[Vector3] = []
var patrol_route_node_ids: Array[String] = []
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
var market_customers: Array[Dictionary] = []
var market_stall_registry: Array[Dictionary] = []
var market_stage_actor: Dictionary = {}
var market_caravans: Array[Dictionary] = []
var market_guards: Array[Dictionary] = []
var market_audience: Array[Dictionary] = []
var market_event_label: Label3D
var market_inspection_label: Label3D
var market_inspection_elapsed := 0.0
var market_inspection_remaining := 0.0
var market_inspection_sequence := 0
var patrol_alert_elapsed := 0.0
var patrol_alert_remaining := 0.0
var patrol_alert_position := Vector3(0.0, 0.0, 12.0)
var patrol_alert_sequence := 0
var patrol_incident_queue: Array[Dictionary] = []
var patrol_incident_records: Array[Dictionary] = []
var patrol_dispatch_queue_elapsed := 0.0
var patrol_incident_focus_id := ""
var judge_workbench_root: Control
var judge_case_list: ItemList
var judge_case_detail: RichTextLabel
var judge_workbench_hint: Label
var judge_review_actions: HFlowContainer
var judge_statement_input: LineEdit
var judge_selected_incident_id := ""
var judge_workbench_open := false
var judge_workbench_refresh_elapsed := 0.0
var autonomous_judicial_elapsed := 0.0
const AUTONOMOUS_JUDICIAL_INTERVAL := 5.0

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
	_build_judge_bureau_workbench()



func _process(delta: float) -> void:
	_update_npc_agents(delta)
	if judge_workbench_open:
		judge_workbench_refresh_elapsed += delta
		if judge_workbench_refresh_elapsed >= 1.0:
			judge_workbench_refresh_elapsed = 0.0
			_show_judge_case_detail(judge_selected_incident_id)
	if player == null:
		return
	if judge_workbench_open:
		_update_camera()
		_update_hud()
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
		if judge_workbench_open:
			_close_judge_bureau_workbench()
		else:
			_release_mouse()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_activity_debug()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_E:
		if judge_workbench_open:
			_close_judge_bureau_workbench()
		elif _is_player_at_judge_bureau():
			_open_judge_bureau_workbench()
		else:
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
	for road_data in WORLD_LAYOUT.get_approach_roads():
		_box(str(road_data.get("id", "ApproachRoad")), road_data.get("center", Vector3.ZERO), road_data.get("size", Vector3.ONE), str(road_data.get("surface", "road")), false)


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
	# Road geometry is generated from stable layout records, not embedded in this scene adapter.
	for road_data in WORLD_LAYOUT.get_roads() + WORLD_LAYOUT.get_local_connectors():
		_box(str(road_data.get("id", "Road")), road_data.get("center", Vector3.ZERO), road_data.get("size", Vector3.ONE), str(road_data.get("surface", "road")), false)


func _build_moat_and_bridges() -> void:
	for moat_data in WORLD_LAYOUT.get_moat_segments():
		_box(str(moat_data.get("id", "Moat")), moat_data.get("center", Vector3.ZERO), moat_data.get("size", Vector3.ONE), "water", false)
	for bridge_data in WORLD_LAYOUT.get_bridges():
		_box(str(bridge_data.get("id", "Bridge")), bridge_data.get("center", Vector3.ZERO), bridge_data.get("size", Vector3.ONE), "bridge", true)


func _build_city_walls() -> void:
	for wall_data in WORLD_LAYOUT.get_wall_segments():
		_box(str(wall_data.get("id", "CityWall")), wall_data.get("center", Vector3.ZERO), wall_data.get("size", Vector3.ONE), "wall", true)
	for tower_data in WORLD_LAYOUT.get_wall_towers():
		_box(str(tower_data.get("id", "CornerTower")), tower_data.get("center", Vector3.ZERO), tower_data.get("size", Vector3.ONE), "dark_stone", true)
		_roof_tier(tower_data.get("roof_center", Vector3.ZERO), float(tower_data.get("roof_width", 12.0)), float(tower_data.get("roof_height", 4.0)))
	for merlon_data in WORLD_LAYOUT.get_wall_merlons():
		_box(str(merlon_data.get("id", "WallMerlon")), merlon_data.get("center", Vector3.ZERO), merlon_data.get("size", Vector3.ONE), "stone", true)


func _build_gate_complexes() -> void:
	for gate_data in WORLD_LAYOUT.get_gates():
		_gate(str(gate_data.get("name", "城门")), gate_data.get("position", Vector3.ZERO), gate_data.get("outward", Vector3.FORWARD), str(gate_data.get("destination", "")))


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
	for district_data in WORLD_LAYOUT.get_districts():
		_district(
			str(district_data.get("name", "未命名区域")),
			district_data.get("center", Vector3.ZERO),
			district_data.get("footprint", Vector2(20, 20)),
			str(district_data.get("subtitle", "")),
			int(district_data.get("building_count", 1)),
			Color(str(district_data.get("accent", "#a9b9c4")))
		)


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
			# The paired hearing courts and central judgment approach are authored in layout data.
			var ten_kings_layout: Dictionary = WORLD_LAYOUT.get_administrative_layout()["ten_kings_court"]
			for court in ten_kings_layout["hearing_courts"]:
				_box("TenKingsCourtWall", center + court["wall_offset"], Vector3(0.8, 2.2, 4.2), "stone", false)
				_box("TenKingsCourtPavilion", center + court["offset"], Vector3(4.0, 5.0, 3.6), "palace", false)
				_roof_tier(center + court["roof_offset"], 5.2, 1.8)
			var judgment_steps: Dictionary = ten_kings_layout["judgment_steps"]
			_box("TenKingsJudgmentSteps", center + judgment_steps["offset"], judgment_steps["size"], "road_edge", false)
		"判官司":
			# Archive and review galleries use stable spatial identities.
			var judge_layout: Dictionary = WORLD_LAYOUT.get_administrative_layout()["judge_bureau"]
			var judge_archive: Dictionary = judge_layout["archive_tower"]
			_box("JudgeArchiveTower", center + judge_archive["offset"], judge_archive["size"], "dark_stone", false)
			for level in range(3):
				_roof_tier(center + judge_archive["roof_base"] + Vector3(0.0, float(level) * 3.0, 0.0), 6.2 - float(level) * 0.8, 1.5)
			for gallery in judge_layout["galleries"]:
				_box("JudgeGallery", center + gallery["offset"], gallery["size"], "palace", false)
		"鬼籍司":
			# The archive tower, its floor bands, and roof line are data-driven.
			var registry_layout: Dictionary = WORLD_LAYOUT.get_administrative_layout()["soul_registry"]
			var registry_archive: Dictionary = registry_layout["archive_tower"]
			_box("SoulRegisterLibrary", center + registry_archive["offset"], registry_archive["size"], "dark_stone", false)
			for band in registry_layout["floor_bands"]:
				_box("SoulRegisterFloorBand", center + band["offset"], Vector3(9.0, 0.42, 8.0), "gold", false)
				var band_index := int(band["level"])
				_roof_tier(center + registry_layout["archive_roof_base"] + Vector3(0.0, float(band_index) * 0.4, 0.0), 9.0 - float(band_index) * 0.8, 1.5)
		"功过司":
			# Two balanced halls represent merit and transgression records.
			for side in [-1.0, 1.0]:
				_box("MeritAndFaultHall", center + Vector3(side * 9.0, 3.5, 1.0), Vector3(7.0, 7.0, 7.0), "palace", false)
				_roof_tier(center + Vector3(side * 9.0, 7.8, 1.0), 9.0, 2.4)
			_box("MeritFaultBalanceBeam", center + Vector3(0, 5.0, -7.0), Vector3(15.0, 0.5, 0.5), "gold", false)
			_box("MeritFaultBalancePost", center + Vector3(0, 2.8, -7.0), Vector3(0.6, 4.5, 0.6), "gold", false)
		"轮回司":
			# Portal pillars, roof, and threshold are authored in the service layout.
			var reincarnation_layout: Dictionary = WORLD_LAYOUT.get_administrative_layout()["reincarnation_bureau"]
			for pillar in reincarnation_layout["portal_pillars"]:
				_box("ReincarnationPortalPillar", center + pillar["offset"], pillar["size"], "dark_stone", false)
			var portal_roof: Dictionary = reincarnation_layout["portal_roof"]
			_roof_tier(center + portal_roof["offset"], float(portal_roof["width"]), float(portal_roof["height"]))
			var threshold: Dictionary = reincarnation_layout["threshold"]
			_box("ReincarnationThreshold", center + threshold["offset"], threshold["size"], "gold", false)
		"万魂鬼市":
			# A broad central trading aisle runs from the southern compound gate to the auction dais.
			_box("GhostMarketMainAisle", center + Vector3(0, 0.12, 0), Vector3(9.0, 0.18, 21.0), "road_edge", false)
			var auction_layout: Dictionary = WORLD_LAYOUT.get_market_auction_layout()
			_box("GhostMarketAuctionDais", center + auction_layout["dais_offset"], auction_layout["dais_size"], "dark_stone", false)
			_box("GhostMarketAuctionDesk", center + auction_layout["desk_offset"], auction_layout["desk_size"], "gold", false)
			_market_auction_steps(center + auction_layout["step_center_offset"])
			_roof_tier(center + auction_layout["roof_offset"], float(auction_layout["roof_width"]), float(auction_layout["roof_height"]))
			_label("万魂竞宝台", center + auction_layout["label_offset"], 22, Color("#f0d29a"))
			for showcase in auction_layout["showcase_orbs"]:
				_market_display_orb(center + showcase["offset"], float(showcase["radius"]), Color(str(showcase["tint"])))
			market_stall_registry.clear()
			for stall_data in WORLD_LAYOUT.get_market_stalls():
				var stall_position: Vector3 = stall_data["position"]
				var stall_facing: float = float(stall_data["facing"])
				var stall_type: String = str(stall_data["stall_type"])
				_market_stall(stall_position, stall_facing, stall_type)
				var display_items: Array = _market_display_items_for_type(stall_type)
				market_stall_registry.append({
					"stall_id": str(stall_data["stall_id"]),
					"stall_type": stall_type,
					"district": str(stall_data["district"]),
					"position": stall_position,
					"facing": stall_facing,
					"display_items": display_items,
					"restock_group": str(stall_data["restock_group"]),
					"restock_label": _create_market_stall_status_label(stall_position, stall_facing),
					"catalog_label": _create_market_stall_catalog_label(stall_position, stall_facing, display_items),
					"business_state": "closed",
					"open_schedule": str(stall_data["open_schedule"]),
					"interaction_type": _market_interaction_for_type(stall_type),
					"presentation_state": str(stall_data["presentation_state"])
				})
			for side in [-1.0, 1.0]:
				_box("GhostMarketBackLane", center + Vector3(side * 15.0, 0.08, 0), Vector3(2.0, 0.16, 20.0), "bridge", false)
			_market_notice_board(center + Vector3(-5.5, 0, -9.5), "鬼市告示", Color("#83c7e4"))
			_market_notice_board(center + Vector3(5.5, 0, -9.5), "悬赏榜", Color("#d27d68"))
			_market_wayfinding(center)
			for bench in auction_layout["audience_benches"]:
				_market_audience_bench(center + bench["offset"], float(bench["facing"]))
			for pedestal in auction_layout["pedestals"]:
				var pedestal_position: Vector3 = center + pedestal["offset"]
				var pedestal_accent := Color("#d9b879") if str(pedestal["point_id"]).ends_with("left") else Color("#83c7e4")
				_market_auction_pedestal(pedestal_position, pedestal_accent)
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
			# Render the semantic arrival -> registration -> waiting -> dispatch layout.
			var waystation: Dictionary = WORLD_LAYOUT.get_waystation_layout()
			var arrival: Dictionary = waystation["arrival_lane"]
			_box("SoulWaystationArrivalLane", center + arrival["offset"], arrival["size"], "road_edge", false)
			var canopy: Dictionary = waystation["canopy"]
			_box("SoulWaystationCanopy", center + canopy["offset"], canopy["size"], "gold", false)
			_roof_tier(center + canopy["roof_offset"], float(canopy["roof_width"]), float(canopy["roof_height"]))
			var desk: Dictionary = waystation["registration_desk"]
			_box("SoulRegistrationDesk", center + desk["offset"], desk["size"], "palace", false)
			var ledger: Dictionary = waystation["registration_ledger"]
			_box("SoulRegistrationLedger", center + ledger["offset"], ledger["size"], "gold", false)
			for pavilion in waystation["waiting_pavilions"]:
				_box("WaystationWaitingPavilion", center + pavilion["offset"], pavilion["size"], "palace", false)
				_roof_tier(center + pavilion["roof_offset"], float(pavilion["roof_width"]), float(pavilion["roof_height"]))
			for rail in waystation["queue_rails"]:
				_box("WaystationQueueRail", center + rail["offset"], rail["size"], "gold", false)
			var dispatch: Dictionary = waystation["dispatch_gate"]
			_box("SoulDispatchGateLeft", center + dispatch["left_post_offset"], dispatch["post_size"], "dark_stone", false)
			_box("SoulDispatchGateRight", center + dispatch["right_post_offset"], dispatch["post_size"], "dark_stone", false)
			_box("SoulDispatchGateLintel", center + dispatch["lintel_offset"], dispatch["lintel_size"], "gold", false)
			_label("分流通道", center + dispatch["label_offset"], 16, Color("#d7bd98"))
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
	# Consume presentation-independent NPC placements and route data.
	activity_points.clear()
	navigation_network_data = WORLD_LAYOUT.get_navigation_network()
	for point in WORLD_LAYOUT.get_npc_activity_points():
		var bound_point: Dictionary = point.duplicate(true)
		bound_point.merge(WORLD_LAYOUT.get_spatial_binding_for_point(bound_point, navigation_network_data), true)
		activity_points.append(bound_point)
	var routes: Array = WORLD_LAYOUT.get_patrol_routes()
	patrol_route.clear()
	patrol_route_node_ids.clear()
	if routes.is_empty():
		return
	var route: Dictionary = routes[0]
	patrol_route_node_ids.assign(route.get("node_ids", []))
	for node_position in route.get("nodes", []):
		patrol_route.append(node_position)
	for route_index in range(patrol_route.size()):
		var route_position: Vector3 = patrol_route[route_index]
		var route_node_id := str(patrol_route_node_ids[route_index]) if route_index < patrol_route_node_ids.size() else "missing"
		var route_point := {
			"point_id": route_node_id,
			"district": str(route.get("district", "巡城司")),
			"role": str(route.get("role", "patrol_guard")),
			"activity": "patrol_route",
			"position": route_position,
			"facing": 0.0,
			"schedule_tag": str(route.get("schedule_tag", "night")),
			"capacity": 1,
			"radius": 1.0,
			"navigation_node_id": route_node_id
		}
		route_point.merge(WORLD_LAYOUT.get_spatial_binding_for_point(route_point, navigation_network_data), true)
		activity_points.append(route_point)


func get_navigation_route_to_district(district_id: String, origin: Vector3 = Vector3.ZERO) -> Dictionary:
	# Public scene adapter for UI, quest and NPC callers. Does not move an actor.
	if navigation_network_data.is_empty():
		navigation_network_data = WORLD_LAYOUT.get_navigation_network()
	last_navigation_route = WORLD_NAVIGATION.find_path_to_district(
		navigation_network_data,
		origin,
		district_id,
		WORLD_LAYOUT.get_district_service_entrances()
	)
	return last_navigation_route.duplicate(true)


func get_navigation_route_between_positions(origin: Vector3, destination: Vector3) -> Dictionary:
	if navigation_network_data.is_empty():
		navigation_network_data = WORLD_LAYOUT.get_navigation_network()
	var destination_node := WORLD_NAVIGATION.find_nearest_node(navigation_network_data, destination)
	if not bool(destination_node.get("found", false)):
		return {"found": false, "reason": "no_navigation_nodes", "node_ids": [], "points": [], "distance": INF}
	last_navigation_route = WORLD_NAVIGATION.find_path_from_position(
		navigation_network_data,
		origin,
		str(destination_node["node_id"])
	)
	last_navigation_route["destination_connector_distance"] = float(destination_node["distance"])
	return last_navigation_route.duplicate(true)


func _district_key(district_name: String) -> String:
	for district_data in WORLD_LAYOUT.get_districts():
		if str(district_data.get("name", "")) == district_name:
			return str(district_data.get("id", "bureau"))
	return "bureau"


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


func _bind_market_merchant(agent: Dictionary, point: Dictionary) -> void:
	# Match the six market merchant agents to the six locally registered stall prototypes.
	var point_position: Vector3 = point.get("position", Vector3.ZERO)
	var nearest_stall: Dictionary = {}
	var nearest_distance := INF
	for stall in market_stall_registry:
		var stall_position: Vector3 = stall.get("position", Vector3.ZERO)
		var distance := point_position.distance_to(stall_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_stall = stall
	if nearest_stall.is_empty():
		return
	var stall_type := str(nearest_stall.get("stall_type", ""))
	var profile := _market_merchant_profile(stall_type)
	agent["market_stall_id"] = str(nearest_stall.get("stall_id", ""))
	agent["market_stall_type"] = stall_type
	agent["market_service"] = str(nearest_stall.get("interaction_type", "unavailable"))
	agent["market_goods"] = nearest_stall.get("display_items", [])
	agent["market_business_state"] = "open" if npc_schedule_night else "closed"
	agent["display_name"] = str(profile.get("name", agent.get("display_name", "无名掌柜")))
	agent["merchant_title"] = str(profile.get("title", "掌柜"))
	agent["interaction_type"] = "trade"


func _update_merchant_market_activity(agent: Dictionary) -> void:
	# Restocking takes priority over customer greetings and the auction glance.
	if not agent.has("market_stall_id"):
		return
	var business_state := str(agent.get("market_business_state", "closed"))
	var previous_state := str(agent.get("state", "trade_idle"))
	if business_state == "restocking":
		agent["player_greeting"] = false
		var restock_phase := fposmod(market_ambience_time + float(agent.get("phase", 0.0)), 5.0)
		agent["state"] = "restock_receive" if restock_phase < 2.35 else "restock_sort"
		agent["market_activity"] = "receive_cargo" if restock_phase < 2.35 else "sort_goods"
		return
	if previous_state == "restock_receive" or previous_state == "restock_sort":
		agent["market_activity"] = "open_for_business"
		agent["state"] = "trade_idle"
		agent["state_elapsed"] = 0.0
		agent["state_cycle_index"] = 0
		agent["player_greeting"] = false
		return
	if business_state != "open" or bool(agent.get("player_greeting", false)):
		return
	if _is_market_auction_time():
		var glance_phase := fposmod(market_ambience_time + float(agent.get("phase", 0.0)), 18.0)
		if glance_phase < 2.8:
			var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
			var stage_position := market_center + Vector3(0.0, 0.0, 10.35)
			var merchant_root: Node3D = agent["root"]
			var stage_direction := stage_position - merchant_root.global_position
			agent["auction_facing"] = atan2(-stage_direction.x, -stage_direction.z)
			agent["state"] = "auction_watch"
			agent["market_activity"] = "watch_auction"
			return
	if previous_state == "auction_watch":
		agent["state"] = "trade_idle"
		agent["market_activity"] = "open_for_business"


func _market_merchant_profile(stall_type: String) -> Dictionary:
	match stall_type:
		"魂珠铺": return {"name": "孟照夜", "title": "魂珠掌柜"}
		"魂籍铺": return {"name": "陆简", "title": "魂籍先生"}
		"药材铺": return {"name": "青禾娘子", "title": "药材掌柜"}
		"法器铺": return {"name": "玄铸", "title": "法器匠师"}
		"魂器铺": return {"name": "百器翁", "title": "魂器鉴主"}
		"悬赏交易": return {"name": "铁算盘", "title": "悬赏牙人"}
	return {"name": "无名掌柜", "title": "掌柜"}


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
		if role == "merchant" and str(point["district"]) == "万魂鬼市":
			_bind_market_merchant(agent, point)
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
		if role == "resident":
			agent["resident_activity"] = str(point.get("resident_activity", "social_idle"))
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

	# Ambient customers and the auction host are visual actors, not server-owned NPCs.
	_build_market_customers()
	_build_market_caravans()
	_build_market_guards()
	_build_market_auction_host()
	_build_market_event_sign()

	# Three route walkers cover different perimeter sectors; static gate guards remain at their posts.
	if patrol_route.size() > 1:
		for patrol_slot in range(3):
			var route_start_index := int(round(float(patrol_route.size()) * float(patrol_slot) / 3.0)) % patrol_route.size()
			_create_patrol_route_guard(patrol_slot, route_start_index)
	_rebuild_npc_population_index()
	_apply_npc_schedules()



func _create_patrol_route_guard(patrol_slot: int, route_start_index: int) -> void:
	var patrol_root := Node3D.new()
	patrol_root.name = "LocalNPC_PatrolWalker_%02d" % (patrol_slot + 1)
	patrol_root.position = patrol_route[route_start_index]
	add_child(patrol_root)
	var patrol_agent := _create_npc_figure(patrol_root, "patrol_guard")
	patrol_agent["npc_id"] = "patrol.guard.walker.%02d" % (patrol_slot + 1)
	patrol_agent["display_name"] = "巡城卫·%s" % ["北巡", "东巡", "西巡"][patrol_slot]
	patrol_agent["district"] = "巡城司"
	patrol_agent["interaction_type"] = "dispatch"
	patrol_agent["importance"] = "regional"
	patrol_agent["root"] = patrol_root
	patrol_agent["role"] = "patrol_guard"
	patrol_agent["activity"] = "patrol_route"
	patrol_agent["phase"] = float(patrol_slot) * 1.73
	patrol_agent["moving"] = true
	patrol_agent["route_node_ids"] = patrol_route_node_ids.duplicate()
	patrol_agent["route_network_id"] = "route.patrol.perimeter_loop"
	patrol_agent["route_index"] = route_start_index
	patrol_agent["route_progress"] = 0.0
	patrol_agent["move_speed"] = 2.6
	patrol_agent["update_accumulator"] = 0.0
	_initialize_npc_behavior(patrol_agent)
	npc_agents.append(patrol_agent)


func _build_market_customers() -> void:
	# Four customers browse selected stalls while leaving the central aisle visibly open.
	# Static ambient props only: they are not server-owned or interactive NPC agents.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	var customer_stalls: Array[Dictionary] = [
		{"position": market_center + Vector3(-7.1, 0.0, -6.5), "yaw": PI * 0.5, "tint": "#9cabb5"},
		{"position": market_center + Vector3(7.1, 0.0, 6.5), "yaw": -PI * 0.5, "tint": "#b7a18a"},
		{"position": market_center + Vector3(-7.1, 0.0, 0.0), "yaw": PI * 0.5, "tint": "#8fae9a"},
		{"position": market_center + Vector3(7.1, 0.0, 0.0), "yaw": -PI * 0.5, "tint": "#a99abf"}
	]
	for index in range(customer_stalls.size()):
		var customer_root := Node3D.new()
		customer_root.name = "AmbientMarketCustomer_%02d" % (index + 1)
		customer_root.position = customer_stalls[index]["position"]
		customer_root.rotation.y = float(customer_stalls[index]["yaw"])
		add_child(customer_root)
		var customer_figure := _create_npc_figure(customer_root, "market_customer")
		var customer_robe := customer_figure["body"].material_override as StandardMaterial3D
		if customer_robe != null:
			customer_robe.albedo_color = Color(str(customer_stalls[index]["tint"]))
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
		var base_position: Vector3 = customer_stalls[index]["position"]
		var local_side := -1.0 if index % 2 == 0 else 1.0
		var customer_waypoints: Array[Vector3] = [
			base_position,
			base_position + Vector3(local_side * 0.55, 0.0, -1.0),
			base_position + Vector3(local_side * 0.55, 0.0, 1.0)
		]
		var auction_layout: Dictionary = WORLD_LAYOUT.get_market_auction_layout()
		var event_points: Array = auction_layout["audience_event_points"]
		var event_position: Vector3 = market_center + event_points[index]["offset"]
		market_customers.append({
			"customer_id": "ghost_market.customer.%02d" % (index + 1),
			"root": customer_root,
			"body": customer_figure["body"],
			"left_arm": customer_figure["left_arm"],
			"right_arm": customer_figure["right_arm"],
			"base_yaw": float(customer_stalls[index]["yaw"]),
			"base_position": base_position,
			"event_position": event_position,
			"preferred_stall_id": _market_customer_route_for_index(index)[0],
			"stall_route_ids": _market_customer_route_for_index(index),
			"route_stall_index": 0,
			"target_stall_id": _market_customer_route_for_index(index)[0],
			"target_position": _market_customer_stand_position("ghost_market.stall.%02d" % (index + 1), index),
			"visit_count": 0,
			"stop_elapsed": 0.0,
			"event_delay": float(index) * 1.15,
			"event_elapsed": 0.0,
			"waypoints": customer_waypoints,
			"route_index": 0,
			"route_progress": 0.0,
			"move_speed": 0.42 + float(index % 2) * 0.08,
			"state": "browse",
			"resume_state": "browse",
			"state_elapsed": float(index) * 1.7,
			"phase": float(index) * 2.4
		})


func _market_customer_route_for_index(customer_index: int) -> Array[String]:
	# Keep two visitors on each side; route order follows each side physical stall positions.
	match clampi(customer_index, 0, 3):
		0:
			return ["ghost_market.stall.01", "ghost_market.stall.02", "ghost_market.stall.03"]
		1:
			return ["ghost_market.stall.06", "ghost_market.stall.05", "ghost_market.stall.04"]
		2:
			return ["ghost_market.stall.02", "ghost_market.stall.03", "ghost_market.stall.01"]
		_:
			return ["ghost_market.stall.05", "ghost_market.stall.04", "ghost_market.stall.06"]


func _market_customer_stand_position(stall_id: String, customer_index: int) -> Vector3:
	for stall in market_stall_registry:
		if str(stall.get("stall_id", "")) != stall_id:
			continue
		var stall_position: Vector3 = stall.get("position", Vector3.ZERO)
		var facing := float(stall.get("facing", 0.0))
		var side_offset := (float(customer_index) - 1.5) * 0.38
		return stall_position + Vector3(facing * 2.75, 0.0, side_offset)
	return Vector3.ZERO


func _market_customer_next_open_stall(customer_data: Dictionary, customer_index: int) -> String:
	var route: Array = customer_data.get("stall_route_ids", [])
	if route.is_empty():
		return ""
	var current_index := int(customer_data.get("route_stall_index", 0))
	for offset in range(1, route.size() + 1):
		var candidate_index := (current_index + offset) % route.size()
		var candidate_id := str(route[candidate_index])
		if not _market_stall_is_restocking(candidate_id):
			for stall in market_stall_registry:
				if str(stall.get("stall_id", "")) == candidate_id and str(stall.get("business_state", "")) == "open":
					customer_data["route_stall_index"] = candidate_index
					customer_data["target_stall_id"] = candidate_id
					customer_data["target_position"] = _market_customer_stand_position(candidate_id, customer_index)
					return candidate_id
	return ""


func _market_customer_face_target(customer_root: Node3D, stall_id: String) -> void:
	for stall in market_stall_registry:
		if str(stall.get("stall_id", "")) == stall_id:
			var stall_position: Vector3 = stall.get("position", Vector3.ZERO)
			var look_direction := stall_position - customer_root.position
			if look_direction.length_squared() > 0.001:
				customer_root.rotation.y = atan2(-look_direction.x, -look_direction.z)
			return


func _build_market_caravans() -> void:
	# Two small supply carts use the rear service lanes, never the central 9m aisle.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	for caravan_data in WORLD_LAYOUT.get_market_caravans():
		var index := market_caravans.size()
		var caravan_id := str(caravan_data["caravan_id"])
		var cargo_type := str(caravan_data["cargo_type"])
		var cargo_palette := Color(str(caravan_data["cargo_palette"]))
		var root := Node3D.new()
		root.name = "AmbientMarketCaravan_%02d" % (index + 1)
		root.position = market_center + caravan_data["offset"]
		root.rotation.y = float(caravan_data["facing"])
		add_child(root)
		var driver := _create_npc_figure(root, "market_customer")
		var driver_material := driver["body"].material_override as StandardMaterial3D
		if driver_material != null:
			driver_material.albedo_color = Color("#8b7766") if index == 0 else Color("#6e8292")
		var cart := Node3D.new()
		cart.name = "SupplyCart"
		cart.position = Vector3(0.0, 0.0, 1.45)
		root.add_child(cart)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("#715b47")
		wood.roughness = 0.94
		var bed := MeshInstance3D.new()
		var bed_mesh := BoxMesh.new()
		bed_mesh.size = Vector3(1.25, 0.22, 1.35)
		bed.mesh = bed_mesh
		bed.position.y = 0.62
		bed.material_override = wood
		cart.add_child(bed)
		for wheel_side in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.34
			wheel_mesh.bottom_radius = 0.34
			wheel_mesh.height = 0.14
			wheel.mesh = wheel_mesh
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wheel_side * 0.68, 0.38, 0.0)
			wheel.material_override = wood
			cart.add_child(wheel)
		for pack_index in range(3):
			var pack := MeshInstance3D.new()
			var pack_mesh := BoxMesh.new()
			pack_mesh.size = Vector3(0.38, 0.42, 0.38)
			pack.mesh = pack_mesh
			pack.position = Vector3(float(pack_index - 1) * 0.38, 0.94, 0.0)
			var pack_material := StandardMaterial3D.new()
			pack_material.albedo_color = Color("#9c8063") if index == 0 else Color("#667b83")
			pack_material.roughness = 0.9
			pack.material_override = pack_material
			cart.add_child(pack)
		var cargo_label := Label3D.new()
		cargo_label.name = "SupplyCargoLabel"
		cargo_label.text = cargo_type
		cargo_label.position = Vector3(0.0, 1.55, 1.45)
		cargo_label.font_size = 11
		cargo_label.pixel_size = 0.009
		cargo_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cargo_label.modulate = Color("#e2c99c")
		cargo_label.outline_size = 4
		cargo_label.outline_modulate = Color("#171d25")
		cart.add_child(cargo_label)
		var cargo_status := Label3D.new()
		cargo_status.name = "SupplyCargoStatus"
		cargo_status.text = "待命"
		cargo_status.position = Vector3(0.0, 2.05, 1.45)
		cargo_status.font_size = 10
		cargo_status.pixel_size = 0.008
		cargo_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cargo_status.modulate = cargo_palette
		cargo_status.outline_size = 4
		cargo_status.outline_modulate = Color("#171d25")
		cart.add_child(cargo_status)
		# One reusable client-side crate visual travels from the cart to the matching stall.
		var unload_crate := MeshInstance3D.new()
		unload_crate.name = "CaravanUnloadingCrate"
		var unload_crate_mesh := BoxMesh.new()
		unload_crate_mesh.size = Vector3(0.52, 0.48, 0.52)
		unload_crate.mesh = unload_crate_mesh
		var unload_crate_material := StandardMaterial3D.new()
		unload_crate_material.albedo_color = Color("#9c8063") if index == 0 else Color("#718d70")
		unload_crate_material.roughness = 0.92
		unload_crate.material_override = unload_crate_material
		unload_crate.visible = false
		add_child(unload_crate)
		# Three persistent, reusable depot crates per caravan; these remain after unloading.
		var storage_crates: Array[MeshInstance3D] = []
		for storage_index in range(3):
			var storage_crate := MeshInstance3D.new()
			storage_crate.name = "MarketDepotCrate_%02d_%02d" % [index + 1, storage_index + 1]
			var storage_mesh := BoxMesh.new()
			storage_mesh.size = Vector3(0.5, 0.46, 0.5)
			storage_crate.mesh = storage_mesh
			var storage_material := StandardMaterial3D.new()
			storage_material.albedo_color = Color("#9c8063") if index == 0 else Color("#718d70")
			storage_material.roughness = 0.92
			storage_crate.material_override = storage_material
			storage_crate.visible = false
			add_child(storage_crate)
			storage_crates.append(storage_crate)
		market_caravans.append({
			"caravan_id": caravan_id,
			"cargo_type": cargo_type,
			"cargo_palette": cargo_palette,
			"root": root,
			"body": driver["body"],
			"left_arm": driver["left_arm"],
			"right_arm": driver["right_arm"],
			"cargo_status": cargo_status,
			"unload_crate": unload_crate,
			"storage_crates": storage_crates,
			"delivered_crates": 0,
			"last_unload_cycle": -1,
			"base_x": root.position.x,
			"base_z": root.position.z,
			"phase": float(caravan_data["phase"])
		})


func _build_market_guards() -> void:
	# Gate sentries frame the entrance while staying outside the central passage.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var root := Node3D.new()
		root.name = "AmbientMarketGateGuard_%02d" % (index + 1)
		root.position = market_center + Vector3(side * 7.4, 0.0, -10.4)
		root.rotation.y = PI
		add_child(root)
		var figure := _create_npc_figure(root, "soldier")
		var uniform := figure["body"].material_override as StandardMaterial3D
		if uniform != null:
			uniform.albedo_color = Color("#596c7a") if index == 0 else Color("#6b667a")
		market_guards.append({
			"root": root,
			"body": figure["body"],
			"left_arm": figure["left_arm"],
			"right_arm": figure["right_arm"],
			"phase": float(index) * 1.9,
			"base_yaw": PI
		})
	market_inspection_label = Label3D.new()
	market_inspection_label.name = "GhostMarketNightInspectionStatus"
	market_inspection_label.position = market_center + Vector3(0.0, 3.35, -12.8)
	market_inspection_label.font_size = 14
	market_inspection_label.pixel_size = 0.01
	market_inspection_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	market_inspection_label.modulate = Color("#a9c3d2")
	market_inspection_label.outline_size = 5
	market_inspection_label.outline_modulate = Color("#101722")
	add_child(market_inspection_label)


func _build_market_event_sign() -> void:
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	market_event_label = Label3D.new()
	market_event_label.name = "GhostMarketAuctionSchedule"
	market_event_label.position = market_center + Vector3(0.0, 6.3, 11.0)
	market_event_label.font_size = 18
	market_event_label.pixel_size = 0.012
	market_event_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	market_event_label.modulate = Color("#e8c58b")
	market_event_label.outline_size = 5
	market_event_label.outline_modulate = Color("#101722")
	add_child(market_event_label)
	_update_market_event_sign()


func _update_market_event_sign() -> void:
	if market_event_label == null:
		return
	var hour := int(npc_world_minutes / 60.0)
	var minute := int(fposmod(npc_world_minutes, 60.0))
	var minute_of_day := hour * 60 + minute
	if minute_of_day >= 19 * 60 and minute_of_day < 19 * 60 + 30:
		market_event_label.text = "竞宝筹备 · 主持与席位准备中"
		market_event_label.modulate = Color("#c5b18e")
	elif minute_of_day >= 19 * 60 + 30 and minute_of_day < 20 * 60:
		market_event_label.text = "宾客入场 · 竞宝即将开场"
		market_event_label.modulate = Color("#d7bd98")
	elif _is_market_auction_time():
		market_event_label.text = "万魂竞宝 · 正在举行"
		market_event_label.modulate = Color("#f0d29a")
	elif minute_of_day >= 22 * 60 and minute_of_day < 22 * 60 + 30:
		market_event_label.text = "竞宝散场 · 清点与离席"
		market_event_label.modulate = Color("#aeb7c2")
	elif minute_of_day >= 22 * 60 + 30 and minute_of_day < 22 * 60 + 45:
		market_event_label.text = "本场竞宝结束 · 下场待定"
		market_event_label.modulate = Color("#aeb7c2")
	else:
		market_event_label.text = "竞宝时段 · 20:00–22:00"
		market_event_label.modulate = Color("#d7bd98")
	market_event_label.visible = npc_schedule_night



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
	_build_market_audience()
	_update_market_ambience(0.0)


func _build_market_audience() -> void:
	# Four ambient spectators frame the auction seating; they are not interactive NPCs.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	var auction_layout: Dictionary = WORLD_LAYOUT.get_market_auction_layout()
	var audience_positions: Array[Vector3] = []
	var audience_facings: Array[float] = []
	for seat in auction_layout["audience_seats"]:
		audience_positions.append(market_center + seat["offset"])
		audience_facings.append(float(seat["facing"]))
	var robes: Array[Color] = [Color("#7e899d"), Color("#9c806e"), Color("#718b82"), Color("#8d789e")]
	for index in range(audience_positions.size()):
		var root := Node3D.new()
		root.name = "AmbientAuctionSpectator_%02d" % (index + 1)
		root.position = audience_positions[index]
		root.rotation.y = audience_facings[index]
		add_child(root)
		var figure := _create_npc_figure(root, "market_customer")
		var robe := figure["body"].material_override as StandardMaterial3D
		if robe != null:
			robe.albedo_color = robes[index]
		market_audience.append({
			"root": root,
			"body": figure["body"],
			"left_arm": figure["left_arm"],
			"right_arm": figure["right_arm"],
			"phase": float(index) * 1.65,
			"base_yaw": root.rotation.y,
			"audience_state": "watch"
		})


func _update_market_ambience(delta: float) -> void:
	market_ambience_time += delta
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
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
	for customer_data in market_customers:
		var customer_root: Node3D = customer_data["root"]
		customer_root.visible = npc_schedule_night
		if not npc_schedule_night:
			continue
		var minute_of_day := int(npc_world_minutes / 60.0) * 60 + int(fposmod(npc_world_minutes, 60.0))
		var event_gathering := minute_of_day >= 19 * 60 + 30 and minute_of_day < 22 * 60 + 30
		var customer_state := str(customer_data.get("state", "browse"))
		var customer_body: MeshInstance3D = customer_data["body"]
		var customer_left: MeshInstance3D = customer_data["left_arm"]
		var customer_right: MeshInstance3D = customer_data["right_arm"]
		var customer_phase := market_ambience_time * 1.1 + float(customer_data["phase"])
		if event_gathering:
			if customer_state != "event_approach" and customer_state != "event_watch":
				customer_data["state"] = "event_approach"
				customer_state = "event_approach"
				customer_data["event_elapsed"] = 0.0
			var event_elapsed := float(customer_data.get("event_elapsed", 0.0)) + delta
			customer_data["event_elapsed"] = event_elapsed
			if event_elapsed < float(customer_data.get("event_delay", 0.0)):
				customer_body.rotation.x = sin(customer_phase * 0.5) * deg_to_rad(1.4)
				customer_left.rotation.z = deg_to_rad(-18.0) + sin(customer_phase * 0.5) * 0.02
				customer_right.rotation.z = deg_to_rad(18.0) - sin(customer_phase * 0.5 + 0.7) * 0.02
				continue
			var event_target: Vector3 = customer_data["event_position"]
			var event_delta: Vector3 = event_target - customer_root.position
			if event_delta.length() > 0.18:
				customer_root.position = customer_root.position.move_toward(event_target, 1.15 * delta)
				customer_root.rotation.y = atan2(-event_delta.x, -event_delta.z)
				customer_data["state"] = "event_approach"
			else:
				customer_root.position = event_target
				customer_data["state"] = "event_watch"
				var stage_direction: Vector3 = market_center + Vector3(0.0, 0.0, 13.0) - customer_root.position
				customer_root.rotation.y = atan2(-stage_direction.x, -stage_direction.z)
			customer_body.rotation.x = sin(customer_phase * 0.5) * deg_to_rad(1.4)
			if _is_market_auction_time():
				var applause := absf(sin(customer_phase * 1.7))
				customer_left.rotation.z = deg_to_rad(-18.0) - applause * 0.16
				customer_right.rotation.z = deg_to_rad(18.0) + applause * 0.16
			else:
				customer_left.rotation.z = deg_to_rad(-18.0) + sin(customer_phase * 0.5) * 0.02
				customer_right.rotation.z = deg_to_rad(18.0) - sin(customer_phase * 0.5 + 0.7) * 0.02
			continue
		if customer_state == "event_approach" or customer_state == "event_watch":
			customer_data["state"] = "return_to_stall"
			customer_data["event_elapsed"] = 0.0
			customer_state = "return_to_stall"
		if customer_state == "return_to_stall":
			var home_position: Vector3 = customer_data["base_position"]
			var home_delta: Vector3 = home_position - customer_root.position
			if home_delta.length() > 0.18:
				customer_root.position = customer_root.position.move_toward(home_position, 1.0 * delta)
				customer_root.rotation.y = atan2(-home_delta.x, -home_delta.z)
			else:
				customer_root.position = home_position
				customer_data["state"] = "browse"
				customer_data["route_index"] = 0
				customer_data["route_progress"] = 0.0
				customer_data["route_stall_index"] = 0
				customer_data["target_stall_id"] = str(customer_data.get("preferred_stall_id", ""))
				customer_data["target_position"] = _market_customer_stand_position(str(customer_data.get("target_stall_id", "")), customer_index)
			continue
		var customer_index := int(str(customer_data.get("customer_id", "customer.01")).get_slice(".", 2)) - 1
		var target_stall_id := str(customer_data.get("target_stall_id", customer_data.get("preferred_stall_id", "")))
		var stall_restocking := _market_stall_is_restocking(target_stall_id)
		var target_position: Vector3 = customer_data.get("target_position", customer_data.get("base_position", customer_root.position))
		if stall_restocking and customer_state != "walk":
			if customer_state != "restock_wait":
				customer_data["resume_state"] = customer_state
				customer_data["state"] = "restock_wait"
				customer_state = "restock_wait"
		if customer_state == "restock_wait":
			var next_stall_id := _market_customer_next_open_stall(customer_data, customer_index)
			if not next_stall_id.is_empty():
				target_stall_id = next_stall_id
				target_position = customer_data["target_position"]
				customer_data["state"] = "walk"
				customer_data["state_elapsed"] = 0.0
				customer_state = "walk"
			else:
				customer_root.rotation.y = float(customer_data["base_yaw"]) + sin(customer_phase * 0.4) * 0.12
				customer_body.rotation.x = deg_to_rad(2.0) + sin(customer_phase * 0.45) * deg_to_rad(1.2)
				customer_left.rotation.z = deg_to_rad(-18.0) + sin(customer_phase * 0.5) * 0.025
				customer_right.rotation.z = deg_to_rad(18.0) - sin(customer_phase * 0.5 + 0.6) * 0.025
				continue
		var customer_elapsed := float(customer_data.get("state_elapsed", 0.0)) + delta
		var customer_duration := 3.4 if customer_state == "browse" else (2.4 if customer_state == "inspect" else (2.8 if customer_state == "talk" else 0.0))
		if customer_state != "walk" and customer_elapsed >= customer_duration:
			customer_elapsed = 0.0
			match customer_state:
				"browse":
					customer_state = "inspect"
				"inspect":
					customer_state = "talk"
				"talk":
					var next_stall_id := _market_customer_next_open_stall(customer_data, customer_index)
					if next_stall_id.is_empty():
						customer_state = "restock_wait"
					else:
						target_stall_id = next_stall_id
						target_position = customer_data["target_position"]
						customer_state = "walk"
				_:
					customer_state = "browse"
			customer_data["state"] = customer_state
		customer_data["state_elapsed"] = customer_elapsed
		if customer_state == "walk":
			var walk_delta := target_position - customer_root.position
			if walk_delta.length() > 0.16:
				customer_root.position = customer_root.position.move_toward(target_position, float(customer_data.get("move_speed", 0.46)) * delta)
				if walk_delta.length_squared() > 0.001:
					customer_root.rotation.y = atan2(-walk_delta.x, -walk_delta.z)
				customer_body.rotation.x = deg_to_rad(1.8)
				customer_left.rotation.z = deg_to_rad(-18.0) - 0.035
				customer_right.rotation.z = deg_to_rad(18.0) + 0.035
			else:
				customer_root.position = target_position
				customer_data["state"] = "browse"
				customer_data["state_elapsed"] = 0.0
				customer_data["visit_count"] = int(customer_data.get("visit_count", 0)) + 1
				_market_customer_face_target(customer_root, target_stall_id)
			continue
		_market_customer_face_target(customer_root, target_stall_id)
		customer_body.rotation.x = deg_to_rad(2.5) + absf(sin(customer_phase * 0.55)) * deg_to_rad(2.0)
		if customer_state == "inspect":
			# Lean toward the stall display and bring one hand forward to examine an item.
			customer_body.rotation.x = deg_to_rad(9.0) + sin(customer_phase) * deg_to_rad(1.2)
			customer_left.rotation.z = deg_to_rad(-18.0) - 0.08
			customer_right.rotation.z = deg_to_rad(18.0) + 0.28 + sin(customer_phase * 1.4) * 0.025
		elif customer_state == "talk":
			# A brief exchange gesture; this remains ambient acting, not a shop transaction.
			customer_body.rotation.x = deg_to_rad(3.5)
			customer_left.rotation.z = deg_to_rad(-18.0) - maxf(sin(customer_phase * 1.2), 0.0) * 0.18
			customer_right.rotation.z = deg_to_rad(18.0) + maxf(sin(customer_phase * 1.2 + 1.2), 0.0) * 0.16
		else:
			customer_left.rotation.z = deg_to_rad(-18.0) + sin(customer_phase * 0.8) * 0.035
			customer_right.rotation.z = deg_to_rad(18.0) - sin(customer_phase * 0.8 + 1.1) * 0.045
	for guard_data in market_guards:
		var guard_root: Node3D = guard_data["root"]
		guard_root.visible = npc_schedule_night
		if not npc_schedule_night:
			continue
		var guard_phase := market_ambience_time * 0.55 + float(guard_data["phase"])
		var guard_body: MeshInstance3D = guard_data["body"]
		var guard_left: MeshInstance3D = guard_data["left_arm"]
		var guard_right: MeshInstance3D = guard_data["right_arm"]
		guard_body.position.y = 0.92 + sin(guard_phase) * 0.012
		guard_left.rotation.z = deg_to_rad(-18.0) + sin(guard_phase * 0.6) * 0.018
		guard_right.rotation.z = deg_to_rad(18.0) - sin(guard_phase * 0.6 + 0.8) * 0.018
		guard_root.rotation.y = float(guard_data["base_yaw"]) + sin(guard_phase * 0.25) * 0.025
	_update_market_gate_inspection(delta)
	for caravan_data in market_caravans:
		var caravan_root: Node3D = caravan_data["root"]
		caravan_root.visible = npc_schedule_night
		if not npc_schedule_night:
			continue
		# 44-second local loop: arrive, stop and unload, depart, then circle back outside the market.
		var route_time := fposmod(market_ambience_time + float(caravan_data["phase"]), 44.0)
		var route_offsets: Array = caravan_data["route_offsets"]
		var arrival_offset: Vector3 = route_offsets[0]
		var dock_offset: Vector3 = route_offsets[1]
		var departure_offset: Vector3 = route_offsets[2]
		var return_offset: Vector3 = route_offsets[3]
		var route_offset := dock_offset
		var caravan_state := "驶入"
		if route_time < 8.0:
			route_offset = arrival_offset.lerp(dock_offset, smoothstep(0.0, 8.0, route_time))
		elif route_time < 23.0:
			caravan_state = "卸货中"
		elif route_time < 31.0:
			caravan_state = "离场"
			route_offset = dock_offset.lerp(departure_offset, smoothstep(23.0, 31.0, route_time))
		else:
			caravan_state = "绕行返回"
			route_offset = departure_offset.lerp(return_offset, smoothstep(31.0, 44.0, route_time))
		caravan_root.position = Vector3(float(caravan_data["base_x"]), 0.0, float(caravan_data["base_z"])) + route_offset
		var travel_direction := -1.0 if route_time < 8.0 else (1.0 if route_time >= 23.0 and route_time < 31.0 else 0.0)
		if travel_direction != 0.0:
			caravan_root.rotation.y = PI if travel_direction < 0.0 else 0.0
		var cargo_status: Label3D = caravan_data["cargo_status"]
		cargo_status.text = caravan_state + " · " + str(caravan_data["cargo_type"])
		var caravan_phase := market_ambience_time * 1.6 + float(caravan_data["phase"])
		var driver_body: MeshInstance3D = caravan_data["body"]
		var driver_left: MeshInstance3D = caravan_data["left_arm"]
		var driver_right: MeshInstance3D = caravan_data["right_arm"]
		var unloading := caravan_state == "卸货中"
		driver_body.position.y = 0.92 + (absf(sin(caravan_phase * 2.0)) * 0.025 if not unloading else 0.0)
		driver_left.rotation.z = deg_to_rad(-18.0) + (sin(caravan_phase * 2.0) * 0.04 if not unloading else -0.12)
		driver_right.rotation.z = deg_to_rad(18.0) - (sin(caravan_phase * 2.0) * 0.04 if not unloading else 0.12)
		var unload_crate: MeshInstance3D = caravan_data["unload_crate"]
		var transfer_elapsed := fposmod(route_time - 8.0, 5.0)
		var transfer_cycle := int((route_time - 8.0) / 5.0) if unloading else -1
		if unloading and transfer_elapsed >= 2.2 and int(caravan_data.get("last_unload_cycle", -1)) != transfer_cycle:
			caravan_data["last_unload_cycle"] = transfer_cycle
			caravan_data["delivered_crates"] = mini(3, int(caravan_data.get("delivered_crates", 0)) + 1)
		var storage_crates: Array = caravan_data.get("storage_crates", [])
		var delivered_count := int(caravan_data.get("delivered_crates", 0))
		var depot_position := _market_restock_destination(str(caravan_data["cargo_type"]), str(caravan_data["caravan_id"]))
		for storage_index in range(storage_crates.size()):
			var stored_crate: MeshInstance3D = storage_crates[storage_index]
			stored_crate.visible = storage_index < delivered_count
			if stored_crate.visible:
				var stack_offset := Vector3(float(storage_index % 2) * 0.56, 0.25 + float(storage_index / 2) * 0.48, float(storage_index / 2) * 0.08)
				stored_crate.global_position = depot_position + stack_offset
				stored_crate.rotation.y = float(storage_index % 2) * 0.12
		unload_crate.visible = unloading and transfer_elapsed < 2.2
		if unload_crate.visible:
			var source_position := caravan_root.global_position + caravan_root.global_transform.basis * Vector3(0.0, 1.05, 1.45)
			var transfer_weight := smoothstep(0.0, 2.2, transfer_elapsed)
			unload_crate.global_position = source_position.lerp(depot_position + Vector3(0.0, 0.25, -0.08), transfer_weight)
			unload_crate.rotation.y = sin(transfer_elapsed * 2.4) * 0.08
	_update_market_stall_states()
	_update_market_event_sign()
	var auction_hour := int(npc_world_minutes / 60.0)
	var auction_minute := int(fposmod(npc_world_minutes, 60.0))
	var auction_minute_of_day := auction_hour * 60 + auction_minute
	var audience_visible := npc_schedule_night and auction_minute_of_day >= 19 * 60 + 30 and auction_minute_of_day < 22 * 60 + 30
	var auction_active := _is_market_auction_time()
	for spectator in market_audience:
		var spectator_root: Node3D = spectator["root"]
		spectator_root.visible = audience_visible
		if not audience_visible:
			continue
		var spectator_phase := market_ambience_time * (2.2 if auction_active else 0.55) + float(spectator["phase"])
		var spectator_body: MeshInstance3D = spectator["body"]
		var spectator_left: MeshInstance3D = spectator["left_arm"]
		var spectator_right: MeshInstance3D = spectator["right_arm"]
		var audience_clock := fposmod(market_ambience_time + float(spectator["phase"]) * 2.1, 18.0)
		var bidding := auction_active and audience_clock >= 4.0 and audience_clock < 7.0
		var cheering := auction_active and audience_clock >= 10.0 and audience_clock < 15.0
		spectator["audience_state"] = "bid" if bidding else ("cheer" if cheering else "watch")
		spectator_body.rotation.x = (deg_to_rad(4.0) if bidding else 0.0) + sin(spectator_phase * 0.65) * deg_to_rad(1.8)
		if bidding:
			# Each spectator raises a hand in a different time window; no synchronized crowd wave.
			spectator_left.rotation.z = deg_to_rad(-18.0) - 0.06
			spectator_right.rotation.z = deg_to_rad(18.0) + 0.72 + sin(spectator_phase * 1.4) * 0.035
		elif cheering:
			var applause := absf(sin(spectator_phase * 1.3))
			spectator_left.rotation.z = deg_to_rad(-18.0) - applause * 0.2
			spectator_right.rotation.z = deg_to_rad(18.0) + applause * 0.2
		else:
			spectator_left.rotation.z = deg_to_rad(-18.0) + sin(spectator_phase) * 0.025
			spectator_right.rotation.z = deg_to_rad(18.0) - sin(spectator_phase + 0.8) * 0.025
		spectator_root.rotation.y = float(spectator["base_yaw"]) + (0.0 if bidding else sin(spectator_phase * 0.25) * 0.035)
	if not market_stage_actor.is_empty():
		var host_root: Node3D = market_stage_actor["root"]
		var auction_active := _is_market_auction_time()
		host_root.visible = npc_schedule_night and auction_active
		if host_root.visible:
			var host_phase := market_ambience_time * 1.25 + float(market_stage_actor["phase"])
			var host_body: MeshInstance3D = market_stage_actor["body"]
			var host_left: MeshInstance3D = market_stage_actor["left_arm"]
			var host_right: MeshInstance3D = market_stage_actor["right_arm"]
			var auction_elapsed_minutes := fposmod(npc_world_minutes - 20.0 * 60.0, 20.0)
			var lot_index := mini(2, int(auction_elapsed_minutes / (20.0 / 3.0)))
			var lot_parts: Array = market_stage_actor.get("lot_parts", [])
			for lot_part_index in range(lot_parts.size()):
				var lot_part: MeshInstance3D = lot_parts[lot_part_index]
				lot_part.visible = lot_part_index == lot_index
				if lot_part.visible:
					lot_part.rotation.y = host_phase * 0.32
			var lot_names: Array = market_stage_actor.get("lot_names", [])
			var lot_label: Label3D = market_stage_actor.get("lot_label")
			if lot_label != null and lot_index < lot_names.size():
				lot_label.text = str(lot_names[lot_index])
			host_body.rotation.x = sin(host_phase * 0.7) * deg_to_rad(1.5)
			match int(auction_elapsed_minutes):
				0, 1, 2:
					# Opening salute: both arms rise together, then settle.
					var salute := sin(host_phase * 0.9) * 0.5 + 0.5
					host_left.rotation.z = deg_to_rad(-18.0) - salute * 0.38
					host_right.rotation.z = deg_to_rad(18.0) + salute * 0.38
					host_body.rotation.x = deg_to_rad(5.0) + sin(host_phase) * deg_to_rad(1.0)
				3, 4, 5, 6:
					# Present the lot with one extended arm.
					host_left.rotation.z = deg_to_rad(-18.0) - 0.08
					host_right.rotation.z = deg_to_rad(18.0) + 0.42 + sin(host_phase) * 0.035
				16, 17, 18:
					# Invite bids with alternating raised hands.
					host_left.rotation.z = deg_to_rad(-18.0) - maxf(sin(host_phase * 1.4), 0.0) * 0.34
					host_right.rotation.z = deg_to_rad(18.0) + maxf(sin(host_phase * 1.4 + 1.4), 0.0) * 0.34
				19:
					# Close the round with a brief respectful bow.
					host_left.rotation.z = deg_to_rad(-18.0) - 0.12
					host_right.rotation.z = deg_to_rad(18.0) + 0.12
					host_body.rotation.x = deg_to_rad(8.0)
				_:
					# Lot introduction: a restrained alternating presenter gesture.
					host_left.rotation.z = deg_to_rad(-18.0) - maxf(sin(host_phase), 0.0) * 0.28
					host_right.rotation.z = deg_to_rad(18.0) + maxf(sin(host_phase + 1.1), 0.0) * 0.28
			host_root.rotation.y = sin(host_phase * 0.35) * 0.025


func _initialize_npc_behavior(agent: Dictionary) -> void:
	var role := str(agent.get("role", ""))
	var states: Array = _npc_behavior_states(role)
	if role == "resident":
		match str(agent.get("resident_activity", "social_idle")):
			"square_walk": states = ["square_walk", "square_chat", "square_walk"]
			"carry_goods": states = ["carry_goods", "square_walk", "carry_goods"]
			"well_idle": states = ["well_idle", "draw_water", "well_idle"]
			"home_idle": states = ["home_idle", "square_chat", "home_idle"]
			"tea_social": states = ["tea_social", "serve_tea", "square_chat", "tea_social"]
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
		"tea_social", "square_chat", "square_walk", "trade_idle", "drill", "carry_goods", "draw_water", "serve_tea":
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
		"restock_receive":
			body.rotation.x = deg_to_rad(12.0) + absf(gesture) * 0.025
			left_arm.rotation.z = deg_to_rad(-62.0) + sin(phase * 1.4) * 0.045
			right_arm.rotation.z = deg_to_rad(62.0) - sin(phase * 1.4 + 0.6) * 0.045
		"restock_sort":
			body.rotation.x = deg_to_rad(8.0) + absf(gesture) * 0.03
			left_arm.rotation.z = deg_to_rad(-48.0) + sin(phase * 1.7) * 0.12
			right_arm.rotation.z = deg_to_rad(48.0) - sin(phase * 1.7 + 0.8) * 0.12
		"auction_watch":
			root.rotation.y = float(agent.get("auction_facing", facing)) + sin(phase * 0.2) * 0.035
			body.rotation.x = deg_to_rad(-3.0) + sin(phase * 0.7) * deg_to_rad(1.0)
			left_arm.rotation.z = deg_to_rad(-18.0)
			right_arm.rotation.z = deg_to_rad(18.0)
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
		"carry_goods":
			body.rotation.x = deg_to_rad(4.0) + absf(gesture) * 0.025
			left_arm.rotation.z = deg_to_rad(-38.0) + sin(phase * 0.9) * 0.035
			right_arm.rotation.z = deg_to_rad(38.0) - sin(phase * 0.9 + 0.5) * 0.035
		"draw_water":
			body.rotation.x = deg_to_rad(9.0) + absf(gesture) * 0.03
			left_arm.rotation.z = deg_to_rad(-48.0) + sin(phase * 0.8) * 0.06
			right_arm.rotation.z = deg_to_rad(48.0) - sin(phase * 0.8 + 0.8) * 0.06
		"serve_tea":
			root.rotation.y = facing + sin(phase * 0.32) * 0.12
			left_arm.rotation.z = deg_to_rad(-42.0) + maxf(gesture, 0.0) * 0.1
			right_arm.rotation.z = deg_to_rad(42.0) - maxf(-gesture, 0.0) * 0.1
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
		"patrol_walk", "patrol_dispatch", "patrol_return":
			left_arm.rotation.z = deg_to_rad(-28.0) + sin(phase * 2.4) * 0.18
			right_arm.rotation.z = deg_to_rad(28.0) - sin(phase * 2.4) * 0.18
		"patrol_watch":
			if not bool(agent.get("moving", false)):
				root.rotation.y = facing + sin(phase * 0.25) * 0.12
		"alert_watch":
			root.rotation.y = float(agent.get("alert_facing", facing))
			left_arm.rotation.z = deg_to_rad(-58.0) + sin(phase * 1.6) * 0.08
			right_arm.rotation.z = deg_to_rad(58.0) - sin(phase * 1.6) * 0.08
			body.rotation.x = deg_to_rad(-3.0) + sin(phase * 1.1) * 0.015
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
	_update_patrol_alert(delta)
	_process_autonomous_judicial_cases(delta)
	var schedule_bucket := int(npc_world_minutes / 5.0)
	if schedule_bucket != npc_schedule_bucket:
		npc_schedule_bucket = schedule_bucket
		_apply_npc_schedules()

	for agent in npc_agents:
		var root: Node3D = agent["root"]
		if root == null or not is_instance_valid(root):
			continue
		_record_npc_activity_sample(agent, root)
		if str(agent.get("judicial_attendance_state", "")) in ["en_route", "called_to_hearing"]:
			_advance_judicial_attendance(agent, delta)
			continue
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
			_update_merchant_market_activity(agent)
		var dispatch_state := str(agent.get("dispatch_state", ""))
		if str(agent.get("judicial_attendance_state", "")) in ["waiting", "in_hearing"]:
			root.position = agent.get("judicial_destination", Vector3(51.0, 0.0, 36.5))
			root.rotation.y = PI
			left_arm.rotation.z = deg_to_rad(-18.0)
			right_arm.rotation.z = deg_to_rad(18.0)
			agent["state"] = "judicial_" + str(agent.get("judicial_attendance_state", "waiting"))
		elif str(agent.get("role", "")) == "patrol_guard" and dispatch_state != "":
			_advance_patrol_dispatch(agent, elapsed, phase)
		elif bool(agent["moving"]):
			var route_index := int(agent["route_index"])
			var route_progress := float(agent["route_progress"])
			var route: Array = agent.get("waypoints", patrol_route)
			var start: Vector3 = route[route_index]
			var next_index := (route_index + 1) % route.size()
			var finish: Vector3 = route[next_index]
			var segment_length := maxf(start.distance_to(finish), 0.01)
			var patrol_route_actor := activity == "patrol_route"
			var patrol_pause := float(agent.get("patrol_pause_remaining", 0.0))
			if patrol_route_actor and patrol_pause > 0.0:
				patrol_pause = maxf(0.0, patrol_pause - elapsed)
				agent["patrol_pause_remaining"] = patrol_pause
				agent["state"] = "patrol_watch"
				root.position = start
				var checkpoint_direction: Vector3 = finish - start
				if checkpoint_direction.length_squared() > 0.01:
					root.rotation.y = atan2(-checkpoint_direction.x, -checkpoint_direction.z)
				left_arm.rotation.z = deg_to_rad(-18.0) + sin(phase * 0.4) * 0.025
				right_arm.rotation.z = deg_to_rad(18.0) - sin(phase * 0.4) * 0.025
			else:
				route_progress += float(agent["move_speed"]) * elapsed / segment_length
				while route_progress >= 1.0:
					route_progress -= 1.0
					route_index = next_index
					next_index = (route_index + 1) % route.size()
					start = route[route_index]
					finish = route[next_index]
					segment_length = maxf(start.distance_to(finish), 0.01)
					if patrol_route_actor:
						route_progress = 0.0
						agent["patrol_pause_remaining"] = 2.4
						agent["state"] = "patrol_watch"
						break
				root.position = start.lerp(finish, route_progress)
				var direction := finish - start
				if direction.length_squared() > 0.01:
					root.rotation.y = atan2(-direction.x, -direction.z)
				body.position.y = 0.92 + absf(sin(phase * 2.4)) * 0.07
				left_arm.rotation.z = deg_to_rad(-28.0) + sin(phase * 2.4) * 0.18
				right_arm.rotation.z = deg_to_rad(28.0) - sin(phase * 2.4) * 0.18
			agent["route_index"] = route_index
			agent["route_progress"] = route_progress
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


func _update_market_gate_inspection(delta: float) -> void:
	if market_inspection_label == null:
		return
	market_inspection_label.visible = npc_schedule_night
	if not npc_schedule_night:
		market_inspection_remaining = 0.0
		market_inspection_label.text = "夜市巡防 · 白日休市"
		return
	if market_inspection_remaining > 0.0:
		market_inspection_remaining = maxf(0.0, market_inspection_remaining - delta)
	elif delta > 0.0:
		market_inspection_elapsed += delta
		if market_inspection_elapsed >= 72.0:
			market_inspection_elapsed = 0.0
			market_inspection_remaining = 10.0
			market_inspection_sequence += 1
			# The gate guard reports a suspicious inspection finding to the patrol network.
			var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
			patrol_alert_position = market_center + Vector3(0.0, 0.0, -12.0)
			patrol_alert_remaining = maxf(patrol_alert_remaining, 45.0)
			patrol_alert_sequence += 1
			var incident_profile := _patrol_incident_profile(patrol_alert_sequence)
			_begin_patrol_dispatch(patrol_alert_position, incident_profile)
			print("[FengduPatrol] market gate report #%d queued: %s / %s" % [
				patrol_alert_sequence,
				str(incident_profile.get("title", "未知事件")),
				str(incident_profile.get("severity_label", "一般"))
			])
	var inspecting := market_inspection_remaining > 0.0
	var minute_of_day := int(npc_world_minutes / 60.0) * 60 + int(fposmod(npc_world_minutes, 60.0))
	var welcoming_guests := minute_of_day >= 19 * 60 + 30 and minute_of_day < 20 * 60
	var guiding_departure := minute_of_day >= 22 * 60 and minute_of_day < 22 * 60 + 30
	var dispatch_status := _patrol_dispatch_status_text()
	if dispatch_status != "":
		market_inspection_label.text = dispatch_status
	elif inspecting:
		market_inspection_label.text = "巡夜巡查 · 入口核验 #%d" % market_inspection_sequence
	elif welcoming_guests:
		market_inspection_label.text = "宾客入场 · 入口引导"
	elif guiding_departure:
		market_inspection_label.text = "竞宝散场 · 引导离席"
	else:
		market_inspection_label.text = "夜市巡防 · 正常"
	market_inspection_label.modulate = Color("#e4bd82") if inspecting else (Color("#d7bd98") if welcoming_guests or guiding_departure else Color("#a9c3d2"))
	for index in range(market_guards.size()):
		var guard_data: Dictionary = market_guards[index]
		var guard_root: Node3D = guard_data["root"]
		if not guard_root.visible:
			continue
		var phase := market_ambience_time * 1.3 + float(guard_data["phase"])
		var left_arm: MeshInstance3D = guard_data["left_arm"]
		var right_arm: MeshInstance3D = guard_data["right_arm"]
		var side := -1.0 if index == 0 else 1.0
		if inspecting:
			guard_root.rotation.y = float(guard_data["base_yaw"]) + side * 0.32
			left_arm.rotation.z = deg_to_rad(-52.0) + sin(phase) * 0.035
			right_arm.rotation.z = deg_to_rad(52.0) - sin(phase) * 0.035
		elif welcoming_guests:
			guard_root.rotation.y = float(guard_data["base_yaw"]) - side * 0.2
			left_arm.rotation.z = deg_to_rad(-34.0) + sin(phase * 0.8) * 0.025
			right_arm.rotation.z = deg_to_rad(34.0) - sin(phase * 0.8 + 0.6) * 0.025
		elif guiding_departure:
			guard_root.rotation.y = float(guard_data["base_yaw"]) + side * 0.24
			left_arm.rotation.z = deg_to_rad(-42.0) + sin(phase * 0.9) * 0.03
			right_arm.rotation.z = deg_to_rad(42.0) - sin(phase * 0.9 + 0.5) * 0.03
		else:
			guard_root.rotation.y = float(guard_data["base_yaw"]) + sin(phase * 0.2) * 0.025
			left_arm.rotation.z = deg_to_rad(-18.0) + sin(phase * 0.6) * 0.018
			right_arm.rotation.z = deg_to_rad(18.0) - sin(phase * 0.6 + 0.8) * 0.018
	for light in market_lights:
		light.light_energy = 0.82 if inspecting else (0.48 + 0.08 * (0.5 + 0.5 * sin(market_ambience_time)))


func _patrol_incident_profile(sequence: int) -> Dictionary:
	# Scripted local demo cycle exercises response tiers; real incident facts must come from the game service.
	match posmod(sequence - 1, 3):
		0:
			return {
				"type": "suspicious_activity",
				"title": "可疑魂影",
				"severity": "low",
				"severity_label": "低级",
				"priority": 1,
				"required_guards": 1,
				"scene_duration": 5.0
			}
		1:
			return {
				"type": "crowd_disorder",
				"title": "鬼市纠纷",
				"severity": "medium",
				"severity_label": "中级",
				"priority": 2,
				"required_guards": 2,
				"scene_duration": 8.0
			}
		_:
			return {
				"type": "violent_conflict",
				"title": "恶性冲突",
				"severity": "high",
				"severity_label": "高级",
				"priority": 3,
				"required_guards": 3,
				"scene_duration": 12.0
			}


func _begin_patrol_dispatch(target_position: Vector3, incident_profile: Dictionary) -> void:
	var incident := incident_profile.duplicate(true)
	incident["incident_id"] = "fengdu.incident.%04d" % patrol_alert_sequence
	incident["target_position"] = target_position
	incident["created_order"] = patrol_alert_sequence
	incident["state"] = "queued"
	incident["created_at"] = npc_simulation_time
	incident["case_workflow_state"] = "unsubmitted"
	incident["case_submission"] = {}
	incident["judge_review_state"] = "not_submitted"
	incident["assigned_guard_ids"] = []
	incident["arrived_guard_ids"] = []
	incident["returned_guard_ids"] = []
	incident["investigation_remaining"] = float(incident.get("scene_duration", 6.0))
	incident["evidence_count"] = 0
	incident["witness_count"] = 0
	incident["player_action_ids"] = []
	incident["player_contribution_log"] = []
	incident["player_evidence_count"] = 0
	incident["player_witness_count"] = 0
	incident["player_contribution_count"] = 0
	var scene_clues := _spawn_patrol_incident_clues(incident)
	incident["evidence_nodes"] = scene_clues.get("evidence_nodes", [])
	incident["witness_root"] = scene_clues.get("witness_root")
	incident["witness_name"] = str(scene_clues.get("witness_name", ""))
	incident["witness_questioned"] = false
	incident["player_clue_tags"] = []
	incident["witness_testimony_tag"] = ""
	incident["witness_question_stage"] = 0
	incident["investigation_timeline"] = []
	incident["nearby_actor_snapshots"] = _capture_incident_nearby_activity(target_position)
	incident["suspect_lead_count"] = incident["nearby_actor_snapshots"].size()
	_append_incident_timeline_entry(incident, "incident_report", "巡防报告登记：" + str(incident.get("title", "现场事件")), "patrol")
	if int(incident["suspect_lead_count"]) > 0:
		_append_incident_timeline_entry(incident, "activity_snapshot", "案发地点附近记录到 %d 名活动人员，均列为待核查线索" % int(incident["suspect_lead_count"]), "local_activity")
	patrol_incident_records.append(incident.duplicate(true))
	patrol_incident_queue.append(incident)
	patrol_incident_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := int(a.get("priority", 0))
		var b_priority := int(b.get("priority", 0))
		if a_priority == b_priority:
			return int(a.get("created_order", 0)) < int(b.get("created_order", 0))
		return a_priority > b_priority
	)
	_process_patrol_dispatch_queue()


func _process_patrol_dispatch_queue() -> void:
	while not patrol_incident_queue.is_empty():
		var incident: Dictionary = patrol_incident_queue[0]
		var available_guards: Array[Dictionary] = []
		for agent in npc_agents:
			if str(agent.get("role", "")) != "patrol_guard":
				continue
			if str(agent.get("activity", "")) != "patrol_route" or str(agent.get("dispatch_state", "")) != "":
				continue
			var guard_root: Node3D = agent.get("root")
			if guard_root == null or not is_instance_valid(guard_root):
				continue
			available_guards.append({
				"agent": agent,
				"distance": guard_root.position.distance_to(incident["target_position"])
			})
		available_guards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance"]) < float(b["distance"])
		)
		var required_guards := maxi(1, int(incident.get("required_guards", 1)))
		if available_guards.size() < required_guards:
			return

		var dispatch_batch: Array[Dictionary] = []
		var route_failed := false
		for guard_slot in range(required_guards):
			var candidate: Dictionary = available_guards[guard_slot]
			var agent: Dictionary = candidate["agent"]
			var guard_root: Node3D = agent["root"]
			var lateral_offset := (float(guard_slot) - float(required_guards - 1) * 0.5) * 1.35
			var guard_target: Vector3 = incident["target_position"] + Vector3(lateral_offset, 0.0, 0.0)
			var path := _build_patrol_dispatch_path(guard_root.position, guard_target)
			if not bool(path.get("found", false)):
				print("[FengduPatrol] incident %s route failed: %s" % [
					str(incident.get("incident_id", "")),
					str(path.get("reason", "unknown"))
				])
				route_failed = true
				break
			dispatch_batch.append({
				"agent": agent,
				"path": path,
				"target": guard_target
			})
		if route_failed:
			return

		var assigned_guard_ids: Array[String] = []
		for dispatch_data in dispatch_batch:
			var assigned_agent: Dictionary = dispatch_data["agent"]
			assigned_guard_ids.append(str(assigned_agent.get("npc_id", "")))
		_update_patrol_incident_record(str(incident.get("incident_id", "")), {
			"state": "assigned",
			"assigned_guard_ids": assigned_guard_ids,
			"assigned_at": npc_simulation_time
		})
		patrol_incident_queue.pop_front()
		for dispatch_data in dispatch_batch:
			_start_patrol_guard_dispatch(
				dispatch_data["agent"],
				dispatch_data["path"],
				dispatch_data["target"],
				incident
			)
		print("[FengduPatrol] incident %s (%s) assigned to %d guards" % [
			str(incident.get("incident_id", "")),
			str(incident.get("severity_label", "一般")),
			dispatch_batch.size()
		])


func _start_patrol_guard_dispatch(agent: Dictionary, dispatch_path: Dictionary, target_position: Vector3, incident: Dictionary) -> void:
	var guard_root: Node3D = agent["root"]
	var route_index := int(agent.get("route_index", 0))
	var resume_index := posmod(route_index, maxi(patrol_route.size(), 1))
	var resume_position: Vector3 = patrol_route[resume_index] if not patrol_route.is_empty() else guard_root.position
	agent["dispatch_resume_route_index"] = resume_index
	agent["dispatch_resume_position"] = resume_position
	agent["dispatch_target_position"] = target_position
	agent["dispatch_waypoints"] = dispatch_path.get("points", [])
	agent["dispatch_waypoint_index"] = 1
	agent["dispatch_state"] = "enroute"
	agent["dispatch_wait_remaining"] = 0.0
	agent["dispatch_incident_id"] = str(incident.get("incident_id", ""))
	agent["dispatch_incident_type"] = str(incident.get("type", "unknown"))
	agent["dispatch_severity"] = str(incident.get("severity", "low"))
	agent["dispatch_priority"] = int(incident.get("priority", 1))
	agent["dispatch_scene_duration"] = float(incident.get("scene_duration", 6.0))
	agent["dispatch_required_guards"] = int(incident.get("required_guards", 1))
	agent["dispatch_incident_sequence"] = int(incident.get("created_order", patrol_alert_sequence))
	agent["state"] = "patrol_dispatch"
	agent["moving"] = false
	print("[FengduPatrol] guard %s en route; path %.1fm, %d waypoints" % [
		str(agent.get("npc_id", "unknown")),
		float(dispatch_path.get("distance", 0.0)),
		(dispatch_path.get("points", []) as Array).size()
	])


func _find_patrol_incident_record(incident_id: String) -> int:
	for index in range(patrol_incident_records.size()):
		if str(patrol_incident_records[index].get("incident_id", "")) == incident_id:
			return index
	return -1


func _update_patrol_incident_record(incident_id: String, changes: Dictionary) -> void:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return
	var record: Dictionary = patrol_incident_records[record_index]
	for key in changes:
		record[key] = changes[key]
	patrol_incident_records[record_index] = record


func _mark_patrol_guard_arrived(agent: Dictionary) -> void:
	var incident_id := str(agent.get("dispatch_incident_id", ""))
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return
	var record: Dictionary = patrol_incident_records[record_index]
	var arrived: Array = record.get("arrived_guard_ids", [])
	var guard_id := str(agent.get("npc_id", ""))
	if not arrived.has(guard_id):
		arrived.append(guard_id)
	record["arrived_guard_ids"] = arrived
	var assigned: Array = record.get("assigned_guard_ids", [])
	if arrived.size() >= assigned.size() and not assigned.is_empty():
		record["state"] = "investigating"
		record["investigation_started_at"] = npc_simulation_time
		record["investigation_remaining"] = float(record.get("scene_duration", 6.0))
		print("[FengduPatrol] incident %s investigation started; %d guards on scene" % [incident_id, arrived.size()])
	patrol_incident_records[record_index] = record


func _update_patrol_incident_lifecycle(delta: float) -> void:
	for index in range(patrol_incident_records.size()):
		var record: Dictionary = patrol_incident_records[index]
		if str(record.get("state", "")) != "investigating":
			continue
		var remaining := maxf(0.0, float(record.get("investigation_remaining", 0.0)) - delta)
		record["investigation_remaining"] = remaining
		if remaining <= 0.0:
			var incident_type := str(record.get("type", ""))
			var evidence_count := 1 if incident_type == "suspicious_activity" else (2 if incident_type == "crowd_disorder" else 3)
			var witness_count := 1 if incident_type == "suspicious_activity" else (2 if incident_type == "crowd_disorder" else 4)
			var result_code := "cleared" if incident_type == "suspicious_activity" else ("mediated" if incident_type == "crowd_disorder" else "secured")
			var result_label := "排除异常" if result_code == "cleared" else ("纠纷调解" if result_code == "mediated" else "现场控制")
			var player_evidence := int(record.get("player_evidence_count", 0))
			var player_witnesses := int(record.get("player_witness_count", 0))
			record["patrol_evidence_count"] = evidence_count
			record["patrol_witness_count"] = witness_count
			record["evidence_count"] = evidence_count + player_evidence
			record["witness_count"] = witness_count + player_witnesses
			var completed_player_actions: Array = record.get("player_action_ids", [])
			record["player_contribution_count"] = completed_player_actions.size()
			var clue_tags: Array = record.get("player_clue_tags", [])
			var testimony_tag := str(record.get("witness_testimony_tag", ""))
			var deduction_code := "inconclusive"
			var deduction_label := "线索不足，暂不能确认完整经过"
			if bool(record.get("witness_revised", false)):
				deduction_code = "testimony_conflict"
				deduction_label = "证人前后陈述与现场物证存在矛盾，需要复核"
			elif clue_tags.has("movement_trace") and testimony_tag == "witness_shadow":
				deduction_code = "route_corroborated"
				deduction_label = "脚印方向与证人所述黑影路线吻合"
			elif clue_tags.has("spirit_residue") and clue_tags.has("broken_artifact"):
				deduction_code = "artifact_linked"
				deduction_label = "阴气残留与魂器碎片存在关联"
			elif clue_tags.has("movement_trace") and clue_tags.has("spirit_residue"):
				deduction_code = "trace_linked"
				deduction_label = "行动轨迹与阴气残留位置相互印证"
			elif testimony_tag == "witness_dispute":
				deduction_code = "dispute_reported"
				deduction_label = "证人证实现场发生争执，仍需补充物证"
			elif testimony_tag == "witness_violence":
				deduction_code = "violence_reported"
				deduction_label = "证人报告发生暴力冲突，仍需核验现场"
			record["deduction_code"] = deduction_code
			record["deduction_label"] = deduction_label
			var timeline: Array = record.get("investigation_timeline", [])
			timeline.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
			record["investigation_timeline"] = timeline
			var timeline_labels: Array[String] = []
			for entry in timeline:
				timeline_labels.append(str(entry.get("label", "调查记录")))
			record["timeline_summary"] = " → ".join(timeline_labels)
			record["player_clue_tags"] = clue_tags
			if player_evidence + player_witnesses > 0:
				result_label = "玩家补充线索 · " + result_label
			record["state"] = "resolved"
			record["result_code"] = result_code
			record["result_label"] = result_label
			record["resolved_at"] = npc_simulation_time
			print("[FengduPatrol] incident %s resolved: %s; deduction %s; evidence %d, witnesses %d" % [
				str(record.get("incident_id", "")), result_label, deduction_label, evidence_count, witness_count
			])
		patrol_incident_records[index] = record
	_prune_patrol_incident_history()


func _process_autonomous_judicial_cases(delta: float) -> void:
	# NPC adjudication is deliberately low-frequency; ordinary cases never wait for a player.
	autonomous_judicial_elapsed += delta
	if autonomous_judicial_elapsed < AUTONOMOUS_JUDICIAL_INTERVAL:
		return
	autonomous_judicial_elapsed = 0.0
	for index in range(patrol_incident_records.size()):
		var record: Dictionary = patrol_incident_records[index]
		if str(record.get("state", "")) != "closed":
			continue
		var workflow := str(record.get("case_workflow_state", "unsubmitted"))
		if workflow in ["judgment_issued", "appeal_pending"]:
			continue
		var incident_id := str(record.get("incident_id", ""))
		if incident_id.is_empty():
			continue
		if workflow in ["unsubmitted", "returned_for_supplement"]:
			_seed_autonomous_case_material(record)
			record["autonomous_processing"] = true
			patrol_incident_records[index] = record
			var transfer := submit_patrol_case_to_judge_bureau(incident_id)
			if not bool(transfer.get("ok", false)):
				continue
		record = patrol_incident_records[index]
		if str(record.get("case_workflow_state", "")) == "transferred_to_judge_bureau":
			begin_judge_bureau_case_review(incident_id)
			record = patrol_incident_records[index]
		if str(record.get("case_workflow_state", "")) == "under_judicial_review":
			var submission: Dictionary = record.get("case_submission", {})
			for tag_value in submission.get("evidence_tags", []):
				var tag := str(tag_value)
				if not record.get("judicial_review", {}).get("evidence_assessments", {}).has(tag):
					record_judicial_evidence_assessment(incident_id, tag, "accepted", "NPC 判官依据巡城司勘验记录完成常规复核")
			if int(submission.get("witness_count", 0)) > 0 and not str(submission.get("testimony_tag", "")).is_empty():
				if record.get("judicial_review", {}).get("testimony_assessment", {}).is_empty():
					var testimony_status := "disputed" if bool(record.get("witness_revised", false)) else "credible"
					var testimony_reason := "证人前后陈述存在矛盾，NPC 判官将其列为争议材料，不单独据此定案" if testimony_status == "disputed" else "常规 NPC 证词与基础勘验材料未发现明显冲突"
					record_judicial_testimony_assessment(incident_id, testimony_status, testimony_reason)
			var review_result := complete_judge_bureau_review(incident_id)
			if bool(review_result.get("ok", false)) and bool(review_result.get("hearing_eligible", false)):
				record_judge_bureau_case_disposition(incident_id, "accept_for_hearing")
		record = patrol_incident_records[index]
		if str(record.get("case_workflow_state", "")) == "hearing_pending":
			begin_case_hearing(incident_id)
			record = patrol_incident_records[index]
		if str(record.get("case_workflow_state", "")) == "hearing_in_progress":
			var current_submission: Dictionary = record.get("case_submission", {})
			for tag_value in current_submission.get("evidence_tags", []):
				var tag := str(tag_value)
				if not record.get("hearing_record", {}).get("presented_evidence_tags", []).has(tag):
					present_case_evidence_at_hearing(incident_id, tag)
			if not str(current_submission.get("testimony_tag", "")).is_empty() and str(record.get("judicial_review", {}).get("testimony_assessment", {}).get("assessment", "")) == "credible" and not bool(record.get("hearing_record", {}).get("testimony_presented", false)):
				present_case_testimony_at_hearing(incident_id)
			close_case_hearing(incident_id, "NPC 判官已完成常规案件审理；玩家未参与，案件按现有材料自动归档。")
			record = patrol_incident_records[index]
		if str(record.get("case_workflow_state", "")) == "hearing_closed_pending_judgment":
			var final_submission: Dictionary = record.get("case_submission", {})
			var final_tags: Array[String] = []
			for tag_value in final_submission.get("evidence_tags", []):
				final_tags.append(str(tag_value))
			var result_code := str(record.get("result_code", ""))
			var outcome := "acquitted" if result_code == "cleared" else ("mitigated" if result_code == "mediated" else "responsible")
			record_case_judgment(incident_id, outcome, "NPC 判官依据巡防处置结果与卷宗材料作出常规裁定。", final_tags)
			finalize_case_judgment(incident_id)


func _seed_autonomous_case_material(record: Dictionary) -> void:
	var tags: Array = record.get("player_clue_tags", []).duplicate()
	var available_tags := ["movement_trace", "spirit_residue", "broken_artifact"]
	var required_count := maxi(2, int(record.get("patrol_evidence_count", 2)))
	for tag_value in available_tags:
		if tags.size() >= required_count:
			break
		if not tags.has(tag_value):
			tags.append(tag_value)
	record["player_clue_tags"] = tags
	if str(record.get("witness_testimony_tag", "")).is_empty():
		var incident_type := str(record.get("type", ""))
		record["witness_testimony_tag"] = "witness_dispute" if incident_type == "crowd_disorder" else ("witness_violence" if incident_type == "hostile_encounter" else "witness_shadow")
	if not record.has("autonomous_case_note"):
		record["autonomous_case_note"] = "由巡城司 NPC 自动补齐基础勘验材料；玩家可在移交前介入并补充线索。"




func _mark_patrol_guard_returned(agent: Dictionary) -> void:
	var incident_id := str(agent.get("dispatch_incident_id", ""))
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return
	var record: Dictionary = patrol_incident_records[record_index]
	var returned: Array = record.get("returned_guard_ids", [])
	var guard_id := str(agent.get("npc_id", ""))
	if not returned.has(guard_id):
		returned.append(guard_id)
	record["returned_guard_ids"] = returned
	var assigned: Array = record.get("assigned_guard_ids", [])
	if not assigned.is_empty() and returned.size() >= assigned.size():
		record["state"] = "closed"
		record["closed_at"] = npc_simulation_time
		print("[FengduPatrol] incident %s archived; all assigned guards returned" % incident_id)
	patrol_incident_records[record_index] = record


func _prune_patrol_incident_history() -> void:
	while patrol_incident_records.size() > 20:
		var removable_index := -1
		for index in range(patrol_incident_records.size()):
			var candidate: Dictionary = patrol_incident_records[index]
			var state := str(candidate.get("state", ""))
			var case_state := str(candidate.get("case_workflow_state", "unsubmitted"))
			var legal_case_active := case_state in [
				"returned_for_supplement",
				"transferred_to_judge_bureau",
				"under_judicial_review",
				"hearing_pending",
				"hearing_in_progress",
				"hearing_closed_pending_judgment",
				"judgment_issued",
				"appeal_pending"
			]
			if state == "closed" and not legal_case_active:
				removable_index = index
				break
		if removable_index < 0:
			return
		var archived: Dictionary = patrol_incident_records[removable_index]
		for clue_node in archived.get("evidence_nodes", []):
			if is_instance_valid(clue_node):
				clue_node.queue_free()
		var witness_root: Node3D = archived.get("witness_root")
		if witness_root != null and is_instance_valid(witness_root):
			witness_root.queue_free()
		patrol_incident_records.remove_at(removable_index)


func _begin_patrol_guard_return(agent: Dictionary) -> void:
	var root: Node3D = agent["root"]
	var resume_position: Vector3 = agent.get("dispatch_resume_position", root.position)
	var return_path := _build_patrol_dispatch_path(root.position, resume_position)
	if bool(return_path.get("found", false)):
		agent["dispatch_waypoints"] = return_path.get("points", [])
		agent["dispatch_waypoint_index"] = 1
		agent["dispatch_state"] = "returning"
		agent["state"] = "patrol_return"
	else:
		_finish_patrol_dispatch(agent)


func _build_patrol_dispatch_path(origin: Vector3, destination: Vector3) -> Dictionary:
	# Connect arbitrary incident/actor positions to the nearest stable road nodes.
	var start_node := WORLD_NAVIGATION.find_nearest_node(navigation_network_data, origin)
	var goal_node := WORLD_NAVIGATION.find_nearest_node(navigation_network_data, destination)
	if not bool(start_node.get("found", false)) or not bool(goal_node.get("found", false)):
		return {"found": false, "reason": "no_nearby_road_node", "points": [], "distance": INF}
	var route := WORLD_NAVIGATION.find_path(
		navigation_network_data,
		str(start_node.get("node_id", "")),
		str(goal_node.get("node_id", ""))
	)
	if not bool(route.get("found", false)):
		return route
	var route_points: Array = route.get("points", [])
	if route_points.is_empty():
		return {"found": false, "reason": "empty_route_points", "points": [], "distance": INF}
	var points: Array[Vector3] = [origin]
	for point in route_points:
		var road_point: Vector3 = point
		if points.back().distance_to(road_point) > 0.35:
			points.append(road_point)
	if points.back().distance_to(destination) > 0.35:
		points.append(destination)
	return {
		"found": true,
		"reason": "",
		"node_ids": route.get("node_ids", []),
		"points": points,
		"distance": float(route.get("distance", 0.0)) + origin.distance_to(route_points[0]) + destination.distance_to(route_points[-1])
	}


func _advance_patrol_dispatch(agent: Dictionary, elapsed: float, phase: float) -> void:
	var root: Node3D = agent["root"]
	var body: MeshInstance3D = agent["body"]
	var left_arm: MeshInstance3D = agent["left_arm"]
	var right_arm: MeshInstance3D = agent["right_arm"]
	var dispatch_state := str(agent.get("dispatch_state", ""))
	if dispatch_state == "on_scene":
		root.rotation.y = float(agent.get("alert_facing", root.rotation.y))
		agent["state"] = "investigating"
		body.position.y = 0.92 + sin(phase * 1.4) * 0.018
		left_arm.rotation.z = deg_to_rad(-58.0) + sin(phase * 1.6) * 0.08
		right_arm.rotation.z = deg_to_rad(58.0) - sin(phase * 1.6) * 0.08
		var incident_index := _find_patrol_incident_record(str(agent.get("dispatch_incident_id", "")))
		if incident_index >= 0:
			var incident_record: Dictionary = patrol_incident_records[incident_index]
			if str(incident_record.get("state", "")) == "resolved" or str(incident_record.get("state", "")) == "closed":
				_begin_patrol_guard_return(agent)
		else:
			_begin_patrol_guard_return(agent)
		return

	var waypoints: Array = agent.get("dispatch_waypoints", [])
	var waypoint_index := int(agent.get("dispatch_waypoint_index", 0))
	if waypoints.is_empty() or waypoint_index >= waypoints.size():
		if dispatch_state == "enroute":
			agent["dispatch_state"] = "on_scene"
			agent["alert_facing"] = root.rotation.y
			agent["state"] = "investigating"
			_mark_patrol_guard_arrived(agent)
			print("[FengduPatrol] guard arrived at incident %s" % str(agent.get("dispatch_incident_id", "unknown")))
		elif dispatch_state == "returning":
			_finish_patrol_dispatch(agent)
		return

	var target: Vector3 = waypoints[waypoint_index]
	var offset := target - root.position
	var distance := offset.length()
	var travel_step := float(agent.get("move_speed", 2.6)) * elapsed
	if distance <= maxf(travel_step, 0.18):
		root.position = target
		waypoint_index += 1
		agent["dispatch_waypoint_index"] = waypoint_index
		if waypoint_index >= waypoints.size():
			if dispatch_state == "enroute":
				agent["dispatch_state"] = "on_scene"
				agent["alert_facing"] = root.rotation.y
				agent["state"] = "investigating"
				_mark_patrol_guard_arrived(agent)
				print("[FengduPatrol] guard arrived at incident %s" % str(agent.get("dispatch_incident_id", "unknown")))
			else:
				_finish_patrol_dispatch(agent)
	else:
		root.position = root.position.move_toward(target, travel_step)
	var direction := target - root.position
	if direction.length_squared() > 0.01:
		root.rotation.y = atan2(-direction.x, -direction.z)
	agent["dispatch_waypoint_index"] = waypoint_index
	body.position.y = 0.92 + absf(sin(phase * 2.4)) * 0.07
	left_arm.rotation.z = deg_to_rad(-28.0) + sin(phase * 2.4) * 0.18
	right_arm.rotation.z = deg_to_rad(28.0) - sin(phase * 2.4) * 0.18
	agent["state"] = "patrol_dispatch" if dispatch_state == "enroute" else "patrol_return"


func _finish_patrol_dispatch(agent: Dictionary) -> void:
	var root: Node3D = agent["root"]
	_mark_patrol_guard_returned(agent)
	var resume_index := int(agent.get("dispatch_resume_route_index", 0))
	if not patrol_route.is_empty():
		resume_index = posmod(resume_index, patrol_route.size())
		root.position = patrol_route[resume_index]
	agent["route_index"] = resume_index
	agent["route_progress"] = 0.0
	agent["patrol_pause_remaining"] = 1.2
	agent["moving"] = true
	agent["dispatch_state"] = ""
	agent["dispatch_waypoints"] = []
	agent["dispatch_waypoint_index"] = 0
	agent["dispatch_incident_id"] = ""
	agent["dispatch_incident_type"] = ""
	agent["dispatch_severity"] = ""
	agent["dispatch_priority"] = 0
	agent["dispatch_required_guards"] = 0
	agent["state"] = "patrol_watch"
	print("[FengduPatrol] guard resumed perimeter patrol at node %s" % str(patrol_route_node_ids[resume_index] if resume_index < patrol_route_node_ids.size() else resume_index))


func _patrol_dispatch_status_text() -> String:
	var enroute_count := 0
	var on_scene_count := 0
	var returning_count := 0
	var investigating_count := 0
	var active_severity := ""
	for agent in npc_agents:
		if str(agent.get("role", "")) != "patrol_guard":
			continue
		var state := str(agent.get("dispatch_state", ""))
		if state == "":
			continue
		if active_severity == "":
			active_severity = str(agent.get("dispatch_severity", ""))
		match state:
			"enroute":
				enroute_count += 1
			"on_scene":
				on_scene_count += 1
			"returning":
				returning_count += 1
			"investigating":
				investigating_count += 1
	var severity_label := "高级" if active_severity == "high" else ("中级" if active_severity == "medium" else "低级")
	var queued_count := patrol_incident_queue.size()
	if enroute_count > 0:
		return "巡防增援 · %s事件 · %d 名巡城卫赶赴现场 · 待处理 %d" % [severity_label, enroute_count, queued_count]
	if investigating_count > 0 or on_scene_count > 0:
		return "现场调查 · %s事件 · %d 名巡城卫调查取证 · 待处理 %d" % [severity_label, investigating_count + on_scene_count, queued_count]
	if returning_count > 0:
		return "巡防归队 · %s事件 · %d 名巡城卫返回 · 待处理 %d" % [severity_label, returning_count, queued_count]
	if queued_count > 0:
		var next_incident: Dictionary = patrol_incident_queue[0]
		return "巡防待命 · %s（%s）等待足够人员" % [
			str(next_incident.get("title", "事件")),
			str(next_incident.get("severity_label", "一般"))
		]
	if not patrol_incident_records.is_empty():
		var latest_incident: Dictionary = patrol_incident_records.back()
		var closed_at := float(latest_incident.get("closed_at", -1000.0))
		if str(latest_incident.get("state", "")) == "closed" and npc_simulation_time - closed_at <= 12.0:
			var timeline_summary := str(latest_incident.get("timeline_summary", "暂无玩家调查记录"))
			if timeline_summary.length() > 64:
				timeline_summary = timeline_summary.left(64) + "…"
			return "事件结案 · %s · %s · 时间线：%s · 证据 %d 件 · 目击者 %d 人" % [
				str(latest_incident.get("result_label", "已处理")),
				str(latest_incident.get("deduction_label", "暂无额外线索结论")),
				timeline_summary,
				int(latest_incident.get("evidence_count", 0)),
				int(latest_incident.get("witness_count", 0))
			]
	return ""


func _update_patrol_alert(delta: float) -> void:
	# Dispatch queue is serviced at a low cadence; it never recalculates a route per frame.
	if patrol_alert_remaining > 0.0:
		patrol_alert_remaining = maxf(0.0, patrol_alert_remaining - delta)
	patrol_dispatch_queue_elapsed += delta
	if patrol_dispatch_queue_elapsed >= 0.5:
		patrol_dispatch_queue_elapsed = 0.0
		_process_patrol_dispatch_queue()
	_update_patrol_incident_lifecycle(delta)


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
	# Merchants greet nearby players but pause reception while their matching stall is restocked.
	var can_receive := str(agent.get("market_business_state", "open")) == "open"
	var should_greet := distance_to_player <= 5.0 and player != null and can_receive
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
			if agent.has("market_stall_id"):
				agent["market_business_state"] = "open" if npc_schedule_night else "closed"
		elif role == "waiting_soul":
			agent["activity"] = "queue_wait"
		elif role == "guide":
			agent["activity"] = "registration"
		elif role == "resident":
			agent["activity"] = "social_idle"
	for customer_data in market_customers:
		var customer_root: Node3D = customer_data["root"]
		customer_root.visible = npc_schedule_night
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


func _market_display_items_for_type(stall_type: String) -> Array:
	match stall_type:
		"魂珠铺": return ["青魂珠", "紫魂珠", "金魂珠"]
		"魂籍铺": return ["魂籍卷册", "登记簿"]
		"药材铺": return ["幽冥药包", "灵草"]
		"法器铺": return ["镇魂法器", "仪式器具"]
		"魂器铺": return ["魂器", "封存魂匣"]
		"悬赏交易": return ["悬赏卷", "交易凭物"]
	return []


func _create_market_stall_status_label(stall_position: Vector3, facing: float) -> Label3D:
	var status := Label3D.new()
	status.name = "GhostMarketBusinessStatus"
	status.position = stall_position + Vector3(facing * 2.28, 4.0, 0.0)
	status.font_size = 11
	status.pixel_size = 0.009
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status.modulate = Color("#a9c3d2")
	status.outline_size = 4
	status.outline_modulate = Color("#101722")
	status.text = "休市"
	add_child(status)
	return status


func _create_market_stall_catalog_label(stall_position: Vector3, facing: float, items: Array) -> Label3D:
	# Compact floating catalog cards improve stall readability without adding per-item meshes.
	var catalog := Label3D.new()
	catalog.name = "GhostMarketCatalogCard"
	catalog.position = stall_position + Vector3(facing * 2.35, 1.62, 0.0)
	catalog.font_size = 10
	catalog.pixel_size = 0.008
	catalog.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	catalog.modulate = Color("#d8d0bd")
	catalog.outline_size = 4
	catalog.outline_modulate = Color("#111820")
	var item_lines: Array[String] = []
	for item_index in range(mini(items.size(), 3)):
		item_lines.append(str(items[item_index]))
	catalog.text = "陈列目录\n" + " · ".join(item_lines) + "\n现场询价"
	add_child(catalog)
	return catalog


func _market_restock_destination(_cargo_type: String, caravan_id: String) -> Vector3:
	# The caravan's stable layout record selects its unloading stall explicitly.
	var target_stall_id := ""
	for caravan in WORLD_LAYOUT.get_market_caravans():
		if str(caravan["caravan_id"]) == caravan_id:
			target_stall_id = str(caravan["restock_stall_id"])
			break
	if target_stall_id.is_empty():
		return Vector3.ZERO
	var target_stall: Dictionary = {}
	for stall in market_stall_registry:
		if str(stall.get("stall_id", "")) == target_stall_id:
			target_stall = stall
			break
	if target_stall.is_empty():
		return Vector3.ZERO
	var stall_position: Vector3 = target_stall.get("position", Vector3.ZERO)
	var facing := float(target_stall.get("facing", 0.0))
	var rear_direction := Vector3(sin(facing), 0.0, cos(facing))
	return stall_position + rear_direction * 1.7 + Vector3(0.0, 0.28, -0.9)


func _market_stall_is_restocking(stall_id: String) -> bool:
	if stall_id.is_empty():
		return false
	for stall in market_stall_registry:
		if str(stall.get("stall_id", "")) == stall_id:
			return str(stall.get("business_state", "")) == "restocking"
	return false


func _update_market_stall_states() -> void:
	# Match the two existing supply routes to only the stalls that sell those goods.
	var unloading_groups: Array[String] = []
	if npc_schedule_night:
		for caravan_data in market_caravans:
			var route_time := fposmod(market_ambience_time + float(caravan_data.get("phase", 0.0)), 44.0)
			if route_time >= 8.0 and route_time < 23.0:
				var cargo_type := str(caravan_data.get("cargo_type", ""))
				if cargo_type == "魂珠与魂籍":
					unloading_groups.append("soul_goods")
				elif cargo_type == "药材与法器":
					unloading_groups.append("herb_goods")
	for stall in market_stall_registry:
		var group := str(stall.get("restock_group", ""))
		var state := "closed"
		if npc_schedule_night:
			state = "restocking" if group != "" and unloading_groups.has(group) else "open"
		stall["business_state"] = state
		var status_label: Label3D = stall.get("restock_label")
		if status_label != null:
			status_label.visible = true
			match state:
				"restocking":
					status_label.text = "补货中 · 暂缓接待"
					status_label.modulate = Color("#e6c58d")
				"open":
					status_label.text = "营业中"
					status_label.modulate = Color("#9fc6a7")
				_:
					status_label.text = "白日休市"
					status_label.modulate = Color("#8e9aa7")
		var catalog_label: Label3D = stall.get("catalog_label")
		if catalog_label != null:
			catalog_label.visible = true
			catalog_label.modulate = Color("#c9b18b") if state == "restocking" else (Color("#d8d0bd") if state == "open" else Color("#87919c"))
			if state == "restocking":
				catalog_label.text = "补货整理中\n稍候再来"
			elif state == "closed":
				catalog_label.text = "白日休市\n夜间开市"
			else:
				var items: Array = stall.get("display_items", [])
				var item_lines: Array[String] = []
				for item_index in range(mini(items.size(), 3)):
					item_lines.append(str(items[item_index]))
				catalog_label.text = "陈列目录\n" + " · ".join(item_lines) + "\n现场询价"
	for agent in npc_agents:
		if not agent.has("market_stall_id"):
			continue
		for stall in market_stall_registry:
			if str(agent.get("market_stall_id", "")) == str(stall.get("stall_id", "")):
				agent["market_business_state"] = str(stall.get("business_state", "closed"))
				break


func _market_interaction_for_type(stall_type: String) -> String:
	match stall_type:
		"魂珠铺": return "trade_soul_gems"
		"魂籍铺": return "archive_service"
		"药材铺": return "trade_herbs"
		"法器铺": return "trade_ritual_items"
		"魂器铺": return "appraise_soul_vessels"
		"悬赏交易": return "bounty_exchange"
	return "unavailable"


func _is_market_auction_time() -> bool:
	var hour := int(npc_world_minutes / 60.0)
	return hour >= 20 and hour < 22


func _build_market_auction_host() -> void:
	# One ceremonial stage actor appears during the local 20:00-22:00 auction window.
	# It is deliberately excluded from npc_agents and all server interaction systems.
	var market_center: Vector3 = district_markers.get("万魂鬼市", Vector3(55.0, 0.0, -53.0))
	var host_root := Node3D.new()
	host_root.name = "AmbientMarketAuctionHost"
	host_root.position = market_center + Vector3(0.0, 0.0, 10.35)
	add_child(host_root)
	var figure := _create_npc_figure(host_root, "market_customer")
	var robe_material := figure["body"].material_override as StandardMaterial3D
	if robe_material != null:
		robe_material.albedo_color = Color("#6d557b")
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.62, 0.18, 0.56)
	cap.mesh = cap_mesh
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color("#c39a5b")
	cap_material.roughness = 0.62
	cap.material_override = cap_material
	cap.position = Vector3(0.0, 2.1, 0.0)
	host_root.add_child(cap)
	var sash := MeshInstance3D.new()
	var sash_mesh := BoxMesh.new()
	sash_mesh.size = Vector3(0.72, 0.16, 0.12)
	sash.mesh = sash_mesh
	sash.material_override = cap_material
	sash.position = Vector3(0.0, 1.48, -0.29)
	host_root.add_child(sash)
	# Three reusable low-poly lots: soul gem, ritual implement and soul vessel.
	var lot_root := Node3D.new()
	lot_root.name = "AuctionLotDisplay"
	lot_root.position = Vector3(0.0, 1.18, 2.25)
	host_root.add_child(lot_root)
	var lot_parts: Array[MeshInstance3D] = []
	var lot_names := ["幽冥魂珠", "镇魂法器", "古战魂器"]
	var lot_colors := [Color("#75c9e6"), Color("#d7a66b"), Color("#a28acb")]
	for lot_index in range(3):
		var lot := MeshInstance3D.new()
		lot.name = "AuctionLot_%02d" % (lot_index + 1)
		if lot_index == 0:
			var gem := SphereMesh.new()
			gem.radius = 0.48
			gem.height = 0.96
			lot.mesh = gem
		elif lot_index == 1:
			var ritual := CylinderMesh.new()
			ritual.top_radius = 0.12
			ritual.bottom_radius = 0.34
			ritual.height = 0.95
			lot.mesh = ritual
		else:
			var vessel := CapsuleMesh.new()
			vessel.radius = 0.32
			vessel.height = 1.05
			lot.mesh = vessel
		var lot_material := StandardMaterial3D.new()
		lot_material.albedo_color = lot_colors[lot_index]
		lot_material.metallic = 0.32
		lot_material.roughness = 0.3
		lot_material.emission_enabled = true
		lot_material.emission = lot_colors[lot_index]
		lot_material.emission_energy_multiplier = 0.24
		lot.material_override = lot_material
		lot.position.y = 0.62
		lot.visible = lot_index == 0
		lot_root.add_child(lot)
		lot_parts.append(lot)
	var lot_label := Label3D.new()
	lot_label.name = "AuctionLotName"
	lot_label.text = lot_names[0]
	lot_label.position = Vector3(0.0, 1.45, 0.0)
	lot_label.font_size = 12
	lot_label.pixel_size = 0.009
	lot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lot_label.modulate = Color("#ead2a6")
	lot_label.outline_size = 4
	lot_label.outline_modulate = Color("#171d25")
	lot_root.add_child(lot_label)
	market_stage_actor = {
		"root": host_root,
		"body": figure["body"],
		"left_arm": figure["left_arm"],
		"right_arm": figure["right_arm"],
		"lot_parts": lot_parts,
		"lot_names": lot_names,
		"lot_label": lot_label,
		"phase": 1.7
	}


func _market_stall(center: Vector3, facing: float, stall_type: String) -> void:
	# Every stall faces the central aisle; type-specific displays remain decorative and non-interactive.
	_box("GhostMarketStallCounter", center + Vector3(facing * 0.85, 0.72, 0), Vector3(1.25, 1.05, 3.8), "palace", false)
	_box("GhostMarketStallStock", center + Vector3(-facing * 0.9, 1.05, 0), Vector3(1.7, 2.1, 3.8), "dark_stone", false)
	_box("GhostMarketStallAwning", center + Vector3(0, 3.0, 0), Vector3(4.8, 0.28, 4.8), "roof", false)
	for side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			_box("GhostMarketStallPost", center + Vector3(side * 2.0, 1.55, z_side * 2.0), Vector3(0.22, 3.0, 0.22), "gold", false)
	_box("GhostMarketStallSign", center + Vector3(facing * 2.15, 2.55, 0), Vector3(0.18, 0.9, 1.6), "gold", false)
	_label(stall_type, center + Vector3(facing * 2.28, 3.18, 0), 17, Color("#f0d5a4"))
	var merchant_profile := _market_merchant_profile(stall_type)
	_label(str(merchant_profile.get("name", "无名掌柜")), center + Vector3(facing * 2.28, 2.82, 0), 11, Color("#d8c5a8"))
	var sign_accent := Color("#83c7e4")
	match stall_type:
		"魂珠铺":
			sign_accent = Color("#83c7e4")
		"魂籍铺":
			sign_accent = Color("#d6bd8b")
		"药材铺":
			sign_accent = Color("#8dbb86")
		"法器铺":
			sign_accent = Color("#e0a96f")
		"魂器铺":
			sign_accent = Color("#9b9fc9")
		"悬赏交易":
			sign_accent = Color("#d27d68")
	# Paired low-cost emissive seals make each shop readable from the aisle without adding lights.
	_market_display_orb(center + Vector3(facing * 2.28, 2.55, -0.72), 0.11, sign_accent)
	_market_display_orb(center + Vector3(facing * 2.28, 2.55, 0.72), 0.11, sign_accent)
	var counter_front := center + Vector3(facing * 0.85, 1.26, 0)
	match stall_type:
		"魂珠铺":
			_market_display_orb(counter_front + Vector3(0, 0.24, -1.12), 0.25, Color("#83c7e4"))
			_market_display_orb(counter_front + Vector3(0, 0.24, 0.0), 0.29, Color("#b99bdc"))
			_market_display_orb(counter_front + Vector3(0, 0.24, 1.12), 0.22, Color("#e8c477"))
		"魂籍铺":
			for z_offset in [-0.92, 0.0, 0.92]:
				var scroll := _box("GhostMarketRegisterScroll", counter_front + Vector3(0, 0.16, z_offset), Vector3(0.52, 0.28, 0.72), "gold", false)
				scroll.rotation.y = deg_to_rad(12.0 * z_offset)
			_box("GhostMarketRegisterLedger", counter_front + Vector3(-facing * 0.16, 0.32, 0), Vector3(0.72, 0.12, 0.9), "road_edge", false)
		"药材铺":
			for z_offset in [-1.0, 0.0, 1.0]:
				_box("GhostMarketHerbBundle", counter_front + Vector3(-facing * 0.18, 0.2, z_offset), Vector3(0.42, 0.34, 0.64), "district", false)
			_market_display_orb(counter_front + Vector3(0, 0.2, 1.48), 0.16, Color("#8dbb86"))
		"法器铺":
			for z_offset in [-0.9, 0.0, 0.9]:
				var artifact := _box("GhostMarketRitualArtifact", counter_front + Vector3(-facing * 0.1, 0.34, z_offset), Vector3(0.22, 0.72, 0.22), "gold", false)
				artifact.rotation.x = deg_to_rad(18.0)
				_box("GhostMarketArtifactBase", counter_front + Vector3(0, 0.12, z_offset), Vector3(0.58, 0.18, 0.58), "dark_stone", false)
		"魂器铺":
			for z_offset in [-0.9, 0.0, 0.9]:
				_market_display_orb(counter_front + Vector3(0, 0.28, z_offset), 0.22, Color("#9b9fc9"))
				_box("GhostMarketSoulVessel", counter_front + Vector3(-facing * 0.2, 0.18, z_offset), Vector3(0.42, 0.3, 0.48), "palace", false)
		"悬赏交易":
			_box("GhostMarketBountyScroll", counter_front + Vector3(0, 0.2, -0.82), Vector3(0.58, 0.26, 0.8), "gold", false)
			_box("GhostMarketTradeToken", counter_front + Vector3(-facing * 0.16, 0.18, 0.55), Vector3(0.38, 0.28, 0.38), "road_edge", false)
			_market_display_orb(counter_front + Vector3(0, 0.26, 1.25), 0.18, Color("#d4a96d"))
	_market_stall_architecture(center, facing, stall_type, sign_accent)


func _market_stall_architecture(center: Vector3, facing: float, stall_type: String, accent: Color) -> void:
	# Small silhouette changes make the six shop families readable before their signs are legible.
	match stall_type:
		"魂珠铺":
			_market_display_orb(center + Vector3(0.0, 3.38, 0.0), 0.2, accent)
			for z_offset in [-1.45, 1.45]:
				_box("GhostMarketOrbShopEaveBrace", center + Vector3(facing * 1.95, 2.72, z_offset), Vector3(0.34, 0.22, 0.72), "gold", false)
		"魂籍铺":
			for level in [1.55, 2.05]:
				_box("GhostMarketArchiveShelf", center + Vector3(-facing * 1.78, level, 0.0), Vector3(0.42, 0.12, 3.25), "gold", false)
			for z_offset in [-1.15, 0.0, 1.15]:
				_box("GhostMarketArchiveSpine", center + Vector3(-facing * 1.76, 1.82, z_offset), Vector3(0.3, 0.48, 0.22), "road_edge", false)
		"药材铺":
			for z_offset in [-1.25, 0.0, 1.25]:
				_box("GhostMarketHerbHanger", center + Vector3(facing * 1.72, 2.42, z_offset), Vector3(0.1, 0.72, 0.1), "district", false)
				_market_display_orb(center + Vector3(facing * 1.72, 2.0, z_offset), 0.14, accent)
		"法器铺":
			for z_offset in [-1.65, 1.65]:
				_box("GhostMarketRitualCornerFinial", center + Vector3(facing * 1.82, 3.42, z_offset), Vector3(0.42, 0.42, 0.42), "gold", false)
				_market_display_orb(center + Vector3(facing * 1.82, 3.72, z_offset), 0.1, accent)
		"魂器铺":
			for z_offset in [-1.35, 1.35]:
				_box("GhostMarketVesselStand", center + Vector3(-facing * 1.68, 1.48, z_offset), Vector3(0.42, 0.82, 0.42), "palace", false)
				_market_display_orb(center + Vector3(-facing * 1.68, 1.98, z_offset), 0.16, accent)
		"悬赏交易":
			_box("GhostMarketBountyPennantBeam", center + Vector3(0.0, 3.35, 0.0), Vector3(3.5, 0.16, 0.16), "gold", false)
			for z_offset in [-1.2, 0.0, 1.2]:
				var pennant := _box("GhostMarketBountyPennant", center + Vector3(facing * 1.92, 2.95, z_offset), Vector3(0.08, 0.62, 0.48), "district", false)
				pennant.rotation.z = deg_to_rad(-8.0 if z_offset < 0.0 else 8.0)


func _market_notice_board(center: Vector3, board_title: String, accent: Color) -> void:
	# Framed boards remain outside the central trading aisle.
	_notice_board(center, board_title)
	for side in [-1.0, 1.0]:
		_box("GhostMarketNoticeFramePost", center + Vector3(side * 1.24, 2.25, 0.0), Vector3(0.16, 2.0, 0.34), "gold", false)
	_box("GhostMarketNoticeHeader", center + Vector3(0.0, 3.12, 0.0), Vector3(2.75, 0.2, 0.36), "roof_edge", false)
	_box("GhostMarketNoticeBase", center + Vector3(0.0, 0.22, 0.0), Vector3(2.7, 0.24, 0.62), "dark_stone", false)
	for index in range(3):
		var notice_strip := _box("GhostMarketNoticeSlip", center + Vector3(-0.62 + float(index) * 0.62, 2.18, -0.19), Vector3(0.38, 0.62, 0.06), "gold", false)
		notice_strip.rotation.z = deg_to_rad(-7.0 + float(index) * 7.0)
	_market_display_orb(center + Vector3(0.0, 3.42, -0.05), 0.12, accent)
	if board_title == "悬赏榜":
		var tier_colors := [Color("#8dbb86"), Color("#d6bd8b"), Color("#d27d68")]
		for index in range(3):
			var tier_x := -0.62 + float(index) * 0.62
			_box("GhostMarketBountyTierPlate", center + Vector3(tier_x, 1.72, -0.205), Vector3(0.46, 0.12, 0.08), "dark_stone", false)
			_market_display_orb(center + Vector3(tier_x, 2.62, -0.24), 0.1, tier_colors[index])
			_box("GhostMarketBountyTierMark", center + Vector3(tier_x, 2.35, -0.23), Vector3(0.28, 0.1, 0.08), "gold", false)


func _market_audience_bench(center: Vector3, facing: float) -> void:
	# Low-cost, non-colliding benches flank the auction dais.
	_box("GhostMarketAudienceSeat", center + Vector3(0.0, 0.72, 0.0), Vector3(1.25, 0.34, 4.0), "dark_stone", false)
	_box("GhostMarketAudienceBack", center + Vector3(-facing * 0.52, 1.18, 0.0), Vector3(0.22, 0.82, 4.0), "gold", false)
	for z_offset in [-1.55, 1.55]:
		_box("GhostMarketAudienceSupport", center + Vector3(0.0, 0.35, z_offset), Vector3(1.1, 0.7, 0.24), "stone", false)
	_box("GhostMarketAudienceFootRail", center + Vector3(facing * 0.58, 0.2, 0.0), Vector3(0.16, 0.16, 3.5), "roof_edge", false)


func _market_auction_steps(center: Vector3) -> void:
	# Stable step and rail IDs stay in layout data; this adapter only creates geometry.
	var auction_layout: Dictionary = WORLD_LAYOUT.get_market_auction_layout()
	for step in auction_layout["steps"]:
		_box("GhostMarketAuctionStep", center + step["offset"], step["size"], "road_edge", false)
	for rail in auction_layout["step_rails"]:
		_box("GhostMarketAuctionStepRailBase", center + rail["offset"], rail["base_size"], "dark_stone", false)
		_box("GhostMarketAuctionStepRailCap", center + rail["offset"] + rail["cap_offset"], rail["cap_size"], "gold", false)

func _market_auction_pedestal(center: Vector3, accent: Color) -> void:
	# Paired low-poly standards frame the dais without narrowing the walkable aisle.
	_box("GhostMarketAuctionPedestalBase", center + Vector3(0.0, 0.28, 0.0), Vector3(0.72, 0.56, 0.72), "dark_stone", false)
	_box("GhostMarketAuctionPedestalShaft", center + Vector3(0.0, 1.0, 0.0), Vector3(0.38, 1.0, 0.38), "gold", false)
	_box("GhostMarketAuctionPedestalCap", center + Vector3(0.0, 1.58, 0.0), Vector3(0.82, 0.2, 0.82), "roof_edge", false)
	_market_display_orb(center + Vector3(0.0, 1.92, 0.0), 0.18, accent)

func _market_wayfinding(center: Vector3) -> void:
	# Ground inlays guide visitors from the southern gate toward the auction.
	for index in range(5):
		var z_offset := -7.2 + float(index) * 2.8
		var marker := _box("GhostMarketWayfindingInlay", center + Vector3(0.0, 0.25, z_offset), Vector3(0.82, 0.07, 0.82), "gold", false)
		marker.rotation.y = deg_to_rad(45.0)
	for side in [-1.0, 1.0]:
		for z_offset in [-6.0, -2.0, 2.0]:
			_box("GhostMarketAisleEdgeStud", center + Vector3(side * 4.12, 0.27, z_offset), Vector3(0.16, 0.08, 0.48), "roof_edge", false)

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
	var center: Vector3 = WORLD_LAYOUT.get_city_config().get("imperial_palace_center", Vector3(0, 0, 72))
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
	if npc_hint_label == null or player == null:
		return
	patrol_incident_focus_id = ""
	if player.global_position.distance_to(Vector3(51.0, 0.0, 36.5)) <= 7.0:
		npc_focus_agent = {}
		npc_hint_label.text = "E 打开判官司工作台 · 案卷复核与庭审"
		return
	var nearest_incident_distance := 9.0
	var nearest_incident: Dictionary = {}
	for incident in patrol_incident_records:
		var incident_state := str(incident.get("state", ""))
		if incident_state not in ["assigned", "investigating"]:
			continue
		var incident_position: Vector3 = incident.get("target_position", Vector3.ZERO)
		var distance := player.global_position.distance_to(incident_position)
		if distance < nearest_incident_distance:
			nearest_incident_distance = distance
			nearest_incident = incident
	if not nearest_incident.is_empty():
		patrol_incident_focus_id = str(nearest_incident.get("incident_id", ""))
		npc_focus_agent = {}
		if str(nearest_incident.get("state", "")) == "investigating":
			var remaining_clues := 0
			for clue_node in nearest_incident.get("evidence_nodes", []):
				if is_instance_valid(clue_node) and clue_node.visible:
					remaining_clues += 1
			var witness_root: Node3D = nearest_incident.get("witness_root")
			var witness_available := witness_root != null and is_instance_valid(witness_root) and int(nearest_incident.get("witness_question_stage", 0)) < 2
			var investigation_hint := "物证 %d 处 · 证人可询问" % remaining_clues if witness_available else "尚有物证 %d 处" % remaining_clues
			if remaining_clues <= 0 and not witness_available:
				investigation_hint = "调查线索已收集完毕"
			npc_hint_label.text = "E 调查附近目标 · %s（%s）" % [
				str(nearest_incident.get("title", "巡防事件")),
				investigation_hint
			]
		else:
			npc_hint_label.text = "巡城卫正在赶赴现场 · %s" % str(nearest_incident.get("title", "巡防事件"))
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


func _interact_with_patrol_incident(incident_id: String) -> void:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		npc_detail_label.text = "巡防事件记录已更新，请稍后再查看。"
		return
	var record: Dictionary = patrol_incident_records[record_index]
	var can_supplement_closed_case := str(record.get("case_workflow_state", "")) == "returned_for_supplement"
	if str(record.get("state", "")) != "investigating" and not can_supplement_closed_case:
		npc_detail_label.text = "%s：巡城卫尚未全部到场，或案件当前不接受现场调查。" % str(record.get("title", "巡防事件"))
		return
	if player == null:
		return
	var evidence_nodes: Array = record.get("evidence_nodes", [])
	var witness_root: Node3D = record.get("witness_root")
	var witness_stage := int(record.get("witness_question_stage", 0))
	var witness_in_range := witness_root != null and is_instance_valid(witness_root) and player.global_position.distance_to(witness_root.global_position) <= 3.8
	var has_clues: Array = record.get("player_clue_tags", [])
	var prioritize_witness := witness_in_range and (witness_stage == 0 or (witness_stage == 1 and not has_clues.is_empty()))
	var nearest_evidence: Node3D
	var nearest_evidence_distance := 3.2
	for clue_node in evidence_nodes:
		if prioritize_witness:
			break
		if not is_instance_valid(clue_node) or not clue_node.visible:
			continue
		var clue_distance := player.global_position.distance_to(clue_node.global_position)
		if clue_distance < nearest_evidence_distance:
			nearest_evidence_distance = clue_distance
			nearest_evidence = clue_node
	if nearest_evidence != null:
		var clue_id := str(nearest_evidence.get_meta("clue_id", ""))
		var action_ids: Array = record.get("player_action_ids", [])
		if clue_id == "" or action_ids.has(clue_id):
			npc_detail_label.text = "这处痕迹已经检查过了。"
			return
		action_ids.append(clue_id)
		record["player_action_ids"] = action_ids
		record["player_evidence_count"] = int(record.get("player_evidence_count", 0)) + 1
		var clue_tags: Array = record.get("player_clue_tags", [])
		var clue_tag := str(nearest_evidence.get_meta("clue_tag", ""))
		if clue_tag != "" and not clue_tags.has(clue_tag):
			clue_tags.append(clue_tag)
		record["player_clue_tags"] = clue_tags
		nearest_evidence.visible = false
		var evidence_log: Array = record.get("player_contribution_log", [])
		var clue_label := str(nearest_evidence.get_meta("clue_label", "现场物证"))
		evidence_log.append({"action_id": clue_id, "label": clue_label, "at": npc_simulation_time})
		record["player_contribution_log"] = evidence_log
		_append_incident_timeline_entry(record, "evidence", clue_label, "player")
		if can_supplement_closed_case:
			_append_incident_timeline_entry(record, "case_supplement", "补充卷宗物证：" + clue_label, "patrol_office")
		patrol_incident_records[record_index] = record
		npc_detail_label.text = "现场物证已收录 · %s\n%s\n玩家已收集物证：%d 件" % [
			str(record.get("title", "巡防事件")),
			str(nearest_evidence.get_meta("clue_label", "现场物证")),
			int(record.get("player_evidence_count", 0))
		]
		print("[FengduPatrol] player collected clue %s for %s" % [clue_id, incident_id])
		return
	if witness_root != null and is_instance_valid(witness_root):
		var witness_distance := player.global_position.distance_to(witness_root.global_position)
		var question_stage := int(record.get("witness_question_stage", 0))
		if witness_distance <= 3.8 and question_stage == 0:
			record["witness_question_stage"] = 1
			record["witness_questioned"] = true
			record["player_witness_count"] = int(record.get("player_witness_count", 0)) + 1
			var testimony_tag := "witness_shadow" if str(record.get("type", "")) == "suspicious_activity" else ("witness_dispute" if str(record.get("type", "")) == "crowd_disorder" else "witness_violence")
			record["witness_testimony_tag"] = testimony_tag
			record["witness_testimony_at"] = npc_simulation_time
			var witness_id := "question_witness_first"
			var witness_actions: Array = record.get("player_action_ids", [])
			witness_actions.append(witness_id)
			record["player_action_ids"] = witness_actions
			var witness_name := str(record.get("witness_name", "现场证人"))
			var witness_log: Array = record.get("player_contribution_log", [])
			witness_log.append({"action_id": witness_id, "label": "首次询问：" + witness_name, "at": npc_simulation_time})
			record["player_contribution_log"] = witness_log
			_append_incident_timeline_entry(record, "testimony", "首次证词：" + witness_name, "witness")
			if can_supplement_closed_case:
				_append_incident_timeline_entry(record, "case_supplement", "补充卷宗证人陈述", "patrol_office")
			patrol_incident_records[record_index] = record
			npc_detail_label.text = "%s：事发时我看见一道黑影从巷口经过，随后听到争执声。\n\n先记录这份证词。找到物证后，可以回来追问细节。" % witness_name
			print("[FengduPatrol] player recorded first testimony for %s" % incident_id)
			return
		if witness_distance <= 3.8 and question_stage == 1:
			var clue_tags: Array = record.get("player_clue_tags", [])
			if clue_tags.is_empty():
				npc_detail_label.text = "证人：你先找找现场痕迹，再来问我。我不想凭空猜测。"
				return
			var conflict_found := clue_tags.has("broken_artifact") or (clue_tags.has("spirit_residue") and str(record.get("witness_testimony_tag", "")) == "witness_shadow")
			record["witness_question_stage"] = 2
			record["witness_revised"] = conflict_found
			var revised_tag := "witness_revised_conflict" if conflict_found else "witness_confirmed"
			record["witness_revised_testimony_tag"] = revised_tag
			record["witness_revised_testimony_at"] = npc_simulation_time
			var followup_id := "question_witness_followup"
			var followup_actions: Array = record.get("player_action_ids", [])
			followup_actions.append(followup_id)
			record["player_action_ids"] = followup_actions
			var followup_label := "追问后证词出现矛盾" if conflict_found else "追问后证词得到部分印证"
			var followup_log: Array = record.get("player_contribution_log", [])
			followup_log.append({"action_id": followup_id, "label": followup_label, "at": npc_simulation_time})
			record["player_contribution_log"] = followup_log
			_append_incident_timeline_entry(record, "testimony_followup", followup_label, "witness")
			patrol_incident_records[record_index] = record
			if conflict_found:
				npc_detail_label.text = "%s：你找到的物证……我想起来了，我当时没有看清黑影。那件魂器碎片是争执之后才出现的。\n\n前后说法存在矛盾，已标记为待复核证词。" % str(record.get("witness_name", "现场证人"))
			else:
				npc_detail_label.text = "%s：我确认当时确实有人经过巷口，但无法看清对方身份。\n\n补充证词已记入案件时间线。" % str(record.get("witness_name", "现场证人"))
			return
	var remaining_evidence := 0
	for clue_node in evidence_nodes:
		if is_instance_valid(clue_node) and clue_node.visible:
			remaining_evidence += 1
	if remaining_evidence > 0:
		npc_detail_label.text = "请走近地面发光的物证标记（3.2 米内）再按 E 调查。"
	elif witness_root != null and is_instance_valid(witness_root) and int(record.get("witness_question_stage", 0)) < 2:
		npc_detail_label.text = "请走近现场证人（3.8 米内）再按 E 询问或追问。"
	else:
		npc_detail_label.text = "现场可调查的物证和证人都已完成记录，等待巡城司汇总。"


func _record_npc_activity_sample(agent: Dictionary, actor_root: Node3D) -> void:
	# Sampling is independent of visual LOD and schedule visibility so hidden/resting
	# actors do not disappear from the event-time reconstruction.
	var last_sample := float(agent.get("activity_history_last_sample_at", -999.0))
	if npc_simulation_time - last_sample < 2.5:
		return
	var history: Array = agent.get("activity_history", [])
	history.append({
		"at": npc_simulation_time,
		"position": actor_root.global_position,
		"activity": str(agent.get("activity", "")),
		"behavior_state": str(agent.get("state", "idle")),
		"visible": actor_root.visible
	})
	while not history.is_empty() and npc_simulation_time - float(history[0].get("at", npc_simulation_time)) > 45.0:
		history.pop_front()
	while history.size() > 24:
		history.pop_front()
	agent["activity_history"] = history
	agent["activity_history_last_sample_at"] = npc_simulation_time


func _capture_incident_nearby_activity(target_position: Vector3) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	var history_start := maxf(0.0, npc_simulation_time - 45.0)
	for agent in npc_agents:
		var role := str(agent.get("role", ""))
		if role in ["patrol_guard", "gate_guard"]:
			continue
		var actor_root: Node3D = agent.get("root")
		if actor_root == null or not is_instance_valid(actor_root):
			continue
		var current_position: Vector3 = actor_root.global_position
		var current_distance := current_position.distance_to(target_position)
		var trail: Array[Dictionary] = []
		var closest_distance := current_distance
		for sample in agent.get("activity_history", []):
			var sample_at := float(sample.get("at", -1.0))
			if sample_at < history_start or sample_at > npc_simulation_time:
				continue
			var sample_position: Vector3 = sample.get("position", current_position)
			var distance_to_incident := sample_position.distance_to(target_position)
			if distance_to_incident > 40.0:
				continue
			closest_distance = minf(closest_distance, distance_to_incident)
			trail.append({
				"at": sample_at,
				"position": sample_position,
				"distance_to_incident": distance_to_incident,
				"activity": str(sample.get("activity", "")),
				"behavior_state": str(sample.get("behavior_state", "idle")),
				"visible": bool(sample.get("visible", true))
			})
		if current_distance > 32.0 and trail.is_empty():
			continue
		trail.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("at", 0.0)) < float(b.get("at", 0.0))
		)
		snapshots.append({
			"actor_id": str(agent.get("npc_id", "")),
			"display_name": str(agent.get("display_name", "无名坊民")),
			"role": role,
			"district": str(agent.get("district", "")),
			"position": current_position,
			"distance_at_report": current_distance,
			"closest_distance_in_history": closest_distance,
			"activity_at_report": str(agent.get("activity", "")),
			"behavior_state_at_report": str(agent.get("state", "idle")),
			"visible_at_report": actor_root.visible,
			"activity_trail": trail,
			"trail_sample_count": trail.size(),
			"lead_status": "unverified"
		})
	snapshots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("closest_distance_in_history", 999.0)) < float(b.get("closest_distance_in_history", 999.0))
	)
	if snapshots.size() > 8:
		snapshots.resize(8)
	return snapshots


func _assess_incident_activity_leads(record: Dictionary) -> Array[Dictionary]:
	var assessments: Array[Dictionary] = []
	var incident_at := float(record.get("created_at", 0.0))
	var clue_tags: Array = record.get("player_clue_tags", [])
	var testimony_tag := str(record.get("witness_testimony_tag", ""))
	var testimony_at := float(record.get("witness_testimony_at", -1.0))
	for raw_lead in record.get("nearby_actor_snapshots", []):
		var lead: Dictionary = raw_lead.duplicate(true)
		var trail: Array = lead.get("activity_trail", [])
		var closest_distance := float(lead.get("closest_distance_in_history", 999.0))
		var incident_window_samples: Array = []
		for sample in trail:
			var sample_at := float(sample.get("at", -1.0))
			if sample_at >= incident_at - 15.0 and sample_at <= incident_at + 1.0:
				incident_window_samples.append(sample)
		var direction_code := "insufficient_samples"
		var direction_label := "轨迹采样不足，无法判断移动方向"
		if incident_window_samples.size() >= 2:
			var first_sample: Dictionary = incident_window_samples[0]
			var last_sample: Dictionary = incident_window_samples[incident_window_samples.size() - 1]
			var first_distance := float(first_sample.get("distance_to_incident", 999.0))
			var last_distance := float(last_sample.get("distance_to_incident", 999.0))
			if last_distance < first_distance - 1.0:
				direction_code = "approaching_scene"
				direction_label = "事发前轨迹呈接近案发点趋势"
			elif last_distance > first_distance + 1.0:
				direction_code = "leaving_scene"
				direction_label = "事发前轨迹呈远离案发点趋势"
			else:
				direction_code = "passing_or_stationary"
				direction_label = "事发前轨迹未显示明显接近或远离趋势"
		var track_match := false
		if clue_tags.has("movement_trace") and not incident_window_samples.is_empty():
			for sample in incident_window_samples:
				if float(sample.get("distance_to_incident", 999.0)) <= 8.0:
					track_match = true
					break
		var testimony_relation := "not_comparable"
		var testimony_note := "尚无可用于交叉核验的证词时间信息"
		if testimony_at >= 0.0 and not incident_window_samples.is_empty():
			if testimony_tag == "witness_shadow" and track_match:
				testimony_relation = "spatial_temporal_overlap"
				testimony_note = "黑影证词对应的事发时间窗内存在接近现场的人员轨迹，但不能据此确认身份"
			elif testimony_tag in ["witness_dispute", "witness_violence"]:
				testimony_relation = "scene_activity_only"
				testimony_note = "证词描述争执或冲突；现有轨迹只能说明人员位置，不能证明其参与冲突"
			else:
				testimony_relation = "no_match_found"
				testimony_note = "当前轨迹未形成与证词相符的空间时间关联"
		var lead_status := "unverified"
		var lead_status_label := "待核查"
		if track_match and testimony_relation == "spatial_temporal_overlap":
			lead_status = "partial_match"
			lead_status_label = "时空线索部分吻合"
		elif track_match:
			lead_status = "track_near_scene"
			lead_status_label = "轨迹接近现场，尚待核实"
		elif closest_distance > 20.0 and float(lead.get("distance_at_report", 999.0)) > 20.0:
			lead_status = "low_relevance"
			lead_status_label = "现有轨迹关联较弱"
		lead["movement_direction_code"] = direction_code
		lead["movement_direction_label"] = direction_label
		lead["incident_window_sample_count"] = incident_window_samples.size()
		lead["movement_trace_match"] = track_match
		lead["testimony_relation"] = testimony_relation
		lead["testimony_relation_note"] = testimony_note
		lead["lead_status"] = lead_status
		lead["lead_status_label"] = lead_status_label
		lead["assessment_is_not_a_verdict"] = true
		assessments.append(lead)
	return assessments


func submit_patrol_case_to_judge_bureau(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	var workflow_state := str(record.get("case_workflow_state", "unsubmitted"))
	if workflow_state in ["transferred_to_judge_bureau", "under_judicial_review", "hearing_pending"]:
		return {"ok": false, "reason": "already_submitted", "case_workflow_state": workflow_state}
	var patrol_state := str(record.get("state", ""))
	if patrol_state not in ["resolved", "closed"]:
		return {"ok": false, "reason": "patrol_investigation_not_complete", "patrol_state": patrol_state}
	var evidence_count := int(record.get("player_evidence_count", 0))
	var witness_count := int(record.get("player_witness_count", 0))
	if bool(record.get("autonomous_processing", false)):
		evidence_count = maxi(evidence_count, int(record.get("patrol_evidence_count", 0)))
		witness_count = maxi(witness_count, int(record.get("patrol_witness_count", 0)))
	var enough_material := evidence_count >= 2 or (evidence_count >= 1 and witness_count >= 1)
	var required_material: Array[String] = []
	if evidence_count < 1:
		required_material.append("至少收集一件现场物证")
	if witness_count < 1:
		required_material.append("至少取得一份证人陈述")
	if evidence_count < 2 and witness_count < 1:
		required_material.append("建议补充第二件独立物证")
	if not enough_material:
		record["case_workflow_state"] = "returned_for_supplement"
		record["case_returned_at"] = npc_simulation_time
		record["case_return_reason"] = "卷宗材料不足，暂不具备移交条件"
		record["case_required_material"] = required_material
		_append_incident_timeline_entry(record, "case_returned", "卷宗退回巡城司：材料不足，需补充调查", "judge_bureau")
		patrol_incident_records[record_index] = record
		return {
			"ok": false,
			"reason": "insufficient_case_material",
			"case_workflow_state": "returned_for_supplement",
			"required_material": required_material
		}
	var conflict := bool(record.get("witness_revised", false))
	var transfer_id := incident_id + ".transfer"
	var lead_assessments: Array[Dictionary] = _assess_incident_activity_leads(record)
	var case_parties: Array[Dictionary] = []
	if not bool(record.get("autonomous_processing", false)):
		for lead in lead_assessments:
			var lead_status := str(lead.get("lead_status", "unverified"))
			if lead_status not in ["partial_match", "track_near_scene"]:
				continue
			var actor_id := str(lead.get("actor_id", ""))
			if actor_id.is_empty():
				continue
			case_parties.append({
				"party_id": actor_id,
				"actor_id": actor_id,
				"display_name": str(lead.get("display_name", "待核查人员")),
				"lead_status": lead_status,
				"suspect_status": "unverified",
				"procedural_status": "notice_pending",
				"defense_status": "not_heard",
				"defense_statement": "",
				"response_at": -1.0
			})
	var submission := {
		"transfer_id": transfer_id,
		"incident_id": incident_id,
		"source_office": "patrol_office",
		"target_office": "judge_bureau",
		"submitted_at": npc_simulation_time,
		"evidence_tags": record.get("player_clue_tags", []).duplicate(),
		"evidence_count": evidence_count,
		"witness_count": witness_count,
		"testimony_tag": str(record.get("witness_testimony_tag", "")),
		"testimony_conflict": conflict,
		"deduction_code": str(record.get("deduction_code", "inconclusive")),
		"deduction_label": str(record.get("deduction_label", "尚无推断")),
		"lead_assessments": lead_assessments,
		"case_parties": case_parties,
		"requires_conflict_review": conflict,
		"judicial_conclusion": "not_determined"
	}
	record["case_submission"] = submission
	record["case_workflow_state"] = "transferred_to_judge_bureau"
	record["judge_review_state"] = "pending"
	record["case_return_reason"] = ""
	record["case_required_material"] = []
	_append_incident_timeline_entry(record, "case_transferred", "巡城司已将案件卷宗移交判官司", "patrol_office")
	patrol_incident_records[record_index] = record
	return {
		"ok": true,
		"transfer_id": transfer_id,
		"case_workflow_state": "transferred_to_judge_bureau",
		"judge_review_state": "pending",
		"requires_conflict_review": conflict,
		"judicial_conclusion": "not_determined"
	}


func begin_judge_bureau_case_review(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "transferred_to_judge_bureau":
		return {"ok": false, "reason": "case_not_transferred"}
	if str(record.get("judge_review_state", "")) != "pending":
		return {"ok": false, "reason": "review_not_pending"}
	record["case_workflow_state"] = "under_judicial_review"
	record["judge_review_state"] = "reviewing"
	record["judicial_review"] = {
		"evidence_assessments": {},
		"testimony_assessment": {},
		"review_complete": false,
		"hearing_eligible": false,
		"started_at": npc_simulation_time,
		"completed_at": -1.0
	}
	_append_incident_timeline_entry(record, "judge_review_started", "判官司已受理卷宗并开始复核", "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "case_workflow_state": "under_judicial_review", "judge_review_state": "reviewing"}


func record_judicial_evidence_assessment(incident_id: String, evidence_tag: String, assessment: String, reason: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "under_judicial_review":
		return {"ok": false, "reason": "case_not_under_review"}
	if assessment not in ["accepted", "needs_verification", "rejected"]:
		return {"ok": false, "reason": "invalid_evidence_assessment"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "assessment_reason_required"}
	var submitted_tags: Array = record.get("case_submission", {}).get("evidence_tags", [])
	if not submitted_tags.has(evidence_tag):
		return {"ok": false, "reason": "evidence_tag_not_in_submission"}
	var review: Dictionary = record.get("judicial_review", {}).duplicate(true)
	var assessments: Dictionary = review.get("evidence_assessments", {})
	assessments[evidence_tag] = {
		"assessment": assessment,
		"reason": reason.strip_edges(),
		"reviewed_at": npc_simulation_time
	}
	review["evidence_assessments"] = assessments
	review["review_complete"] = false
	review["hearing_eligible"] = false
	review["completed_at"] = -1.0
	record["judicial_review"] = review
	record["judge_review_state"] = "reviewing"
	_append_incident_timeline_entry(record, "evidence_assessed", "判官司复核物证（%s）：%s" % [evidence_tag, assessment], "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "evidence_tag": evidence_tag, "assessment": assessment}


func record_judicial_testimony_assessment(incident_id: String, assessment: String, reason: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "under_judicial_review":
		return {"ok": false, "reason": "case_not_under_review"}
	if str(record.get("witness_testimony_tag", "")).is_empty():
		return {"ok": false, "reason": "no_testimony_in_submission"}
	if assessment not in ["credible", "disputed", "insufficient"]:
		return {"ok": false, "reason": "invalid_testimony_assessment"}
	if bool(record.get("witness_revised", false)) and assessment == "credible":
		return {"ok": false, "reason": "conflicting_testimony_cannot_be_marked_credible"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "assessment_reason_required"}
	var review: Dictionary = record.get("judicial_review", {}).duplicate(true)
	review["testimony_assessment"] = {
		"assessment": assessment,
		"reason": reason.strip_edges(),
		"reviewed_at": npc_simulation_time
	}
	review["review_complete"] = false
	review["hearing_eligible"] = false
	review["completed_at"] = -1.0
	record["judicial_review"] = review
	record["judge_review_state"] = "reviewing"
	_append_incident_timeline_entry(record, "testimony_assessed", "判官司复核证词：%s" % assessment, "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "testimony_assessment": assessment}


func complete_judge_bureau_review(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "under_judicial_review":
		return {"ok": false, "reason": "case_not_under_review"}
	var review: Dictionary = record.get("judicial_review", {}).duplicate(true)
	var submitted_tags: Array = record.get("case_submission", {}).get("evidence_tags", [])
	var assessments: Dictionary = review.get("evidence_assessments", {})
	var missing_tags: Array[String] = []
	var accepted_count := 0
	var unresolved_count := 0
	for tag_value in submitted_tags:
		var tag := str(tag_value)
		if not assessments.has(tag):
			missing_tags.append(tag)
			continue
		var assessment := str(assessments[tag].get("assessment", ""))
		if assessment == "accepted":
			accepted_count += 1
		elif assessment == "needs_verification":
			unresolved_count += 1
	var testimony_tag := str(record.get("witness_testimony_tag", ""))
	var testimony_review: Dictionary = review.get("testimony_assessment", {})
	var testimony_missing := not testimony_tag.is_empty() and testimony_review.is_empty()
	if not missing_tags.is_empty() or testimony_missing:
		return {
			"ok": false,
			"reason": "review_items_incomplete",
			"missing_evidence_tags": missing_tags,
			"testimony_assessment_required": testimony_missing
		}
	var testimony_status := str(testimony_review.get("assessment", "not_applicable"))
	var autonomous_evidence_override := bool(record.get("autonomous_processing", false)) and accepted_count >= 2 and unresolved_count == 0
	var hearing_eligible := accepted_count > 0 and unresolved_count == 0 and (testimony_status not in ["disputed", "insufficient"] or autonomous_evidence_override)
	review["review_complete"] = true
	review["hearing_eligible"] = hearing_eligible
	review["completed_at"] = npc_simulation_time
	review["accepted_evidence_count"] = accepted_count
	review["unresolved_evidence_count"] = unresolved_count
	review["testimony_status"] = testimony_status
	record["judicial_review"] = review
	record["judge_review_state"] = "review_complete"
	_append_incident_timeline_entry(record, "judge_review_completed", "判官司完成证据与证词复核；%s" % ("可进入候审" if hearing_eligible else "需补充或进一步核验"), "judge_bureau")
	patrol_incident_records[record_index] = record
	return {
		"ok": true,
		"review_complete": true,
		"hearing_eligible": hearing_eligible,
		"accepted_evidence_count": accepted_count,
		"unresolved_evidence_count": unresolved_count,
		"testimony_status": testimony_status,
		"judicial_conclusion": "not_determined"
	}


func record_judge_bureau_case_disposition(incident_id: String, disposition: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "under_judicial_review":
		return {"ok": false, "reason": "case_not_under_review"}
	if disposition not in ["request_supplement", "accept_for_hearing"]:
		return {"ok": false, "reason": "invalid_disposition"}
	if disposition == "accept_for_hearing":
		var judicial_review: Dictionary = record.get("judicial_review", {})
		if not bool(judicial_review.get("review_complete", false)):
			return {"ok": false, "reason": "judicial_review_not_completed"}
		if not bool(judicial_review.get("hearing_eligible", false)):
			return {"ok": false, "reason": "evidence_or_testimony_requires_supplement"}
	if disposition == "request_supplement":
		record["case_workflow_state"] = "returned_for_supplement"
		record["judge_review_state"] = "supplement_requested"
		record["case_returned_at"] = npc_simulation_time
		record["case_return_reason"] = "判官司要求补充调查材料"
		_append_incident_timeline_entry(record, "supplement_requested", "判官司退回补充调查，尚未作出实体判决", "judge_bureau")
	else:
		record["case_workflow_state"] = "hearing_pending"
		record["judge_review_state"] = "accepted_for_hearing"
		record["hearing_record"] = {
			"state": "pending",
			"opened_at": -1.0,
			"closed_at": -1.0,
			"presented_evidence_tags": [],
			"proceedings": [],
			"hearing_note": ""
		}
		record["case_return_reason"] = ""
		_append_incident_timeline_entry(record, "hearing_accepted", "卷宗材料已通过形式复核，进入候审阶段", "judge_bureau")
	var submission: Dictionary = record.get("case_submission", {})
	submission["last_disposition"] = disposition
	submission["disposition_at"] = npc_simulation_time
	record["case_submission"] = submission
	patrol_incident_records[record_index] = record
	return {
		"ok": true,
		"case_workflow_state": str(record.get("case_workflow_state", "")),
		"judge_review_state": str(record.get("judge_review_state", "")),
		"judicial_conclusion": "not_determined"
	}


func update_case_party_procedural_status(incident_id: String, party_id: String, status: String, reason: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) not in ["hearing_pending", "hearing_in_progress"]:
		return {"ok": false, "reason": "case_not_in_hearing_phase"}
	if status not in ["notice_served", "appeared", "unavailable", "declined_to_respond"]:
		return {"ok": false, "reason": "invalid_party_procedural_status"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "procedural_reason_required"}
	var submission: Dictionary = record.get("case_submission", {}).duplicate(true)
	var parties: Array = submission.get("case_parties", []).duplicate(true)
	var found := false
	for index in range(parties.size()):
		var party: Dictionary = parties[index]
		if str(party.get("party_id", "")) != party_id:
			continue
		var current_status := str(party.get("procedural_status", "notice_pending"))
		var allowed_next_statuses: Array = []
		if current_status == "notice_pending":
			allowed_next_statuses = ["notice_served", "unavailable"]
		elif current_status == "notice_served":
			allowed_next_statuses = ["appeared", "unavailable", "declined_to_respond"]
		if not allowed_next_statuses.has(status):
			return {"ok": false, "reason": "invalid_procedural_status_transition", "current_status": current_status}
		party["procedural_status"] = status
		party["procedural_reason"] = reason.strip_edges()
		party["procedural_updated_at"] = npc_simulation_time
		parties[index] = party
		found = true
		break
	if not found:
		return {"ok": false, "reason": "case_party_not_found"}
	submission["case_parties"] = parties
	record["case_submission"] = submission
	_append_incident_timeline_entry(record, "party_procedure", "涉案人员程序状态更新：%s" % status, "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "party_id": party_id, "procedural_status": status}


func record_case_party_defense_statement(incident_id: String, party_id: String, statement: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) not in ["hearing_pending", "hearing_in_progress"]:
		return {"ok": false, "reason": "case_not_in_hearing_phase"}
	if statement.strip_edges().is_empty():
		return {"ok": false, "reason": "defense_statement_required"}
	var submission: Dictionary = record.get("case_submission", {}).duplicate(true)
	var parties: Array = submission.get("case_parties", []).duplicate(true)
	var found := false
	for index in range(parties.size()):
		var party: Dictionary = parties[index]
		if str(party.get("party_id", "")) != party_id:
			continue
		if str(party.get("procedural_status", "notice_pending")) != "appeared":
			return {"ok": false, "reason": "party_must_appear_before_defense"}
		party["defense_status"] = "statement_recorded"
		party["defense_statement"] = statement.strip_edges()
		party["response_at"] = npc_simulation_time
		parties[index] = party
		found = true
		break
	if not found:
		return {"ok": false, "reason": "case_party_not_found"}
	submission["case_parties"] = parties
	record["case_submission"] = submission
	_append_incident_timeline_entry(record, "defense_statement", "记录涉案人员申辩陈述", party_id)
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	var proceedings: Array = hearing.get("proceedings", []).duplicate(true)
	proceedings.append({
		"entry_type": "defense_statement",
		"party_id": party_id,
		"statement": statement.strip_edges(),
		"at": npc_simulation_time
	})
	hearing["proceedings"] = proceedings
	record["hearing_record"] = hearing
	patrol_incident_records[record_index] = record
	return {"ok": true, "party_id": party_id, "defense_status": "statement_recorded"}


func begin_case_hearing(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_pending":
		return {"ok": false, "reason": "case_not_hearing_pending"}
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	hearing["state"] = "in_progress"
	hearing["opened_at"] = npc_simulation_time
	record["hearing_record"] = hearing
	record["case_workflow_state"] = "hearing_in_progress"
	record["judge_review_state"] = "hearing_in_progress"
	_append_incident_timeline_entry(record, "hearing_started", "判官司正式开庭，进入举证与申辩程序", "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "case_workflow_state": "hearing_in_progress"}


func present_case_evidence_at_hearing(incident_id: String, evidence_tag: String, statement: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_in_progress":
		return {"ok": false, "reason": "hearing_not_in_progress"}
	if statement.strip_edges().is_empty():
		return {"ok": false, "reason": "presentation_statement_required"}
	var review: Dictionary = record.get("judicial_review", {})
	var assessments: Dictionary = review.get("evidence_assessments", {})
	if not assessments.has(evidence_tag):
		return {"ok": false, "reason": "evidence_not_reviewed"}
	if str(assessments[evidence_tag].get("assessment", "")) != "accepted":
		return {"ok": false, "reason": "evidence_not_accepted"}
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	var presented: Array = hearing.get("presented_evidence_tags", []).duplicate()
	if presented.has(evidence_tag):
		return {"ok": false, "reason": "evidence_already_presented"}
	presented.append(evidence_tag)
	hearing["presented_evidence_tags"] = presented
	var proceedings: Array = hearing.get("proceedings", []).duplicate(true)
	proceedings.append({
		"entry_type": "evidence_presentation",
		"evidence_tag": evidence_tag,
		"statement": statement.strip_edges(),
		"at": npc_simulation_time
	})
	hearing["proceedings"] = proceedings
	record["hearing_record"] = hearing
	_append_incident_timeline_entry(record, "evidence_presented", "庭审出示物证：" + evidence_tag, "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "presented_evidence_tags": presented}


func present_case_testimony_at_hearing(incident_id: String, statement: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_in_progress":
		return {"ok": false, "reason": "hearing_not_in_progress"}
	if str(record.get("witness_testimony_tag", "")).is_empty():
		return {"ok": false, "reason": "no_witness_testimony"}
	if statement.strip_edges().is_empty():
		return {"ok": false, "reason": "testimony_presentation_required"}
	var testimony_review: Dictionary = record.get("judicial_review", {}).get("testimony_assessment", {})
	if str(testimony_review.get("assessment", "")) != "credible":
		return {"ok": false, "reason": "testimony_not_assessed_as_credible"}
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	if bool(hearing.get("testimony_presented", false)):
		return {"ok": false, "reason": "testimony_already_presented"}
	hearing["testimony_presented"] = true
	hearing["testimony_presentation"] = {
		"testimony_tag": str(record.get("witness_testimony_tag", "")),
		"statement": statement.strip_edges(),
		"presented_at": npc_simulation_time
	}
	var proceedings: Array = hearing.get("proceedings", []).duplicate(true)
	proceedings.append({
		"entry_type": "testimony_presentation",
		"testimony_tag": str(record.get("witness_testimony_tag", "")),
		"statement": statement.strip_edges(),
		"at": npc_simulation_time
	})
	hearing["proceedings"] = proceedings
	record["hearing_record"] = hearing
	_append_incident_timeline_entry(record, "testimony_presented", "庭审出示证人陈述", "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "testimony_presented": true}


func record_case_evidence_challenge_at_hearing(incident_id: String, party_id: String, evidence_tag: String, challenge: String, reason: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_in_progress":
		return {"ok": false, "reason": "hearing_not_in_progress"}
	if challenge not in ["authenticity_disputed", "chain_of_custody_disputed", "interpretation_disputed", "relevance_disputed"]:
		return {"ok": false, "reason": "invalid_evidence_challenge"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "challenge_reason_required"}
	var party_found := false
	for party_value in record.get("case_submission", {}).get("case_parties", []):
		if str(party_value.get("party_id", "")) == party_id:
			party_found = true
			if str(party_value.get("procedural_status", "notice_pending")) != "appeared":
				return {"ok": false, "reason": "party_must_appear_to_challenge"}
			break
	if not party_found:
		return {"ok": false, "reason": "case_party_not_found"}
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	if not hearing.get("presented_evidence_tags", []).has(evidence_tag):
		return {"ok": false, "reason": "evidence_not_presented"}
	var proceedings: Array = hearing.get("proceedings", []).duplicate(true)
	proceedings.append({
		"entry_type": "evidence_challenge",
		"party_id": party_id,
		"evidence_tag": evidence_tag,
		"challenge": challenge,
		"reason": reason.strip_edges(),
		"at": npc_simulation_time
	})
	hearing["proceedings"] = proceedings
	record["hearing_record"] = hearing
	_append_incident_timeline_entry(record, "evidence_challenged", "庭审中对物证提出质证", party_id)
	patrol_incident_records[record_index] = record
	return {"ok": true, "evidence_tag": evidence_tag, "challenge_recorded": true, "evidence_assessment_unchanged": true}


func record_case_testimony_challenge_at_hearing(incident_id: String, party_id: String, challenge: String, reason: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_in_progress":
		return {"ok": false, "reason": "hearing_not_in_progress"}
	if challenge not in ["credibility_disputed", "time_disputed", "content_disputed", "identity_disputed"]:
		return {"ok": false, "reason": "invalid_testimony_challenge"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "challenge_reason_required"}
	var party_found := false
	for party_value in record.get("case_submission", {}).get("case_parties", []):
		if str(party_value.get("party_id", "")) == party_id:
			party_found = true
			if str(party_value.get("procedural_status", "notice_pending")) != "appeared":
				return {"ok": false, "reason": "party_must_appear_to_challenge"}
			break
	if not party_found:
		return {"ok": false, "reason": "case_party_not_found"}
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	if not bool(hearing.get("testimony_presented", false)):
		return {"ok": false, "reason": "testimony_not_presented"}
	var proceedings: Array = hearing.get("proceedings", []).duplicate(true)
	proceedings.append({
		"entry_type": "testimony_challenge",
		"party_id": party_id,
		"testimony_tag": str(record.get("witness_testimony_tag", "")),
		"challenge": challenge,
		"reason": reason.strip_edges(),
		"at": npc_simulation_time
	})
	hearing["proceedings"] = proceedings
	record["hearing_record"] = hearing
	_append_incident_timeline_entry(record, "testimony_challenged", "庭审中对证人陈述提出质证", party_id)
	patrol_incident_records[record_index] = record
	return {"ok": true, "testimony_challenge_recorded": true, "testimony_assessment_unchanged": true}


func close_case_hearing(incident_id: String, hearing_note: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_in_progress":
		return {"ok": false, "reason": "hearing_not_in_progress"}
	if hearing_note.strip_edges().is_empty():
		return {"ok": false, "reason": "hearing_note_required"}
	var hearing: Dictionary = record.get("hearing_record", {}).duplicate(true)
	if hearing.get("presented_evidence_tags", []).is_empty():
		return {"ok": false, "reason": "no_evidence_presented"}
	hearing["state"] = "closed_pending_judgment"
	hearing["closed_at"] = npc_simulation_time
	hearing["hearing_note"] = hearing_note.strip_edges()
	record["hearing_record"] = hearing
	record["case_workflow_state"] = "hearing_closed_pending_judgment"
	record["judge_review_state"] = "hearing_closed"
	_append_incident_timeline_entry(record, "hearing_closed", "庭审结束，案件等待独立判决", "judge_bureau")
	patrol_incident_records[record_index] = record
	return {
		"ok": true,
		"case_workflow_state": "hearing_closed_pending_judgment",
		"judicial_conclusion": "not_determined"
	}


func record_case_party_judgment(incident_id: String, party_id: String, outcome: String, reason: String, cited_evidence_tags: Array[String]) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_closed_pending_judgment":
		return {"ok": false, "reason": "hearing_must_be_closed_before_judgment"}
	if outcome not in ["acquitted", "insufficient_evidence", "responsible", "mitigated"]:
		return {"ok": false, "reason": "invalid_judgment_outcome"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "judgment_reason_required"}
	var submission: Dictionary = record.get("case_submission", {})
	var parties: Array = submission.get("case_parties", [])
	var party_found := false
	var party_procedural_status := "notice_pending"
	for party_value in parties:
		if str(party_value.get("party_id", "")) == party_id:
			party_found = true
			party_procedural_status = str(party_value.get("procedural_status", "notice_pending"))
			break
	if not party_found:
		return {"ok": false, "reason": "case_party_not_found"}
	if party_procedural_status not in ["appeared", "declined_to_respond", "unavailable"]:
		return {"ok": false, "reason": "party_procedure_not_completed", "procedural_status": party_procedural_status}
	var judgments: Dictionary = record.get("party_judgments", {}).duplicate(true)
	if judgments.has(party_id):
		return {"ok": false, "reason": "party_judgment_already_recorded"}
	var hearing: Dictionary = record.get("hearing_record", {})
	var presented: Array = hearing.get("presented_evidence_tags", [])
	var assessments: Dictionary = record.get("judicial_review", {}).get("evidence_assessments", {})
	var validated_tags: Array[String] = []
	for tag in cited_evidence_tags:
		if not presented.has(tag):
			return {"ok": false, "reason": "judgment_cites_unpresented_evidence", "evidence_tag": tag}
		if not assessments.has(tag) or str(assessments[tag].get("assessment", "")) != "accepted":
			return {"ok": false, "reason": "judgment_cites_unaccepted_evidence", "evidence_tag": tag}
		if not validated_tags.has(tag):
			validated_tags.append(tag)
	if outcome in ["responsible", "mitigated"] and validated_tags.is_empty():
		return {"ok": false, "reason": "responsibility_requires_presented_accepted_evidence"}
	var defense_statement := ""
	for party_value in parties:
		if str(party_value.get("party_id", "")) == party_id:
			defense_statement = str(party_value.get("defense_statement", ""))
			break
	judgments[party_id] = {
		"party_id": party_id,
		"outcome": outcome,
		"reason": reason.strip_edges(),
		"cited_evidence_tags": validated_tags,
		"defense_statement_considered": not defense_statement.is_empty(),
		"defense_statement": defense_statement,
		"issued_at": npc_simulation_time,
		"source": "judge_bureau"
	}
	record["party_judgments"] = judgments
	_append_incident_timeline_entry(record, "party_judgment_recorded", "涉案人员判决已记录：%s" % outcome, party_id)
	patrol_incident_records[record_index] = record
	return {"ok": true, "party_id": party_id, "outcome": outcome, "case_finalized": false}


func record_case_judgment(incident_id: String, outcome: String, reason: String, cited_evidence_tags: Array[String]) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_closed_pending_judgment":
		return {"ok": false, "reason": "hearing_must_be_closed_before_judgment"}
	if not record.get("case_submission", {}).get("case_parties", []).is_empty():
		return {"ok": false, "reason": "individual_party_judgments_required"}
	if record.has("case_judgment"):
		return {"ok": false, "reason": "case_judgment_already_recorded"}
	if outcome not in ["acquitted", "insufficient_evidence", "responsible", "mitigated"]:
		return {"ok": false, "reason": "invalid_judgment_outcome"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "judgment_reason_required"}
	var hearing: Dictionary = record.get("hearing_record", {})
	var presented: Array = hearing.get("presented_evidence_tags", [])
	var assessments: Dictionary = record.get("judicial_review", {}).get("evidence_assessments", {})
	var validated_tags: Array[String] = []
	for tag in cited_evidence_tags:
		if not presented.has(tag):
			return {"ok": false, "reason": "judgment_cites_unpresented_evidence", "evidence_tag": tag}
		if not assessments.has(tag) or str(assessments[tag].get("assessment", "")) != "accepted":
			return {"ok": false, "reason": "judgment_cites_unaccepted_evidence", "evidence_tag": tag}
		if not validated_tags.has(tag):
			validated_tags.append(tag)
	if outcome in ["responsible", "mitigated"] and validated_tags.is_empty():
		return {"ok": false, "reason": "responsibility_requires_presented_accepted_evidence"}
	record["case_judgment"] = {
		"outcome": outcome,
		"reason": reason.strip_edges(),
		"cited_evidence_tags": validated_tags,
		"issued_at": npc_simulation_time,
		"source": "judge_bureau"
	}
	_append_incident_timeline_entry(record, "case_judgment_recorded", "案件判决已记录：%s" % outcome, "judge_bureau")
	patrol_incident_records[record_index] = record
	return {"ok": true, "outcome": outcome, "case_finalized": false}


func finalize_case_judgment(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_closed_pending_judgment":
		return {"ok": false, "reason": "case_not_waiting_for_judgment"}
	var parties: Array = record.get("case_submission", {}).get("case_parties", [])
	var judgments: Dictionary = record.get("party_judgments", {})
	var outcomes: Array[String] = []
	if parties.is_empty():
		if not record.has("case_judgment"):
			return {"ok": false, "reason": "case_judgment_required"}
		outcomes.append(str(record.get("case_judgment", {}).get("outcome", "insufficient_evidence")))
	else:
		var missing_parties: Array[String] = []
		for party_value in parties:
			var party_id := str(party_value.get("party_id", ""))
			if not judgments.has(party_id):
				missing_parties.append(party_id)
			else:
				outcomes.append(str(judgments[party_id].get("outcome", "")))
		if not missing_parties.is_empty():
			return {"ok": false, "reason": "party_judgments_incomplete", "missing_party_ids": missing_parties}
	var overall_outcome := outcomes[0] if not outcomes.is_empty() else "insufficient_evidence"
	for outcome in outcomes:
		if outcome != overall_outcome:
			overall_outcome = "mixed_outcomes"
			break
	record["case_workflow_state"] = "judgment_issued"
	record["judge_review_state"] = "judgment_issued"
	record["judicial_conclusion"] = overall_outcome
	record["judgment_issued_at"] = npc_simulation_time
	record["appeal_records"] = record.get("appeal_records", []).duplicate(true)
	_append_incident_timeline_entry(record, "judgment_issued", "判官司完成判决：%s" % overall_outcome, "judge_bureau")
	patrol_incident_records[record_index] = record
	return {
		"ok": true,
		"case_workflow_state": "judgment_issued",
		"judicial_conclusion": overall_outcome,
		"party_judgment_count": outcomes.size(),
		"appeal_available": true
	}


func submit_case_appeal(incident_id: String, party_id: String, reason: String, challenged_evidence_tags: Array[String]) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) not in ["judgment_issued", "appeal_pending"]:
		return {"ok": false, "reason": "case_not_appealable"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "appeal_reason_required"}
	var party_exists := false
	if record.get("case_submission", {}).get("case_parties", []).is_empty():
		party_exists = party_id.is_empty() and record.has("case_judgment")
	else:
		party_exists = record.get("party_judgments", {}).has(party_id)
	if not party_exists:
		return {"ok": false, "reason": "appealing_party_has_no_judgment"}
	var appeal_records: Array = record.get("appeal_records", []).duplicate(true)
	for appeal_value in appeal_records:
		if str(appeal_value.get("party_id", "")) == party_id and str(appeal_value.get("status", "")) == "pending":
			return {"ok": false, "reason": "appeal_already_pending"}
	var judgment: Dictionary = record.get("case_judgment", {}) if party_id.is_empty() else record.get("party_judgments", {}).get(party_id, {})
	var judgment_tags: Array = judgment.get("cited_evidence_tags", [])
	for tag in challenged_evidence_tags:
		if not judgment_tags.has(tag):
			return {"ok": false, "reason": "appeal_references_evidence_not_in_judgment", "evidence_tag": tag}
	var appeal_id := "%s.appeal.%d" % [incident_id, appeal_records.size() + 1]
	appeal_records.append({
		"appeal_id": appeal_id,
		"party_id": party_id,
		"reason": reason.strip_edges(),
		"challenged_evidence_tags": challenged_evidence_tags.duplicate(),
		"status": "pending",
		"submitted_at": npc_simulation_time,
		"decision": "",
		"decision_reason": "",
		"decided_at": -1.0
	})
	record["appeal_records"] = appeal_records
	record["case_workflow_state"] = "appeal_pending"
	record["judge_review_state"] = "appeal_pending"
	_append_incident_timeline_entry(record, "appeal_submitted", "收到申诉申请", party_id if not party_id.is_empty() else "case_party")
	patrol_incident_records[record_index] = record
	return {"ok": true, "appeal_id": appeal_id, "status": "pending"}


func review_case_appeal(incident_id: String, appeal_id: String, decision: String, reason: String, revised_outcome: String = "") -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "appeal_pending":
		return {"ok": false, "reason": "no_appeal_pending"}
	if decision not in ["uphold", "reopen_hearing", "revise_judgment"]:
		return {"ok": false, "reason": "invalid_appeal_decision"}
	if reason.strip_edges().is_empty():
		return {"ok": false, "reason": "appeal_decision_reason_required"}
	var appeal_records: Array = record.get("appeal_records", []).duplicate(true)
	var appeal_index := -1
	for index in range(appeal_records.size()):
		if str(appeal_records[index].get("appeal_id", "")) == appeal_id and str(appeal_records[index].get("status", "")) == "pending":
			appeal_index = index
			break
	if appeal_index < 0:
		return {"ok": false, "reason": "pending_appeal_not_found"}
	var appeal: Dictionary = appeal_records[appeal_index]
	var party_id := str(appeal.get("party_id", ""))
	if decision == "revise_judgment":
		if revised_outcome not in ["acquitted", "insufficient_evidence", "responsible", "mitigated"]:
			return {"ok": false, "reason": "invalid_revised_outcome"}
		var tags: Array = appeal.get("challenged_evidence_tags", [])
		if revised_outcome in ["responsible", "mitigated"] and tags.is_empty():
			return {"ok": false, "reason": "revised_responsibility_requires_challenged_evidence"}
		if party_id.is_empty():
			var case_judgment: Dictionary = record.get("case_judgment", {}).duplicate(true)
			case_judgment["outcome"] = revised_outcome
			case_judgment["appeal_revision_reason"] = reason.strip_edges()
			case_judgment["revised_at"] = npc_simulation_time
			record["case_judgment"] = case_judgment
		else:
			var party_judgments: Dictionary = record.get("party_judgments", {}).duplicate(true)
			var party_judgment: Dictionary = party_judgments.get(party_id, {}).duplicate(true)
			if party_judgment.is_empty():
				return {"ok": false, "reason": "party_judgment_not_found"}
			party_judgment["outcome"] = revised_outcome
			party_judgment["appeal_revision_reason"] = reason.strip_edges()
			party_judgment["revised_at"] = npc_simulation_time
			party_judgments[party_id] = party_judgment
			record["party_judgments"] = party_judgments
		if party_id.is_empty():
			record["judicial_conclusion"] = revised_outcome
		else:
			var revised_outcomes: Array[String] = []
			var all_party_judgments: Dictionary = record.get("party_judgments", {})
			for party_judgment_value in all_party_judgments.values():
				revised_outcomes.append(str(party_judgment_value.get("outcome", "")))
			var aggregate_outcome := revised_outcomes[0] if not revised_outcomes.is_empty() else "insufficient_evidence"
			for party_outcome in revised_outcomes:
				if party_outcome != aggregate_outcome:
					aggregate_outcome = "mixed_outcomes"
					break
			record["judicial_conclusion"] = aggregate_outcome
		record["case_workflow_state"] = "judgment_issued"
		record["judge_review_state"] = "judgment_revised_on_appeal"
	elif decision == "reopen_hearing":
		var hearing_history: Array = record.get("hearing_history", []).duplicate(true)
		hearing_history.append(record.get("hearing_record", {}).duplicate(true))
		record["hearing_history"] = hearing_history
		record["hearing_record"] = {
			"state": "pending",
			"opened_at": -1.0,
			"closed_at": -1.0,
			"presented_evidence_tags": [],
			"proceedings": [],
			"hearing_note": "",
			"reopened_on_appeal": true
		}
		record["party_judgment_history"] = record.get("party_judgment_history", []).duplicate(true)
		record["party_judgment_history"].append(record.get("party_judgments", {}).duplicate(true))
		record["party_judgments"] = {}
		if record.has("case_judgment"):
			var case_history: Array = record.get("case_judgment_history", []).duplicate(true)
			case_history.append(record["case_judgment"].duplicate(true))
			record["case_judgment_history"] = case_history
			record.erase("case_judgment")
		record["case_workflow_state"] = "hearing_pending"
		record["judge_review_state"] = "appeal_remanded_for_hearing"
		record["judicial_conclusion"] = "not_determined"
		record["judgment_issued_at"] = -1.0
	else:
		record["case_workflow_state"] = "judgment_issued"
		record["judge_review_state"] = "appeal_rejected"
	appeal["status"] = "resolved"
	appeal["decision"] = decision
	appeal["decision_reason"] = reason.strip_edges()
	appeal["revised_outcome"] = revised_outcome
	appeal["decided_at"] = npc_simulation_time
	appeal_records[appeal_index] = appeal
	if decision == "reopen_hearing":
		for pending_index in range(appeal_records.size()):
			if pending_index == appeal_index:
				continue
			var other_appeal: Dictionary = appeal_records[pending_index]
			if str(other_appeal.get("status", "")) == "pending":
				other_appeal["status"] = "superseded"
				other_appeal["decision_reason"] = "案件已因申诉发回重审，原待处理申诉并入重审程序"
				other_appeal["decided_at"] = npc_simulation_time
				appeal_records[pending_index] = other_appeal
	else:
		var another_pending_appeal := false
		for other_appeal in appeal_records:
			if str(other_appeal.get("status", "")) == "pending":
				another_pending_appeal = true
				break
		if another_pending_appeal:
			record["case_workflow_state"] = "appeal_pending"
			record["judge_review_state"] = "appeal_pending"
		else:
			record["case_workflow_state"] = "judgment_issued"
			if decision == "uphold":
				record["judge_review_state"] = "judgment_issued"
	record["appeal_records"] = appeal_records
	_append_incident_timeline_entry(record, "appeal_decided", "申诉处理结果：%s" % decision, "judge_bureau")
	patrol_incident_records[record_index] = record
	return {
		"ok": true,
		"appeal_id": appeal_id,
		"decision": decision,
		"case_workflow_state": str(record.get("case_workflow_state", "")),
		"judicial_conclusion": str(record.get("judicial_conclusion", "not_determined"))
	}


func get_case_judgment_and_appeals(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	return {
		"ok": true,
		"incident_id": incident_id,
		"case_judgment": record.get("case_judgment", {}).duplicate(true),
		"party_judgments": record.get("party_judgments", {}).duplicate(true),
		"party_judgment_history": record.get("party_judgment_history", []).duplicate(true),
		"case_judgment_history": record.get("case_judgment_history", []).duplicate(true),
		"appeal_records": record.get("appeal_records", []).duplicate(true),
		"judicial_conclusion": str(record.get("judicial_conclusion", "not_determined")),
		"case_workflow_state": str(record.get("case_workflow_state", ""))
	}


func get_judge_bureau_appeal_queue() -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	for record_value in patrol_incident_records:
		var record: Dictionary = record_value
		for appeal_value in record.get("appeal_records", []):
			var appeal: Dictionary = appeal_value
			if str(appeal.get("status", "")) != "pending":
				continue
			queue.append({
				"incident_id": str(record.get("incident_id", "")),
				"appeal_id": str(appeal.get("appeal_id", "")),
				"party_id": str(appeal.get("party_id", "")),
				"title": str(record.get("title", "巡防案件")),
				"reason": str(appeal.get("reason", "")),
				"submitted_at": float(appeal.get("submitted_at", -1.0))
			})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("submitted_at", 0.0)) < float(b.get("submitted_at", 0.0))
	)
	return queue


func get_case_hearing_record(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	return {
		"ok": true,
		"incident_id": incident_id,
		"case_parties": record.get("case_submission", {}).get("case_parties", []).duplicate(true),
		"hearing_record": record.get("hearing_record", {}).duplicate(true),
		"judicial_conclusion": str(record.get("judicial_conclusion", "not_determined")),
		"party_judgments": record.get("party_judgments", {}).duplicate(true),
		"case_judgment": record.get("case_judgment", {}).duplicate(true),
		"appeal_records": record.get("appeal_records", []).duplicate(true),
		"judicial_review": record.get("judicial_review", {}).duplicate(true),
		"judicial_conclusion": "not_determined"
	}


func get_judge_bureau_case_queue() -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	for record_value in patrol_incident_records:
		var record: Dictionary = record_value
		var workflow_state := str(record.get("case_workflow_state", ""))
		if workflow_state not in ["transferred_to_judge_bureau", "under_judicial_review", "hearing_pending", "hearing_in_progress", "hearing_closed_pending_judgment", "judgment_issued", "appeal_pending"]:
			continue
		var submission: Dictionary = record.get("case_submission", {})
		var pending_appeal_count := 0
		for appeal_value in record.get("appeal_records", []):
			if str(appeal_value.get("status", "")) == "pending":
				pending_appeal_count += 1
		queue.append({
			"incident_id": str(record.get("incident_id", "")),
			"title": str(record.get("title", "巡防案件")),
			"severity": str(record.get("severity_label", "一般")),
			"workflow_state": workflow_state,
			"review_state": str(record.get("judge_review_state", "pending")),
			"submitted_at": float(submission.get("submitted_at", -1.0)),
			"evidence_count": int(submission.get("evidence_count", 0)),
			"witness_count": int(submission.get("witness_count", 0)),
			"testimony_conflict": bool(submission.get("testimony_conflict", false)),
			"party_count": submission.get("case_parties", []).size(),
			"judicial_conclusion": str(record.get("judicial_conclusion", "not_determined")),
			"pending_appeal_count": pending_appeal_count,
			"deduction_label": str(submission.get("deduction_label", "尚无推断"))
		})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("submitted_at", 0.0)) < float(b.get("submitted_at", 0.0))
	)
	return queue


func get_patrol_case_supplement_queue() -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	for record_value in patrol_incident_records:
		var record: Dictionary = record_value
		if str(record.get("case_workflow_state", "")) != "returned_for_supplement":
			continue
		queue.append({
			"incident_id": str(record.get("incident_id", "")),
			"title": str(record.get("title", "巡防案件")),
			"return_reason": str(record.get("case_return_reason", "")),
			"required_material": record.get("case_required_material", []).duplicate(),
			"evidence_count": int(record.get("player_evidence_count", 0)),
			"witness_count": int(record.get("player_witness_count", 0)),
			"returned_at": float(record.get("case_returned_at", -1.0))
		})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("returned_at", 0.0)) < float(b.get("returned_at", 0.0))
	)
	return queue


func get_patrol_case_dossier(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	var timeline: Array = record.get("investigation_timeline", []).duplicate(true)
	timeline.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("at", 0.0)) < float(b.get("at", 0.0))
	)
	var lead_assessments := _assess_incident_activity_leads(record)
	return {
		"ok": true,
		"incident_id": incident_id,
		"title": str(record.get("title", "巡防案件")),
		"state": str(record.get("state", "")),
		"case_workflow_state": str(record.get("case_workflow_state", "unsubmitted")),
		"judge_review_state": str(record.get("judge_review_state", "not_submitted")),
		"judicial_conclusion": str(record.get("judicial_conclusion", "not_determined")),
		"case_return_reason": str(record.get("case_return_reason", "")),
		"case_required_material": record.get("case_required_material", []).duplicate(),
		"case_submission": record.get("case_submission", {}).duplicate(true),
		"judicial_review": record.get("judicial_review", {}).duplicate(true),
		"case_parties": record.get("case_submission", {}).get("case_parties", []).duplicate(true),
		"hearing_record": record.get("hearing_record", {}).duplicate(true),
		"severity": str(record.get("severity_label", "一般")),
		"created_at": float(record.get("created_at", 0.0)),
		"resolved_at": float(record.get("resolved_at", -1.0)),
		"result_label": str(record.get("result_label", "")),
		"deduction_code": str(record.get("deduction_code", "inconclusive")),
		"deduction_label": str(record.get("deduction_label", "尚无推断")),
		"evidence_tags": record.get("player_clue_tags", []).duplicate(),
		"testimony_tag": str(record.get("witness_testimony_tag", "")),
		"testimony_conflict": bool(record.get("witness_revised", false)),
		"timeline": timeline,
		"nearby_actor_snapshots": lead_assessments,
		"lead_assessments": lead_assessments.duplicate(true),
		"witness_testimony_at": float(record.get("witness_testimony_at", -1.0)),
		"witness_revised_testimony_at": float(record.get("witness_revised_testimony_at", -1.0)),
		"activity_trail_window_seconds": 45.0,
		"activity_trail_sample_interval_seconds": 2.5,
		"player_contribution_log": record.get("player_contribution_log", []).duplicate(true)
	}


func _append_incident_timeline_entry(record: Dictionary, entry_type: String, label: String, source: String) -> void:
	var timeline: Array = record.get("investigation_timeline", [])
	timeline.append({
		"entry_type": entry_type,
		"label": label,
		"source": source,
		"at": npc_simulation_time,
		"sequence": timeline.size()
	})
	record["investigation_timeline"] = timeline


func _spawn_patrol_incident_clues(incident: Dictionary) -> Dictionary:
	var center: Vector3 = incident.get("target_position", Vector3.ZERO)
	var evidence_nodes: Array[Node3D] = []
	var clue_specs := [
		{"id": "clue_footprints", "label": "巷口脚印", "tag": "movement_trace", "offset": Vector3(-2.0, 0.22, 0.8), "color": Color("#78b9c8")},
		{"id": "clue_residue", "label": "残留阴气", "tag": "spirit_residue", "offset": Vector3(1.8, 0.28, -0.6), "color": Color("#9b8bd1")},
		{"id": "clue_fragment", "label": "破损魂器碎片", "tag": "broken_artifact", "offset": Vector3(0.4, 0.2, 2.0), "color": Color("#d5a56c")}
	]
	for spec in clue_specs:
		var clue := MeshInstance3D.new()
		clue.name = "IncidentEvidence_" + str(spec["id"])
		var mesh := SphereMesh.new()
		mesh.radius = 0.2
		mesh.height = 0.4
		clue.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = spec["color"]
		material.emission_enabled = true
		material.emission = spec["color"]
		material.emission_energy_multiplier = 1.2
		material.roughness = 0.35
		clue.material_override = material
		clue.position = center + spec["offset"]
		clue.set_meta("clue_id", str(spec["id"]))
		clue.set_meta("clue_label", str(spec["label"]))
		clue.set_meta("clue_tag", str(spec["tag"]))
		add_child(clue)
		var marker := Label3D.new()
		marker.text = "可调查 · " + str(spec["label"])
		marker.position = Vector3(0, 0.55, 0)
		marker.font_size = 28
		marker.modulate = spec["color"]
		clue.add_child(marker)
		evidence_nodes.append(clue)
	var witness_root := Node3D.new()
	witness_root.name = "IncidentWitness_" + str(incident.get("incident_id", "unknown"))
	witness_root.position = center + Vector3(5.0, 0.0, 4.5)
	add_child(witness_root)
	_create_npc_figure(witness_root, "resident")
	var witness_label := Label3D.new()
	witness_label.text = "目击者 · 可询问"
	witness_label.position = Vector3(0, 2.35, 0)
	witness_label.font_size = 28
	witness_label.modulate = Color("#e6c58d")
	witness_root.add_child(witness_label)
	return {"evidence_nodes": evidence_nodes, "witness_root": witness_root, "witness_name": "坊民证人"}

func summon_case_parties_to_judge_bureau(incident_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) not in ["hearing_pending", "hearing_in_progress"]:
		return {"ok": false, "reason": "case_not_in_hearing_phase"}
	var submission: Dictionary = record.get("case_submission", {}).duplicate(true)
	var parties: Array = submission.get("case_parties", []).duplicate(true)
	var summoned := 0
	var unavailable := 0
	for party_index in range(parties.size()):
		var party: Dictionary = parties[party_index]
		var party_id := str(party.get("party_id", ""))
		var current_status := str(party.get("procedural_status", "notice_pending"))
		if current_status != "notice_pending":
			continue
		var notice_result := update_case_party_procedural_status(incident_id, party_id, "notice_served", "判官司工作台发出到庭通知。")
		if not bool(notice_result.get("ok", false)):
			continue
		var agent_index := -1
		for index in range(npc_agents.size()):
			if str(npc_agents[index].get("npc_id", "")) == str(party.get("actor_id", party_id)):
				agent_index = index
				break
		if agent_index < 0:
			update_case_party_procedural_status(incident_id, party_id, "unavailable", "本地场景未找到对应 NPC 代理，无法执行到庭移动。")
			unavailable += 1
			continue
		var agent: Dictionary = npc_agents[agent_index]
		var root: Node3D = agent.get("root")
		if root == null or not is_instance_valid(root):
			update_case_party_procedural_status(incident_id, party_id, "unavailable", "涉案 NPC 场景实例已失效，无法执行到庭移动。")
			unavailable += 1
			continue
		var destination := Vector3(51.0 + float(summoned % 3 - 1) * 1.8, 0.0, 42.0 + float(summoned / 3) * 1.8)
		var route_result := get_navigation_route_between_positions(root.global_position, destination)
		if not bool(route_result.get("found", false)):
			update_case_party_procedural_status(incident_id, party_id, "unavailable", "无法规划前往判官司的道路路线：" + str(route_result.get("reason", "no_route")))
			unavailable += 1
			continue
		var waypoints: Array = route_result.get("points", []).duplicate()
		waypoints.push_front(root.global_position)
		if waypoints.is_empty() or waypoints[waypoints.size() - 1].distance_to(destination) > 0.5:
			waypoints.append(destination)
		elif waypoints.size() == 1:
			waypoints.append(destination)
		agent["judicial_attendance_state"] = "en_route"
		agent["judicial_incident_id"] = incident_id
		agent["judicial_party_id"] = party_id
		agent["judicial_waypoints"] = waypoints
		agent["judicial_route_index"] = 0
		agent["judicial_route_progress"] = 0.0
		agent["judicial_destination"] = destination
		agent["judicial_move_speed"] = 3.2
		agent["moving"] = false
		agent["base_position"] = root.position
		npc_agents[agent_index] = agent
		summoned += 1
	patrol_incident_records[record_index] = record
	return {"ok": true, "summoned_count": summoned, "unavailable_count": unavailable}


func call_case_party_into_hearing(incident_id: String, party_id: String) -> Dictionary:
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return {"ok": false, "reason": "case_not_found"}
	var record: Dictionary = patrol_incident_records[record_index]
	if str(record.get("case_workflow_state", "")) != "hearing_in_progress":
		return {"ok": false, "reason": "hearing_not_in_progress"}
	var party: Dictionary = {}
	for party_value in record.get("case_submission", {}).get("case_parties", []):
		if str(party_value.get("party_id", "")) == party_id:
			party = party_value
			break
	if party.is_empty():
		return {"ok": false, "reason": "case_party_not_found"}
	if str(party.get("procedural_status", "")) != "appeared":
		return {"ok": false, "reason": "party_must_appear_before_entering_hearing"}
	for index in range(npc_agents.size()):
		var agent: Dictionary = npc_agents[index]
		if str(agent.get("npc_id", "")) != str(party.get("actor_id", party_id)):
			continue
		if str(agent.get("judicial_attendance_state", "")) != "waiting":
			return {"ok": false, "reason": "party_not_waiting_in_hall"}
		var root: Node3D = agent.get("root")
		if root == null or not is_instance_valid(root):
			return {"ok": false, "reason": "party_actor_instance_missing"}
		var seat_index := int(agent.get("judicial_seat_index", 0))
		var destination := Vector3(51.0 + float(seat_index % 3 - 1) * 1.6, 0.0, 35.0 + float(seat_index / 3) * 1.4)
		var route_result := get_navigation_route_between_positions(root.global_position, destination)
		if not bool(route_result.get("found", false)):
			return {"ok": false, "reason": "hearing_route_unavailable"}
		var waypoints: Array = route_result.get("points", []).duplicate()
		waypoints.push_front(root.global_position)
		waypoints.append(destination)
		agent["judicial_attendance_state"] = "called_to_hearing"
		agent["judicial_attendance_target_state"] = "in_hearing"
		agent["judicial_waypoints"] = waypoints
		agent["judicial_route_index"] = 0
		agent["judicial_route_progress"] = 0.0
		agent["judicial_destination"] = destination
		agent["judicial_move_speed"] = 2.4
		npc_agents[index] = agent
		_append_incident_timeline_entry(record, "party_called_to_hearing", "传唤涉案人员进入庭审席位", party_id)
		patrol_incident_records[record_index] = record
		return {"ok": true, "party_id": party_id, "attendance_state": "called_to_hearing"}
	return {"ok": false, "reason": "party_actor_not_found"}


func _advance_judicial_attendance(agent: Dictionary, delta: float) -> void:
	var root: Node3D = agent.get("root")
	if root == null or not is_instance_valid(root):
		return
	var waypoints: Array = agent.get("judicial_waypoints", [])
	if waypoints.size() < 2:
		return
	var route_index := int(agent.get("judicial_route_index", 0))
	var progress := float(agent.get("judicial_route_progress", 0.0))
	var start: Vector3 = waypoints[route_index]
	var next_index := mini(route_index + 1, waypoints.size() - 1)
	var finish: Vector3 = waypoints[next_index]
	var segment_length := maxf(start.distance_to(finish), 0.01)
	progress += float(agent.get("judicial_move_speed", 3.2)) * delta / segment_length
	while progress >= 1.0 and next_index < waypoints.size() - 1:
		progress -= 1.0
		route_index = next_index
		next_index = mini(route_index + 1, waypoints.size() - 1)
		start = waypoints[route_index]
		finish = waypoints[next_index]
		segment_length = maxf(start.distance_to(finish), 0.01)
	if next_index == waypoints.size() - 1 and progress >= 1.0:
		var destination: Vector3 = agent.get("judicial_destination", finish)
		root.position = destination
		var target_state := str(agent.get("judicial_attendance_target_state", "waiting"))
		agent["judicial_attendance_state"] = target_state
		agent["judicial_route_progress"] = 1.0
		if target_state == "waiting":
			var incident_id := str(agent.get("judicial_incident_id", ""))
			var party_id := str(agent.get("judicial_party_id", ""))
			var arrival_result := update_case_party_procedural_status(incident_id, party_id, "appeared", "涉案人员已沿判官司路网抵达候审区。")
			if not bool(arrival_result.get("ok", false)):
				agent["judicial_attendance_state"] = "arrival_record_failed"
				print("[JudgeBureau] arrival status failed party=%s reason=%s" % [party_id, str(arrival_result.get("reason", ""))])
		return
	root.position = start.lerp(finish, progress)
	var direction := finish - start
	if direction.length_squared() > 0.01:
		root.rotation.y = atan2(-direction.x, -direction.z)
	agent["judicial_route_index"] = route_index
	agent["judicial_route_progress"] = progress


func get_case_party_attendance(incident_id: String) -> Array[Dictionary]:
	var attendance: Array[Dictionary] = []
	var record_index := _find_patrol_incident_record(incident_id)
	if record_index < 0:
		return attendance
	var parties: Array = patrol_incident_records[record_index].get("case_submission", {}).get("case_parties", [])
	for party_value in parties:
		var party: Dictionary = party_value
		var state := "not_summoned"
		for agent_value in npc_agents:
			var agent: Dictionary = agent_value
			if str(agent.get("npc_id", "")) == str(party.get("actor_id", party.get("party_id", ""))):
				state = str(agent.get("judicial_attendance_state", "not_summoned"))
				break
		attendance.append({
			"party_id": str(party.get("party_id", "")),
			"display_name": str(party.get("display_name", "未知人员")),
			"procedural_status": str(party.get("procedural_status", "notice_pending")),
			"attendance_state": state
		})
	return attendance


func _interact_with_focused_npc() -> void:
	if npc_detail_label == null:
		return
	if patrol_incident_focus_id != "":
		_interact_with_patrol_incident(patrol_incident_focus_id)
		return
	if npc_focus_agent.is_empty():
		return
	var npc_name := str(npc_focus_agent.get("display_name", "无名阴差"))
	var npc_id := str(npc_focus_agent.get("npc_id", "unknown"))
	var message := ""
	match str(npc_focus_agent.get("interaction_type", "none")):
		"trade":
			var merchant_state := str(npc_focus_agent.get("state", "trade_idle"))
			var stall_type := str(npc_focus_agent.get("market_stall_type", "鬼市商铺"))
			var goods: Array = npc_focus_agent.get("market_goods", [])
			var goods_text := "、".join(PackedStringArray(goods))
			var business_code := str(npc_focus_agent.get("market_business_state", "closed"))
			var business_state := "营业中" if business_code == "open" else ("补货中 · 暂缓接待" if business_code == "restocking" else "今日休市")
			var stall_id := str(npc_focus_agent.get("market_stall_id", "待绑定"))
			var service := str(npc_focus_agent.get("market_service", "unavailable"))
			var service_note := "商队正在卸货，掌柜暂缓接待" if business_code == "restocking" else "交易功能接入后可查看实时货单"
			if merchant_state == "restock_receive" or merchant_state == "restock_sort":
				message = "%s（%s）\n%s · 补货中\n正在接收并整理%s，暂缓交易接待。\n摊位编号：%s\n\n当前为本地场景演示，不会修改真实库存。" % [npc_name, str(npc_focus_agent.get("merchant_title", "掌柜")), stall_type, goods_text, stall_id]
			elif merchant_state == "auction_watch":
				message = "%s（%s）\n%s · 正在关注万魂竞宝\n掌柜暂时留意台上拍品，稍后继续经营。\n陈列：%s\n摊位编号：%s" % [npc_name, str(npc_focus_agent.get("merchant_title", "掌柜")), stall_type, goods_text, stall_id]
			elif merchant_state == "greet":
				message = "%s（%s）\n%s · %s\n经营：%s\n陈列：%s\n服务标识：%s\n摊位编号：%s\n\n%s。" % [npc_name, str(npc_focus_agent.get("merchant_title", "掌柜")), stall_type, business_state, stall_type, goods_text, service, stall_id, service_note]
			else:
				message = "%s · %s\n经营：%s\n陈列：%s\n服务标识：%s\n摊位编号：%s\n\n%s；当前仅为场景展示，真实库存与交易尚未开放。" % [npc_name, business_state, stall_type, goods_text, service, stall_id, service_note]
		"registration": message = "%s：请准备好魂籍凭证，先登记来处，再按引导前往分流处。" % npc_name
		"queue_info":
			var queue_state := str(npc_focus_agent.get("state", "queue_wait"))
			match queue_state:
				"queue_registered": message = "%s：魂籍登记已完成，请留在原位等待分流引导（当前为本地演示）。" % npc_name
				"queue_called", "queue_glance": message = "%s：引魂使正在叫号，请回应并准备登记。" % npc_name
				"queue_registering": message = "%s：引魂使正在核验魂籍，请稍候。" % npc_name
				_: message = "%s：请依次候登记，不要越过前方魂灵。" % npc_name
		"dispatch":
			var patrol_state := str(npc_focus_agent.get("state", "patrol_watch"))
			var patrol_index := int(npc_focus_agent.get("route_index", 0))
			var patrol_names := ["中轴巡街", "北城官道", "北侧坊巷", "东侧官道", "东城外廊", "东南巡段", "南城官道", "西南巡段", "西侧官道", "西城外廊", "西北坊巷", "北西巡段", "北城回巡", "中轴复核", "巡防起点"]
			var patrol_zone := patrol_names[patrol_index % patrol_names.size()] if str(npc_focus_agent.get("activity", "")) == "patrol_route" else "巡城司值守区"
			if patrol_state == "alert_watch":
				message = "%s：信号塔已发出警戒令，附近巡卫正在响应并确认周边动静。\n这是本地警戒演练，不代表真实治安事件或服务端执法结果。" % npc_name
			elif patrol_state == "patrol_watch":
				message = "%s：当前驻察%s。城门、坊巷与主街均在巡防簿册之内。\n本地演示：巡逻卫正在检查此处，不代表服务端治安事件。" % [npc_name, patrol_zone]
			else:
				message = "%s：巡防事务请报明来意。负责区域：%s。军令与治安任务尚未接入。" % [npc_name, patrol_zone]
		"talk":
			var resident_state := str(npc_focus_agent.get("state", "social_idle"))
			var resident_lines := {
				"square_walk": "街坊巷口刚打扫过，沿着石板路走一圈，便能认全邻里。",
				"square_chat": "近日坊里安稳，听说鬼市今晚又有新货。",
				"carry_goods": "家中还有些物件要搬，等忙完了再去茶亭歇脚。",
				"well_idle": "井水清凉，取水也要排个先后，莫要扰了街坊。",
				"draw_water": "打些井水回去，灶上还等着用呢。",
				"tea_social": "茶亭今日有新茶，坐下来听听街坊闲谈吧。",
				"serve_tea": "客官请用茶，坊里的消息多半都在这盏茶里。",
				"home_idle": "忙完家事，便在门前坐坐，看看街坊来往。"
			}
			message = "%s：%s" % [npc_name, str(resident_lines.get(resident_state, "魂坊今日安宁，若有闲暇，不妨去茶亭坐坐。"))]
		_: message = "%s 暂无可用交互。" % npc_name
	npc_detail_label.text = message
	print("[FengduNPC] interact id=%s type=%s" % [npc_id, str(npc_focus_agent.get("interaction_type", "none"))])


func _is_player_at_judge_bureau() -> bool:
	return player != null and player.global_position.distance_to(Vector3(51.0, 0.0, 36.5)) <= 7.0


func _build_judge_bureau_workbench() -> void:
	var layer := CanvasLayer.new()
	layer.name = "JudgeBureauWorkbenchLayer"
	layer.layer = 12
	add_child(layer)
	judge_workbench_root = Control.new()
	judge_workbench_root.name = "JudgeBureauWorkbench"
	judge_workbench_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	judge_workbench_root.visible = false
	layer.add_child(judge_workbench_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.04, 0.065, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	judge_workbench_root.add_child(backdrop)
	var shell := PanelContainer.new()
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 48.0
	shell.offset_top = 34.0
	shell.offset_right = -48.0
	shell.offset_bottom = -34.0
	judge_workbench_root.add_child(shell)
	var root_column := VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 12)
	shell.add_child(root_column)
	var header := HBoxContainer.new()
	root_column.add_child(header)
	var heading := Label.new()
	heading.text = "判官司 · 司法卷宗工作台"
	heading.add_theme_font_size_override("font_size", 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", Color("#e7c58e"))
	header.add_child(heading)
	var close_button := Button.new()
	close_button.text = "关闭  [E / ESC]"
	close_button.pressed.connect(_close_judge_bureau_workbench)
	header.add_child(close_button)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300.0
	split.add_child(left)
	var queue_title := Label.new()
	queue_title.text = "待办卷宗 · 选择案件查看详情"
	queue_title.add_theme_color_override("font_color", Color("#a9bdcf"))
	left.add_child(queue_title)
	judge_case_list = ItemList.new()
	judge_case_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	judge_case_list.item_selected.connect(_on_judge_case_selected)
	left.add_child(judge_case_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	judge_case_detail = RichTextLabel.new()
	judge_case_detail.bbcode_enabled = true
	judge_case_detail.fit_content = false
	judge_case_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	judge_case_detail.scroll_active = true
	right.add_child(judge_case_detail)
	judge_review_actions = HFlowContainer.new()
	right.add_child(judge_review_actions)
	judge_statement_input = LineEdit.new()
	judge_statement_input.placeholder_text = "输入申辩或质证理由（必填），再选择对应人员与操作"
	judge_statement_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(judge_statement_input)
	var action_row := HFlowContainer.new()
	right.add_child(action_row)
	_add_judge_action_button(action_row, "开始复核", _judge_action_begin_review)
	_add_judge_action_button(action_row, "完成材料复核", _judge_action_complete_review)
	_add_judge_action_button(action_row, "接纳候审", _judge_action_accept_hearing)
	_add_judge_action_button(action_row, "传唤涉案人员", _judge_action_summon_parties)
	_add_judge_action_button(action_row, "开始庭审", _judge_action_begin_hearing)
	_add_judge_action_button(action_row, "结庭", _judge_action_close_hearing)
	_add_judge_action_button(action_row, "签发判决", _judge_action_finalize)
	judge_workbench_hint = Label.new()
	judge_workbench_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	judge_workbench_hint.add_theme_color_override("font_color", Color("#e7c58e"))
	root_column.add_child(judge_workbench_hint)
	judge_workbench_hint.text = "原型操作台：当前客户端规则演示，不代表真实官职授权或服务端司法权限。"


func _add_judge_action_button(parent: Container, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)


func _open_judge_bureau_workbench() -> void:
	if judge_workbench_root == null:
		return
	judge_workbench_open = true
	judge_workbench_root.visible = true
	_release_mouse()
	_refresh_judge_bureau_workbench()


func _close_judge_bureau_workbench() -> void:
	judge_workbench_open = false
	if judge_workbench_root != null:
		judge_workbench_root.visible = false


func _refresh_judge_bureau_workbench() -> void:
	if judge_case_list == null or judge_case_detail == null:
		return
	judge_case_list.clear()
	var queue := get_judge_bureau_case_queue()
	var selected_index := -1
	for i in range(queue.size()):
		var item: Dictionary = queue[i]
		var label := "%s  ·  %s\n%s | 物证 %d | 证词 %d | 涉案 %d | 申诉 %d" % [
			str(item.get("title", "巡防案件")),
			str(item.get("incident_id", "")),
			str(item.get("workflow_state", "")),
			int(item.get("evidence_count", 0)),
			int(item.get("witness_count", 0)),
			int(item.get("party_count", 0)),
			int(item.get("pending_appeal_count", 0))
		]
		judge_case_list.add_item(label)
		if str(item.get("incident_id", "")) == judge_selected_incident_id:
			selected_index = i
	if selected_index < 0 and not queue.is_empty():
		selected_index = 0
		judge_selected_incident_id = str(queue[0].get("incident_id", ""))
	if selected_index >= 0:
		judge_case_list.select(selected_index)
		_show_judge_case_detail(judge_selected_incident_id)
	else:
		judge_selected_incident_id = ""
		judge_case_detail.text = "[center][color=#a9bdcf]当前没有已移交判官司的卷宗[/color][/center]\n\n巡城司完成现场调查并正式移交后，案件才会出现在这里。"


func _on_judge_case_selected(index: int) -> void:
	var queue := get_judge_bureau_case_queue()
	if index < 0 or index >= queue.size():
		return
	judge_selected_incident_id = str(queue[index].get("incident_id", ""))
	_show_judge_case_detail(judge_selected_incident_id)


func _show_judge_case_detail(incident_id: String) -> void:
	var dossier := get_patrol_case_dossier(incident_id)
	if not bool(dossier.get("ok", false)):
		judge_case_detail.text = "卷宗读取失败：" + str(dossier.get("reason", "unknown"))
		return
	var submission: Dictionary = dossier.get("case_submission", {})
	var review: Dictionary = dossier.get("judicial_review", {})
	var hearing: Dictionary = dossier.get("hearing_record", {})
	var lines := PackedStringArray()
	lines.append("[font_size=22][color=#e7c58e]%s[/color][/font_size]" % str(dossier.get("title", "巡防案件")))
	lines.append("[color=#91a9bf]案卷编号：%s  |  严重程度：%s[/color]" % [incident_id, str(dossier.get("severity", "一般"))])
	lines.append("卷宗状态：%s  |  复核状态：%s" % [str(dossier.get("case_workflow_state", "")), str(dossier.get("judge_review_state", ""))])
	lines.append("初步推断：%s  |  现场结果：%s" % [str(submission.get("deduction_label", dossier.get("deduction_label", "尚无推断"))), str(dossier.get("result_label", ""))])
	lines.append("\n[b][color=#a9bdcf]移交证据[/color][/b]")
	var evidence_tags: Array = submission.get("evidence_tags", [])
	var assessments: Dictionary = review.get("evidence_assessments", {})
	if evidence_tags.is_empty():
		lines.append("尚无移交物证")
	for tag_value in evidence_tags:
		var tag := str(tag_value)
		var assessment: Dictionary = assessments.get(tag, {})
		lines.append("• %s  →  %s" % [tag, str(assessment.get("assessment", "待复核"))])
	lines.append("\n[b][color=#a9bdcf]证人陈述[/color][/b]")
	lines.append("证词标签：%s  |  复核：%s  |  前后矛盾：%s" % [
		str(submission.get("testimony_tag", "无")),
		str(review.get("testimony_assessment", {}).get("assessment", "待复核")),
		"是" if bool(submission.get("testimony_conflict", false)) else "否"
	])
	lines.append("\n[b][color=#a9bdcf]涉案人员与程序[/color][/b]")
	var parties: Array = submission.get("case_parties", [])
	if parties.is_empty():
		lines.append("本案没有独立涉案人员记录")
	for party_value in parties:
		var party: Dictionary = party_value
		lines.append("• %s（%s）— %s；申辩：%s" % [
			str(party.get("display_name", party.get("party_id", "未知人员"))),
			str(party.get("party_id", "")),
			str(party.get("procedural_status", "notice_pending")),
			"已记录" if not str(party.get("defense_statement", "")).is_empty() else "未记录"
		])
	lines.append("\n[b][color=#a9bdcf]出庭状态[/color][/b]")
	for attendance_value in get_case_party_attendance(incident_id):
		var attendance: Dictionary = attendance_value
		lines.append("• %s — 程序：%s；移动：%s" % [
			str(attendance.get("display_name", "未知人员")),
			str(attendance.get("procedural_status", "")),
			str(attendance.get("attendance_state", "not_summoned"))
		])
	lines.append("\n[b][color=#a9bdcf]庭审记录[/color][/b]")
	lines.append("庭审：%s  |  已出示物证：%d  |  程序记录：%d" % [
		str(hearing.get("state", "未开庭")),
		hearing.get("presented_evidence_tags", []).size(),
		hearing.get("proceedings", []).size()
	])
	var proceedings: Array = hearing.get("proceedings", [])
	for entry_value in proceedings.slice(maxi(0, proceedings.size() - 8), proceedings.size()):
		var entry: Dictionary = entry_value
		lines.append("  · %s：%s" % [str(entry.get("entry_type", "记录")), str(entry.get("statement", entry.get("reason", entry.get("challenge", entry.get("evidence_tag", entry.get("party_id", ""))))))])
	lines.append("\n[b][color=#a9bdcf]判决与申诉[/color][/b]")
	lines.append("判决：%s  |  待处理申诉：%d" % [
		str(dossier.get("judicial_conclusion", "not_determined")),
		get_judge_bureau_appeal_queue().filter(func(a: Dictionary) -> bool: return str(a.get("incident_id", "")) == incident_id).size()
	])
	judge_case_detail.text = "\n".join(lines)


func _refresh_judge_review_actions(submission: Dictionary, review: Dictionary) -> void:
	if judge_review_actions == null:
		return
	for child in judge_review_actions.get_children():
		child.queue_free()
	var dossier := get_patrol_case_dossier(judge_selected_incident_id)
	var workflow := str(dossier.get("case_workflow_state", ""))
	var assessments: Dictionary = review.get("evidence_assessments", {})
	if workflow == "under_judicial_review":
		for tag_value in submission.get("evidence_tags", []):
			var tag := str(tag_value)
			var current := str(assessments.get(tag, {}).get("assessment", "待复核"))
			var caption := "物证 %s：%s" % [tag, current]
			var accepted := Button.new()
			accepted.text = caption + " · 采信"
			accepted.pressed.connect(func(): _judge_assess_evidence(tag, "accepted"))
			judge_review_actions.add_child(accepted)
			var verify := Button.new()
			verify.text = "待核验"
			verify.pressed.connect(func(): _judge_assess_evidence(tag, "needs_verification"))
			judge_review_actions.add_child(verify)
			var rejected := Button.new()
			rejected.text = "不采信"
			rejected.pressed.connect(func(): _judge_assess_evidence(tag, "rejected"))
			judge_review_actions.add_child(rejected)
		if int(submission.get("witness_count", 0)) > 0:
			var testimony_review: Dictionary = review.get("testimony_assessment", {})
			var testimony_state := str(testimony_review.get("assessment", "待复核"))
			var credible := Button.new()
			credible.text = "证词可信（当前：%s）" % testimony_state
			credible.pressed.connect(func(): _judge_assess_testimony("credible"))
			judge_review_actions.add_child(credible)
			var disputed := Button.new()
			disputed.text = "证词存疑"
			disputed.pressed.connect(func(): _judge_assess_testimony("disputed"))
			judge_review_actions.add_child(disputed)
			var insufficient := Button.new()
			insufficient.text = "证词不足"
			insufficient.pressed.connect(func(): _judge_assess_testimony("insufficient"))
			judge_review_actions.add_child(insufficient)
	elif workflow == "hearing_in_progress":
		var hearing: Dictionary = dossier.get("hearing_record", {})
		var presented: Array = hearing.get("presented_evidence_tags", [])
		for tag_value in submission.get("evidence_tags", []):
			var tag := str(tag_value)
			if presented.has(tag) or str(assessments.get(tag, {}).get("assessment", "")) != "accepted":
				continue
			var present_button := Button.new()
			present_button.text = "庭审出示物证 · " + tag
			present_button.pressed.connect(func(): _judge_present_evidence(tag))
			judge_review_actions.add_child(present_button)
		var testimony_review: Dictionary = review.get("testimony_assessment", {})
		if int(submission.get("witness_count", 0)) > 0 and str(testimony_review.get("assessment", "")) == "credible" and not bool(hearing.get("testimony_presented", false)):
			var testimony_button := Button.new()
			testimony_button.text = "庭审出示证人陈述"
			testimony_button.pressed.connect(_judge_present_testimony)
			judge_review_actions.add_child(testimony_button)
		for party_value in submission.get("case_parties", []):
			var party: Dictionary = party_value
			var party_id := str(party.get("party_id", ""))
			var party_name := str(party.get("display_name", party_id))
			if str(party.get("procedural_status", "")) == "appeared":
				var attendance_state := "not_summoned"
				for attendance_value in get_case_party_attendance(judge_selected_incident_id):
					if str(attendance_value.get("party_id", "")) == party_id:
						attendance_state = str(attendance_value.get("attendance_state", ""))
						break
				if attendance_state == "waiting":
					var call_button := Button.new()
					call_button.text = party_name + " · 传唤入庭"
					call_button.pressed.connect(func(): _judge_call_party_into_hearing(party_id))
					judge_review_actions.add_child(call_button)
				var defense_button := Button.new()
				defense_button.text = party_name + " · 记录申辩"
				defense_button.pressed.connect(func(): _judge_record_defense(party_id))
				judge_review_actions.add_child(defense_button)
				for tag_value in presented:
					var challenge_tag := str(tag_value)
					for challenge_data in [
						["质疑真实性", "authenticity_disputed"],
						["质疑保管链", "chain_of_custody_disputed"],
						["质疑证据解释", "interpretation_disputed"],
						["质疑关联性", "relevance_disputed"]
					]:
						var challenge_button := Button.new()
						challenge_button.text = party_name + " · " + str(challenge_data[0]) + "：" + challenge_tag
						var challenge_code := str(challenge_data[1])
						challenge_button.pressed.connect(func(): _judge_challenge_evidence(party_id, challenge_tag, challenge_code))
						judge_review_actions.add_child(challenge_button)
				if bool(hearing.get("testimony_presented", false)):
					for testimony_challenge in [
						["质疑证人可信度", "credibility_disputed"],
						["质疑陈述时间", "time_disputed"],
						["质疑陈述内容", "content_disputed"],
						["质疑证人身份", "identity_disputed"]
					]:
						var testimony_challenge_button := Button.new()
						testimony_challenge_button.text = party_name + " · " + str(testimony_challenge[0])
						var testimony_code := str(testimony_challenge[1])
						testimony_challenge_button.pressed.connect(func(): _judge_challenge_testimony(party_id, testimony_code))
						judge_review_actions.add_child(testimony_challenge_button)
	elif workflow == "hearing_closed_pending_judgment":
		var judgment_data := get_case_judgment_and_appeals(judge_selected_incident_id)
		var party_judgments: Dictionary = judgment_data.get("party_judgments", {})
		var parties: Array = submission.get("case_parties", [])
		if parties.is_empty() and judgment_data.get("case_judgment", {}).is_empty():
			var acquit_case := Button.new()
			acquit_case.text = "本案判决 · 无罪"
			acquit_case.pressed.connect(func(): _judge_record_case_judgment("acquitted"))
			judge_review_actions.add_child(acquit_case)
			var insufficient_case := Button.new()
			insufficient_case.text = "本案判决 · 证据不足"
			insufficient_case.pressed.connect(func(): _judge_record_case_judgment("insufficient_evidence"))
			judge_review_actions.add_child(insufficient_case)
		for party_value in parties:
			var party: Dictionary = party_value
			var party_id := str(party.get("party_id", ""))
			if party_judgments.has(party_id):
				continue
			var acquit := Button.new()
			acquit.text = "%s · 无罪" % str(party.get("display_name", party_id))
			acquit.pressed.connect(func(): _judge_record_party_judgment(party_id, "acquitted"))
			judge_review_actions.add_child(acquit)
			var insufficient_party := Button.new()
			insufficient_party.text = "%s · 证据不足" % str(party.get("display_name", party_id))
			insufficient_party.pressed.connect(func(): _judge_record_party_judgment(party_id, "insufficient_evidence"))
			judge_review_actions.add_child(insufficient_party)
			var responsible := Button.new()
			responsible.text = "%s · 承担责任" % str(party.get("display_name", party_id))
			responsible.pressed.connect(func(): _judge_record_party_judgment(party_id, "responsible"))
			judge_review_actions.add_child(responsible)


func _judge_record_defense(party_id: String) -> void:
	if judge_selected_incident_id.is_empty() or judge_statement_input == null:
		return
	var statement := judge_statement_input.text.strip_edges()
	if statement.is_empty():
		_run_judge_action({"ok": false, "reason": "请先输入当事人申辩内容"}, "")
		return
	_run_judge_action(record_case_party_defense_statement(judge_selected_incident_id, party_id, statement), "已记录当事人申辩：" + party_id)


func _judge_challenge_evidence(party_id: String, evidence_tag: String, challenge: String) -> void:
	if judge_selected_incident_id.is_empty() or judge_statement_input == null:
		return
	var reason := judge_statement_input.text.strip_edges()
	if reason.is_empty():
		_run_judge_action({"ok": false, "reason": "请先输入质证理由"}, "")
		return
	_run_judge_action(record_case_evidence_challenge_at_hearing(judge_selected_incident_id, party_id, evidence_tag, challenge, reason), "已记录物证质证意见：" + evidence_tag)


func _judge_challenge_testimony(party_id: String, challenge: String) -> void:
	if judge_selected_incident_id.is_empty() or judge_statement_input == null:
		return
	var reason := judge_statement_input.text.strip_edges()
	if reason.is_empty():
		_run_judge_action({"ok": false, "reason": "请先输入质证理由"}, "")
		return
	_run_judge_action(record_case_testimony_challenge_at_hearing(judge_selected_incident_id, party_id, challenge, reason), "已记录证人陈述质证意见。")


func _judge_call_party_into_hearing(party_id: String) -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(call_case_party_into_hearing(judge_selected_incident_id, party_id), "已传唤涉案人员进入庭审席位。")


func _judge_present_evidence(tag: String) -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(present_case_evidence_at_hearing(judge_selected_incident_id, tag, "庭审中向各方出示该项已采信物证。"), "已在庭审中出示物证：" + tag)


func _judge_present_testimony() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(present_case_testimony_at_hearing(judge_selected_incident_id, "庭审中宣读经复核的证人陈述。"), "已在庭审中出示证人陈述。")


func _judge_record_case_judgment(outcome: String) -> void:
	if judge_selected_incident_id.is_empty():
		return
	var no_party_evidence: Array[String] = []
	_run_judge_action(record_case_judgment(judge_selected_incident_id, outcome, "根据庭审已完成的举证与质证程序作出判决。", no_party_evidence), "本案判决结果已记录：" + outcome)


func _judge_record_party_judgment(party_id: String, outcome: String) -> void:
	if judge_selected_incident_id.is_empty():
		return
	var cited: Array[String] = []
	if outcome == "responsible":
		var hearing_result: Dictionary = get_case_hearing_record(judge_selected_incident_id)
		var hearing: Dictionary = hearing_result.get("hearing_record", {})
		for tag_value in hearing.get("presented_evidence_tags", []):
			cited.append(str(tag_value))
	var reason := "根据庭审记录作出判决；当前原型以已完成程序和已出示证据为依据。"
	_run_judge_action(record_case_party_judgment(judge_selected_incident_id, party_id, outcome, reason, cited), "涉案人员判决已记录：" + outcome)


func _judge_assess_evidence(tag: String, assessment: String) -> void:
	if judge_selected_incident_id.is_empty():
		return
	var reason := "判官司工作台逐项复核：%s" % assessment
	_run_judge_action(record_judicial_evidence_assessment(judge_selected_incident_id, tag, assessment, reason), "物证 %s 已更新为 %s。" % [tag, assessment])


func _judge_assess_testimony(assessment: String) -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(record_judicial_testimony_assessment(judge_selected_incident_id, assessment, "判官司工作台逐项复核：%s" % assessment), "证词复核结果已更新：%s。" % assessment)


func _run_judge_action(result: Dictionary, success_text: String) -> void:
	if not bool(result.get("ok", false)):
		if judge_workbench_hint != null:
			judge_workbench_hint.text = "操作未执行：%s" % str(result.get("reason", "unknown"))
	else:
		if judge_workbench_hint != null:
			judge_workbench_hint.text = success_text
	_refresh_judge_bureau_workbench()


func _judge_action_begin_review() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(begin_judge_bureau_case_review(judge_selected_incident_id), "已开始卷宗复核。")


func _judge_action_complete_review() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(complete_judge_bureau_review(judge_selected_incident_id), "材料复核完成；是否接纳候审由判官另行决定。")

func _judge_action_accept_hearing() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(record_judge_bureau_case_disposition(judge_selected_incident_id, "accept_for_hearing"), "案件已接纳候审。")


func _judge_action_summon_parties() -> void:
	if judge_selected_incident_id.is_empty():
		return
	var result := summon_case_parties_to_judge_bureau(judge_selected_incident_id)
	if bool(result.get("ok", false)):
		_run_judge_action(result, "已发出传唤：%d 人开始沿道路前往候审区；无法移动：%d 人。" % [
			int(result.get("summoned_count", 0)),
			int(result.get("unavailable_count", 0))
		])
	else:
		_run_judge_action(result, "")


func _judge_action_begin_hearing() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(begin_case_hearing(judge_selected_incident_id), "庭审已开始。请先完成涉案人员程序，再进行举证与申辩。")


func _judge_action_close_hearing() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(close_case_hearing(judge_selected_incident_id, "庭审记录已由判官司工作台封存。"), "庭审已结束，进入判决阶段。")


func _judge_action_finalize() -> void:
	if judge_selected_incident_id.is_empty():
		return
	_run_judge_action(finalize_case_judgment(judge_selected_incident_id), "判决已签发。")


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
