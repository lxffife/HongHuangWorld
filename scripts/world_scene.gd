extends Node3D

const UnderworldVisualFactory = preload("res://scripts/underworld_visual_factory.gd")

@onready var hud_label: Label = $HUD/Panel/Margin/Content/Status
@onready var progression_label: Label = $HUD/Panel/Margin/Content/Progression
@onready var breakthrough_button: Button = $HUD/Panel/Margin/Content/Breakthrough
@onready var awaken_bloodline_button: Button = $HUD/Panel/Margin/Content/AwakenBloodline
@onready var train_technique_button: Button = $HUD/Panel/Margin/Content/TrainTechnique
@onready var attribute_points_label: Label = $HUD/Panel/Margin/Content/AttributePoints
@onready var strength_button: Button = $HUD/Panel/Margin/Content/AttributeButtons/Strength
@onready var constitution_button: Button = $HUD/Panel/Margin/Content/AttributeButtons/Constitution
@onready var agility_button: Button = $HUD/Panel/Margin/Content/AttributeButtons/Agility
@onready var spirit_button: Button = $HUD/Panel/Margin/Content/AttributeButtons/Spirit
@onready var vitality_button: Button = $HUD/Panel/Margin/Content/AttributeButtons/Vitality
@onready var reconnect_button: Button = $HUD/Panel/Margin/Content/Reconnect

var respawn_http: HTTPRequest
var respawn_button: Button
var respawn_busy := false
var progression_http: HTTPRequest
var soul_essence_http: HTTPRequest
var soul_essence_profile: Dictionary = {}
var soul_essence_request_busy := false
var soul_choice_http: HTTPRequest
var soul_choice_request_busy := false
var pending_rare_choice_dialog: ConfirmationDialog
var pending_rare_choice_option: OptionButton
var pending_rare_choice_record_id := ""
var soul_choice_button: Button
var progression_request_context := ""
var reconnect_http: HTTPRequest
var reconnect_network: HHWorldNetwork
var reconnect_request_busy := false
var chat_panel: PanelContainer
var chat_log: VBoxContainer
var chat_input: LineEdit
var chat_status: Label
var chat_expanded := false
var chat_lines_by_channel: Dictionary = {"nearby": [], "world": [], "cross_world": []}
var chat_seen_ids: Dictionary = {}
var selected_chat_channel := "nearby"

var local_player: Variant
var hud_visible := true
var death_panel: PanelContainer
var death_message_label: Label
var compact_hud_panel: PanelContainer
var compact_hud_label: Label
var details_toggle_button: Button
var details_visible := false
var vitals_panel: PanelContainer
var health_label: Label
var health_bar: ProgressBar
var notification_panel: PanelContainer
var notification_label: Label
var notification_timer: Timer
var vitals_known := false
var input_debug_panel: PanelContainer
var input_debug_label: Label
var input_debug_visible := false
var input_debug_accumulator := 0.0
var region_update_accumulator := 0.0
var current_region_name := ""
var local_target_position := Vector3.ZERO
var remote_players: Dictionary = {}
var remote_targets: Dictionary = {}
var remote_yaws: Dictionary = {}
var monsters: Dictionary = {}
var monster_targets: Dictionary = {}
var monster_entities: Dictionary = {}
var monster_animation_time := 0.0
var selected_monster_id := ""
var target_info_panel: PanelContainer
var target_info_label: Label
var target_selection_ring: MeshInstance3D
var floating_combat_labels: Dictionary = {}
var floating_combat_lifetimes: Dictionary = {}
var drops: Dictionary = {}
var drop_targets: Dictionary = {}
var inventory_http: HTTPRequest
var inventory_button: Button
var inventory_panel: PanelContainer
var inventory_status: Label
var inventory_items: VBoxContainer
var inventory_cache: Array = []
var inventory_filter := "all"
var inventory_sort_mode := "quality"
var inventory_sort_option: OptionButton
var inventory_equipment: VBoxContainer
var equipment_http: HTTPRequest
var equipment_action_http: HTTPRequest
var consumable_http: HTTPRequest
var consumable_busy := false
var equipment_action_busy := false
var inventory_visible := false
var inventory_request_busy := false

var npc_http: HTTPRequest
var npc_request_context := ""
var npc_definitions: Array = []
var npc_nodes: Dictionary = {}
var npc_animation_time := 0.0
var npc_panel: PanelContainer
var npc_title_label: Label
var npc_dialogue_label: Label
var npc_status_label: Label
var npc_choice_container: VBoxContainer
var npc_interact_button: Button
var npc_trial_button: Button
var npc_eligibility_button: Button
var npc_soul_button: Button
var npc_fusion_button: Button
var npc_soul_breakthrough_button: Button
var npc_reincarnation_leave_button: Button
var npc_fate_encounter_button: Button
var exploration_open_button: Button
var exploration_container: VBoxContainer
var exploration_progress_label: Label
var exploration_feedback := ""
var exploration_markers: Dictionary = {}
var exploration_buttons: Dictionary = {}
var exploration_point_data: Dictionary = {}
var exploration_event_buttons: Dictionary = {}
var exploration_event_data: Dictionary = {}
var pending_exploration_event_id := ""
var exploration_animation_time := 0.0
var npc_current_interaction_id := ""
var leaving_for_reincarnation := false
var npc_selected_id := ""
var npc_request_busy := false

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_player()
	_build_compact_hud()
	_build_chat_hud()
	if not HHChatNetwork.message_received.is_connected(_on_chat_socket_message):
		HHChatNetwork.message_received.connect(_on_chat_socket_message)
	if not HHChatNetwork.history_received.is_connected(_on_chat_history_received):
		HHChatNetwork.history_received.connect(_on_chat_history_received)
	if not HHChatNetwork.connected.is_connected(_on_chat_socket_connected):
		HHChatNetwork.connected.connect(_on_chat_socket_connected)
	if not HHChatNetwork.connection_error.is_connected(_on_chat_socket_error):
		HHChatNetwork.connection_error.connect(_on_chat_socket_error)
	if not HHSession.access_token.is_empty():
		HHChatNetwork.connect_chat(HHSession.get_chat_api_base(), HHSession.access_token)
	_build_combat_hud()
	_build_input_debug_hud()
	if HHSession.world_network != null:
		HHSession.world_network.entities_updated.connect(_on_entities_updated)
		HHSession.world_network.player_joined.connect(_on_player_joined)
		HHSession.world_network.player_left.connect(_on_player_left)
		HHSession.world_network.combat_event.connect(_on_combat_event)
		HHSession.world_network.monster_action_event.connect(_on_monster_action_event)
		HHSession.world_network.pickup_event.connect(_on_pickup_event)
		HHSession.world_network.chat_event.connect(_on_chat_event)
		HHSession.world_network.disconnected.connect(_on_world_disconnected)
		var spawn: Dictionary = HHSession.world_snapshot
		local_target_position = Vector3(float(spawn.get("position_x", 0.0)), float(spawn.get("position_y", 0.15)), float(spawn.get("position_z", 0.0)))
		local_player.position = local_target_position
	_refresh_current_region(false)
	_update_hud()
	progression_http = HTTPRequest.new()
	progression_http.timeout = 10.0
	add_child(progression_http)
	progression_http.request_completed.connect(_on_progression_request_completed)
	soul_essence_http = HTTPRequest.new()
	soul_essence_http.timeout = 10.0
	add_child(soul_essence_http)
	soul_essence_http.request_completed.connect(_on_soul_essence_request_completed)
	soul_choice_http = HTTPRequest.new()
	soul_choice_http.timeout = 10.0
	add_child(soul_choice_http)
	soul_choice_http.request_completed.connect(_on_soul_choice_request_completed)
	_build_soul_choice_ui()
	_apply_world_player_form()
	_request_soul_essence()
	respawn_http = HTTPRequest.new()
	respawn_http.timeout = 12.0
	add_child(respawn_http)
	respawn_http.request_completed.connect(_on_respawn_request_completed)
	breakthrough_button.pressed.connect(_on_breakthrough_pressed)
	awaken_bloodline_button.pressed.connect(_on_awaken_bloodline_pressed)
	train_technique_button.pressed.connect(_on_train_technique_pressed)
	strength_button.pressed.connect(_on_allocate_attribute_pressed.bind("strength"))
	constitution_button.pressed.connect(_on_allocate_attribute_pressed.bind("constitution"))
	agility_button.pressed.connect(_on_allocate_attribute_pressed.bind("agility"))
	spirit_button.pressed.connect(_on_allocate_attribute_pressed.bind("spirit"))
	vitality_button.pressed.connect(_on_allocate_attribute_pressed.bind("vitality"))
	reconnect_button.pressed.connect(_on_reconnect_pressed)
	reconnect_http = HTTPRequest.new()
	reconnect_http.timeout = 12.0
	add_child(reconnect_http)
	reconnect_http.request_completed.connect(_on_reconnect_request_completed)
	_refresh_character_status()
	_build_inventory_ui()
	_build_npc_ui()
	_build_death_ui()
	_request_world_npcs()
	_show_notification("已进入「" + _world_display_name(str(HHSession.world_snapshot.get("world_id", ""))) + "」", 5.0)

func _refresh_character_status() -> void:
	if HHSession.access_token.is_empty():
		progression_label.text = "角色修炼信息暂不可用：缺少登录凭证"
		breakthrough_button.disabled = true
		return
	progression_request_context = "status"
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var error := progression_http.request(
		HHSession.api_base + "/api/v1/characters/current/status",
		headers,
		HTTPClient.METHOD_GET
	)
	if error != OK:
		progression_label.text = "读取修炼状态失败，错误码：" + str(error)

func _on_breakthrough_pressed() -> void:
	if progression_request_context != "":
		return
	breakthrough_button.disabled = true
	progression_label.text = "正在向中心服申请突破……"
	progression_request_context = "breakthrough"
	var headers := PackedStringArray([
		"Authorization: Bearer " + HHSession.access_token,
		"Content-Type: application/json"
	])
	var error := progression_http.request(
		HHSession.api_base + "/api/v1/characters/current/breakthrough",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	if error != OK:
		progression_request_context = ""
		progression_label.text = "提交突破失败，错误码：" + str(error)
		breakthrough_button.disabled = false

func _on_awaken_bloodline_pressed() -> void:
	var primary_id := str(HHSession.world_snapshot.get("primary_bloodline_id", ""))
	if primary_id.is_empty():
		primary_id = str(get_meta("primary_bloodline_id", ""))
	if primary_id.is_empty():
		progression_label.text = "当前角色没有可觉醒的血脉。"
		return
	_submit_growth_action("bloodlines/awaken", {"bloodline_id": primary_id}, "awaken")

func _on_train_technique_pressed() -> void:
	var technique_id := str(get_meta("starter_technique_id", ""))
	if technique_id.is_empty():
		progression_label.text = "当前角色没有已拥有的功法。"
		return
	_submit_growth_action("techniques/train", {"technique_id": technique_id, "points": 1}, "train")

func _on_allocate_attribute_pressed(attribute: String) -> void:
	if progression_request_context != "":
		return
	_submit_growth_action("attributes/allocate", {"attribute": attribute, "points": 1}, "attribute")


func _submit_growth_action(path: String, payload: Dictionary, context: String) -> void:
	if progression_request_context != "":
		return
	progression_request_context = context
	awaken_bloodline_button.disabled = true
	train_technique_button.disabled = true
	for button in [strength_button, constitution_button, agility_button, spirit_button, vitality_button]:
		button.disabled = true
	progression_label.text = "正在向中心服提交成长请求……"
	var headers := PackedStringArray([
		"Authorization: Bearer " + HHSession.access_token,
		"Content-Type: application/json"
	])
	var error := progression_http.request(
		HHSession.api_base + "/api/v1/characters/current/" + path,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		progression_request_context = ""
		progression_label.text = "提交成长请求失败，错误码：" + str(error)
		_refresh_character_status()

func _on_progression_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var context := progression_request_context
	progression_request_context = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		progression_label.text = "修炼服务连接失败，请检查中心服。"
		breakthrough_button.disabled = false
		awaken_bloodline_button.disabled = false
		train_technique_button.disabled = false
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if context == "breakthrough":
		if response_code >= 200 and response_code < 300:
			if bool(data.get("advanced_realm", false)):
				progression_label.text = "大境界突破成功！正在刷新修炼状态……"
			else:
				progression_label.text = "小境界突破成功！正在刷新修炼状态……"
			_refresh_character_status()
			return
		progression_label.text = "突破未成功：" + body.get_string_from_utf8()
		breakthrough_button.disabled = false
		return
	if context == "awaken" or context == "train" or context == "attribute":
		if response_code >= 200 and response_code < 300:
			if context == "awaken":
				progression_label.text = "血脉觉醒成功，正在刷新状态……"
			elif context == "train":
				progression_label.text = "功法修炼成功，正在刷新状态……"
			else:
				progression_label.text = "属性分配成功，正在刷新状态……"
			_refresh_character_status()
			return
		progression_label.text = "成长操作未完成：" + body.get_string_from_utf8()
		_refresh_character_status()
		return
	if response_code < 200 or response_code >= 300:
		progression_label.text = "读取修炼状态失败：" + body.get_string_from_utf8()
		breakthrough_button.disabled = true
		return
	var progression: Dictionary = data.get("progression", {})
	var cultivation := int(progression.get("cultivation", 0))
	var bloodlines: Array = data.get("bloodlines", [])
	var primary_bloodline := "未觉醒"
	var bloodline_purity := 0
	var primary_bloodline_id := ""
	var awakening_stage := 0
	for bloodline_variant in bloodlines:
		if bloodline_variant is Dictionary and bool(bloodline_variant.get("is_primary", false)):
			primary_bloodline = str(bloodline_variant.get("name", "未知血脉"))
			bloodline_purity = int(bloodline_variant.get("purity", 0))
			primary_bloodline_id = str(bloodline_variant.get("id", ""))
			awakening_stage = int(bloodline_variant.get("awakening_stage", 0))
			break
	set_meta("primary_bloodline_id", primary_bloodline_id)
	var techniques: Array = data.get("techniques", [])
	var starter_technique_id := ""
	var starter_technique_name := "暂无已拥有功法"
	var starter_technique_grade := 0
	var starter_technique_proficiency := 0
	for technique_variant in techniques:
		if technique_variant is Dictionary:
			starter_technique_id = str(technique_variant.get("id", ""))
			starter_technique_name = str(technique_variant.get("name", "未知功法"))
			starter_technique_grade = int(technique_variant.get("grade", 0))
			starter_technique_proficiency = int(technique_variant.get("proficiency", 0))
			break
	set_meta("starter_technique_id", starter_technique_id)
	awaken_bloodline_button.text = "觉醒血脉 · " + primary_bloodline + "（" + str(awakening_stage) + "/9）"
	awaken_bloodline_button.disabled = primary_bloodline_id.is_empty() or awakening_stage >= 9
	train_technique_button.text = "修炼功法 · " + starter_technique_name + "（熟练度 " + str(starter_technique_proficiency) + "）"
	train_technique_button.disabled = starter_technique_id.is_empty() or cultivation < starter_technique_grade * 100
	var attributes: Dictionary = data.get("attributes", {})
	var unspent_points := int(progression.get("unspent_attribute_points", 0))
	attribute_points_label.text = "可分配属性点：" + str(unspent_points) + "  |  力量 " + str(attributes.get("strength", 0)) + " · 体魄 " + str(attributes.get("constitution", 0)) + " · 敏捷 " + str(attributes.get("agility", 0)) + " · 灵识 " + str(attributes.get("spirit", 0)) + " · 元气 " + str(attributes.get("vitality", 0))
	for button in [strength_button, constitution_button, agility_button, spirit_button, vitality_button]:
		button.disabled = unspent_points <= 0
	var system_name := str(progression.get("system_name", "未知体系"))
	var realm_name := str(progression.get("realm_name", "未知境界"))
	var stage_name := str(progression.get("realm_stage_name", ""))
	var tier_name := str(progression.get("power_tier_name", "未映射"))
	var next_stage: Variant = progression.get("required_for_next_stage", null)
	var next_realm: Variant = progression.get("required_for_next_realm", null)
	var threshold_text := ""
	if next_stage != null:
		threshold_text = "下一阶段修为：" + str(next_stage)
	elif next_realm != null:
		threshold_text = "大境界突破修为：" + str(next_realm)
	else:
		threshold_text = "已达到当前体系最高配置境界"
	_update_compact_hud(progression)
	progression_label.text = system_name + " · " + realm_name + stage_name + "\n累计修为：" + str(cultivation) + "  |  跨族参考：" + tier_name + "\n主血脉：" + primary_bloodline + "（纯度 " + str(bloodline_purity) + "/10000）\n" + threshold_text
	breakthrough_button.disabled = next_stage == null and next_realm == null

func _build_environment() -> void:
	var world_id := str(HHSession.world_snapshot.get("world_id", "qingyun_human"))
	var is_underworld := world_id == "underworld_fengdu"
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	if is_underworld:
		sky_material.sky_top_color = Color("#080d20")
		sky_material.sky_horizon_color = Color("#382b4d")
		sky_material.ground_bottom_color = Color("#080b14")
		sky_material.ground_horizon_color = Color("#241d32")
	else:
		sky_material.sky_top_color = Color("#142b49")
		sky_material.sky_horizon_color = Color("#d3a878")
		sky_material.ground_bottom_color = Color("#182333")
		sky_material.ground_horizon_color = Color("#a58b6b")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#66708f") if is_underworld else Color("#9fb4d0")
	environment.ambient_light_energy = 0.32 if is_underworld else 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#51445f") if is_underworld else Color("#9ba9b8")
	environment.fog_density = 0.012 if is_underworld else 0.0018
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 0.42 if is_underworld else 1.35
	sun.light_color = Color("#9a8abf") if is_underworld else Color("#fff0d2")
	sun.shadow_enabled = true
	add_child(sun)

func _add_world_box(node_name: String, size: Vector3, world_position: Vector3, color: Color, emissive: bool = false) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = world_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
	instance.material_override = material
	add_child(instance)

func _add_world_landmark_label(node_name: String, text_value: String, world_position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text_value
	label.position = world_position
	label.font_size = 42
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	add_child(label)

func _add_world_cylinder(node_name: String, radius: float, height: float, world_position: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	instance.mesh = cylinder
	instance.position = world_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	instance.material_override = material
	add_child(instance)

func _build_terrain() -> void:
	var world_id := str(HHSession.world_snapshot.get("world_id", "qingyun_human"))
	var is_underworld := world_id == "underworld_fengdu"
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(240.0, 240.0)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#211f30") if is_underworld else Color("#354c43")
	material.roughness = 0.94
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(240.0, 0.2, 240.0)
	collision.shape = shape
	collision.position.y = -0.1
	ground.add_child(collision)
	add_child(ground)

	if is_underworld:
		# Fengdu gate and the soul lantern avenue.
		add_child(UnderworldVisualFactory.create_fengdu_gate())
		for side in [-1.0, 1.0]:
			var lantern_position := Vector3(side * 7.0, 2.1, -14.0)
			_add_world_box("SoulLanternStone_" + str(side), Vector3(0.8, 2.2, 0.8), lantern_position, Color("#393344"))
			var flame := MeshInstance3D.new()
			flame.name = "SoulLanternFlame_" + str(side)
			var flame_mesh := SphereMesh.new()
			flame_mesh.radius = 0.34
			flame_mesh.height = 0.9
			flame.mesh = flame_mesh
			flame.position = lantern_position + Vector3(0.0, 1.45, 0.0)
			var flame_material := StandardMaterial3D.new()
			flame_material.albedo_color = Color("#82a8d8")
			flame_material.emission_enabled = true
			flame_material.emission = Color("#537fc4")
			flame_material.emission_energy_multiplier = 2.4
			flame.material_override = flame_material
			add_child(flame)
		for i in range(8):
			var x := -24.0 + float(i) * 7.0
			var height := 2.8 + float(i % 3) * 0.8
			_add_world_box("UnderworldStele_" + str(i), Vector3(0.9, height, 0.8), Vector3(x, height * 0.5, -31.0), Color("#373342"))

		# The River of Forgetfulness runs north-south; a stone bridge crosses it.
		var river := MeshInstance3D.new()
		river.name = "RiverOfForgetfulness"
		var river_mesh := PlaneMesh.new()
		river_mesh.size = Vector2(8.0, 150.0)
		river.mesh = river_mesh
		river.position = Vector3(22.0, 0.045, 8.0)
		var water_material := StandardMaterial3D.new()
		water_material.albedo_color = Color(0.18, 0.34, 0.52, 0.78)
		water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_material.metallic = 0.28
		water_material.roughness = 0.2
		water_material.emission_enabled = true
		water_material.emission = Color("#243f70")
		water_material.emission_energy_multiplier = 0.45
		river.material_override = water_material
		add_child(river)
		for side in [-1.0, 1.0]:
			_add_world_box("RiverBank_" + str(side), Vector3(1.0, 0.65, 150.0), Vector3(22.0 + side * 4.5, 0.22, 8.0), Color("#383344"))
		_add_world_box("NaiheBridgeDeck", Vector3(13.0, 0.65, 3.2), Vector3(22.0, 0.72, 2.0), Color("#777080"))
		_add_world_box("NaiheBridgeRailLeft", Vector3(13.0, 0.8, 0.28), Vector3(22.0, 1.38, 0.45), Color("#9b91a3"))
		_add_world_box("NaiheBridgeRailRight", Vector3(13.0, 0.8, 0.28), Vector3(22.0, 1.38, 3.55), Color("#9b91a3"))
		for i in range(7):
			var x := 16.5 + float(i) * 1.85
			_add_world_box("BridgePostL_" + str(i), Vector3(0.32, 1.2, 0.32), Vector3(x, 1.55, 0.45), Color("#aaa0ae"))
			_add_world_box("BridgePostR_" + str(i), Vector3(0.32, 1.2, 0.32), Vector3(x, 1.55, 3.55), Color("#aaa0ae"))
		_add_world_landmark_label("NaiheBridgeName", "奈何桥", Vector3(22.0, 3.1, 2.0), Color("#b8c9e8"))

		# Distant reincarnation hall silhouette, placed beyond the gate avenue.
		_add_world_box("ReincarnationHallBase", Vector3(22.0, 1.2, 12.0), Vector3(-22.0, 0.6, -55.0), Color("#383344"))
		_add_world_box("ReincarnationHallBody", Vector3(16.0, 7.0, 9.0), Vector3(-22.0, 4.1, -55.0), Color("#51465c"))
		_add_world_box("ReincarnationHallRoof", Vector3(20.0, 1.0, 12.0), Vector3(-22.0, 8.1, -55.0), Color("#292536"))
		_add_world_box("ReincarnationHallRoofTop", Vector3(12.0, 0.7, 8.0), Vector3(-22.0, 9.0, -55.0), Color("#65536d"))
		_add_world_landmark_label("ReincarnationHallName", "轮回殿", Vector3(-22.0, 11.0, -54.0), Color("#c4b6dc"))
	else:
		# Qingyun mountain gate, a stone path, and layered pine silhouettes.
		_add_world_box("QingyunGateLeft", Vector3(1.1, 6.5, 1.1), Vector3(-5.0, 3.25, -22.0), Color("#777d70"))
		_add_world_box("QingyunGateRight", Vector3(1.1, 6.5, 1.1), Vector3(5.0, 3.25, -22.0), Color("#777d70"))
		_add_world_box("QingyunGateBeam", Vector3(12.0, 1.0, 1.5), Vector3(0.0, 6.7, -22.0), Color("#a18a61"))
		_add_world_box("QingyunGatePlaque", Vector3(3.8, 1.2, 0.35), Vector3(0.0, 6.0, -20.9), Color("#354c43"))
		_add_world_landmark_label("QingyunGateName", "青云山门", Vector3(0.0, 8.3, -21.5), Color("#f0d7a8"))
		for i in range(12):
			var z := -4.0 - float(i) * 3.0
			var width := 5.5 if i < 7 else 7.0
			_add_world_box("QingyunPathStone_" + str(i), Vector3(width, 0.12, 2.2), Vector3(0.0, 0.04, z), Color("#777e70"))
		for i in range(16):
			var side := -1.0 if i % 2 == 0 else 1.0
			var row := float(i / 2)
			var x := side * (9.0 + float(i % 3) * 2.0)
			var z := -8.0 - row * 7.0
			_add_world_cylinder("QingyunPineTrunk_" + str(i), 0.28, 2.8, Vector3(x, 1.4, z), Color("#514638"))
			var crown := MeshInstance3D.new()
			crown.name = "QingyunPineCrown_" + str(i)
			var cone := ConeMesh.new()
			cone.bottom_radius = 2.0
			cone.height = 5.2
			crown.mesh = cone
			crown.position = Vector3(x, 4.4, z)
			var pine_material := StandardMaterial3D.new()
			pine_material.albedo_color = Color("#294b3d")
			pine_material.roughness = 1.0
			crown.material_override = pine_material
			add_child(crown)
		# Natural rocks frame the path without obscuring the spawn area.
		for i in range(12):
			var rock := MeshInstance3D.new()
			var rock_mesh := SphereMesh.new()
			rock_mesh.radius = randf_range(0.7, 2.0)
			rock_mesh.height = rock_mesh.radius * 1.5
			rock.mesh = rock_mesh
			rock.position = Vector3(randf_range(-28.0, 28.0), rock_mesh.radius * 0.35, randf_range(-28.0, 28.0))
			var rock_material := StandardMaterial3D.new()
			rock_material.albedo_color = Color("#53645d")
			rock_material.roughness = 1.0
			rock.material_override = rock_material
			add_child(rock)

func _build_player() -> void:
	# Avoid a global class-cache dependency for the player controller. This also
	# makes a missing/invalid controller report at the point where it is created.
	var controller_script := load("res://scripts/player_controller.gd") as Script
	if controller_script == null:
		push_error("无法加载玩家控制器：res://scripts/player_controller.gd")
		return
	var controller_instance: Variant = controller_script.new()
	if not (controller_instance is CharacterBody3D):
		push_error("玩家控制器脚本必须继承 CharacterBody3D。")
		return
	local_player = controller_instance
	local_player.name = "LocalPlayer"
	local_player.position = Vector3(0.0, 0.15, 0.0)
	add_child(local_player)

func _build_compact_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	$HUD/Panel.visible = false
	$HUD/Panel.offset_top = 146.0
	$HUD/Panel.offset_bottom = 548.0
	compact_hud_panel = PanelContainer.new()
	compact_hud_panel.position = Vector2(18.0, 18.0)
	compact_hud_panel.custom_minimum_size = Vector2(340.0, 92.0)
	var compact_style := StyleBoxFlat.new()
	compact_style.bg_color = Color(0.035, 0.055, 0.085, 0.88)
	compact_style.border_color = Color("#526783")
	compact_style.set_border_width_all(1)
	compact_style.set_corner_radius_all(9)
	compact_style.content_margin_left = 12.0
	compact_style.content_margin_top = 9.0
	compact_style.content_margin_right = 12.0
	compact_style.content_margin_bottom = 9.0
	compact_hud_panel.add_theme_stylebox_override("panel", compact_style)
	hud.add_child(compact_hud_panel)
	compact_hud_label = Label.new()
	compact_hud_label.text = "洪荒 · 正在载入角色状态……"
	compact_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compact_hud_label.custom_minimum_size = Vector2(316.0, 72.0)
	compact_hud_label.add_theme_font_size_override("font_size", 13)
	compact_hud_label.add_theme_color_override("font_color", Color("#e2e8f0"))
	compact_hud_panel.add_child(compact_hud_label)
	details_toggle_button = Button.new()
	details_toggle_button.text = "角色 · 修炼"
	details_toggle_button.position = Vector2(18.0, 118.0)
	details_toggle_button.custom_minimum_size = Vector2(112.0, 34.0)
	details_toggle_button.pressed.connect(_toggle_details_panel)
	hud.add_child(details_toggle_button)
	soul_choice_button = Button.new()
	soul_choice_button.text = "分配无相灵魄"
	soul_choice_button.position = Vector2(140.0, 118.0)
	soul_choice_button.custom_minimum_size = Vector2(150.0, 34.0)
	soul_choice_button.visible = false
	soul_choice_button.pressed.connect(_open_pending_rare_choice)
	hud.add_child(soul_choice_button)

func _build_soul_choice_ui() -> void:
	pending_rare_choice_dialog = ConfirmationDialog.new()
	pending_rare_choice_dialog.title = "无相灵魄 · 选择来世资质"
	pending_rare_choice_dialog.dialog_text = "选择一项属性，永久记入灵魂的来世资质。每枚无相灵魄只能分配一次。"
	pending_rare_choice_dialog.min_size = Vector2i(420, 190)
	pending_rare_choice_option = OptionButton.new()
	pending_rare_choice_option.add_item("力量 · 攻击成长")
	pending_rare_choice_option.add_item("体质 · 防御成长")
	pending_rare_choice_option.add_item("敏捷 · 身法成长")
	pending_rare_choice_option.add_item("灵力 · 法术成长")
	pending_rare_choice_option.add_item("气血 · 生命成长")
	pending_rare_choice_option.position = Vector2(24.0, 82.0)
	pending_rare_choice_option.custom_minimum_size = Vector2(360.0, 38.0)
	pending_rare_choice_option.size = Vector2(360.0, 38.0)
	pending_rare_choice_dialog.add_child(pending_rare_choice_option)
	pending_rare_choice_dialog.confirmed.connect(_submit_rare_essence_choice)
	add_child(pending_rare_choice_dialog)

func _open_pending_rare_choice() -> void:
	var pending: Array = soul_essence_profile.get("pending_rare_choices", [])
	if pending.is_empty():
		return
	pending_rare_choice_record_id = str(pending[0].get("record_id", ""))
	pending_rare_choice_option.select(0)
	pending_rare_choice_dialog.popup_centered()

func _submit_rare_essence_choice() -> void:
	if pending_rare_choice_record_id.is_empty() or soul_choice_request_busy or HHSession.access_token.is_empty():
		return
	var attributes := ["strength", "constitution", "agility", "spirit", "vitality"]
	var payload := {"record_id": pending_rare_choice_record_id, "attribute": attributes[pending_rare_choice_option.selected]}
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token, "Content-Type: application/json"])
	soul_choice_request_busy = true
	var error := soul_choice_http.request(HHSession.api_base + "/api/v1/souls/current/essence/allocate", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		soul_choice_request_busy = false
		_show_notification("无相灵魄分配请求失败：" + str(error), 4.0)

func _on_soul_choice_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	soul_choice_request_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_show_notification("无相灵魄分配失败（HTTP " + str(response_code) + "）", 4.0)
		return
	pending_rare_choice_record_id = ""
	_show_notification("无相灵魄已融入来世资质", 4.0)
	_request_soul_essence()

func _build_combat_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	vitals_panel = PanelContainer.new()
	vitals_panel.position = Vector2(18.0, -104.0)
	vitals_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitals_panel.custom_minimum_size = Vector2(300.0, 82.0)
	hud.add_child(vitals_panel)
	var vitals_layout := VBoxContainer.new()
	vitals_layout.add_theme_constant_override("separation", 6)
	vitals_panel.add_child(vitals_layout)
	health_label = Label.new()
	health_label.text = "生命：等待服务端战斗状态"
	vitals_layout.add_child(health_label)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(270.0, 16.0)
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 0.0
	health_bar.show_percentage = false
	vitals_layout.add_child(health_bar)
	notification_panel = PanelContainer.new()
	notification_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notification_panel.position = Vector2(-220.0, 112.0)
	notification_panel.custom_minimum_size = Vector2(440.0, 48.0)
	notification_panel.visible = false
	hud.add_child(notification_panel)
	notification_label = Label.new()
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification_panel.add_child(notification_label)
	notification_timer = Timer.new()
	notification_timer.one_shot = true
	notification_timer.wait_time = 3.2
	notification_timer.timeout.connect(func(): notification_panel.visible = false)
	add_child(notification_timer)

	target_info_panel = PanelContainer.new()
	target_info_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_info_panel.position = Vector2(-150.0, 18.0)
	target_info_panel.custom_minimum_size = Vector2(300.0, 66.0)
	target_info_panel.visible = false
	hud.add_child(target_info_panel)
	target_info_label = Label.new()
	target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_info_panel.add_child(target_info_label)

func _show_notification(message: String, duration: float = 3.2) -> void:
	if not is_instance_valid(notification_panel) or not is_instance_valid(notification_label):
		return
	notification_label.text = message
	notification_panel.visible = true
	if is_instance_valid(notification_timer):
		notification_timer.start(duration)

func _update_vitals(current_health: int, max_health: int) -> void:
	if max_health <= 0 or current_health < 0:
		return
	vitals_known = true
	health_label.text = "生命  " + str(current_health) + " / " + str(max_health)
	health_bar.max_value = max_health
	health_bar.value = clampi(current_health, 0, max_health)

func _toggle_details_panel() -> void:
	details_visible = not details_visible
	$HUD/Panel.visible = hud_visible and details_visible
	details_toggle_button.text = "收起角色面板" if details_visible else "角色 · 修炼"

func _world_display_name(world_id: String) -> String:
	match world_id:
		"underworld_fengdu":
			return "冥界 · 酆都"
		"qingyun_human":
			return "青云界 · 人界"
		"myriad_demon":
			return "万妖界"
		_:
			return "未知世界（" + world_id + "）"

func _region_for_position(world_id: String, position: Vector3) -> String:
	var x := position.x
	var z := position.z
	if world_id == "underworld_fengdu":
		# Match named landmarks before broad terrain regions.
		if x >= 15.0 and x <= 29.0 and z >= -0.5 and z <= 5.5:
			return "奈何桥"
		if x >= -35.0 and x <= -8.0 and z >= -69.0 and z <= -42.0:
			return "轮回殿前"
		if x >= -12.0 and x <= 12.0 and z >= -28.0 and z <= -9.0:
			return "酆都鬼门关"
		if x >= 17.0 and x <= 27.0 and z >= -68.0 and z <= 82.0:
			return "忘川河畔"
		if x >= -32.0 and x <= 32.0 and z >= -40.0 and z <= -26.0:
			return "引魂石道"
		if x <= -36.0 and z >= 10.0 and z <= 46.0:
			return "古战场遗址"
		return "酆都荒原"
	if world_id == "qingyun_human":
		if x >= -9.0 and x <= 9.0 and z >= -28.0 and z <= -16.0:
			return "青云山门"
		if x >= -7.0 and x <= 7.0 and z >= -42.0 and z <= -3.0:
			return "青云石径"
		if absf(x) >= 8.0 and absf(x) <= 30.0 and z >= -48.0 and z <= 8.0:
			return "青云松林"
		return "青云郊野"
	return "未知区域"

func _refresh_current_region(show_entry_notice: bool) -> void:
	if not is_instance_valid(local_player):
		return
	var world_id := str(HHSession.world_snapshot.get("world_id", ""))
	var next_region := _region_for_position(world_id, local_player.position)
	if next_region == current_region_name:
		return
	var previous_region := current_region_name
	current_region_name = next_region
	_update_hud()
	if show_entry_notice and not previous_region.is_empty():
		_show_notification("已进入「" + next_region + "」", 2.8)

func _update_compact_hud(progression: Dictionary = {}) -> void:
	if not is_instance_valid(compact_hud_label):
		return
	var snapshot: Dictionary = HHSession.world_snapshot
	var world_id := str(snapshot.get("world_id", ""))
	var world_name := _world_display_name(world_id)
	var character_name := str(snapshot.get("name", "初入洪荒"))
	var system_name := str(progression.get("system_name", "修炼信息加载中"))
	var realm_name := str(progression.get("realm_name", ""))
	var stage_name := str(progression.get("realm_stage_name", ""))
	var cultivation := int(progression.get("cultivation", 0))
	var region_name := current_region_name if not current_region_name.is_empty() else "区域载入中"
	var lines := [
		world_name + "  /  " + region_name,
		character_name + "  ·  " + system_name + " " + realm_name + stage_name,
		"修为 " + str(cultivation)
	]
	if world_id == "underworld_fengdu":
		lines.append("魂力 " + str(soul_essence_profile.get("soul_power", 0)) + "  ·  吞噬 " + str(soul_essence_profile.get("absorbed_count", 0)) + "  ·  " + str(soul_essence_profile.get("growth_name", "初生魂团")))
		var progress_by_attribute: Dictionary = {}
		for progress_variant in soul_essence_profile.get("attribute_progress", []):
			if progress_variant is Dictionary:
				var progress_item: Dictionary = progress_variant
				progress_by_attribute[str(progress_item.get("attribute", ""))] = progress_item
		var attribute_labels := {
			"strength": "力",
			"constitution": "体",
			"agility": "敏",
			"spirit": "灵",
			"vitality": "气"
		}
		var progress_parts: Array[String] = []
		for attribute in ["strength", "constitution", "agility", "spirit", "vitality"]:
			if not progress_by_attribute.has(attribute):
				continue
			var progress_item: Dictionary = progress_by_attribute[attribute]
			var next_threshold := int(progress_item.get("next_threshold", 0))
			var absorbed := int(progress_item.get("absorbed_count", 0))
			var applied := int(progress_item.get("applied_points", 0))
			var max_points := int(progress_item.get("max_points", 10))
			var milestone_text := "满" if next_threshold <= 0 or applied >= max_points else str(absorbed) + "/" + str(next_threshold)
			progress_parts.append(str(attribute_labels.get(attribute, attribute)) + "+" + str(applied) + " " + milestone_text)
		if not progress_parts.is_empty():
			lines.append("来世资质 · " + "  ".join(PackedStringArray(progress_parts)))
		compact_hud_panel.custom_minimum_size = Vector2(420.0, 116.0)
		compact_hud_label.custom_minimum_size = Vector2(396.0, 96.0)
		var pending_choices: Array = soul_essence_profile.get("pending_rare_choices", [])
		if is_instance_valid(soul_choice_button):
			soul_choice_button.visible = not pending_choices.is_empty()
			if not pending_choices.is_empty():
				soul_choice_button.text = "分配无相灵魄 · " + str(pending_choices.size())
	else:
		compact_hud_panel.custom_minimum_size = Vector2(340.0, 92.0)
		compact_hud_label.custom_minimum_size = Vector2(316.0, 72.0)
	compact_hud_label.text = "\n".join(PackedStringArray(lines))

func _apply_world_player_form() -> void:
	if not is_instance_valid(local_player):
		return
	var is_underworld := str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu"
	if is_underworld:
		var affinities: Dictionary = soul_essence_profile.get("affinity_counts", {})
		local_player.set_soul_form(true,
			int(soul_essence_profile.get("form_stage", 1)),
			float(soul_essence_profile.get("visual_scale", 0.35)),
			affinities,
			int(soul_essence_profile.get("growth_stage", 1)),
			soul_essence_profile.get("fusion_names", []))
	else:
		local_player.set_soul_form(false)
	if is_instance_valid(soul_choice_button):
		var pending: Array = soul_essence_profile.get("pending_rare_choices", [])
		soul_choice_button.visible = hud_visible and pending.size() > 0

func _request_soul_essence() -> void:
	if soul_essence_http == null or HHSession.access_token.is_empty() or soul_essence_request_busy:
		return
	soul_essence_request_busy = true
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var error := soul_essence_http.request(
		HHSession.api_base + "/api/v1/souls/current/essence",
		headers,
		HTTPClient.METHOD_GET
	)
	if error != OK:
		soul_essence_request_busy = false
		_show_notification("灵魂状态暂时无法读取，错误码：" + str(error), 4.0)

func _on_soul_essence_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	soul_essence_request_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_show_notification("灵魂状态读取失败（HTTP " + str(response_code) + "），请确认已执行 000027 和 000028 迁移", 5.0)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var had_previous_essence_profile := soul_essence_profile.has("mutation_count")
	var previous_mutation_count := int(soul_essence_profile.get("mutation_count", 0))
	var previous_attribute_points: Dictionary = {}
	for previous_variant in soul_essence_profile.get("attribute_progress", []):
		if previous_variant is Dictionary:
			var previous_item: Dictionary = previous_variant
			previous_attribute_points[str(previous_item.get("attribute", ""))] = int(previous_item.get("awarded_points", 0))
	soul_essence_profile = parsed
	var growth_notifications: Array[String] = []
	var current_mutation_count := int(soul_essence_profile.get("mutation_count", 0))
	if had_previous_essence_profile and current_mutation_count > previous_mutation_count:
		var mutations: Array = soul_essence_profile.get("mutations", [])
		if mutations.size() > 0:
			var latest: Dictionary = mutations[0]
			growth_notifications.append(str(latest.get("name", "未知异变")) + " · " + str({"strength":"力量","constitution":"体质","agility":"敏捷","spirit":"灵力","vitality":"气血"}.get(str(latest.get("attribute", "")), "资质")) + " +" + str(latest.get("attribute_bonus", 1)))
	if had_previous_essence_profile:
		for current_variant in soul_essence_profile.get("attribute_progress", []):
			if not current_variant is Dictionary:
				continue
			var current_item: Dictionary = current_variant
			var attribute := str(current_item.get("attribute", ""))
			var old_points := int(previous_attribute_points.get(attribute, 0))
			var new_points := int(current_item.get("awarded_points", 0))
			if new_points > old_points:
				var attribute_name := str({"strength":"力量","constitution":"体质","agility":"敏捷","spirit":"灵力","vitality":"气血"}.get(attribute, attribute))
				growth_notifications.append(attribute_name + "资质突破 +" + str(new_points - old_points))
	if growth_notifications.size() > 0:
		_show_notification("魂质成长 · " + "；".join(PackedStringArray(growth_notifications)), 5.0)
	_apply_world_player_form()
	_update_compact_hud()
	var pending: Array = soul_essence_profile.get("pending_rare_choices", [])
	if is_instance_valid(soul_choice_button):
		soul_choice_button.visible = pending.size() > 0 and hud_visible
	if pending.size() > 0 and pending_rare_choice_record_id.is_empty():
		pending_rare_choice_record_id = str(pending[0].get("record_id", ""))
		_show_notification("获得无相灵魄！可在左上方选择一项来世属性", 6.0)

func _update_hud() -> void:
	var snapshot: Dictionary = HHSession.world_snapshot
	var world_id := str(snapshot.get("world_id", ""))
	var world_name := _world_display_name(world_id)
	var character_name := str(snapshot.get("name", "初入洪荒"))
	hud_label.text = "当前世界 · " + world_name + " · 所在区域 " + (current_region_name if not current_region_name.is_empty() else "区域载入中") + "\n" + character_name + "  |  WASD 移动 · 鼠标转向 · ESC 释放鼠标 · F1 隐藏/显示状态栏\nF NPC交互 · E 拾取 · I 背包 · C 聊天 · 鼠标左键攻击附近怪物 · 首次点击画面锁定鼠标 · F2 网络诊断"
	_update_compact_hud()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_entities_updated(entities: Array) -> void:
	var seen: Dictionary = {}
	var seen_monsters: Dictionary = {}
	var seen_drops: Dictionary = {}
	var own_id := str(HHSession.world_snapshot.get("character_id", ""))
	for entity in entities:
		if not (entity is Dictionary):
			continue
		var entity_type := str(entity.get("entity_type", "player"))
		if entity_type == "monster":
			var monster_id := str(entity.get("entity_id", ""))
			if monster_id.is_empty():
				continue
			seen_monsters[monster_id] = true
			_upsert_monster(entity)
			continue
		if entity_type == "drop":
			var drop_id := str(entity.get("entity_id", ""))
			if drop_id.is_empty():
				continue
			seen_drops[drop_id] = true
			_upsert_drop(entity)
			continue
		var character_id := str(entity.get("character_id", ""))
		if character_id.is_empty():
			continue
		var target := Vector3(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)), float(entity.get("z", 0.0)))
		if character_id == own_id:
			local_target_position = target
			continue
		seen[character_id] = true
		_upsert_remote_player(entity)
	for character_id in remote_players.keys():
		if not seen.has(character_id):
			remote_players[character_id].queue_free()
			remote_players.erase(character_id)
			remote_targets.erase(character_id)
			remote_yaws.erase(character_id)
	for monster_id in monsters.keys():
		if not seen_monsters.has(monster_id):
			var missing_monster := monsters[monster_id] as Node3D
			if float(missing_monster.get_meta("death_reaction_time", 0.0)) > 0.0:
				missing_monster.set_meta("pending_corpse_cleanup", true)
				monster_targets.erase(monster_id)
				monster_entities.erase(monster_id)
				if monster_id == selected_monster_id:
					_clear_monster_target()
				continue
			missing_monster.queue_free()
			monsters.erase(monster_id)
			monster_targets.erase(monster_id)
			monster_entities.erase(monster_id)
			if monster_id == selected_monster_id:
				_clear_monster_target()
	for drop_id in drops.keys():
		if not seen_drops.has(drop_id):
			drops[drop_id].queue_free()
			drops.erase(drop_id)
			drop_targets.erase(drop_id)

func _upsert_remote_player(entity: Dictionary) -> void:
	var character_id := str(entity.get("character_id", ""))
	if character_id.is_empty() or character_id == str(HHSession.world_snapshot.get("character_id", "")):
		return
	if not remote_players.has(character_id):
		remote_players[character_id] = _create_remote_player(str(entity.get("name", "修士")))
	remote_targets[character_id] = Vector3(
		float(entity.get("x", 0.0)),
		float(entity.get("y", 0.0)),
		float(entity.get("z", 0.0))
	)
	remote_yaws[character_id] = float(entity.get("yaw", 0.0))

func _upsert_monster(entity: Dictionary) -> void:
	var monster_id := str(entity.get("entity_id", ""))
	if monster_id.is_empty():
		return
	if not monsters.has(monster_id):
		monsters[monster_id] = _create_monster(str(entity.get("name", "野兽")), int(entity.get("level", 1)))
	monster_targets[monster_id] = Vector3(
		float(entity.get("x", 0.0)),
		float(entity.get("y", 0.0)),
		float(entity.get("z", 0.0))
	)
	monster_entities[monster_id] = entity.duplicate(true)
	if monster_id == selected_monster_id:
		_update_target_info()
	var monster := monsters[monster_id] as Node3D
	var nameplate := monster.get_node_or_null("Nameplate") as Label3D
	if nameplate != null:
		var base_text := str(entity.get("name", "野兽")) + " · Lv." + str(int(entity.get("level", 1)))
		if entity.has("health") and entity.has("max_health"):
			var hp := int(entity.get("health", 0))
			var max_hp := int(entity.get("max_health", 0))
			if max_hp > 0:
				base_text += "\n生命 " + str(maxi(hp, 0)) + " / " + str(max_hp)
		nameplate.text = base_text

func _create_monster(monster_name: String, monster_level: int) -> Node3D:
	var monster: Node3D = UnderworldVisualFactory.create_monster(monster_name, monster_level)
	var is_wraith := monster_name.contains("游祟") or monster_name.contains("幽魂") or monster_name.contains("灵识")
	var is_war_god := monster_name.contains("战神") or monster_name.contains("战魂")
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = monster_name + " · Lv." + str(monster_level)
	label.position.y = 2.05 if is_war_god else (1.85 if is_wraith else 1.75)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#ff9b55") if is_war_god else (Color("#b9d9ff") if is_wraith else Color("#ffd0a8"))
	monster.add_child(label)
	monster.set_meta("base_visual_scale", monster.scale)
	monster.set_meta("death_reaction_time", 0.0)
	monster.set_meta("hit_reaction_time", 0.0)
	add_child(monster)
	return monster

func _upsert_drop(entity: Dictionary) -> void:
	var drop_id := str(entity.get("entity_id", ""))
	if drop_id.is_empty():
		return
	if not drops.has(drop_id):
		drops[drop_id] = _create_drop(str(entity.get("item_name", "掉落物")), int(entity.get("quality", 1)), int(entity.get("quantity", 1)))
	drop_targets[drop_id] = Vector3(
		float(entity.get("x", 0.0)),
		float(entity.get("y", 0.15)),
		float(entity.get("z", 0.0))
	)

func _create_drop(item_name: String, quality: int, quantity: int) -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.5
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	var quality_colors := [Color("#c6c6c6"), Color("#72c98a"), Color("#5ba9ef"), Color("#b184ed"), Color("#e8b85b")]
	material.albedo_color = quality_colors[clampi(quality - 1, 0, quality_colors.size() - 1)]
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.22
	material.roughness = 0.35
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	var label := Label3D.new()
	label.text = item_name + " ×" + str(quantity) + "\n按 E 拾取"
	label.position.y = 0.65
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#f4e6bd")
	root.add_child(label)
	add_child(root)
	return root

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		input_debug_visible = not input_debug_visible
		if is_instance_valid(input_debug_panel):
			input_debug_panel.visible = hud_visible and input_debug_visible
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		hud_visible = not hud_visible
		$HUD/Panel.visible = hud_visible and details_visible
		if is_instance_valid(compact_hud_panel):
			compact_hud_panel.visible = hud_visible
		if is_instance_valid(chat_panel):
			chat_panel.visible = hud_visible
		if is_instance_valid(details_toggle_button):
			details_toggle_button.visible = hud_visible
		if is_instance_valid(soul_choice_button):
			soul_choice_button.visible = hud_visible and soul_essence_profile.get("pending_rare_choices", []).size() > 0
		if is_instance_valid(vitals_panel):
			vitals_panel.visible = hud_visible
		if is_instance_valid(target_info_panel):
			target_info_panel.visible = hud_visible and not selected_monster_id.is_empty()
		if is_instance_valid(input_debug_panel):
			input_debug_panel.visible = hud_visible and input_debug_visible
		if is_instance_valid(notification_panel) and not hud_visible:
			notification_panel.visible = false
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if is_instance_valid(chat_input) and not chat_input.has_focus():
			_set_chat_expanded(true)
			chat_input.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and chat_expanded:
		if is_instance_valid(chat_input):
			chat_input.release_focus()
		_set_chat_expanded(false)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_TAB:
		_cycle_monster_target()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F:
		_try_interact_nearest_npc()
		return
	if event.keycode == KEY_I:
		_on_inventory_button_pressed()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_C:
		_set_chat_expanded(not chat_expanded)
		if chat_expanded and is_instance_valid(chat_input):
			chat_input.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_E:
		return
	var network := HHSession.world_network
	if network == null or not network.is_world_ready() or not is_instance_valid(local_player):
		return
	var nearest_id := ""
	var nearest_distance := 3.0
	for drop_id in drops.keys():
		var target: Vector3 = drop_targets.get(drop_id, drops[drop_id].position)
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = str(drop_id)
	if nearest_id.is_empty():
		return
	var error := network.send_pickup(nearest_id)
	if error == OK:
		hud_label.text = "正在拾取物品……"
	else:
		hud_label.text = "发送拾取请求失败，错误码：" + str(error)

func _build_chat_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	chat_panel = PanelContainer.new()
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	chat_panel.offset_left = -408.0
	chat_panel.offset_top = -66.0
	chat_panel.offset_right = -18.0
	chat_panel.offset_bottom = -18.0
	chat_panel.custom_minimum_size = Vector2(390.0, 48.0)
	var chat_style := StyleBoxFlat.new()
	chat_style.bg_color = Color(0.035, 0.055, 0.085, 0.90)
	chat_style.border_color = Color("#526783")
	chat_style.set_border_width_all(1)
	chat_style.set_corner_radius_all(9)
	chat_panel.add_theme_stylebox_override("panel", chat_style)
	hud.add_child(chat_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	chat_panel.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "万界传音 · 附近"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var toggle := Button.new()
	toggle.text = "展开"
	toggle.pressed.connect(func(): _set_chat_expanded(not chat_expanded))
	heading.add_child(toggle)
	var channels := HBoxContainer.new()
	layout.add_child(channels)
	for channel_data in [["nearby", "附近"], ["world", "世界"], ["cross_world", "跨界"]]:
		var channel_button := Button.new()
		channel_button.text = channel_data[1]
		channel_button.pressed.connect(_select_chat_channel.bind(str(channel_data[0])))
		channels.add_child(channel_button)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360.0, 132.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	chat_log = VBoxContainer.new()
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(chat_log)
	var input_row := HBoxContainer.new()
	layout.add_child(input_row)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "输入附近消息（最多 200 字）"
	chat_input.max_length = 200
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(_on_chat_input_submitted)
	input_row.add_child(chat_input)
	var send_button := Button.new()
	send_button.text = "发送"
	send_button.pressed.connect(func(): _on_chat_input_submitted(chat_input.text))
	input_row.add_child(send_button)
	chat_status = Label.new()
	chat_status.text = "附近频道 · 仅同一实例、80 米范围内可见"
	chat_status.modulate = Color(0.72, 0.78, 0.84)
	layout.add_child(chat_status)
	_set_chat_expanded(false)

func _set_chat_expanded(expanded: bool) -> void:
	chat_expanded = expanded
	if not is_instance_valid(chat_panel):
		return
	chat_panel.offset_top = -270.0 if expanded else -66.0
	chat_panel.offset_bottom = -18.0
	chat_panel.custom_minimum_size.y = 252.0 if expanded else 48.0
	for child in chat_panel.get_child(0).get_children():
		if child is Control and child != chat_panel.get_child(0).get_child(0):
			child.visible = expanded
	var heading := chat_panel.get_child(0).get_child(0) as HBoxContainer
	if heading != null and heading.get_child_count() > 1:
		var toggle := heading.get_child(1) as Button
		toggle.text = "收起" if expanded else "展开"

func _on_chat_input_submitted(value: String) -> void:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return
	var error: Error
	if selected_chat_channel == "nearby":
		var network := HHSession.world_network
		if network == null or not network.is_world_ready():
			chat_status.text = "世界连接尚未就绪，消息未发送。"
			return
		error = network.send_chat("nearby", normalized)
	else:
		var raw_id := Crypto.new().generate_random_bytes(16).hex_encode()
		var message_id := "%s-%s-%s-%s-%s" % [raw_id.substr(0, 8), raw_id.substr(8, 4), raw_id.substr(12, 4), raw_id.substr(16, 4), raw_id.substr(20, 12)]
		error = HHChatNetwork.send_message(selected_chat_channel, normalized, message_id)
	if error != OK:
		chat_status.text = "发送失败：" + str(error)
		return
	chat_input.clear()
	chat_input.release_focus()


func _select_chat_channel(channel: String) -> void:
	if channel not in ["nearby", "world", "cross_world"]:
		return
	selected_chat_channel = channel
	var names := {"nearby": "附近", "world": "世界", "cross_world": "跨界"}
	chat_input.placeholder_text = "输入" + str(names[channel]) + "消息（最多 200 字）"
	_render_chat_lines()
	if channel == "nearby":
		chat_status.text = "附近频道 · 仅当前实例 AOI 范围内可见"
	elif HHChatNetwork.socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		chat_status.text = str(names[channel]) + "频道 · 独立聊天连接已建立"
	else:
		chat_status.text = str(names[channel]) + "频道 · 正在连接独立聊天服务"

func _on_chat_socket_connected() -> void:
	HHChatNetwork.fetch_history("nearby", 50)
	HHChatNetwork.fetch_history("world", 50)
	HHChatNetwork.fetch_history("cross_world", 50)
	if selected_chat_channel != "nearby" and is_instance_valid(chat_status):
		chat_status.text = "聊天服务已连接 · " + ("世界频道" if selected_chat_channel == "world" else "跨界频道")

func _on_chat_history_received(channel: String, messages: Array) -> void:
	if channel not in ["nearby", "world", "cross_world"]:
		return
	for message in messages:
		if not message is Dictionary:
			continue
		var sender := str(message.get("sender_name", "未知玩家"))
		var content := str(message.get("content", ""))
		if not content.is_empty():
			_append_chat_line("[" + sender + "] " + content, channel, str(message.get("id", "")), str(message.get("created_at", "")))

func _on_chat_socket_error(message: String) -> void:
	if is_instance_valid(chat_status):
		chat_status.text = message + "（游戏操作不受影响）"

func _on_chat_socket_message(message: Dictionary) -> void:
	if not bool(message.get("accepted", true)):
		if is_instance_valid(chat_status):
			chat_status.text = str(message.get("reason", "聊天消息未送达。"))
		return
	var channel := str(message.get("channel", selected_chat_channel))
	if channel not in ["nearby", "world", "cross_world"]:
		return
	var sender := str(message.get("sender_name", "未知玩家"))
	var content := str(message.get("content", ""))
	if not content.is_empty():
		_append_chat_line("[" + sender + "] " + content, channel, str(message.get("id", "")))
		if is_instance_valid(chat_status) and channel == selected_chat_channel:
			chat_status.text = "聊天消息已送达"

func _on_chat_event(event: Dictionary) -> void:
	if not bool(event.get("accepted", false)):
		chat_status.text = str(event.get("reason", "消息发送失败。"))
		return
	# ENet returns only the delivery acknowledgement. The full nearby message
	# arrives through the authenticated ChatServer WebSocket and is deduplicated
	# by its persisted message ID.
	if selected_chat_channel == "nearby":
		chat_status.text = "附近频道 · 消息已写入本地持久队列，正在投递"

func _append_chat_line(line: String, channel: String = "", message_id: String = "", created_at: String = "") -> void:
	var target_channel := channel if not channel.is_empty() else selected_chat_channel
	if not message_id.is_empty():
		if chat_seen_ids.has(message_id):
			return
		chat_seen_ids[message_id] = true
		while chat_seen_ids.size() > 1000:
			chat_seen_ids.erase(chat_seen_ids.keys()[0])
	if not chat_lines_by_channel.has(target_channel):
		chat_lines_by_channel[target_channel] = []
	var lines: Array = chat_lines_by_channel[target_channel]
	var timestamp := created_at
	if timestamp.is_empty():
		timestamp = Time.get_datetime_string_from_system(true)
	var entry := {"text": line, "id": message_id, "created_at": timestamp, "sort_key": timestamp + message_id}
	var insert_at := lines.size()
	for index in range(lines.size()):
		if str(lines[index].get("sort_key", "")) > str(entry["sort_key"]):
			insert_at = index
			break
	lines.insert(insert_at, entry)
	while lines.size() > 40:
		lines.pop_front()
	chat_lines_by_channel[target_channel] = lines
	if target_channel == selected_chat_channel:
		_render_chat_lines()

func _render_chat_lines() -> void:
	if not is_instance_valid(chat_log):
		return
	var visible_lines: Array = chat_lines_by_channel.get(selected_chat_channel, [])
	for child in chat_log.get_children():
		child.queue_free()
	for entry in visible_lines:
		var label := Label.new()
		label.text = str(entry.get("text", ""))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_log.add_child(label)

func _on_pickup_event(event: Dictionary) -> void:
	if bool(event.get("pending", false)):
		_show_notification(str(event.get("reason", "正在结算拾取……")))
		return
	if bool(event.get("accepted", false)):
		_show_notification("拾取成功：" + str(event.get("item_id", "物品")) + " ×" + str(event.get("quantity", 1)))
		_refresh_inventory()
	else:
		_show_notification(str(event.get("reason", "拾取失败。")))

func _build_inventory_ui() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	inventory_button = Button.new()
	inventory_button.text = "背包"
	inventory_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inventory_button.offset_left = -118.0
	inventory_button.offset_top = 18.0
	inventory_button.offset_right = -18.0
	inventory_button.offset_bottom = 58.0
	inventory_button.pressed.connect(_on_inventory_button_pressed)
	hud.add_child(inventory_button)

	inventory_panel = PanelContainer.new()
	inventory_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inventory_panel.offset_left = -360.0
	inventory_panel.offset_top = 68.0
	inventory_panel.offset_right = -18.0
	inventory_panel.offset_bottom = 470.0
	inventory_panel.visible = false
	hud.add_child(inventory_panel)
	var layout := VBoxContainer.new()
	inventory_panel.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "角色背包"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(func():
		inventory_panel.visible = false
		inventory_visible = false
	)
	heading.add_child(close_button)
	var equipment_title := Label.new()
	equipment_title.text = "已装备"
	layout.add_child(equipment_title)
	inventory_equipment = VBoxContainer.new()
	layout.add_child(inventory_equipment)
	inventory_status = Label.new()
	inventory_status.text = "正在读取背包……"
	layout.add_child(inventory_status)
	var filter_row := HBoxContainer.new()
	layout.add_child(filter_row)
	for filter_data in [["all","全部"],["equipment","装备"],["consumable","消耗品"],["material","材料"],["quest","任务"]] :
		var filter_button := Button.new()
		filter_button.text = filter_data[1]
		filter_button.pressed.connect(_on_inventory_filter_pressed.bind(filter_data[0]))
		filter_row.add_child(filter_button)
	inventory_sort_option = OptionButton.new()
	inventory_sort_option.add_item("品质优先", 0)
	inventory_sort_option.add_item("名称排序", 1)
	inventory_sort_option.add_item("数量排序", 2)
	inventory_sort_option.item_selected.connect(_on_inventory_sort_selected)
	layout.add_child(inventory_sort_option)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320.0, 330.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	inventory_items = VBoxContainer.new()
	inventory_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inventory_items)
	inventory_http = HTTPRequest.new()
	inventory_http.timeout = 10.0
	add_child(inventory_http)
	inventory_http.request_completed.connect(_on_inventory_request_completed)
	equipment_http = HTTPRequest.new()
	equipment_http.timeout = 10.0
	add_child(equipment_http)
	equipment_http.request_completed.connect(_on_equipment_request_completed)
	equipment_action_http = HTTPRequest.new()
	equipment_action_http.timeout = 10.0
	add_child(equipment_action_http)
	equipment_action_http.request_completed.connect(_on_equipment_action_completed)
	consumable_http = HTTPRequest.new()
	consumable_http.timeout = 10.0
	add_child(consumable_http)
	consumable_http.request_completed.connect(_on_consumable_completed)

func _on_inventory_button_pressed() -> void:
	inventory_visible = not inventory_visible
	inventory_panel.visible = inventory_visible
	if inventory_visible:
		_refresh_inventory()
		_refresh_equipment()

func _refresh_inventory() -> void:
	if inventory_http == null or HHSession.access_token.is_empty():
		if inventory_status != null:
			inventory_status.text = "请先登录后查看背包。"
		return
	if inventory_request_busy:
		return
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var error := inventory_http.request(
		HHSession.api_base + "/api/v1/characters/current/inventory",
		headers,
		HTTPClient.METHOD_GET
	)
	if error != OK:
		inventory_status.text = "读取背包请求失败，错误码：" + str(error)
	else:
		inventory_request_busy = true

func _on_inventory_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	inventory_request_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		inventory_status.text = "背包读取失败：" + body.get_string_from_utf8()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not (parsed.get("items", []) is Array):
		inventory_status.text = "中心服返回了无效的背包数据。"
		return
	inventory_cache = parsed.get("items", [])
	inventory_status.text = "物品种类：" + str(inventory_cache.size())
	_render_inventory_items()

func _on_inventory_filter_pressed(filter_type: String) -> void:
	inventory_filter = filter_type
	_render_inventory_items()

func _on_inventory_sort_selected(index: int) -> void:
	match index:
		0: inventory_sort_mode = "quality"
		1: inventory_sort_mode = "name"
		2: inventory_sort_mode = "quantity"
	_render_inventory_items()

func _render_inventory_items() -> void:
	for child in inventory_items.get_children():
		child.queue_free()
	var items: Array = []
	for item in inventory_cache:
		if not (item is Dictionary):
			continue
		if inventory_filter != "all" and str(item.get("item_type", "")) != inventory_filter:
			continue
		items.append(item)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match inventory_sort_mode:
			"name":
				return str(a.get("name", "")) < str(b.get("name", ""))
			"quantity":
				return int(a.get("quantity", 0)) > int(b.get("quantity", 0))
			_:
				if int(a.get("quality", 1)) != int(b.get("quality", 1)):
					return int(a.get("quality", 1)) > int(b.get("quality", 1))
				return str(a.get("name", "")) < str(b.get("name", ""))
	)
	if items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前分类没有物品。"
		inventory_items.add_child(empty_label)
		return
	for item in items:
		var row := HBoxContainer.new()
		inventory_items.add_child(row)
		var line := Label.new()
		var quality := int(item.get("quality", 1))
		var quality_names := ["普通", "优秀", "精良", "稀有", "传说"]
		var quality_name: String = quality_names[clampi(quality - 1, 0, quality_names.size() - 1)]
		line.text = str(item.get("name", item.get("item_id", "未知物品"))) + " · " + quality_name + " · ×" + str(item.get("quantity", 0))
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(line)
		var detail_button := Button.new()
		detail_button.text = "详情"
		detail_button.pressed.connect(_show_item_details.bind(item))
		row.add_child(detail_button)
		if str(item.get("item_type", "")) == "equipment":
			var equip_button := Button.new()
			equip_button.text = "穿戴"
			equip_button.pressed.connect(_on_equip_item_pressed.bind(str(item.get("item_id", "")), str(item.get("equipment_slot", ""))))
			row.add_child(equip_button)
		elif str(item.get("item_type", "")) == "consumable":
			var use_button := Button.new()
			use_button.text = "使用"
			use_button.disabled = consumable_busy
			use_button.pressed.connect(_on_use_consumable_pressed.bind(str(item.get("item_id", ""))))
			row.add_child(use_button)

func _show_item_details(item: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = str(item.get("name", "物品详情"))
	var details := str(item.get("description", "暂无描述"))
	details += "\n\n分类：" + str(item.get("item_type", "未知"))
	details += "\n品质：" + str(item.get("quality", 1))
	details += "\n数量：" + str(item.get("quantity", 0)) + " / " + str(item.get("max_stack", 1))
	var stats: Dictionary = item.get("base_stats", {})
	if not stats.is_empty():
		details += "\n属性加成：" + str(stats)
	if str(item.get("equipment_slot", "")) != "":
		details += "\n装备部位：" + str(item.get("equipment_slot", ""))
	dialog.dialog_text = details
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(440, 300))


func _cycle_monster_target() -> void:
	if monsters.is_empty():
		_clear_monster_target()
		_show_notification("附近没有可锁定的目标")
		return
	var candidates: Array[String] = []
	for monster_id in monsters.keys():
		var monster_key := str(monster_id)
		if monster_targets.has(monster_key):
			candidates.append(monster_key)
	candidates.sort()
	if candidates.is_empty():
		return
	var next_index := 0
	var current_index := candidates.find(selected_monster_id)
	if current_index >= 0:
		next_index = (current_index + 1) % candidates.size()
	_set_monster_target(candidates[next_index])

func _set_monster_target(monster_id: String) -> void:
	if not monsters.has(monster_id):
		return
	_clear_target_ring()
	selected_monster_id = monster_id
	var target := monsters[monster_id] as Node3D
	var ring := MeshInstance3D.new()
	ring.name = "TargetSelectionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.72
	ring.mesh = torus
	ring.position.y = 0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#f0c66e")
	material.emission_enabled = true
	material.emission = Color("#d99b35")
	material.emission_energy_multiplier = 1.6
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	target.add_child(ring)
	target_selection_ring = ring
	_update_target_info()
	_show_notification("目标锁定：" + str(monster_entities.get(monster_id, {}).get("name", "怪物")))

func _clear_target_ring() -> void:
	if is_instance_valid(target_selection_ring):
		target_selection_ring.queue_free()
	target_selection_ring = null

func _clear_monster_target() -> void:
	_clear_target_ring()
	selected_monster_id = ""
	if is_instance_valid(target_info_panel):
		target_info_panel.visible = false

func _update_target_info() -> void:
	if not is_instance_valid(target_info_panel) or not is_instance_valid(target_info_label):
		return
	if selected_monster_id.is_empty() or not monsters.has(selected_monster_id):
		target_info_panel.visible = false
		return
	var entity: Dictionary = monster_entities.get(selected_monster_id, {})
	var title := str(entity.get("name", "怪物")) + "  ·  Lv." + str(int(entity.get("level", 1)))
	var hp_line := "目标已锁定"
	if entity.has("health") and entity.has("max_health"):
		hp_line = "生命 " + str(int(entity.get("health", 0))) + " / " + str(int(entity.get("max_health", 0)))
	target_info_label.text = title + "\n" + hp_line + "    ·    Tab 切换目标"
	target_info_panel.visible = hud_visible

func _request_nearest_monster_attack() -> void:
	var network := HHSession.world_network
	if network == null or not network.is_world_ready() or not is_instance_valid(local_player):
		return
	var nearest_id := selected_monster_id if monsters.has(selected_monster_id) else ""
	var nearest_distance := 4.5
	if nearest_id.is_empty():
		for monster_id in monster_targets:
			var target: Vector3 = monster_targets[monster_id]
			var distance := Vector2(local_player.global_position.x, local_player.global_position.z).distance_to(Vector2(target.x, target.z))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_id = str(monster_id)
	if nearest_id.is_empty():
		hud_label.text = "附近没有可攻击的怪物。"
		return
	var error: Error = network.send_attack(nearest_id)
	if error != OK:
		hud_label.text = "攻击指令发送失败：" + str(error)

func _on_monster_action_event(event: Dictionary) -> void:
	var attacker_id := str(event.get("source_entity_id", ""))
	if attacker_id.is_empty() or not monsters.has(attacker_id):
		return
	var attacker := monsters[attacker_id] as Node3D
	if is_instance_valid(attacker):
		attacker.set_meta("attack_reaction_time", 0.78)

func _on_combat_event(event: Dictionary) -> void:
	if not bool(event.get("accepted", true)):
		hud_label.text = str(event.get("reason", "攻击未命中。"))
		return
	if str(event.get("source", "")) == "monster":
		var incoming_damage := int(event.get("damage", 0))
		_spawn_combat_number(incoming_damage, true, false)
		var current_health := int(event.get("health", 0))
		var max_health := int(event.get("max_health", 0))
		_update_vitals(current_health, max_health)
		if bool(event.get("defeated", false)):
			local_player.is_dead = true
			local_target_position = local_player.position
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			death_message_label.text = "角色已倒地，无法继续行动。\n受到 " + str(incoming_damage) + " 点伤害，生命 " + str(current_health) + "/" + str(max_health) + "。\n确认后将结算复活并返回角色界面。"
			death_panel.visible = true
		else:
			_show_notification("受到怪物攻击 -" + str(incoming_damage) + " 生命")
		return
	var monster_name := str(event.get("target_name", "目标"))
	var hit_target_id := str(event.get("target_entity_id", ""))
	if monsters.has(hit_target_id):
		var hit_monster := monsters[hit_target_id] as Node3D
		hit_monster.set_meta("hit_reaction_time", 0.24)
		if bool(event.get("defeated", false)):
			hit_monster.set_meta("death_reaction_time", 1.15)
			hit_monster.set_meta("defeated_visual", true)
			var defeated_nameplate := hit_monster.get_node_or_null("Nameplate") as Label3D
			if is_instance_valid(defeated_nameplate):
				defeated_nameplate.visible = false
	var damage := int(event.get("damage", 0))
	if not selected_monster_id.is_empty() and monster_entities.has(selected_monster_id):
		var selected_entity: Dictionary = monster_entities[selected_monster_id]
		if event.has("health"):
			selected_entity["health"] = int(event.get("health", 0))
		if event.has("max_health"):
			selected_entity["max_health"] = int(event.get("max_health", 0))
		monster_entities[selected_monster_id] = selected_entity
		_update_target_info()
	_spawn_combat_number(damage, false, bool(event.get("critical", false)))
	if bool(event.get("defeated", false)):
		if str(event.get("target_entity_id", "")) == selected_monster_id:
			_clear_monster_target()
		var experience := int(event.get("experience_reward", 0))
		var cultivation := int(event.get("cultivation_reward", 0))
		var defeat_message := monster_name + " 已被击败！伤害 " + str(damage) + " · 经验 +" + str(experience) + " · 修为 +" + str(cultivation)
		if str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu":
			defeat_message += " · 魂魄正在归入魂光"
		_show_notification(defeat_message, 4.5)
		_refresh_reward_status_later()
	else:
		_show_notification("命中 " + monster_name + " · 造成 " + str(damage) + " 点伤害")


func _spawn_combat_number(amount: int, incoming: bool, critical: bool) -> void:
	if amount <= 0:
		return
	var origin := Vector3.ZERO
	if incoming and is_instance_valid(local_player):
		origin = local_player.global_position + Vector3(0.0, 1.8, 0.0)
	elif is_instance_valid(local_player):
		var nearest_id := ""
		var nearest_distance := INF
		for monster_id in monster_targets.keys():
			var target: Vector3 = monster_targets[monster_id]
			var distance := local_player.global_position.distance_to(target)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_id = str(monster_id)
		if not nearest_id.is_empty() and monsters.has(nearest_id):
			var target_node := monsters[nearest_id] as Node3D
			origin = target_node.global_position + Vector3(0.0, 2.0, 0.0)
		else:
			origin = local_player.global_position + Vector3(0.0, 1.8, 0.0)
	var label := Label3D.new()
	label.name = "CombatDamageNumber"
	label.text = ("-" if incoming else "") + str(amount)
	label.font_size = 42 if critical else 32
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("#ff6262") if incoming else (Color("#ffe08a") if critical else Color("#fff1d0"))
	label.position = origin
	label.pixel_size = 0.01
	add_child(label)
	var label_id := str(label.get_instance_id())
	floating_combat_labels[label_id] = label
	floating_combat_lifetimes[label_id] = 1.0 if critical else 0.82

func _update_floating_combat_labels(delta: float) -> void:
	for label_id in floating_combat_labels.keys():
		var label := floating_combat_labels[label_id] as Label3D
		if not is_instance_valid(label):
			floating_combat_labels.erase(label_id)
			floating_combat_lifetimes.erase(label_id)
			continue
		var lifetime := float(floating_combat_lifetimes.get(label_id, 0.0)) - delta
		floating_combat_lifetimes[label_id] = lifetime
		label.position.y += delta * (1.15 if lifetime > 0.35 else 0.55)
		var fade := clampf(lifetime / 0.35, 0.0, 1.0)
		var tint := label.modulate
		tint.a = fade
		label.modulate = tint
		if lifetime <= 0.0:
			label.queue_free()
			floating_combat_labels.erase(label_id)
			floating_combat_lifetimes.erase(label_id)

func _refresh_reward_status_later() -> void:
	await get_tree().create_timer(2.0).timeout
	if str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu":
		_request_soul_essence()
	if progression_request_context.is_empty():
		_refresh_character_status()

func _on_player_joined(player: Dictionary) -> void:
	_upsert_remote_player(player)

func _on_player_left(character_id: String) -> void:
	if not remote_players.has(character_id):
		return
	remote_players[character_id].queue_free()
	remote_players.erase(character_id)
	remote_targets.erase(character_id)
	remote_yaws.erase(character_id)

func _create_remote_player(character_name: String) -> Node3D:
	var remote := Node3D.new()
	var body := MeshInstance3D.new()
	var is_underworld := str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu"
	if is_underworld:
		var orb := SphereMesh.new()
		orb.radius = 0.34
		orb.height = 0.68
		body.mesh = orb
		var spirit_material := StandardMaterial3D.new()
		spirit_material.albedo_color = Color(0.36, 0.72, 1.0, 0.72)
		spirit_material.emission_enabled = true
		spirit_material.emission = Color(0.12, 0.48, 1.0)
		spirit_material.emission_energy_multiplier = 1.8
		spirit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spirit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		body.material_override = spirit_material
		body.position.y = 0.42
		var halo := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.47
		halo.mesh = torus
		var halo_material := StandardMaterial3D.new()
		halo_material.albedo_color = Color(0.2, 0.62, 1.0, 0.45)
		halo_material.emission_enabled = true
		halo_material.emission = Color(0.08, 0.4, 1.0)
		halo_material.emission_energy_multiplier = 1.2
		halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo.material_override = halo_material
		halo.position.y = 0.42
		remote.add_child(halo)
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.4
		capsule.height = 1.75
		body.mesh = capsule
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#79a9c9")
		body.material_override = material
		body.position.y = 0.88
	remote.add_child(body)
	var label := Label3D.new()
	label.text = character_name
	label.position.y = 1.15 if is_underworld else 2.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	remote.add_child(label)
	add_child(remote)
	return remote

func _build_input_debug_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	input_debug_panel = PanelContainer.new()
	input_debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	input_debug_panel.position = Vector2(-238.0, -154.0)
	input_debug_panel.custom_minimum_size = Vector2(220.0, 126.0)
	input_debug_panel.visible = false
	hud.add_child(input_debug_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	input_debug_panel.add_child(layout)
	var title := Label.new()
	title.text = "键盘 / 移动诊断"
	title.add_theme_font_size_override("font_size", 15)
	layout.add_child(title)
	input_debug_label = Label.new()
	input_debug_label.text = "W A S D\n网络：检测中"
	input_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(input_debug_label)

func _update_input_debug_hud() -> void:
	if not is_instance_valid(input_debug_label) or not is_instance_valid(local_player):
		return
	var keys := ""
	keys += "[W]" if local_player.is_move_key_pressed("forward") else " W "
	keys += " "
	keys += "[A]" if local_player.is_move_key_pressed("left") else " A "
	keys += " "
	keys += "[S]" if local_player.is_move_key_pressed("back") else " S "
	keys += " "
	keys += "[D]" if local_player.is_move_key_pressed("right") else " D "
	var network_text := "已连接" if local_player.movement_network_ready else "未就绪"
	var movement_text := "有移动输入" if local_player.current_move_input.length_squared() > 0.001 else "无移动输入"
	var send_text := "发送正常" if local_player.last_send_error == OK else "发送错误 " + str(local_player.last_send_error)
	input_debug_label.text = keys + "\n" + movement_text + " · 网络：" + network_text + "\n" + send_text + " · ESC 释放鼠标"

func _process(delta: float) -> void:
	if is_instance_valid(local_player):
		local_player.position = local_player.position.lerp(local_target_position, minf(delta * 14.0, 1.0))
	for character_id in remote_players:
		var remote: Node3D = remote_players[character_id]
		var target: Vector3 = remote_targets.get(character_id, remote.position)
		remote.position = remote.position.lerp(target, minf(delta * 14.0, 1.0))
		var target_yaw := float(remote_yaws.get(character_id, remote.rotation.y))
		remote.rotation.y = lerp_angle(remote.rotation.y, target_yaw, minf(delta * 12.0, 1.0))
	for monster_id in monsters:
		var monster: Node3D = monsters[monster_id]
		var target: Vector3 = monster_targets.get(monster_id, monster.position)
		monster.position = monster.position.lerp(target, minf(delta * 10.0, 1.0))
	_animate_monster_visuals(delta)
	for drop_id in drops:
		var drop: Node3D = drops[drop_id]
		var target: Vector3 = drop_targets.get(drop_id, drop.position)
		drop.position = drop.position.lerp(target, minf(delta * 12.0, 1.0))
	_update_floating_combat_labels(delta)
	_animate_npc_visuals(delta)
	_update_nearest_npc_prompt()
	_update_exploration_proximity()
	_animate_exploration_markers(delta)
	region_update_accumulator += delta
	if region_update_accumulator >= 0.2:
		region_update_accumulator = 0.0
		_refresh_current_region(true)
	input_debug_accumulator += delta
	if input_debug_accumulator >= 0.05:
		input_debug_accumulator = 0.0
		_update_input_debug_hud()


func _animate_monster_visuals(delta: float) -> void:
	monster_animation_time += delta
	for monster_id in monsters.keys():
		var monster := monsters[monster_id] as Node3D
		if not is_instance_valid(monster):
			continue
		var archetype := str(monster.get_meta("visual_archetype", ""))
		var target: Vector3 = monster_targets.get(monster_id, monster.position)
		var moving := monster.position.distance_to(target) > 0.055
		var phase := monster_animation_time * (8.5 if moving else 1.7) + float(abs(hash(str(monster_id))) % 100) * 0.031
		var stride := sin(phase)
		var hit_time := maxf(float(monster.get_meta("hit_reaction_time", 0.0)) - delta, 0.0)
		var attack_time := maxf(float(monster.get_meta("attack_reaction_time", 0.0)) - delta, 0.0)
		var death_time := maxf(float(monster.get_meta("death_reaction_time", 0.0)) - delta, 0.0)
		monster.set_meta("hit_reaction_time", hit_time)
		monster.set_meta("attack_reaction_time", attack_time)
		monster.set_meta("death_reaction_time", death_time)
		var animation_state := "death" if death_time > 0.0 else ("hit" if hit_time > 0.0 else ("attack" if attack_time > 0.0 else ("move" if moving else "idle")))
		monster.set_meta("animation_state", animation_state)
		match archetype:
			"wolf":
				_animate_wolf_monster(monster, stride, moving, phase)
			"iron_beast":
				_animate_iron_beast(monster, stride, moving, phase)
			"warrior":
				_animate_warrior_monster(monster, stride, moving, phase, animation_state)
			"life_soul", "wind_soul", "wraith":
				_animate_soul_monster(monster, delta, phase, moving, archetype)
		if attack_time > 0.0 and death_time <= 0.0:
			_animate_monster_attack(monster, archetype, 1.0 - attack_time / 0.78)
		var body := monster.get_node_or_null("Torso") as Node3D
		if not is_instance_valid(body):
			body = monster.get_node_or_null("IronCore") as Node3D
		if is_instance_valid(body):
			if hit_time > 0.0:
				var hit_weight := sin((0.24 - hit_time) / 0.24 * PI)
				body.position.x = hit_weight * 0.10
			else:
				body.position.x = move_toward(body.position.x, 0.0, delta * 0.8)
		var base_scale: Vector3 = monster.get_meta("base_visual_scale", Vector3.ONE)
		if death_time > 0.0:
			var death_weight := 1.0 - death_time / 1.15
			monster.rotation.z = death_weight * 0.42
			monster.scale = base_scale * maxf(0.08, 1.0 - death_weight * 0.72)
			_apply_monster_death_fade(monster, death_weight)
		else:
			monster.rotation.z = move_toward(monster.rotation.z, 0.0, delta * 2.0)
			monster.scale = monster.scale.lerp(base_scale, minf(delta * 8.0, 1.0))
			if bool(monster.get_meta("pending_corpse_cleanup", false)):
				monsters.erase(monster_id)
				monster.queue_free()
			elif bool(monster.get_meta("defeated_visual", false)):
				monster.rotation.z = 0.42
				monster.scale = base_scale * 0.28
				_apply_monster_death_fade(monster, 0.92)


func _animate_monster_attack(monster: Node3D, archetype: String, progress: float) -> void:
	# A short server-confirmed attack cue; it never applies damage or changes combat state.
	var strike := sin(clampf(progress, 0.0, 1.0) * PI)
	match archetype:
		"wolf":
			var torso := monster.get_node_or_null("Torso") as Node3D
			if is_instance_valid(torso):
				torso.position.z = 0.05 - strike * 0.18
			var jaw := monster.get_node_or_null("JawPivot") as Node3D
			if is_instance_valid(jaw):
				jaw.rotation.x = -strike * 0.42
			var front_left := monster.get_node_or_null("FrontLegLeft") as Node3D
			var front_right := monster.get_node_or_null("FrontLegRight") as Node3D
			if is_instance_valid(front_left):
				front_left.rotation.x -= strike * 0.24
			if is_instance_valid(front_right):
				front_right.rotation.x -= strike * 0.24
		"iron_beast":
			var core := monster.get_node_or_null("IronCore") as Node3D
			if is_instance_valid(core):
				core.position.z = 0.05 - strike * 0.16
			var skull := monster.get_node_or_null("SkullPivot") as Node3D
			if is_instance_valid(skull):
				skull.rotation.x = -strike * 0.48
		"warrior":
			var arm := monster.get_node_or_null("ArmPivotRight") as Node3D
			if is_instance_valid(arm):
				arm.rotation.x = -strike * 1.05
				arm.rotation.z = -0.18 - strike * 0.34
		"life_soul", "wind_soul", "wraith":
			var core := monster.get_node_or_null("SoulCore") as Node3D
			if is_instance_valid(core):
				core.scale = Vector3.ONE * (1.0 + strike * 0.48)
			var spark := monster.get_node_or_null("SoulSpark") as Node3D
			if is_instance_valid(spark):
				spark.scale = Vector3.ONE * (1.0 + strike * 1.8)
			var orbit := monster.get_node_or_null("SoulOrbit") as Node3D
			if is_instance_valid(orbit):
				orbit.scale = Vector3.ONE * (1.0 + strike * 0.22)


func _apply_monster_death_fade(monster: Node3D, weight: float) -> void:
	for child in monster.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var material := mesh_instance.material_override as StandardMaterial3D
			if material == null:
				continue
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var tint := material.albedo_color
			tint.a = 1.0 - weight
			material.albedo_color = tint
			material.emission_energy_multiplier = maxf(0.0, 1.0 - weight)
		elif child is Node3D:
			_apply_monster_death_fade(child as Node3D, weight)


func _animate_wolf_monster(monster: Node3D, stride: float, moving: bool, phase: float) -> void:
	var torso := monster.get_node_or_null("Torso") as MeshInstance3D
	if is_instance_valid(torso):
		torso.position.y = 0.62 + (absf(stride) * 0.035 if moving else sin(phase) * 0.012)
		torso.position.z = move_toward(torso.position.z, 0.05, 0.9)
	for pivot_name in ["FrontLegLeft", "HindLegRight"]:
		var leg := monster.get_node_or_null(pivot_name) as Node3D
		if is_instance_valid(leg):
			leg.rotation.x = stride * (0.42 if moving else 0.025)
	for pivot_name in ["FrontLegRight", "HindLegLeft"]:
		var leg := monster.get_node_or_null(pivot_name) as Node3D
		if is_instance_valid(leg):
			leg.rotation.x = -stride * (0.42 if moving else 0.025)
	var jaw := monster.get_node_or_null("JawPivot") as Node3D
	if is_instance_valid(jaw):
		jaw.rotation.x = move_toward(jaw.rotation.x, 0.0, 2.4 * get_process_delta_time())
	var tail := monster.get_node_or_null("TailPivot") as Node3D
	if is_instance_valid(tail):
		tail.rotation.y = sin(monster_animation_time * 2.4 + phase) * (0.24 if moving else 0.14)
		tail.rotation.z = sin(monster_animation_time * 1.8 + phase) * 0.08


func _animate_iron_beast(monster: Node3D, stride: float, moving: bool, phase: float) -> void:
	var iron_core := monster.get_node_or_null("IronCore") as MeshInstance3D
	if is_instance_valid(iron_core):
		iron_core.position.y = 0.66 + (absf(stride) * 0.045 if moving else sin(phase) * 0.018)
		iron_core.position.z = move_toward(iron_core.position.z, 0.05, 0.8)
	for pivot_name in ["FrontLegLeft", "HindLegRight"]:
		var leg := monster.get_node_or_null(pivot_name) as Node3D
		if is_instance_valid(leg):
			leg.rotation.x = stride * (0.28 if moving else 0.012)
	for pivot_name in ["FrontLegRight", "HindLegLeft"]:
		var leg := monster.get_node_or_null(pivot_name) as Node3D
		if is_instance_valid(leg):
			leg.rotation.x = -stride * (0.28 if moving else 0.012)
	var skull := monster.get_node_or_null("SkullPivot") as Node3D
	if is_instance_valid(skull):
		skull.rotation.x = move_toward(skull.rotation.x, sin(phase * 0.5) * (0.055 if moving else 0.025), 1.8 * get_process_delta_time())
	var spine := monster.get_node_or_null("SpineArmor") as Node3D
	if is_instance_valid(spine):
		spine.rotation.z = sin(phase * 0.5) * (0.018 if moving else 0.008)
	var tail := monster.get_node_or_null("TailPivot") as Node3D
	if is_instance_valid(tail):
		tail.rotation.y = sin(monster_animation_time * 1.45 + phase) * (0.12 if moving else 0.07)


func _animate_warrior_monster(monster: Node3D, stride: float, moving: bool, phase: float, animation_state: String) -> void:
	var torso := monster.get_node_or_null("Torso") as Node3D
	if is_instance_valid(torso):
		torso.position.y = 1.08 + (absf(stride) * 0.025 if moving else sin(phase) * 0.008)
	var left_arm := monster.get_node_or_null("ArmPivotLeft") as Node3D
	var right_arm := monster.get_node_or_null("ArmPivotRight") as Node3D
	if is_instance_valid(left_arm):
		left_arm.rotation.x = stride * (0.16 if moving else 0.025)
	if is_instance_valid(right_arm):
		var attack_pose := 0.72 if animation_state == "hit" else 0.0
		right_arm.rotation.x = lerpf(right_arm.rotation.x, attack_pose + (stride * 0.12 if moving else sin(phase) * 0.015), 0.22)
		right_arm.rotation.z = lerpf(right_arm.rotation.z, -0.12, 0.18)
	var blade := monster.get_node_or_null("ArmPivotRight/Blade") as Node3D
	if is_instance_valid(blade):
		blade.rotation.z = sin(phase * 0.5) * 0.035


func _animate_soul_monster(monster: Node3D, delta: float, phase: float, moving: bool, archetype: String) -> void:
	var drift_speed := 1.35 if archetype == "life_soul" else (2.1 if archetype == "wind_soul" else 1.0)
	var amplitude := 0.12 if archetype == "life_soul" else (0.20 if archetype == "wind_soul" else 0.075)
	var core := monster.get_node_or_null("SoulCore") as Node3D
	if is_instance_valid(core):
		core.position.y = 0.94 + sin(monster_animation_time * drift_speed + phase) * amplitude
		var pulse := 1.0 + sin(monster_animation_time * drift_speed * 1.7 + phase) * (0.08 if archetype == "wind_soul" else 0.045)
		core.scale = Vector3.ONE * pulse
	var mantle := monster.get_node_or_null("WraithMantle") as Node3D
	if is_instance_valid(mantle):
		mantle.position.y = 0.86 + sin(monster_animation_time * drift_speed + phase + 0.8) * amplitude * 0.72
		mantle.rotation.y = sin(monster_animation_time * 0.65 + phase) * (0.16 if archetype == "wind_soul" else 0.06)
	var lower := monster.get_node_or_null("LowerWisp") as Node3D
	if is_instance_valid(lower):
		lower.rotation.z = sin(monster_animation_time * drift_speed * 0.8 + phase) * (0.18 if moving else 0.10)
	var orbit := monster.get_node_or_null("SoulOrbit") as Node3D
	if is_instance_valid(orbit):
		orbit.rotation.y += delta * (1.8 if archetype == "wind_soul" else 0.72)
		orbit.scale = orbit.scale.lerp(Vector3.ONE, minf(delta * 6.0, 1.0))
	var spark := monster.get_node_or_null("SoulSpark") as Node3D
	if is_instance_valid(spark):
		spark.position.y = 1.42 + sin(monster_animation_time * drift_speed * 1.4 + phase) * amplitude * 1.8
		spark.scale = Vector3.ONE * (0.85 + absf(sin(monster_animation_time * 1.8 + phase)) * 0.35)
	for side in [-1.0, 1.0]:
		var shard_name := "SoulShardLeft" if side < 0.0 else "SoulShardRight"
		var shard := monster.get_node_or_null(shard_name) as Node3D
		if is_instance_valid(shard):
			shard.rotation.y = sin(monster_animation_time * drift_speed + phase + side) * 0.55
			shard.position.y = 0.88 + sin(monster_animation_time * drift_speed * 0.7 + phase + side) * amplitude
	for side in [-1.0, 1.0]:
		var wisp := monster.get_node_or_null("Wisp" + str(side)) as Node3D
		if is_instance_valid(wisp):
			wisp.position.y = 0.60 + sin(monster_animation_time * drift_speed + phase + side) * amplitude * 1.4
			wisp.position.x = side * (0.47 + sin(monster_animation_time * 0.9 + phase) * 0.045)


func _on_world_disconnected() -> void:
	hud_label.text = "与世界服务器的连接已断开。角色位置会周期保存，重连后将恢复到最近一次成功保存的位置。"
	reconnect_button.visible = true
	reconnect_button.disabled = false

func _on_reconnect_pressed() -> void:
	if reconnect_request_busy:
		return
	if HHSession.access_token.is_empty():
		hud_label.text = "登录状态已失效，请返回登录界面重新登录。"
		return
	reconnect_request_busy = true
	reconnect_button.disabled = true
	hud_label.text = "正在向中心服申请新的世界入口……"
	var headers := PackedStringArray([
		"Authorization: Bearer " + HHSession.access_token,
		"Content-Type: application/json"
	])
	var error := reconnect_http.request(
		HHSession.api_base + "/api/v1/worlds/enter",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	if error != OK:
		reconnect_request_busy = false
		reconnect_button.disabled = false
		hud_label.text = "申请重连失败，错误码：" + str(error)

func _on_reconnect_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	reconnect_request_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		reconnect_button.disabled = false
		hud_label.text = "无法连接中心服，请检查网络后重试。"
		return
	if response_code < 200 or response_code >= 300:
		reconnect_button.disabled = false
		hud_label.text = "暂时无法重新进入世界（HTTP " + str(response_code) + "）：" + body.get_string_from_utf8()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		reconnect_button.disabled = false
		hud_label.text = "中心服返回了无效的世界入口信息。"
		return
	var host := str(parsed.get("host", ""))
	var port := int(parsed.get("udp_port", 0))
	var ticket := str(parsed.get("ticket", ""))
	if host.is_empty() or port < 1 or ticket.is_empty():
		reconnect_button.disabled = false
		hud_label.text = "中心服返回的重连信息不完整。"
		return

	if reconnect_network != null and is_instance_valid(reconnect_network):
		reconnect_network.close()
		reconnect_network.queue_free()
	reconnect_network = HHWorldNetwork.new()
	HHSession.add_child(reconnect_network)
	reconnect_network.welcomed.connect(_on_reconnected_welcomed)
	reconnect_network.rejected.connect(func(reason: String):
		hud_label.text = "世界服务器拒绝重连：" + reason
		reconnect_button.disabled = false
	)
	reconnect_network.connection_error.connect(func(message: String):
		hud_label.text = message
		reconnect_button.disabled = false
	)
	reconnect_network.disconnected.connect(func():
		reconnect_button.visible = true
		reconnect_button.disabled = false
	)
	hud_label.text = "正在重新连接世界服务器 " + host + ":" + str(port) + "……"
	var connect_error := reconnect_network.connect_with_ticket(host, port, ticket)
	if connect_error != OK:
		reconnect_button.disabled = false
		hud_label.text = "初始化重连失败，错误码：" + str(connect_error)

func _on_reconnected_welcomed(snapshot: Dictionary) -> void:
	var previous: HHWorldNetwork = HHSession.world_network
	HHSession.world_network = reconnect_network
	HHSession.world_snapshot = snapshot
	if previous != null and is_instance_valid(previous):
		if previous.disconnected.is_connected(_on_world_disconnected):
			previous.disconnected.disconnect(_on_world_disconnected)
		previous.close()
		previous.queue_free()
	if not reconnect_network.entities_updated.is_connected(_on_entities_updated):
		reconnect_network.entities_updated.connect(_on_entities_updated)
	if not reconnect_network.player_joined.is_connected(_on_player_joined):
		reconnect_network.player_joined.connect(_on_player_joined)
	if not reconnect_network.player_left.is_connected(_on_player_left):
		reconnect_network.player_left.connect(_on_player_left)
	if not reconnect_network.combat_event.is_connected(_on_combat_event):
		reconnect_network.combat_event.connect(_on_combat_event)
	if not reconnect_network.monster_action_event.is_connected(_on_monster_action_event):
		reconnect_network.monster_action_event.connect(_on_monster_action_event)
	if not reconnect_network.pickup_event.is_connected(_on_pickup_event):
		reconnect_network.pickup_event.connect(_on_pickup_event)
	if not reconnect_network.chat_event.is_connected(_on_chat_event):
		reconnect_network.chat_event.connect(_on_chat_event)
	local_target_position = Vector3(
		float(snapshot.get("position_x", 0.0)),
		float(snapshot.get("position_y", 0.15)),
		float(snapshot.get("position_z", 0.0))
	)
	local_player.position = local_target_position
	soul_essence_profile.clear()
	_apply_world_player_form()
	_request_soul_essence()
	for character_id in remote_players.keys():
		remote_players[character_id].queue_free()
	remote_players.clear()
	remote_targets.clear()
	remote_yaws.clear()
	for monster_id in monsters.keys():
		monsters[monster_id].queue_free()
	monsters.clear()
	monster_targets.clear()
	for drop_id in drops.keys():
		drops[drop_id].queue_free()
	drops.clear()
	drop_targets.clear()
	reconnect_button.visible = false
	reconnect_button.disabled = false
	hud_label.text = "已重新进入青云人界，角色已恢复到最近保存的位置。"
	_update_hud()

func _refresh_equipment() -> void:
	if equipment_http == null or HHSession.access_token.is_empty():
		return
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var error := equipment_http.request(HHSession.api_base + "/api/v1/characters/current/equipment", headers, HTTPClient.METHOD_GET)
	if error != OK:
		inventory_status.text = "读取装备栏失败，错误码：" + str(error)

func _on_equipment_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	for child in inventory_equipment.get_children():
		child.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		inventory_status.text = "装备栏读取失败：" + body.get_string_from_utf8()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var items: Array = parsed.get("items", [])
	var slots := ["weapon", "head", "chest", "legs", "boots", "accessory"]
	var labels := {"weapon":"武器", "head":"头部", "chest":"胸甲", "legs":"腿部", "boots":"鞋子", "accessory":"饰品"}
	var equipped: Dictionary = {}
	for item in items:
		if item is Dictionary:
			equipped[str(item.get("slot", ""))] = item
	for slot in slots:
		var row := HBoxContainer.new()
		inventory_equipment.add_child(row)
		var label := Label.new()
		var item: Dictionary = equipped.get(slot, {})
		label.text = str(labels[slot]) + "：" + (str(item.get("name", "未装备")) if not item.is_empty() else "未装备")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if not item.is_empty():
			var button := Button.new()
			button.text = "卸下"
			button.pressed.connect(_on_unequip_item_pressed.bind(slot))
			row.add_child(button)

func _on_equip_item_pressed(item_id: String, slot: String) -> void:
	_submit_equipment_action("equip", {"item_id": item_id, "slot": slot})

func _on_unequip_item_pressed(slot: String) -> void:
	_submit_equipment_action("unequip", {"slot": slot})

func _submit_equipment_action(action: String, payload: Dictionary) -> void:
	if equipment_action_busy or equipment_action_http == null:
		return
	equipment_action_busy = true
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token, "Content-Type: application/json"])
	var error := equipment_action_http.request(
		HHSession.api_base + "/api/v1/characters/current/equipment/" + action,
		headers, HTTPClient.METHOD_POST, JSON.stringify(payload)
	)
	if error != OK:
		equipment_action_busy = false
		inventory_status.text = "装备操作提交失败，错误码：" + str(error)

func _on_equipment_action_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	equipment_action_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		inventory_status.text = "装备操作失败：" + body.get_string_from_utf8()
		return
	inventory_status.text = "装备已更新。"
	_refresh_inventory()
	_refresh_equipment()

func _make_request_uuid() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return hex.substr(0,8) + "-" + hex.substr(8,4) + "-4" + hex.substr(13,3) + "-a" + hex.substr(17,3) + "-" + hex.substr(20,12)

func _on_use_consumable_pressed(item_id: String) -> void:
	if consumable_busy or consumable_http == null or item_id.is_empty():
		return
	consumable_busy = true
	var payload := {"request_id": _make_request_uuid(), "item_id": item_id, "quantity": 1}
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token, "Content-Type: application/json"])
	var error := consumable_http.request(
		HHSession.api_base + "/api/v1/characters/current/inventory/use",
		headers, HTTPClient.METHOD_POST, JSON.stringify(payload)
	)
	if error != OK:
		consumable_busy = false
		inventory_status.text = "使用物品请求失败，错误码：" + str(error)

func _on_consumable_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	consumable_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		inventory_status.text = "使用物品失败：" + body.get_string_from_utf8()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		if bool(parsed.get("applied", false)):
			inventory_status.text = "使用成功：生命 +" + str(parsed.get("health_restored", 0)) + "，灵力 +" + str(parsed.get("mana_restored", 0))
		else:
			inventory_status.text = "该使用请求已结算，正在同步背包。"
	_refresh_inventory()
	_refresh_equipment()

func _build_death_ui() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	death_panel = PanelContainer.new()
	death_panel.set_anchors_preset(Control.PRESET_CENTER)
	death_panel.offset_left = -230.0
	death_panel.offset_top = -115.0
	death_panel.offset_right = 230.0
	death_panel.offset_bottom = 115.0
	death_panel.visible = false
	death_panel.z_index = 100
	hud.add_child(death_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	death_panel.add_child(layout)
	var title := Label.new()
	title.text = "角色倒地"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)
	death_message_label = Label.new()
	death_message_label.text = "角色已倒地。"
	death_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	death_message_label.custom_minimum_size = Vector2(400.0, 90.0)
	layout.add_child(death_message_label)
	respawn_button = Button.new()
	respawn_button.text = "复活并返回角色界面"
	respawn_button.custom_minimum_size.y = 44.0
	respawn_button.pressed.connect(_on_respawn_pressed)
	layout.add_child(respawn_button)

func _on_respawn_pressed() -> void:
	if respawn_busy or HHSession.access_token.is_empty():
		return
	respawn_busy = true
	respawn_button.disabled = true
	hud_label.text = "正在返回冥界·酆都……"
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var error := respawn_http.request(
		HHSession.api_base + "/api/v1/characters/current/respawn",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	if error != OK:
		respawn_busy = false
		respawn_button.disabled = false
		hud_label.text = "提交复活请求失败，错误码：" + str(error)

func _on_respawn_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	respawn_busy = false
	respawn_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		death_message_label.text = "复活请求失败：\n" + body.get_string_from_utf8() + "\n请检查中心服后重试。"
		return
	death_message_label.text = "复活成功，正在返回角色界面……"
	if HHSession.world_network != null:
		HHSession.world_network.close()
		HHSession.world_network.queue_free()
		HHSession.world_network = null
	var change_error := get_tree().change_scene_to_file("res://scenes/Startup.tscn")
	if change_error != OK:
		death_message_label.text = "复活成功，但返回角色界面失败，错误码：" + str(change_error)


# ---------------- World NPC interaction ----------------

func _build_npc_ui() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	npc_interact_button = Button.new()
	npc_interact_button.text = "F · 与附近 NPC 交互"
	npc_interact_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	npc_interact_button.offset_left = -250.0
	npc_interact_button.offset_top = -76.0
	npc_interact_button.offset_right = -18.0
	npc_interact_button.offset_bottom = -30.0
	npc_interact_button.visible = false
	npc_interact_button.pressed.connect(_try_interact_nearest_npc)
	hud.add_child(npc_interact_button)
	exploration_open_button = Button.new()
	exploration_open_button.text = "探索本区域"
	exploration_open_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	exploration_open_button.offset_left = 18.0
	exploration_open_button.offset_top = -76.0
	exploration_open_button.offset_right = 180.0
	exploration_open_button.offset_bottom = -30.0
	exploration_open_button.pressed.connect(_request_exploration_points)
	hud.add_child(exploration_open_button)

	npc_panel = PanelContainer.new()
	npc_panel.set_anchors_preset(Control.PRESET_CENTER)
	npc_panel.offset_left = -230.0
	npc_panel.offset_top = -170.0
	npc_panel.offset_right = 230.0
	npc_panel.offset_bottom = 170.0
	npc_panel.visible = false
	hud.add_child(npc_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	npc_panel.add_child(layout)
	npc_title_label = Label.new()
	npc_title_label.add_theme_font_size_override("font_size", 22)
	npc_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(npc_title_label)
	npc_dialogue_label = Label.new()
	npc_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_dialogue_label.custom_minimum_size = Vector2(420.0, 120.0)
	npc_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(npc_dialogue_label)
	npc_status_label = Label.new()
	npc_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(npc_status_label)
	npc_choice_container = VBoxContainer.new()
	npc_choice_container.add_theme_constant_override("separation", 6)
	layout.add_child(npc_choice_container)
	var exploration_scroll := ScrollContainer.new()
	exploration_scroll.custom_minimum_size = Vector2(420.0, 110.0)
	exploration_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(exploration_scroll)
	exploration_container = VBoxContainer.new()
	exploration_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exploration_container.add_theme_constant_override("separation", 5)
	exploration_scroll.add_child(exploration_container)
	npc_trial_button = Button.new()
	npc_trial_button.text = "查看冥界试炼"
	npc_trial_button.pressed.connect(_request_soul_trials)
	layout.add_child(npc_trial_button)
	npc_eligibility_button = Button.new()
	npc_eligibility_button.text = "查看投胎资格"
	npc_eligibility_button.pressed.connect(_request_reincarnation_eligibility)
	layout.add_child(npc_eligibility_button)
	npc_fate_encounter_button = Button.new()
	npc_fate_encounter_button.text = "探查命格奇遇"
	npc_fate_encounter_button.visible = false
	npc_fate_encounter_button.pressed.connect(_discover_npc_fate_encounter)
	layout.add_child(npc_fate_encounter_button)
	npc_soul_button = Button.new()
	npc_soul_button.text = "查看灵魂境界"
	npc_soul_button.pressed.connect(_request_soul_progression)
	layout.add_child(npc_soul_button)
	npc_fusion_button = Button.new()
	npc_fusion_button.text = "查看魂质融合"
	npc_fusion_button.visible = false
	npc_fusion_button.pressed.connect(_request_soul_fusions)
	layout.add_child(npc_fusion_button)
	npc_soul_breakthrough_button = Button.new()
	npc_soul_breakthrough_button.text = "主动突破灵魂境界"
	npc_soul_breakthrough_button.visible = false
	npc_soul_breakthrough_button.pressed.connect(_request_soul_breakthrough)
	layout.add_child(npc_soul_breakthrough_button)
	npc_reincarnation_leave_button = Button.new()
	npc_reincarnation_leave_button.text = "返回角色界面办理轮回"
	npc_reincarnation_leave_button.visible = false
	npc_reincarnation_leave_button.pressed.connect(_leave_world_for_reincarnation)
	layout.add_child(npc_reincarnation_leave_button)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(func(): npc_panel.visible = false)
	layout.add_child(close_button)

	npc_http = HTTPRequest.new()
	npc_http.timeout = 12.0
	add_child(npc_http)
	npc_http.request_completed.connect(_on_npc_request_completed)

func _request_world_npcs() -> void:
	_send_npc_request("GET", "/api/v1/worlds/current/npcs", "list")

func _send_npc_request(method: String, path: String, context: String, payload: Dictionary = {}) -> void:
	if npc_http == null:
		push_warning("[NPC API] 请求未发送：HTTPRequest 节点为空，context=" + context)
		return
	if npc_request_busy:
		push_warning("[NPC API] 请求未发送：上一个请求仍在处理中，context=" + context)
		return
	if HHSession.access_token.is_empty():
		push_warning("[NPC API] 请求未发送：登录令牌为空，context=" + context)
		if npc_status_label != null: npc_status_label.text = "未登录或登录令牌已失效，请重新登录。"
		return
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var http_method := HTTPClient.METHOD_GET
	var body := ""
	if method == "POST":
		http_method = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	npc_request_context = context
	var request_url := HHSession.api_base + path
	print("[NPC API] -> ", method, " ", request_url, " context=", context)
	var error := npc_http.request(request_url, headers, http_method, body)
	if error != OK:
		npc_request_context = ""
		npc_status_label.text = "无法向中心服发送 NPC 请求，错误码：" + str(error)
	else:
		npc_request_busy = true
		print("[NPC API] request queued context=", context)

func _on_npc_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	npc_request_busy = false
	var context := npc_request_context
	npc_request_context = ""
	var raw := body.get_string_from_utf8()
	print("[NPC API] <- context=", context, " result=", result, " HTTP=", response_code, " body=", raw.substr(0, 800))
	if context != "eligibility" and npc_reincarnation_leave_button != null:
		npc_reincarnation_leave_button.visible = false
	if result != HTTPRequest.RESULT_SUCCESS:
		if npc_status_label != null:
			npc_status_label.text = "中心服请求连接失败，请检查网络。"
		if context == "list":
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-points", "exploration_bootstrap")
		return
	# Go 的 http.Error 会返回纯文本，必须先判断 HTTP 状态，不能把错误文本交给 JSON 解析器。
	if response_code < 200 or response_code >= 300:
		var error_text := raw.strip_edges()
		if error_text.length() > 240:
			error_text = error_text.substr(0, 240) + "……"
		if npc_status_label != null:
			npc_status_label.text = "请求未完成（HTTP " + str(response_code) + "）：" + error_text
		if context == "list":
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-points", "exploration_bootstrap")
		return
	var json_parser := JSON.new()
	var parse_error := json_parser.parse(raw)
	if parse_error != OK:
		if npc_status_label != null:
			npc_status_label.text = "服务器返回的数据格式异常（HTTP " + str(response_code) + "）：第 " + str(json_parser.get_error_line()) + " 行，" + json_parser.get_error_message()
		push_warning("NPC API returned invalid JSON: " + raw.substr(0, 500))
		return
	var parsed: Variant = json_parser.data
	if not parsed is Dictionary:
		if npc_status_label != null:
			npc_status_label.text = "服务器返回的数据不是 JSON 对象。"
		return
	var data: Dictionary = parsed
	match context:
		"list":
			npc_definitions = data.get("npcs", [])
			_render_world_npcs()
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-points", "exploration_bootstrap")
		"exploration_bootstrap":
			_render_exploration_points(data.get("points", []))
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-events", "exploration_events_bootstrap")
		"exploration_list":
			_render_exploration_points(data.get("points", []))
			npc_title_label.text = "区域探索 · 已发现记录"
			npc_dialogue_label.text = exploration_feedback if not exploration_feedback.is_empty() else "探索点由中心服依据角色实际位置验证。发现记录属于灵魂，轮回后仍会保留。"
			npc_status_label.text = "探索进度已同步。先调查地点，再回应已解锁的奇遇。"
			npc_panel.visible = true
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-events", "exploration_events")
		"exploration_events_bootstrap", "exploration_events":
			_render_exploration_events(data.get("events", []))
			_request_exploration_progress()
		"exploration_progress":
			_render_exploration_progress(data)
		"exploration_discover":
			var merit_delta := int(data.get("merit_delta", 0))
			var karma_delta := int(data.get("karma_delta", 0))
			var discovered_name := str(data.get("name", "探索点"))
			exploration_feedback = "已发现「" + discovered_name + "」。功德 " + ("+" if merit_delta >= 0 else "") + str(merit_delta) + "，业力 " + ("+" if karma_delta >= 0 else "") + str(karma_delta) + "。记录已永久写入灵魂因果簿。"
			_show_notification("探索发现 · " + discovered_name + "  已记入灵魂因果簿", 4.0)
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-points", "exploration_list")
		"exploration_event":
			var event_merit_delta := int(data.get("merit_delta", 0))
			var event_karma_delta := int(data.get("karma_delta", 0))
			var event_title := str(data.get("title", "未知奇遇"))
			pending_exploration_event_id = ""
			var chosen_text := str(data.get("choice_text", ""))
			var outcome_text := str(data.get("outcome", data.get("description", "")))
			exploration_feedback = "奇遇「" + event_title + "」已完成。\n你的选择：" + chosen_text + "\n" + outcome_text + "\n功德 " + ("+" if event_merit_delta >= 0 else "") + str(event_merit_delta) + "，业力 " + ("+" if event_karma_delta >= 0 else "") + str(event_karma_delta) + "。"
			_show_notification("奇遇完成 · " + event_title + "  因果已记录", 4.2)
			npc_title_label.text = "因果已定 · " + event_title
			npc_dialogue_label.text = exploration_feedback
			npc_status_label.text = "本次结果已由中心服写入灵魂因果簿。"
			_clear_npc_choice_buttons()
			npc_panel.visible = true
			_send_npc_request("GET", "/api/v1/worlds/current/exploration-points", "exploration_list")
		"interact":
			_clear_npc_choice_buttons()
			var npc_data: Dictionary = data.get("npc", {})
			var dialogue: Dictionary = data.get("dialogue", {})
			npc_current_interaction_id = str(npc_data.get("id", ""))
			npc_fate_encounter_button.visible = bool(npc_data.get("fate_encounter_available", false))
			npc_title_label.text = str(npc_data.get("name", "冥界来者")) + " · " + str(npc_data.get("title", ""))
			var lines: Array[String] = []
			lines.append(str(dialogue.get("greeting", "这位道友，有何事？")))
			var fate_reaction := str(npc_data.get("fate_reaction", ""))
			if not fate_reaction.is_empty():
				lines.append("")
				lines.append("【命格感应】" + fate_reaction)
			var topics: Variant = dialogue.get("topics", [])
			if topics is Array:
				for topic in topics:
					lines.append("· " + str(topic))
			npc_dialogue_label.text = "\n".join(PackedStringArray(lines))
			var choices: Variant = dialogue.get("choices", [])
			if choices is Array:
				for choice_variant in choices:
					if choice_variant is Dictionary:
						var choice: Dictionary = choice_variant
						var choice_button := Button.new()
						choice_button.text = str(choice.get("text", "选择"))
						choice_button.tooltip_text = str(choice.get("description", ""))
						choice_button.pressed.connect(_submit_npc_fate_choice.bind(str(npc_data.get("id", "")), str(choice.get("id", ""))))
						npc_choice_container.add_child(choice_button)
			npc_status_label.text = "交互已由中心服验证。选择会影响功德与业力；与该 NPC 的因果抉择只能作出一次。"
			npc_trial_button.visible = str(npc_data.get("interaction_type", "")) == "soul_trials"
			npc_eligibility_button.visible = str(npc_data.get("interaction_type", "")) == "reincarnation_guidance"
			npc_soul_button.visible = true
			npc_soul_breakthrough_button.visible = false
			npc_fusion_button.visible = str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu"
			npc_panel.visible = true
		"fate_encounter":
			npc_title_label.text = "命格奇遇 · " + str(data.get("title", "未知奇遇"))
			npc_dialogue_label.text = str(data.get("description", "奇遇已记入因果簿。")) + "\n功德：" + str(data.get("merit", 0)) + "（+" + str(data.get("merit_delta", 0)) + "）\n业力：" + str(data.get("karma", 0)) + "（" + str(data.get("karma_delta", 0)) + "）"
			npc_status_label.text = "这次奇遇已由中心服永久记入灵魂因果簿，每个灵魂只能发现一次。"
			npc_fate_encounter_button.visible = false
			_clear_npc_choice_buttons()
			npc_panel.visible = true
		"fate_choice":
			npc_title_label.text = "因果已记入 · " + str(data.get("npc_id", "NPC"))
			npc_dialogue_label.text = str(data.get("result", "此事已记入因果簿。")) + "\n功德：" + str(data.get("merit", 0)) + "（" + ("+" if int(data.get("merit_delta", 0)) >= 0 else "") + str(data.get("merit_delta", 0)) + "）" + "\n业力：" + str(data.get("karma", 0)) + "（" + ("+" if int(data.get("karma_delta", 0)) >= 0 else "") + str(data.get("karma_delta", 0)) + "）"
			npc_status_label.text = "该 NPC 的因果抉择已永久记录；不能再选择另一分支。"
			_clear_npc_choice_buttons()
			npc_trial_button.visible = false
			npc_eligibility_button.visible = false
			npc_soul_button.visible = true
			npc_soul_breakthrough_button.visible = false
			npc_panel.visible = true
		"trials":
			var trials: Array = data.get("trials", [])
			var lines: Array[String] = ["冥界试炼进度"]
			for trial in trials:
				if trial is Dictionary:
					var state := "已完成" if bool(trial.get("completed", false)) else "进行中"
					lines.append(str(trial.get("name", "试炼")) + "：" + str(trial.get("progress", 0)) + "/" + str(trial.get("target", 0)) + " · " + state)
					lines.append(str(trial.get("description", "")))
					if bool(trial.get("reward_granted", false)):
						lines.append("奖励已入账：" + str(trial.get("reward_experience", 0)) + " 灵魂经验")
			npc_dialogue_label.text = "\n".join(PackedStringArray(lines))
			npc_status_label.text = "任务进度来自中心服；击败怪物后会自动更新。"
			npc_trial_button.visible = true
			npc_eligibility_button.visible = false
			npc_soul_button.visible = true
			npc_soul_breakthrough_button.visible = false
			npc_reincarnation_leave_button.visible = false
			npc_panel.visible = true
		"soul_progression":
			var experience := int(data.get("experience", 0))
			var realm_name := str(data.get("realm_name", "未知"))
			var next_name := str(data.get("next_realm_name", ""))
			var next_required: Variant = data.get("next_required_experience", null)
			npc_title_label.text = "灵魂修炼 · " + realm_name
			if next_required == null:
				npc_dialogue_label.text = "当前灵魂经验：" + str(experience) + "\n已达到当前配置的最高灵魂境界。"
				npc_soul_breakthrough_button.visible = false
				npc_reincarnation_leave_button.visible = false
			else:
				npc_dialogue_label.text = "当前灵魂经验：" + str(experience) + "\n下一境界：" + next_name + "\n突破所需累计经验：" + str(next_required)
				npc_soul_breakthrough_button.visible = experience >= int(next_required)
			npc_status_label.text = "灵魂经验跨越轮回保留；达到门槛后仍需主动突破。"
			npc_trial_button.visible = false
			npc_eligibility_button.visible = false
			npc_soul_button.visible = true
			npc_panel.visible = true
		"soul_breakthrough":
			npc_title_label.text = "灵魂境界突破"
			npc_dialogue_label.text = "灵魂境界突破成功：" + str(data.get("realm_name", "新境界"))
			npc_status_label.text = "境界已由中心服更新，正在刷新灵魂经验。"
			npc_soul_breakthrough_button.visible = false
			npc_trial_button.visible = false
			npc_eligibility_button.visible = false
			npc_panel.visible = true
			_request_soul_progression()
		"soul_fusions":
			_clear_npc_choice_buttons()
			var recipes: Array = data.get("recipes", [])
			var lines: Array[String] = ["魂质融合 · 灵魂永久传承", "融合不会消耗或删除原始异变记录；每种配方每个灵魂只能完成一次。"]
			var attribute_names := {"strength":"力量","constitution":"体质","agility":"敏捷","spirit":"灵力","vitality":"气血"}
			for recipe_variant in recipes:
				if not recipe_variant is Dictionary:
					continue
				var recipe: Dictionary = recipe_variant
				var recipe_name := str(recipe.get("name", "未知融合"))
				var required: Array = recipe.get("required_attributes", [])
				var missing: Array = recipe.get("missing_attributes", [])
				var required_names: Array[String] = []
				var missing_names: Array[String] = []
				for attribute in required:
					required_names.append(str(attribute_names.get(str(attribute), str(attribute))))
				for attribute in missing:
					missing_names.append(str(attribute_names.get(str(attribute), str(attribute))))
				var state := "已融合" if bool(recipe.get("completed", false)) else ("材料齐备" if bool(recipe.get("available", false)) else "缺少：" + ", ".join(PackedStringArray(missing_names)))
				lines.append(recipe_name + "（" + ", ".join(PackedStringArray(required_names)) + "）· " + state)
				lines.append(str(recipe.get("description", "")))
				if bool(recipe.get("available", false)):
					var fuse_button := Button.new()
					fuse_button.text = "融合 · " + recipe_name
					fuse_button.pressed.connect(_fuse_soul_recipe.bind(str(recipe.get("id", "")), recipe_name))
					npc_choice_container.add_child(fuse_button)
			npc_title_label.text = "魂质融合 · 灵魂本源"
			npc_dialogue_label.text = "\n".join(PackedStringArray(lines))
			npc_status_label.text = "融合由中心服验证异变材料并结算来世资质；五种魂质异变齐全可尝试五行混元魂。"
			npc_fusion_button.visible = true
			npc_panel.visible = true
		"soul_fusion":
			npc_title_label.text = "魂质融合成功 · " + str(data.get("name", "灵魂异变"))
			npc_dialogue_label.text = str(data.get("description", "魂质已成功融合。")) + "\n融合结果已永久写入灵魂，并强化来世五维资质。"
			npc_status_label.text = "原始魂质异变仍完整保留；正在刷新灵魂档案。"
			_show_notification("魂质融合成功 · " + str(data.get("name", "新魂印")), 5.0)
			npc_fusion_button.visible = true
			npc_panel.visible = true
			_request_soul_essence()
			_request_soul_fusions()
		"eligibility":
			var realm := str(data.get("current_realm_name", "未知"))
			var required := str(data.get("required_realm_name", "聚灵境"))
			var completed := bool(data.get("trial_completed", false))
			var reasons: Array = data.get("reasons", [])
			var eligible := bool(data.get("eligible", false))
			npc_title_label.text = "轮回殿 · 投胎资格"
			npc_dialogue_label.text = "当前灵魂境界：" + realm + "\n要求灵魂境界：" + required + "\n引魂试炼：" + ("已完成" if completed else "尚未完成")
			npc_status_label.text = "已满足首次投胎条件。请先安全退出世界，再在角色界面选择新肉身名称与种族。" if eligible else "尚未满足条件：" + ", ".join(PackedStringArray(reasons))
			npc_trial_button.visible = false
			npc_eligibility_button.visible = true
			npc_soul_button.visible = true
			npc_soul_breakthrough_button.visible = false
			npc_reincarnation_leave_button.visible = eligible
			npc_reincarnation_leave_button.disabled = false
			npc_panel.visible = true

func _clear_npc_choice_buttons() -> void:
	if npc_choice_container == null:
		return
	for child in npc_choice_container.get_children():
		child.queue_free()



func _discover_npc_fate_encounter() -> void:
	if npc_request_busy or npc_current_interaction_id.is_empty():
		return
	npc_status_label.text = "正在探查命格与忘川因缘……"
	_send_npc_request("POST", "/api/v1/worlds/current/npcs/discover", "fate_encounter", {
		"npc_id": npc_current_interaction_id
	})


func _submit_npc_fate_choice(npc_id: String, choice_id: String) -> void:
	if npc_request_busy or npc_id.is_empty() or choice_id.is_empty():
		return
	npc_status_label.text = "正在向中心服提交因果选择……"
	_send_npc_request("POST", "/api/v1/worlds/current/npcs/choose", "fate_choice", {
		"npc_id": npc_id,
		"choice_id": choice_id
	})


func _leave_world_for_reincarnation() -> void:
	if leaving_for_reincarnation:
		return
	if HHSession.world_network == null or not is_instance_valid(HHSession.world_network):
		hud_label.text = "当前世界连接已不存在，正在返回角色界面……"
		_finish_leave_for_reincarnation()
		return
	leaving_for_reincarnation = true
	npc_reincarnation_leave_button.disabled = true
	npc_status_label.text = "正在保存当前位置并安全退出世界……"
	var network: HHWorldNetwork = HHSession.world_network
	if not network.disconnected.is_connected(_on_reincarnation_world_left):
		network.disconnected.connect(_on_reincarnation_world_left, CONNECT_ONE_SHOT)
	network.close()

func _on_reincarnation_world_left() -> void:
	_finish_leave_for_reincarnation()

func _finish_leave_for_reincarnation() -> void:
	var network: HHWorldNetwork = HHSession.world_network
	if network != null and is_instance_valid(network):
		if network.get_parent() == HHSession:
			HHSession.remove_child(network)
		network.queue_free()
	HHSession.world_network = null
	HHSession.world_snapshot = {}
	var error := get_tree().change_scene_to_file("res://scenes/Startup.tscn")
	if error != OK:
		leaving_for_reincarnation = false
		hud_label.text = "返回角色界面失败，错误码：" + str(error)

func _make_npc_part(parent: Node3D, part_name: String, mesh: Mesh, local_position: Vector3, color: Color, emissive: bool = false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = local_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.7
	part.material_override = material
	parent.add_child(part)
	return part

func _render_world_npcs() -> void:
	for npc_id in npc_nodes.keys():
		if is_instance_valid(npc_nodes[npc_id]):
			npc_nodes[npc_id].queue_free()
	npc_nodes.clear()
	for npc_variant in npc_definitions:
		if not (npc_variant is Dictionary):
			continue
		var npc_data: Dictionary = npc_variant
		var npc_id := str(npc_data.get("id", ""))
		if npc_id.is_empty():
			continue
		var npc_type := str(npc_data.get("npc_type", "guide"))
		var npc_name := str(npc_data.get("name", "NPC"))
		var marker := Node3D.new()
		marker.name = "NPC_" + npc_id
		marker.position = Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
		marker.rotation.y = float(npc_data.get("rotation_y", 0.0))

		var npc_visual := UnderworldVisualFactory.create_npc(npc_type, npc_name)
		marker.add_child(npc_visual)
		var accent_color := Color("#9bd8ce")
		match npc_type:
			"judge":
				accent_color = Color("#b99be8")
			"trial_master":
				accent_color = Color("#e5a16c")
			"guard":
				accent_color = Color("#a9c5d9")
			"soup_keeper":
				accent_color = Color("#9bd8ce")
			_:
				accent_color = Color("#e6c77d")

		var label := Label3D.new()
		var title := str(npc_data.get("title", ""))
		label.text = npc_name + (("\n" + title) if not title.is_empty() else "") + "\nF · 交互"
		label.position.y = 2.55
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = accent_color.lightened(0.35)
		marker.add_child(label)
		add_child(marker)
		npc_nodes[npc_id] = marker
	_update_nearest_npc_prompt()

func _animate_npc_visuals(delta: float) -> void:
	npc_animation_time += delta
	for npc_id in npc_nodes:
		var marker := npc_nodes[npc_id] as Node3D
		if not is_instance_valid(marker) or marker.get_child_count() == 0:
			continue
		var visual := marker.get_child(0) as Node3D
		if not is_instance_valid(visual):
			continue
		var phase := float(abs(hash(str(npc_id))) % 100) * 0.0628
		var breath := sin(npc_animation_time * 1.7 + phase)
		visual.position.y = breath * 0.018
		var left_arm := visual.get_node_or_null("ArmPivotLeft") as Node3D
		var right_arm := visual.get_node_or_null("ArmPivotRight") as Node3D
		if is_instance_valid(left_arm):
			left_arm.rotation.z = -0.035 + breath * 0.025
		if is_instance_valid(right_arm):
			right_arm.rotation.z = 0.035 - breath * 0.025
		var mist := visual.get_node_or_null("BowlMist") as Node3D
		if is_instance_valid(mist):
			mist.position.y = 1.16 + sin(npc_animation_time * 2.4 + phase) * 0.045
			var mist_scale := 1.0 + sin(npc_animation_time * 2.0 + phase) * 0.12
			mist.scale = Vector3.ONE * mist_scale

func _update_nearest_npc_prompt() -> void:
	if npc_interact_button == null or not is_instance_valid(local_player):
		return
	var nearest_npc_distance := INF
	var nearest_npc_name := ""
	for npc_variant in npc_definitions:
		if not (npc_variant is Dictionary):
			continue
		var npc_data: Dictionary = npc_variant
		var target := Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		var radius := float(npc_data.get("interaction_radius", 3.0))
		if distance <= radius and distance < nearest_npc_distance:
			nearest_npc_distance = distance
			nearest_npc_name = str(npc_data.get("name", "NPC"))
	if not nearest_npc_name.is_empty():
		npc_interact_button.visible = true
		npc_interact_button.text = "F · 与 " + nearest_npc_name + " 交互"
		return

	var nearest_point_id := ""
	var nearest_point_name := ""
	var nearest_point_distance := INF
	var nearest_point_radius := 4.0
	for point_id in exploration_point_data.keys():
		var point: Dictionary = exploration_point_data.get(point_id, {})
		if bool(point.get("discovered", false)):
			continue
		var target := Vector3(float(point.get("position_x", 0.0)), float(point.get("position_y", 0.0)), float(point.get("position_z", 0.0)))
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		if distance < nearest_point_distance:
			nearest_point_distance = distance
			nearest_point_id = str(point_id)
			nearest_point_name = str(point.get("name", "未知地点"))
			nearest_point_radius = float(point.get("interaction_radius", 4.0))
	npc_interact_button.visible = not nearest_point_id.is_empty() and nearest_point_distance <= 32.0
	if npc_interact_button.visible:
		if nearest_point_distance <= nearest_point_radius:
			npc_interact_button.text = "F · 发现：" + nearest_point_name
		else:
			npc_interact_button.text = "探索点：" + nearest_point_name + " · " + str(roundi(nearest_point_distance)) + "m"

func _try_interact_nearest_npc() -> void:
	if npc_request_busy or not is_instance_valid(local_player):
		return
	var nearest_npc_id := ""
	var nearest_npc_distance := INF
	for npc_variant in npc_definitions:
		if not (npc_variant is Dictionary):
			continue
		var npc_data: Dictionary = npc_variant
		var target := Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		if distance <= float(npc_data.get("interaction_radius", 3.0)) and distance < nearest_npc_distance:
			nearest_npc_distance = distance
			nearest_npc_id = str(npc_data.get("id", ""))
	if not nearest_npc_id.is_empty():
		npc_selected_id = nearest_npc_id
		npc_status_label.text = "正在与 NPC 建立交互……"
		_send_npc_request("POST", "/api/v1/worlds/current/npcs/interact", "interact", {"npc_id": nearest_npc_id})
		return

	var nearest_point_id := ""
	var nearest_point_distance := INF
	for point_id in exploration_point_data.keys():
		var point: Dictionary = exploration_point_data.get(point_id, {})
		if bool(point.get("discovered", false)):
			continue
		var target := Vector3(float(point.get("position_x", 0.0)), float(point.get("position_y", 0.0)), float(point.get("position_z", 0.0)))
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		if distance <= float(point.get("interaction_radius", 4.0)) and distance < nearest_point_distance:
			nearest_point_distance = distance
			nearest_point_id = str(point_id)
	if not nearest_point_id.is_empty():
		_discover_exploration_point(nearest_point_id)

func _request_soul_fusions() -> void:
	if npc_request_busy:
		return
	npc_status_label.text = "正在核验灵魂已觉醒的魂质异变……"
	_send_npc_request("GET", "/api/v1/souls/current/fusions", "soul_fusions")

func _fuse_soul_recipe(recipe_id: String, recipe_name: String) -> void:
	if npc_request_busy or recipe_id.is_empty():
		return
	npc_status_label.text = "正在融合「" + recipe_name + "」，由中心服校验材料与来世资质……"
	_send_npc_request("POST", "/api/v1/souls/current/fusions", "soul_fusion", {"recipe_id": recipe_id})

func _request_soul_trials() -> void:
	if npc_request_busy:
		return
	npc_status_label.text = "正在读取中心服试炼进度……"
	_send_npc_request("GET", "/api/v1/souls/current/trials", "trials")

func _request_reincarnation_eligibility() -> void:
	if npc_request_busy:
		return
	npc_status_label.text = "正在核验灵魂境界与试炼记录……"
	_send_npc_request("GET", "/api/v1/souls/current/reincarnation-eligibility", "eligibility")


func _request_soul_progression() -> void:
	if npc_request_busy:
		return
	npc_status_label.text = "正在读取跨世保留的灵魂经验……"
	_send_npc_request("GET", "/api/v1/souls/current/progression", "soul_progression")

func _request_soul_breakthrough() -> void:
	if npc_request_busy:
		return
	npc_status_label.text = "正在向中心服申请灵魂境界突破……"
	_send_npc_request("POST", "/api/v1/souls/current/breakthrough", "soul_breakthrough", {})


func _request_exploration_points() -> void:
	if npc_request_busy:
		return
	exploration_feedback = ""
	npc_title_label.text = "正在读取区域探索点……"
	npc_dialogue_label.text = "正在向中心服查询本世界的探索记录。"
	npc_panel.visible = true
	_send_npc_request("GET", "/api/v1/worlds/current/exploration-points", "exploration_list")

func _request_exploration_progress() -> void:
	if npc_request_busy:
		return
	_send_npc_request("GET", "/api/v1/worlds/current/exploration-progress", "exploration_progress")


func _render_exploration_points(points: Variant) -> void:
	if exploration_container == null:
		return
	for marker_id in exploration_markers.keys():
		var old_marker: Node3D = exploration_markers[marker_id]
		if is_instance_valid(old_marker):
			old_marker.queue_free()
	exploration_markers.clear()
	exploration_buttons.clear()
	exploration_point_data.clear()
	exploration_event_buttons.clear()
	exploration_event_data.clear()
	for child in exploration_container.get_children():
		child.queue_free()
	if not points is Array or points.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前世界暂未配置探索点。"
		exploration_container.add_child(empty_label)
		return
	for point_variant in points:
		if not point_variant is Dictionary:
			continue
		var point: Dictionary = point_variant
		var discovered := bool(point.get("discovered", false))
		var point_id := str(point.get("id", ""))
		_create_exploration_marker(point)
		var point_button := Button.new()
		var danger := int(point.get("danger_level", 1))
		var target := Vector3(float(point.get("position_x", 0.0)), float(point.get("position_y", 0.0)), float(point.get("position_z", 0.0)))
		var distance := local_player.global_position.distance_to(target) if is_instance_valid(local_player) else INF
		var radius := float(point.get("interaction_radius", 4.0))
		var state_text := "已发现" if discovered else ("调查" if distance <= radius else "未抵达 · " + str(roundi(distance)) + "m")
		point_button.text = str(point.get("region_name", "未知区域")) + " · " + state_text + " · " + str(point.get("name", "未知地点")) + "  | 危险 " + str(danger) + "/10"
		point_button.disabled = discovered or distance > radius or npc_request_busy
		point_button.tooltip_text = str(point.get("description", ""))
		point_button.pressed.connect(_discover_exploration_point.bind(point_id))
		exploration_container.add_child(point_button)
		exploration_buttons[point_id] = point_button
		exploration_point_data[point_id] = point.duplicate(true)


func _exploration_percent(done: int, total: int) -> int:
	if total <= 0:
		return 0
	return clampi(roundi(float(done) * 100.0 / float(total)), 0, 100)


func _exploration_bar(percent: int) -> String:
	var filled := roundi(float(percent) / 10.0)
	var bar := ""
	for index in range(10):
		bar += "■" if index < filled else "□"
	return bar


func _render_exploration_progress(data: Dictionary) -> void:
	if exploration_container == null:
		return
	if exploration_progress_label == null or not is_instance_valid(exploration_progress_label):
		exploration_progress_label = Label.new()
		exploration_progress_label.name = "ExplorationProgressSummary"
		exploration_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		exploration_progress_label.add_theme_font_size_override("font_size", 15)
		exploration_container.add_child(exploration_progress_label)
	exploration_container.move_child(exploration_progress_label, 0)
	var total_points := int(data.get("total_points", 0))
	var discovered_points := int(data.get("discovered_points", 0))
	var total_events := int(data.get("total_events", 0))
	var claimed_events := int(data.get("claimed_events", 0))
	var point_percent := _exploration_percent(discovered_points, total_points)
	var event_percent := _exploration_percent(claimed_events, total_events)
	var lines: Array[String] = []
	lines.append("【灵魂探索总览】地点 %d/%d · %d%%" % [discovered_points, total_points, point_percent])
	lines.append(_exploration_bar(point_percent) + "  奇遇 %d/%d · %d%%" % [claimed_events, total_events, event_percent])
	var regions: Variant = data.get("regions", [])
	if regions is Array:
		for region_variant in regions:
			if not region_variant is Dictionary:
				continue
			var region: Dictionary = region_variant
			var region_points := int(region.get("total_points", 0))
			var region_discovered := int(region.get("discovered_points", 0))
			var region_events := int(region.get("total_events", 0))
			var region_claimed := int(region.get("claimed_events", 0))
			var region_percent := _exploration_percent(region_discovered, region_points)
			lines.append("%s  地点 %d/%d · %d%%" % [
				str(region.get("region_name", region.get("region_id", "未知区域"))),
				region_discovered, region_points, region_percent
			])
			lines.append(_exploration_bar(region_percent) + "  奇遇 %d/%d（%d%%）" % [
				region_claimed, region_events, _exploration_percent(region_claimed, region_events)
			])
	exploration_progress_label.text = "\n".join(PackedStringArray(lines))


func _exploration_event_state_text(event: Dictionary, distance: float) -> String:
	var status := str(event.get("status", "locked"))
	var in_range := distance <= float(event.get("interaction_radius", 4.0))
	match status:
		"completed":
			return "已完成"
		"available":
			return "触发奇遇" if in_range else "待触发 · 距离 %dm" % roundi(distance)
		_:
			return "未解锁 · 需满足前置因果并发现地点"


func _render_exploration_events(events: Variant) -> void:
	if exploration_container == null or not events is Array:
		return
	for event_button_id in exploration_event_buttons.keys():
		var old_button: Button = exploration_event_buttons[event_button_id]
		if is_instance_valid(old_button):
			old_button.queue_free()
	exploration_event_buttons.clear()
	exploration_event_data.clear()
	var heading := Label.new()
	heading.text = "区域奇遇 · 灵魂因果记录"
	heading.add_theme_font_size_override("font_size", 18)
	exploration_container.add_child(heading)
	if events.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前世界尚无配置的奇遇。"
		exploration_container.add_child(empty_label)
		return
	for event_variant in events:
		if not event_variant is Dictionary:
			continue
		var event: Dictionary = event_variant
		var event_id := str(event.get("id", ""))
		if event_id.is_empty():
			continue
		var target := Vector3(float(event.get("position_x", 0.0)), float(event.get("position_y", 0.0)), float(event.get("position_z", 0.0)))
		var distance := local_player.global_position.distance_to(target) if is_instance_valid(local_player) else INF
		var in_range := distance <= float(event.get("interaction_radius", 4.0))
		var status := str(event.get("status", "locked"))
		var state_text := _exploration_event_state_text(event, distance)
		var event_button := Button.new()
		event_button.text = str(event.get("point_name", "探索地点")) + " · " + str(event.get("title", "未知奇遇")) + " · " + state_text
		event_button.tooltip_text = str(event.get("description", ""))
		event_button.disabled = status != "available" or not in_range or npc_request_busy
		if status == "available":
			event_button.pressed.connect(_open_exploration_event.bind(event_id))
		exploration_container.add_child(event_button)
		exploration_event_buttons[event_id] = event_button
		exploration_event_data[event_id] = event.duplicate(true)


func _open_exploration_event(event_id: String) -> void:
	if not exploration_event_data.has(event_id):
		return
	var event: Dictionary = exploration_event_data[event_id]
	if str(event.get("status", "locked")) != "available":
		return
	var target := Vector3(float(event.get("position_x", 0.0)), float(event.get("position_y", 0.0)), float(event.get("position_z", 0.0)))
	var distance := local_player.global_position.distance_to(target) if is_instance_valid(local_player) else INF
	if distance > float(event.get("interaction_radius", 4.0)):
		npc_status_label.text = "尚未抵达奇遇地点，距离约 %dm。" % roundi(distance)
		return
	pending_exploration_event_id = event_id
	_clear_npc_choice_buttons()
	npc_title_label.text = "因果奇遇 · " + str(event.get("title", "未知奇遇"))
	npc_dialogue_label.text = str(event.get("description", "一段因果正在等待你的回应。")) + "\n\n地点：" + str(event.get("point_name", "未知地点")) + "\n\n你的选择会影响功德与业力，并永久记入灵魂因果簿。每个奇遇只能选择一次。"
	npc_status_label.text = "请选择你对这段因果的回应。不同选择会产生不同结果，具体结算由中心服裁定。"
	var choices: Variant = event.get("choices", [])
	var choice_count := 0
	if choices is Array:
		for choice_variant in choices:
			if not choice_variant is Dictionary:
				continue
			var choice: Dictionary = choice_variant
			var choice_id := str(choice.get("id", ""))
			if choice_id.is_empty():
				continue
			var choice_button := Button.new()
			choice_button.text = str(choice.get("text", "作出回应"))
			choice_button.tooltip_text = str(choice.get("description", ""))
			choice_button.pressed.connect(_confirm_exploration_event.bind(choice_id))
			npc_choice_container.add_child(choice_button)
			choice_count += 1
	if choice_count == 0:
		npc_status_label.text = "此奇遇尚未配置有效分支，暂时无法回应。"
	var cancel_button := Button.new()
	cancel_button.text = "暂不回应"
	cancel_button.pressed.connect(_cancel_exploration_event)
	npc_choice_container.add_child(cancel_button)
	npc_trial_button.visible = false
	npc_eligibility_button.visible = false
	npc_fate_encounter_button.visible = false
	npc_soul_button.visible = false
	npc_soul_breakthrough_button.visible = false
	npc_reincarnation_leave_button.visible = false
	npc_panel.visible = true


func _confirm_exploration_event(choice_id: String) -> void:
	if pending_exploration_event_id.is_empty() or choice_id.is_empty() or npc_request_busy:
		return
	var event_id := pending_exploration_event_id
	npc_status_label.text = "正在向中心服验证你的选择、位置与因果资格……"
	# npc_request_busy prevents duplicate submissions while preserving the
	# ability to cancel or retry if the center server rejects the request.
	_send_npc_request("POST", "/api/v1/worlds/current/exploration-events/trigger", "exploration_event", {
		"event_id": event_id,
		"choice_id": choice_id
	})


func _cancel_exploration_event() -> void:
	pending_exploration_event_id = ""
	_clear_npc_choice_buttons()
	npc_panel.visible = false


func _trigger_exploration_event(event_id: String) -> void:
	# Kept as a compatibility entry point for any older scene binding.
	_open_exploration_event(event_id)


func _discover_exploration_point(point_id: String) -> void:
	if npc_request_busy or point_id.is_empty():
		return
	npc_status_label.text = "正在验证距离并记录探索发现……"
	_send_npc_request("POST", "/api/v1/worlds/current/exploration-points/discover", "exploration_discover", {
		"point_id": point_id
	})



func _add_exploration_marker_mesh(marker: Node3D, node_name: String, mesh: Mesh, local_position: Vector3, color: Color, emissive: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if emissive:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	instance.material_override = material
	marker.add_child(instance)
	return instance


func _create_exploration_marker(point: Dictionary) -> void:
	var point_id := str(point.get("id", ""))
	if point_id.is_empty():
		return
	var marker := Node3D.new()
	marker.name = "Exploration_" + point_id
	marker.position = Vector3(
		float(point.get("position_x", 0.0)),
		float(point.get("position_y", 0.0)) + 0.08,
		float(point.get("position_z", 0.0))
	)
	var discovered := bool(point.get("discovered", false))
	var marker_color := Color("#79c8a4") if discovered else Color("#e7bd69")
	var stone_color := Color("#52645e") if discovered else Color("#74634f")
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.72
	ring_mesh.outer_radius = 0.9
	var ring := _add_exploration_marker_mesh(marker, "Ring", ring_mesh, Vector3.ZERO, marker_color, true)

	# Each authored point has its own silhouette; unknown future points retain a simple beacon.
	match point_id:
		"fengdu_gate_soul_lantern":
			var post := CylinderMesh.new()
			post.top_radius = 0.07
			post.bottom_radius = 0.11
			post.height = 1.15
			_add_exploration_marker_mesh(marker, "LanternStand", post, Vector3(0, 0.58, 0), stone_color)
			var body := BoxMesh.new()
			body.size = Vector3(0.58, 0.58, 0.48)
			_add_exploration_marker_mesh(marker, "LanternBody", body, Vector3(0, 1.35, 0), marker_color, true)
			var roof := CylinderMesh.new()
			roof.top_radius = 0.22
			roof.bottom_radius = 0.42
			roof.height = 0.18
			_add_exploration_marker_mesh(marker, "LanternRoof", roof, Vector3(0, 1.73, 0), stone_color)
			var flame := SphereMesh.new()
			flame.radius = 0.14
			flame.height = 0.3
			_add_exploration_marker_mesh(marker, "SoulFlame", flame, Vector3(0, 1.36, 0), marker_color, true)
		"forgotten_river_echo_stone":
			var slab := BoxMesh.new()
			slab.size = Vector3(0.82, 1.55, 0.34)
			var stone := _add_exploration_marker_mesh(marker, "EchoStone", slab, Vector3(0, 0.82, 0), stone_color)
			stone.rotation.z = -0.1
			var echo_mesh := TorusMesh.new()
			echo_mesh.inner_radius = 0.28
			echo_mesh.outer_radius = 0.34
			var echo := _add_exploration_marker_mesh(marker, "EchoEtching", echo_mesh, Vector3(0, 1.0, 0.2), marker_color, true)
			echo.rotation.x = PI / 2.0
		"naihe_bridge_soul_mark":
			var seal := CylinderMesh.new()
			seal.top_radius = 0.22
			seal.bottom_radius = 0.3
			seal.height = 0.16
			_add_exploration_marker_mesh(marker, "SoulSeal", seal, Vector3(0, 0.12, 0), marker_color, true)
			for pillar_index in range(3):
				var angle := TAU * float(pillar_index) / 3.0
				var pillar := CylinderMesh.new()
				pillar.top_radius = 0.045
				pillar.bottom_radius = 0.075
				pillar.height = 0.62
				_add_exploration_marker_mesh(marker, "SealPillar" + str(pillar_index), pillar, Vector3(cos(angle) * 0.48, 0.31, sin(angle) * 0.48), stone_color)
		"fengdu_ancient_battlefield":
			var altar := BoxMesh.new()
			altar.size = Vector3(2.2, 0.32, 1.5)
			_add_exploration_marker_mesh(marker, "BattlefieldAltar", altar, Vector3(0, 0.28, 0), stone_color)
			for blade_index in range(3):
				var blade := BoxMesh.new()
				blade.size = Vector3(0.12, 1.25 + float(blade_index) * 0.18, 0.2)
				var blade_node := _add_exploration_marker_mesh(marker, "BrokenWarBlade" + str(blade_index), blade, Vector3(-0.62 + float(blade_index) * 0.62, 0.95, 0.0), marker_color, true)
				blade_node.rotation.z = -0.16 + float(blade_index) * 0.13
			var battle_ring := TorusMesh.new()
			battle_ring.inner_radius = 0.48
			battle_ring.outer_radius = 0.55
			var ring_node := _add_exploration_marker_mesh(marker, "BattlefieldSeal", battle_ring, Vector3(0, 0.56, 0), marker_color, true)
			ring_node.rotation.x = PI / 2.0
		"fengdu_lantern_shadow_trace":
			var shadow_stone := CylinderMesh.new()
			shadow_stone.top_radius = 0.24
			shadow_stone.bottom_radius = 0.34
			shadow_stone.height = 0.42
			_add_exploration_marker_mesh(marker, "ShadowStone", shadow_stone, Vector3(0, 0.24, 0), stone_color)
			var shadow_flame := SphereMesh.new()
			shadow_flame.radius = 0.22
			shadow_flame.height = 0.62
			_add_exploration_marker_mesh(marker, "ShadowFlame", shadow_flame, Vector3(0, 0.92, 0), marker_color, true)
			var shadow_halo_mesh := TorusMesh.new()
			shadow_halo_mesh.inner_radius = 0.32
			shadow_halo_mesh.outer_radius = 0.38
			var shadow_halo := _add_exploration_marker_mesh(marker, "ShadowHalo", shadow_halo_mesh, Vector3(0, 0.94, 0), marker_color, true)
			shadow_halo.rotation.x = PI / 2.0
		"reincarnation_hall_tablet":
			var tablet_mesh := BoxMesh.new()
			tablet_mesh.size = Vector3(0.9, 1.65, 0.28)
			_add_exploration_marker_mesh(marker, "ReincarnationTablet", tablet_mesh, Vector3(0, 0.88, 0), stone_color)
			var cap := BoxMesh.new()
			cap.size = Vector3(1.08, 0.16, 0.38)
			_add_exploration_marker_mesh(marker, "TabletCap", cap, Vector3(0, 1.78, 0), marker_color)
			for line_index in range(3):
				var inscription := BoxMesh.new()
				inscription.size = Vector3(0.42, 0.035, 0.025)
				_add_exploration_marker_mesh(marker, "Inscription" + str(line_index), inscription, Vector3(0, 1.28 - float(line_index) * 0.22, 0.16), marker_color, true)
		_:
			var beacon_mesh := CylinderMesh.new()
			beacon_mesh.top_radius = 0.035
			beacon_mesh.bottom_radius = 0.035
			beacon_mesh.height = 1.35
			_add_exploration_marker_mesh(marker, "Beacon", beacon_mesh, Vector3(0, 0.72, 0), marker_color, true)

	var title := Label3D.new()
	title.text = ("已发现 · " if discovered else "探索 · ") + str(point.get("name", "未知地点")) + ("" if discovered else "\nF · 靠近后调查")
	title.position.y = 2.15 if point_id == "reincarnation_hall_tablet" or point_id == "forgotten_river_echo_stone" else 2.0
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.font_size = 28
	title.modulate = marker_color
	marker.add_child(title)
	add_child(marker)
	marker.set_meta("base_y", marker.position.y)
	marker.set_meta("phase", float(abs(point_id.hash()) % 1000) / 1000.0 * TAU)
	marker.set_meta("discovered", discovered)
	exploration_markers[point_id] = marker


func _animate_exploration_markers(delta: float) -> void:
	exploration_animation_time += delta
	for marker_id in exploration_markers.keys():
		var marker: Node3D = exploration_markers[marker_id]
		if not is_instance_valid(marker):
			continue
		var phase := float(marker.get_meta("phase", 0.0))
		var discovered := bool(marker.get_meta("discovered", false))
		var speed := 1.25 if discovered else 2.1
		var amplitude := 0.035 if discovered else 0.13
		var base_y := float(marker.get_meta("base_y", marker.position.y))
		marker.position.y = base_y + sin(exploration_animation_time * speed + phase) * amplitude
		var ring := marker.get_node_or_null("Ring") as MeshInstance3D
		if ring != null:
			var pulse := 1.0 + sin(exploration_animation_time * (1.5 if discovered else 2.8) + phase) * (0.025 if discovered else 0.09)
			ring.scale = Vector3.ONE * pulse
		var beacon := marker.get_node_or_null("Beacon") as MeshInstance3D
		if beacon != null:
			beacon.rotation.y = sin(exploration_animation_time * 0.8 + phase) * 0.12


func _update_exploration_proximity() -> void:
	if not is_instance_valid(local_player):
		return
	for point_id in exploration_buttons.keys():
		var point: Dictionary = exploration_point_data.get(point_id, {})
		var point_button: Button = exploration_buttons[point_id]
		if not is_instance_valid(point_button):
			continue
		var discovered := bool(point.get("discovered", false))
		if discovered:
			point_button.disabled = true
			continue
		var target := Vector3(
			float(point.get("position_x", 0.0)),
			float(point.get("position_y", 0.0)),
			float(point.get("position_z", 0.0))
		)
		var distance := local_player.global_position.distance_to(target)
		var in_range := distance <= float(point.get("interaction_radius", 4.0))
		point_button.disabled = not in_range or npc_request_busy
		var danger := int(point.get("danger_level", 1))
		point_button.text = str(point.get("region_name", "未知区域")) + " · " + ("调查" if in_range else "未抵达 · " + str(roundi(distance)) + "m") + " · " + str(point.get("name", "未知地点")) + "  | 危险 " + str(danger) + "/10"
	for event_id in exploration_event_buttons.keys():
		var event: Dictionary = exploration_event_data.get(event_id, {})
		var event_button: Button = exploration_event_buttons[event_id]
		if not is_instance_valid(event_button):
			continue
		var event_target := Vector3(float(event.get("position_x", 0.0)), float(event.get("position_y", 0.0)), float(event.get("position_z", 0.0)))
		var event_distance := local_player.global_position.distance_to(event_target)
		var event_in_range := event_distance <= float(event.get("interaction_radius", 4.0))
		var event_status := str(event.get("status", "locked"))
		event_button.disabled = event_status != "available" or not event_in_range or npc_request_busy
		event_button.text = str(event.get("point_name", "探索地点")) + " · " + str(event.get("title", "未知奇遇")) + " · " + _exploration_event_state_text(event, event_distance)
