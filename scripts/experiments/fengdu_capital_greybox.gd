extends Node3D
## Standalone, walkable Fengdu capital blockout.
## All dimensions below are gameplay-scale greybox dimensions, not final art assets.

const WorldEnvironmentBuilder = preload("res://scripts/world_environment_builder.gd")
const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const CityModuleScene = preload("res://scenes/experiments/FengduCityModule.tscn")
const NpcDialoguePanel = preload("res://scripts/experiments/npc_dialogue_panel.gd")
const FengduQuestManager = preload("res://scripts/experiments/fengdu_quest_manager.gd")
const FengduQuestJournal = preload("res://scripts/experiments/fengdu_quest_journal.gd")
const FengduQuestTracker = preload("res://scripts/experiments/fengdu_quest_tracker.gd")

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
var _dialogue_panel: CanvasLayer
var _quest_manager: Node
var _quest_journal: CanvasLayer
var _quest_tracker: CanvasLayer


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
	_build_named_yin_officials()
	_build_citizens()
	_build_street_furniture()
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
	_add_box("SouthGateToCityRoad", Vector3(44.0, 0.5, 260.0), Vector3(0.0, 0.28, 610.0), "road", false)
	_add_box("WestInnerStreet", Vector3(26.0, 0.5, 520.0), Vector3(-260.0, 0.28, 150.0), "road", false)
	_add_box("EastInnerStreet", Vector3(26.0, 0.5, 520.0), Vector3(260.0, 0.28, 150.0), "road", false)
	_add_box("NorthernCrossStreet", Vector3(520.0, 0.5, 26.0), Vector3(0.0, 0.28, -100.0), "road", false)
	_add_box("SouthernCrossStreet", Vector3(520.0, 0.5, 26.0), Vector3(0.0, 0.28, 310.0), "road", false)
	_add_box("MarketApproachWest", Vector3(100.0, 0.5, 26.0), Vector3(-310.0, 0.28, 310.0), "road", false)
	_add_box("MarketApproachEast", Vector3(100.0, 0.5, 26.0), Vector3(310.0, 0.28, 310.0), "road", false)
	_add_box("ReincarnationApproach", Vector3(26.0, 0.5, 140.0), Vector3(380.0, 0.28, 535.0), "road", false)


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
		{"name": "南门守城阴兵", "position": Vector3(-52.0, 0.0, 660.0), "patrol_points": [Vector3(0.0, 0.0, -9.0), Vector3(0.0, 0.0, 9.0)]},
		{"name": "南门巡逻阴兵", "position": Vector3(52.0, 0.0, 660.0), "patrol_points": [Vector3(0.0, 0.0, 9.0), Vector3(0.0, 0.0, -9.0)]},
		{"name": "北门守城阴兵", "position": Vector3(-52.0, 0.0, -660.0), "patrol_points": [Vector3(0.0, 0.0, -9.0), Vector3(0.0, 0.0, 9.0)]},
		{"name": "北门巡逻阴兵", "position": Vector3(52.0, 0.0, -660.0), "patrol_points": [Vector3(0.0, 0.0, 9.0), Vector3(0.0, 0.0, -9.0)]},
		{"name": "西门守城阴兵", "position": Vector3(-875.0, 0.0, -52.0), "patrol_points": [Vector3(-9.0, 0.0, 0.0), Vector3(9.0, 0.0, 0.0)]},
		{"name": "东门守城阴兵", "position": Vector3(875.0, 0.0, 52.0), "patrol_points": [Vector3(9.0, 0.0, 0.0), Vector3(-9.0, 0.0, 0.0)]},
		{"name": "皇城巡逻阴兵", "position": Vector3(-92.0, 0.0, -260.0), "patrol_points": [Vector3(0.0, 0.0, -12.0), Vector3(0.0, 0.0, 12.0)]},
		{"name": "皇城巡逻阴兵", "position": Vector3(92.0, 0.0, -260.0), "patrol_points": [Vector3(0.0, 0.0, 12.0), Vector3(0.0, 0.0, -12.0)]},
		{"name": "鬼市巡逻阴兵", "position": Vector3(430.0, 0.0, 420.0), "patrol_points": [Vector3(-10.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), Vector3(10.0, 0.0, 12.0), Vector3(-10.0, 0.0, 12.0)]},
		{"name": "魂坊巡逻阴兵", "position": Vector3(-430.0, 0.0, 420.0), "patrol_points": [Vector3(-10.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), Vector3(10.0, 0.0, 12.0), Vector3(-10.0, 0.0, 12.0)]}
	]
	for index in range(guards.size()):
		var guard_data: Dictionary = guards[index]
		var module := CityModuleScene.instantiate() as Node3D
		module.name = "PatrolGuard_%02d" % index
		guard_data["module_kind"] = "guard"
		module.call("configure", guard_data)
		module.position = guard_data["position"]
		add_child(module)


func _build_named_yin_officials() -> void:
	var officials := [
		{
			"id": "black_impermanence",
			"name": "黑无常 · 范无救",
			"archetype": "black_impermanence",
			"behavior_profile": "soul_capture",
			"interaction_type": "capture_and_escort",
			"quest_id": "black_soul_document",
			"status_text": "拘魂巡查中",
			"position": Vector3(-30.0, 0.0, 585.0),
			"patrol_points": [Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 3.0)],
			"route_speed": 0.7,
			"hat_text": "天下太平",
			"robe_color": "#202127",
			"face_color": "#d8d0c3",
			"trim_color": "#b79a69",
			"authority": "阴司拘魂使 · 黑无常",
			"access": "亡魂接引、拘魂文牒与引魂差事",
			"description": "黑无常范无救，负责拘魂与押送亡魂。交互原型：可查看拘魂文牒、了解押魂流程；当前不创建正式任务，也不改变玩家魂魄状态。"
		},
		{
			"id": "white_impermanence",
			"name": "白无常 · 谢必安",
			"archetype": "white_impermanence",
			"behavior_profile": "soul_guidance",
			"interaction_type": "new_soul_guidance",
			"quest_id": "white_soul_registration",
			"status_text": "接引新魂中",
			"position": Vector3(30.0, 0.0, 585.0),
			"patrol_points": [Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, -3.0)],
			"route_speed": 0.7,
			"hat_text": "一见生财",
			"robe_color": "#e4e0d8",
			"face_color": "#e0d6c8",
			"trim_color": "#8d765b",
			"authority": "阴司拘魂使 · 白无常",
			"access": "新魂登记、引路与轮回指引",
			"description": "白无常谢必安，负责接引与引路。交互原型：可查看新魂登记说明、了解轮回引导流程；当前不登记真实角色数据，也不触发转生。"
		},
		{
			"id": "ox_head",
			"name": "牛头将军",
			"archetype": "ox_head",
			"behavior_profile": "gate_guard",
			"interaction_type": "gate_inspection",
			"quest_id": "ox_gate_records",
			"status_text": "南门盘查中",
			"position": Vector3(-30.0, 0.0, 675.0),
			"patrol_points": [Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)],
			"route_speed": 0.55,
			"robe_color": "#604337",
			"face_color": "#95614b",
			"trim_color": "#b28b56",
			"authority": "南幽门守将 · 牛头",
			"access": "城门盘查、阴兵调度与边境通行",
			"description": "牛头将军驻守南幽门，负责城门盘查与秩序维护。交互原型：展示来魂核验、通行盘查与阴兵调度规则；当前不授予或拒绝真实通行权限。"
		},
		{
			"id": "horse_face",
			"name": "马面将军",
			"archetype": "horse_face",
			"behavior_profile": "gate_patrol",
			"interaction_type": "pass_check",
			"quest_id": "horse_patrol_report",
			"status_text": "南门巡防中",
			"position": Vector3(30.0, 0.0, 675.0),
			"patrol_points": [Vector3(2.0, 0.0, 0.0), Vector3(-2.0, 0.0, 0.0)],
			"route_speed": 0.55,
			"robe_color": "#3d505b",
			"face_color": "#776b61",
			"trim_color": "#a68a62",
			"authority": "南幽门守将 · 马面",
			"access": "城门巡查、通行核验与阴司军令",
			"description": "马面将军与牛头共同守卫南幽门。交互原型：展示通行核验、巡防告示与阴司军令说明；当前不执行服务端门禁或战斗行为。"
		}
	]
	for official_data in officials:
		official_data["module_kind"] = "special_character"
		var official := _spawn_city_module(official_data, official_data["position"])
		official.name = "YinOfficial_" + str(official_data["id"])
		official.connect("player_entered", Callable(self, "_on_district_entered"))
		official.connect("player_exited", Callable(self, "_on_district_exited"))


func _build_citizens() -> void:
	var citizens := [
		{"name": "鬼市灵材商", "role": "鬼市商贩", "position": Vector3(475.0, 0.0, 445.0), "patrol_points": [Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)], "route_speed": 1.2},
		{"name": "鬼市法器商", "role": "鬼市商贩", "position": Vector3(475.0, 0.0, 515.0), "patrol_points": [Vector3(2.0, 0.0, 0.0), Vector3(-2.0, 0.0, 0.0)], "route_speed": 1.0},
		{"name": "鬼市情报贩", "role": "鬼市商贩", "position": Vector3(475.0, 0.0, 585.0), "patrol_points": [Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, 2.0)], "route_speed": 0.9},
		{"name": "魂坊居民", "role": "坊民", "position": Vector3(-475.0, 0.0, 455.0), "patrol_points": [Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)], "route_speed": 1.1},
		{"name": "魂坊工匠", "role": "坊民", "position": Vector3(-475.0, 0.0, 545.0), "patrol_points": [Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, 3.0)], "route_speed": 0.8},
		{"name": "魂坊引路人", "role": "坊民", "position": Vector3(-475.0, 0.0, 625.0), "patrol_points": [Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)], "route_speed": 1.0},
		{"name": "鬼籍登记书吏", "role": "鬼籍书吏", "position": Vector3(-475.0, 0.0, 250.0)},
		{"name": "功过司文吏", "role": "判官文吏", "position": Vector3(475.0, 0.0, 250.0)},
		{"name": "巡城司值守", "role": "判官文吏", "position": Vector3(155.0, 0.0, 245.0)},
		{"name": "引魂驿接引使", "role": "引魂使", "position": Vector3(762.0, 0.0, 95.0)},
		{"name": "十王府案牍吏", "role": "判官文吏", "position": Vector3(-475.0, 0.0, -115.0)},
		{"name": "判官司执事", "role": "判官文吏", "position": Vector3(475.0, 0.0, -115.0)},
		{"name": "轮回司引路使", "role": "引魂使", "position": Vector3(380.0, 0.0, 500.0)}
	]
	for index in range(citizens.size()):
		var citizen_data: Dictionary = citizens[index]
		citizen_data["module_kind"] = "citizen"
		var citizen_module := _spawn_city_module(citizen_data, citizen_data["position"])
		citizen_module.name = "Citizen_%02d" % index


func _build_street_furniture() -> void:
	for side in [-1.0, 1.0]:
		for index in range(5):
			var z := -70.0 + float(index) * 110.0
			var post_position := Vector3(side * 278.0, 4.5, z)
			_add_box("InnerStreetLampPost_%s_%d" % [side, index], Vector3(2.4, 9.0, 2.4), post_position, "stone", true)
			_add_box("InnerStreetLampGlow_%s_%d" % [side, index], Vector3(3.2, 3.2, 3.2), post_position + Vector3.UP * 5.6, "lantern", false)
	for index in range(8):
		var x := -770.0 + float(index) * 220.0
		for side in [-1.0, 1.0]:
			var p := Vector3(x, 4.5, side * 42.0)
			_add_box("CrossAvenueLampPost_%d_%s" % [index, side], Vector3(2.2, 9.0, 2.2), p, "stone", true)
			_add_box("CrossAvenueLampGlow_%d_%s" % [index, side], Vector3(3.0, 3.0, 3.0), p + Vector3.UP * 5.6, "lantern", false)
	_add_box("CentralAvenuePlaza", Vector3(110.0, 0.5, 110.0), Vector3(0.0, 0.3, 0.0), "road_edge", false)


func _on_district_entered(data: Dictionary) -> void:
	_nearby_district_data = data.duplicate(true)
	var title := str(data.get("name", "城区"))
	_hint_label.text = "已接近：%s · 按 E 交谈 / 查看" % title


func _open_interaction_dialogue(data: Dictionary) -> void:
	if _dialogue_panel == null:
		return
	_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var target_id := str(data.get("id", ""))
	var quest_progressed := false
	if _quest_manager != null:
		quest_progressed = bool(_quest_manager.call("notify_interaction", target_id))
	if quest_progressed:
		_hint_label.text = "差事目标已更新 · 按 J 查看阴司差事簿"
	var quest_id := str(data.get("quest_id", ""))
	var quest_data: Dictionary = _quest_manager.call("get_quest", quest_id) if _quest_manager != null and not quest_id.is_empty() else {}
	if not quest_data.is_empty():
		quest_data["can_accept"] = bool(_quest_manager.call("can_accept_quest", quest_id))
	_dialogue_panel.call("present", data, quest_data)


func _on_quest_updated(quest_data: Dictionary) -> void:
	if _dialogue_panel != null:
		_dialogue_panel.call("update_quest_state", quest_data)


func _on_quest_action_requested(action: String, quest_id: String) -> void:
	if _quest_manager == null:
		return
	if action == "accept":
		_quest_manager.call("accept_quest", quest_id)
	elif action == "journal":
		if _quest_journal != null:
			_quest_journal.call("toggle")


func _toggle_quest_journal() -> void:
	if _quest_journal == null:
		return
	if _dialogue_panel != null and _dialogue_panel.call("is_open"):
		_dialogue_panel.call("close_dialogue")
	_mouse_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_quest_journal.call("toggle")


func _on_district_exited(data: Dictionary) -> void:
	if str(_nearby_district_data.get("id", "")) == str(data.get("id", "")):
		_nearby_district_data.clear()
		if _dialogue_panel == null or not _dialogue_panel.call("is_open"):
			_hint_label.text = "WASD 移动 · 鼠标观察 · Shift 奔跑 · Space 跳跃 · E 交谈 / 查看 · Esc 释放鼠标"


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
	_camera_pivot.position = Vector3(0.0, 2.8, 0.0)
	_player.add_child(_camera_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 74.0
	_camera.position = Vector3(0.0, 0.0, 5.5)
	_camera_pivot.add_child(_camera)
	add_child(_player)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GreyboxHUD"
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(560.0, 184.0)
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
	_hint_label.text = "WASD 移动 · 鼠标观察 · Shift 奔跑 · Space 跳跃 · E 交谈 / 查看 · Esc 释放鼠标"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint_label)
	var note := Label.new()
	note.text = "南门入城：牛头马面镇守城门，黑白无常接引新魂。当前为比例灰盒，NPC 对话与行为状态为本地原型。"
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var journal_button := Button.new()
	journal_button.text = "打开阴司差事簿  [J]"
	journal_button.custom_minimum_size = Vector2(220.0, 34.0)
	journal_button.pressed.connect(_toggle_quest_journal)
	column.add_child(journal_button)
	add_child(layer)

	_quest_manager = FengduQuestManager.new()
	_quest_manager.name = "FengduQuestManager"
	add_child(_quest_manager)
	_quest_journal = FengduQuestJournal.new()
	_quest_journal.name = "FengduQuestJournal"
	add_child(_quest_journal)
	_quest_journal.call("configure", _quest_manager)
	_quest_tracker = FengduQuestTracker.new()
	_quest_tracker.name = "FengduQuestTracker"
	add_child(_quest_tracker)
	_quest_tracker.call("configure", _quest_manager)

	_dialogue_panel = NpcDialoguePanel.new()
	_dialogue_panel.name = "NpcDialoguePanel"
	_dialogue_panel.connect("closed", Callable(self, "_on_dialogue_closed"))
	_dialogue_panel.connect("quest_action_requested", Callable(self, "_on_quest_action_requested"))
	_quest_manager.connect("quest_updated", Callable(self, "_on_quest_updated"))
	add_child(_dialogue_panel)


func _on_dialogue_closed() -> void:
	if _nearby_district_data.is_empty():
		_hint_label.text = "WASD 移动 · 鼠标观察 · Shift 奔跑 · Space 跳跃 · E 交谈 / 查看 · Esc 释放鼠标"
	else:
		_hint_label.text = "已接近：%s · 按 E 交谈 / 查看" % str(_nearby_district_data.get("name", "目标"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_captured = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J:
			_toggle_quest_journal()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and _quest_journal != null and _quest_journal.call("is_open"):
			_quest_journal.call("close_journal")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and _dialogue_panel != null and _dialogue_panel.call("is_open"):
			_dialogue_panel.call("close_dialogue")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and not _nearby_district_data.is_empty():
			_open_interaction_dialogue(_nearby_district_data)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _dialogue_panel != null and _dialogue_panel.call("is_open"):
				_dialogue_panel.call("close_dialogue")
				get_viewport().set_input_as_handled()
			if _quest_journal != null and _quest_journal.call("is_open"):
				_quest_journal.call("close_journal")
				get_viewport().set_input_as_handled()
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
	if (_dialogue_panel != null and _dialogue_panel.call("is_open")) or (_quest_journal != null and _quest_journal.call("is_open")):
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
		if not _player.is_on_floor():
			_player.velocity.y -= 24.0 * delta
		_player.move_and_slide()
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
