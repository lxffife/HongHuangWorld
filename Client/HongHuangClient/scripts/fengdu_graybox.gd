extends Node3D

const WORLD_LAYOUT = preload("res://scripts/fengdu_world_layout.gd")
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
	var navigation_network: Dictionary = WORLD_LAYOUT.get_navigation_network()
	for point in WORLD_LAYOUT.get_npc_activity_points():
		var bound_point: Dictionary = point.duplicate(true)
		bound_point.merge(WORLD_LAYOUT.get_spatial_binding_for_point(bound_point, navigation_network), true)
		activity_points.append(bound_point)
	var routes: Array = WORLD_LAYOUT.get_patrol_routes()
	patrol_route.clear()
	if routes.is_empty():
		return
	var route: Dictionary = routes[0]
	for node_position in route.get("nodes", []):
		patrol_route.append(node_position)
	for route_index in range(patrol_route.size()):
		var route_position: Vector3 = patrol_route[route_index]
		var route_point := {
			"point_id": "patrol.route.%02d" % (route_index + 1),
			"district": str(route.get("district", "巡城司")),
			"role": str(route.get("role", "patrol_guard")),
			"activity": "patrol_route",
			"position": route_position,
			"facing": 0.0,
			"schedule_tag": str(route.get("schedule_tag", "night")),
			"capacity": 1,
			"radius": 1.0
		}
		route_point.merge(WORLD_LAYOUT.get_spatial_binding_for_point(route_point, navigation_network), true)
		activity_points.append(route_point)


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
		"patrol_walk":
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
			_update_merchant_market_activity(agent)
		var patrol_alert_override := false
		if str(agent.get("role", "")) == "patrol_guard":
			var should_alert := patrol_alert_remaining > 0.0 and root.global_position.distance_to(patrol_alert_position) <= 60.0
			var was_alerted := bool(agent.get("alert_override", false))
			if should_alert:
				if not was_alerted:
					agent["alert_resume_moving"] = bool(agent.get("moving", false))
					agent["alert_hold_position"] = root.position
				var alert_direction := patrol_alert_position - root.global_position
				if alert_direction.length_squared() > 0.01:
					agent["alert_facing"] = atan2(-alert_direction.x, -alert_direction.z)
				agent["alert_override"] = true
				agent["state"] = "alert_watch"
				patrol_alert_override = true
			elif was_alerted:
				agent["alert_override"] = false
				agent["moving"] = bool(agent.get("alert_resume_moving", false))
				agent["state"] = "patrol_walk" if bool(agent["moving"]) else "patrol_watch"
		if patrol_alert_override:
			root.position = agent.get("alert_hold_position", root.position)
			root.rotation.y = float(agent.get("alert_facing", root.rotation.y))
			body.position.y = 0.92 + sin(phase * 1.4) * 0.018
			left_arm.rotation.z = deg_to_rad(-58.0) + sin(phase * 1.6) * 0.08
			right_arm.rotation.z = deg_to_rad(58.0) - sin(phase * 1.6) * 0.08
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
			patrol_alert_remaining = maxf(patrol_alert_remaining, 7.0)
			patrol_alert_sequence += 1
			print("[FengduPatrol] market gate report #%d dispatched to patrol guards" % patrol_alert_sequence)
	var inspecting := market_inspection_remaining > 0.0
	var minute_of_day := int(npc_world_minutes / 60.0) * 60 + int(fposmod(npc_world_minutes, 60.0))
	var welcoming_guests := minute_of_day >= 19 * 60 + 30 and minute_of_day < 20 * 60
	var guiding_departure := minute_of_day >= 22 * 60 and minute_of_day < 22 * 60 + 30
	market_inspection_label.text = ("巡夜巡查 · 入口核验 #%d" % market_inspection_sequence) if inspecting else ("宾客入场 · 入口引导" if welcoming_guests else ("竞宝散场 · 引导离席" if guiding_departure else "夜市巡防 · 正常"))
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


func _update_patrol_alert(delta: float) -> void:
	# Alert duration is driven by a gate report; no unrelated periodic drill is generated.
	if patrol_alert_remaining > 0.0:
		patrol_alert_remaining = maxf(0.0, patrol_alert_remaining - delta)


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
