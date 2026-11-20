extends Node3D

const UnderworldVisualFactory = preload("res://scripts/underworld_visual_factory.gd")
const VisualModelLibrary = preload("res://scripts/visual_model_library.gd")
const EquipmentVisualFactory = preload("res://scripts/equipment_visual_factory.gd")
const HumanoidAnimationDriver = preload("res://scripts/humanoid_animation_driver.gd")
const MonsterAnimationDriver = preload("res://scripts/monster_animation_driver.gd")
const QingyunVisualFactory = preload("res://scripts/qingyun_visual_factory.gd")
const FriendPanelScript = preload("res://scripts/friend_panel.gd")
const WorldMiniMapScript = preload("res://scripts/world_minimap.gd")
const WorldRegionCatalog = preload("res://scripts/world_region_catalog.gd")
const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const WorldMapViewScript = preload("res://scripts/world_map_view.gd")
const WorldTerrainBuilder = preload("res://scripts/world_terrain_builder.gd")
const WorldEnvironmentBuilder = preload("res://scripts/world_environment_builder.gd")

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
var chat_scroll: ScrollContainer
var chat_toggle_button: Button
var chat_title_label: Label
var chat_unread_badge: Label
var friend_panel: Variant
var selected_friend_character_id := ""
var selected_friend_character_name := ""
var chat_channel_buttons: Array[Button] = []
var chat_unread_count := 0
var chat_expanded := false
var chat_restore_mouse_captured := false
var chat_order_sequence := 0
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
var mana_label: Label
var health_bar: ProgressBar
var mana_bar: ProgressBar
var spell_cooldown_labels: Dictionary = {}
var spell_cooldown_remaining: Dictionary = {"fireball": 0.0, "ice_bolt": 0.0}
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
var target_health_bar: ProgressBar
var minimap_panel: PanelContainer
var world_map_panel: PanelContainer
var world_map_canvas: Control
var world_map_open_button: Button
var world_map_restore_mouse_captured := false
var minimap_view: Control
var minimap_region_label: Label
var minimap_exploration_label: Label
var minimap_navigation_label: Label
var minimap_clear_navigation_button: Button
var minimap_navigation_target: Dictionary = {}
var minimap_refresh_accumulator := 0.0
var target_selection_ring: MeshInstance3D
var floating_combat_labels: Dictionary = {}
var floating_combat_lifetimes: Dictionary = {}
var drops: Dictionary = {}
var drop_targets: Dictionary = {}
var projectiles: Dictionary = {}
var projectile_targets: Dictionary = {}
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
var player_slow_visual_remaining := 0.0
var player_poison_visual_remaining := 0.0
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
	if not HHChatNetwork.conversation_history_received.is_connected(_on_chat_conversation_history_received):
		HHChatNetwork.conversation_history_received.connect(_on_chat_conversation_history_received)
	if not HHChatNetwork.connected.is_connected(_on_chat_socket_connected):
		HHChatNetwork.connected.connect(_on_chat_socket_connected)
	if not HHChatNetwork.connection_error.is_connected(_on_chat_socket_error):
		HHChatNetwork.connection_error.connect(_on_chat_socket_error)
	if not HHSession.access_token.is_empty():
		HHChatNetwork.connect_chat(HHSession.get_chat_api_base(), HHSession.access_token)
	_build_combat_hud()
	_build_minimap_hud()
	_build_world_map_hud()
	_build_input_debug_hud()
	if HHSession.world_network != null:
		HHSession.world_network.entities_updated.connect(_on_entities_updated)
		HHSession.world_network.player_joined.connect(_on_player_joined)
		HHSession.world_network.player_left.connect(_on_player_left)
		HHSession.world_network.combat_event.connect(_on_combat_event)
		HHSession.world_network.monster_action_event.connect(_on_monster_action_event)
		HHSession.world_network.player_action_event.connect(_on_player_action_event)
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
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()
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
	var character_variant: Variant = data.get("character", {})
	if is_instance_valid(local_player):
		var birth_data: Dictionary = character_variant.get("birth_inheritance", {}) if character_variant is Dictionary else {}
		local_player.set_birth_inheritance_visuals(birth_data)
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
	add_child(WorldEnvironmentBuilder.build(world_id))

func _build_terrain() -> void:
	var world_id := str(HHSession.world_snapshot.get("world_id", "qingyun_human"))
	add_child(WorldTerrainBuilder.build(world_id))

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
	compact_hud_panel.custom_minimum_size = Vector2(340.0, 112.0)
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
	compact_hud_label.custom_minimum_size = Vector2(316.0, 92.0)
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

func _build_minimap_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	minimap_panel = PanelContainer.new()
	minimap_panel.name = "WorldMiniMapPanel"
	minimap_panel.custom_minimum_size = Vector2(184.0, 300.0)
	_apply_panel_theme(minimap_panel)
	hud.add_child(minimap_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	minimap_panel.add_child(layout)
	var header := Label.new()
	header.text = "附近地图 · 北向上"
	header.add_theme_color_override("font_color", Color("#d4b47b"))
	header.add_theme_font_size_override("font_size", 13)
	layout.add_child(header)
	world_map_open_button = Button.new()
	world_map_open_button.text = "打开世界地图"
	world_map_open_button.custom_minimum_size.y = 28.0
	_apply_button_theme(world_map_open_button)
	world_map_open_button.pressed.connect(_toggle_world_map)
	layout.add_child(world_map_open_button)
	minimap_region_label = Label.new()
	minimap_region_label.text = current_region_name if not current_region_name.is_empty() else "正在定位区域…"
	minimap_region_label.add_theme_color_override("font_color", Color("#a9bac7"))
	minimap_region_label.add_theme_font_size_override("font_size", 11)
	layout.add_child(minimap_region_label)
	minimap_exploration_label = Label.new()
	minimap_exploration_label.text = "本区域探索 0 / 0"
	minimap_exploration_label.add_theme_color_override("font_color", Color("#d6c49f"))
	minimap_exploration_label.add_theme_font_size_override("font_size", 10)
	layout.add_child(minimap_exploration_label)
	minimap_view = Control.new()
	minimap_view.name = "LiveMapCanvas"
	minimap_view.set_script(WorldMiniMapScript)
	minimap_view.connect("marker_selected", Callable(self, "_on_minimap_marker_selected"))
	minimap_view.custom_minimum_size = Vector2(156.0, 156.0)
	minimap_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(minimap_view)
	var legend := Label.new()
	legend.text = "金 探索点   青 NPC   红 妖兽   紫 地标   白 你"
	legend.add_theme_color_override("font_color", Color("#9eafbd"))
	legend.add_theme_font_size_override("font_size", 10)
	layout.add_child(legend)
	minimap_navigation_label = Label.new()
	minimap_navigation_label.text = "点击地图标记开始导航"
	minimap_navigation_label.add_theme_color_override("font_color", Color("#f0d18b"))
	minimap_navigation_label.add_theme_font_size_override("font_size", 10)
	minimap_navigation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(minimap_navigation_label)
	minimap_clear_navigation_button = Button.new()
	minimap_clear_navigation_button.text = "取消导航"
	_apply_button_theme(minimap_clear_navigation_button)
	minimap_clear_navigation_button.pressed.connect(_clear_minimap_navigation)
	minimap_clear_navigation_button.visible = false
	layout.add_child(minimap_clear_navigation_button)
	_update_minimap_data()


func _build_world_map_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	world_map_panel = PanelContainer.new()
	world_map_panel.name = "FullWorldMapPanel"
	world_map_panel.visible = false
	world_map_panel.z_index = 80
	_apply_panel_theme(world_map_panel)
	hud.add_child(world_map_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	world_map_panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "世界地图"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color("#e0c58f"))
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭"
	_apply_button_theme(close_button)
	close_button.pressed.connect(_toggle_world_map)
	header.add_child(close_button)
	world_map_canvas = Control.new()
	world_map_canvas.name = "WorldMapCanvas"
	world_map_canvas.set_script(WorldMapViewScript)
	world_map_canvas.custom_minimum_size = Vector2(620.0, 430.0)
	world_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_map_canvas.connect("marker_selected", Callable(self, "_on_world_map_marker_selected"))
	world_map_canvas.connect("world_position_selected", Callable(self, "_on_world_map_position_selected"))
	layout.add_child(world_map_canvas)
	var hint := Label.new()
	hint.text = "金色：探索点 · 青色：NPC · 红色：妖兽 · 紫色：地标 · 点击标记导航，点击空白处设置坐标"
	hint.add_theme_color_override("font_color", Color("#a9bac7"))
	hint.add_theme_font_size_override("font_size", 11)
	layout.add_child(hint)
	_layout_hud()
	_update_minimap_data()


func _toggle_world_map() -> void:
	if not is_instance_valid(world_map_panel):
		return
	world_map_panel.visible = not world_map_panel.visible
	if world_map_panel.visible:
		world_map_restore_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_update_minimap_data()
		world_map_canvas.grab_focus()
	else:
		if is_instance_valid(world_map_canvas):
			world_map_canvas.release_focus()
		if world_map_restore_mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		world_map_restore_mouse_captured = false


func _update_minimap_data() -> void:
	if not is_instance_valid(minimap_view):
		return
	if is_instance_valid(minimap_panel):
		var viewport_width := get_viewport().get_visible_rect().size.x
		minimap_panel.visible = hud_visible and viewport_width >= 520.0 and not (is_instance_valid(friend_panel) and friend_panel.visible)
	if is_instance_valid(local_player):
		minimap_view.set("player_position", local_player.global_position)
		minimap_view.set("player_yaw", local_player.global_rotation.y)
	minimap_view.set("exploration_points", exploration_point_data.values())
	minimap_view.set("npc_points", npc_definitions)
	var current_world_id := str(HHSession.world_snapshot.get("world_id", ""))
	minimap_view.set("landmark_points", WorldMapCatalog.get_minimap_landmarks(current_world_id))
	if is_instance_valid(world_map_canvas):
		world_map_canvas.set("world_id", current_world_id)
		world_map_canvas.set("world_bounds", WorldMapCatalog.get_world_bounds(current_world_id))
		world_map_canvas.set("region_data", WorldMapCatalog.get_regions(current_world_id))
		world_map_canvas.set("water_data", WorldMapCatalog.get_world_map_water_bodies(current_world_id))
		world_map_canvas.set("landmark_data", WorldMapCatalog.get_world_map_landmarks(current_world_id))
		world_map_canvas.set("exploration_points", exploration_point_data.values())
		world_map_canvas.set("npc_points", npc_definitions)
		world_map_canvas.set("player_position", local_player.global_position if is_instance_valid(local_player) else Vector3.ZERO)
		world_map_canvas.set("navigation_target", minimap_navigation_target)
		world_map_canvas.queue_redraw()
	var nearby_monsters: Array = []
	for monster_id in monster_targets.keys():
		var target: Vector3 = monster_targets[monster_id]
		var monster_data: Dictionary = monster_entities.get(str(monster_id), {})
		nearby_monsters.append({"id": str(monster_id), "name": str(monster_data.get("name", "妖兽")), "x": target.x, "z": target.z})
	minimap_view.set("monster_points", nearby_monsters)
	if is_instance_valid(world_map_canvas):
		world_map_canvas.set("monster_points", nearby_monsters)
		world_map_canvas.queue_redraw()
	if not minimap_navigation_target.is_empty():
		var nav_kind := str(minimap_navigation_target.get("kind", ""))
		var nav_id := str(minimap_navigation_target.get("id", ""))
		var nav_position := Vector3(float(minimap_navigation_target.get("x", 0.0)), 0.0, float(minimap_navigation_target.get("z", 0.0)))
		if nav_kind == "monster":
			if monster_targets.has(nav_id):
				nav_position = monster_targets[nav_id]
				minimap_navigation_target["x"] = nav_position.x
				minimap_navigation_target["z"] = nav_position.z
			else:
				minimap_navigation_target.clear()
		var horizontal_distance := Vector2(local_player.global_position.x, local_player.global_position.z).distance_to(Vector2(nav_position.x, nav_position.z)) if is_instance_valid(local_player) else -1.0
		var distance_text := ("距离 %.0f 米" % horizontal_distance) if horizontal_distance >= 0.0 else "距离计算中"
		if is_instance_valid(minimap_navigation_label):
			minimap_navigation_label.text = "导航：%s · %s" % [str(minimap_navigation_target.get("name", "目标")), distance_text]
		if is_instance_valid(minimap_clear_navigation_button):
			minimap_clear_navigation_button.visible = true
	else:
		if is_instance_valid(minimap_navigation_label):
			minimap_navigation_label.text = "点击地图标记开始导航"
		if is_instance_valid(minimap_clear_navigation_button):
			minimap_clear_navigation_button.visible = false
	minimap_view.set("navigation_target", minimap_navigation_target)
	if is_instance_valid(minimap_region_label):
		var world_name := _world_display_name(str(HHSession.world_snapshot.get("world_id", "")))
		minimap_region_label.text = world_name + " · " + (current_region_name if not current_region_name.is_empty() else "区域载入中")
	if is_instance_valid(minimap_exploration_label):
		var region_total := 0
		var region_discovered := 0
		for point_variant in exploration_point_data.values():
			if not point_variant is Dictionary:
				continue
			var point: Dictionary = point_variant
			if str(point.get("region_name", "")) != current_region_name:
				continue
			region_total += 1
			if bool(point.get("discovered", false)):
				region_discovered += 1
		minimap_exploration_label.text = "本区域探索 %d / %d" % [region_discovered, region_total] if region_total > 0 else "本区域暂无探索点数据"

func _on_minimap_marker_selected(kind: String, marker_id: String, marker_name: String) -> void:
	if marker_id.is_empty():
		return
	var target_position := Vector3.ZERO
	match kind:
		"monster":
			if not monster_targets.has(marker_id):
				return
			target_position = monster_targets[marker_id]
			_set_monster_target(marker_id)
		"npc":
			var found_npc := false
			for npc_variant in npc_definitions:
				if not npc_variant is Dictionary:
					continue
				var npc_data: Dictionary = npc_variant
				if str(npc_data.get("id", "")) == marker_id:
					target_position = Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
					found_npc = true
					break
			if not found_npc:
				return
		"exploration":
			if not exploration_point_data.has(marker_id):
				return
			var point: Dictionary = exploration_point_data[marker_id]
			target_position = Vector3(float(point.get("position_x", 0.0)), float(point.get("position_y", 0.0)), float(point.get("position_z", 0.0)))
		"landmark":
			var landmark_found := false
			var world_id := str(HHSession.world_snapshot.get("world_id", ""))
			for landmark in WorldMapCatalog.get_minimap_landmarks(world_id):
				if str(landmark.get("id", "")) == marker_id:
					target_position = Vector3(float(landmark.get("position_x", 0.0)), 0.0, float(landmark.get("position_z", 0.0)))
					landmark_found = true
					break
			if not landmark_found:
				return
		_:
			return
	minimap_navigation_target = {"kind": kind, "id": marker_id, "name": marker_name, "x": target_position.x, "z": target_position.z}
		if kind != "monster":
			_show_notification("导航目标：" + marker_name)
	_update_minimap_data()


func _on_world_map_marker_selected(kind: String, marker_id: String, marker_name: String) -> void:
	_on_minimap_marker_selected(kind, marker_id, marker_name)
	if is_instance_valid(world_map_canvas):
		world_map_canvas.set("navigation_target", minimap_navigation_target)
		world_map_canvas.queue_redraw()


func _on_world_map_position_selected(world_position: Vector3) -> void:
	minimap_navigation_target = {
		"kind": "map_position",
		"id": "map_%d_%d" % [roundi(world_position.x), roundi(world_position.z)],
		"name": "地图坐标（%.0f，%.0f）" % [world_position.x, world_position.z],
		"x": world_position.x,
		"z": world_position.z
	}
	_show_notification("已设置地图坐标导航目标")
	_update_minimap_data()


func _clear_minimap_navigation() -> void:
	minimap_navigation_target.clear()
	if is_instance_valid(minimap_view):
		minimap_view.set("navigation_target", {})
	_update_minimap_data()

func _build_combat_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	vitals_panel = PanelContainer.new()
	vitals_panel.position = Vector2(18.0, -104.0)
	vitals_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitals_panel.custom_minimum_size = Vector2(320.0, 154.0)
	var vitals_style := StyleBoxFlat.new()
	vitals_style.bg_color = Color("#0c1724", 0.94)
	vitals_style.border_color = Color("#3b5368")
	vitals_style.set_border_width_all(1)
	vitals_style.set_corner_radius_all(10)
	vitals_style.content_margin_left = 12.0
	vitals_style.content_margin_right = 12.0
	vitals_style.content_margin_top = 9.0
	vitals_style.content_margin_bottom = 9.0
	vitals_panel.add_theme_stylebox_override("panel", vitals_style)
	hud.add_child(vitals_panel)
	var vitals_layout := VBoxContainer.new()
	vitals_layout.add_theme_constant_override("separation", 6)
	vitals_panel.add_child(vitals_layout)
	health_label = Label.new()
	health_label.text = "生命  ·  等待服务端战斗状态"
	health_label.add_theme_color_override("font_color", Color("#f0c4b8"))
	health_label.add_theme_font_size_override("font_size", 13)
	vitals_layout.add_child(health_label)
	mana_label = Label.new()
	mana_label.text = "灵力  " + str(int(HHSession.world_snapshot.get("mana", 0))) + " / " + str(int(HHSession.world_snapshot.get("max_mana", 0)))
	vitals_layout.add_child(mana_label)
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(270.0, 16.0)
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 0.0
	health_bar.show_percentage = false
	var health_track := StyleBoxFlat.new()
	health_track.bg_color = Color("#2a303c")
	health_track.set_corner_radius_all(5)
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color("#c65d5d")
	health_fill.set_corner_radius_all(5)
	health_bar.add_theme_stylebox_override("background", health_track)
	health_bar.add_theme_stylebox_override("fill", health_fill)
	vitals_layout.add_child(health_bar)
	mana_label = Label.new()
	mana_label.text = "灵力  " + str(int(HHSession.world_snapshot.get("mana", 0))) + " / " + str(int(HHSession.world_snapshot.get("max_mana", 0)))
	mana_label.add_theme_color_override("font_color", Color("#a9d4f2"))
	mana_label.add_theme_font_size_override("font_size", 12)
	vitals_layout.add_child(mana_label)
	mana_bar = ProgressBar.new()
	mana_bar.custom_minimum_size = Vector2(270.0, 10.0)
	mana_bar.min_value = 0.0
	mana_bar.max_value = maxf(1.0, float(HHSession.world_snapshot.get("max_mana", 0)))
	mana_bar.value = clampf(float(HHSession.world_snapshot.get("mana", 0)), 0.0, mana_bar.max_value)
	mana_bar.show_percentage = false
	var mana_track := StyleBoxFlat.new()
	mana_track.bg_color = Color("#202f40")
	mana_track.set_corner_radius_all(5)
	var mana_fill := StyleBoxFlat.new()
	mana_fill.bg_color = Color("#4b91c7")
	mana_fill.set_corner_radius_all(5)
	mana_bar.add_theme_stylebox_override("background", mana_track)
	mana_bar.add_theme_stylebox_override("fill", mana_fill)
	vitals_layout.add_child(mana_bar)
	var spell_hint := Label.new()
	spell_hint.text = "快捷技能"
	spell_hint.add_theme_color_override("font_color", Color("#d6bd8b"))
	spell_hint.add_theme_font_size_override("font_size", 11)
	vitals_layout.add_child(spell_hint)
	for spell_id in ["fireball", "ice_bolt"]:
		var cooldown_label := Label.new()
		cooldown_label.text = "Q  火球术：就绪" if spell_id == "fireball" else "R  冰锥术：就绪"
		cooldown_label.add_theme_color_override("font_color", Color("#c4d2df"))
		cooldown_label.add_theme_font_size_override("font_size", 11)
		spell_cooldown_labels[spell_id] = cooldown_label
		vitals_layout.add_child(cooldown_label)
	_update_spell_cooldown_hud()
	notification_panel = PanelContainer.new()
	notification_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notification_panel.position = Vector2(-220.0, 96.0)
	notification_panel.custom_minimum_size = Vector2(440.0, 48.0)
	notification_panel.visible = false
	_apply_panel_theme(notification_panel)
	hud.add_child(notification_panel)
	notification_label = Label.new()
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification_label.add_theme_color_override("font_color", Color("#f2e8d6"))
	notification_label.add_theme_font_size_override("font_size", 14)
	notification_panel.add_child(notification_label)
	notification_timer = Timer.new()
	notification_timer.one_shot = true
	notification_timer.wait_time = 3.2
	notification_timer.timeout.connect(func(): notification_panel.visible = false)
	add_child(notification_timer)

	target_info_panel = PanelContainer.new()
	target_info_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_info_panel.position = Vector2(-180.0, 18.0)
	target_info_panel.custom_minimum_size = Vector2(360.0, 82.0)
	target_info_panel.visible = false
	_apply_panel_theme(target_info_panel)
	hud.add_child(target_info_panel)
	var target_layout := VBoxContainer.new()
	target_layout.add_theme_constant_override("separation", 5)
	target_info_panel.add_child(target_layout)
	target_info_label = Label.new()
	target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_info_label.add_theme_color_override("font_color", Color("#f2e8d6"))
	target_info_label.add_theme_font_size_override("font_size", 14)
	target_layout.add_child(target_info_label)
	target_health_bar = ProgressBar.new()
	target_health_bar.custom_minimum_size = Vector2(320.0, 10.0)
	target_health_bar.min_value = 0.0
	target_health_bar.max_value = 1.0
	target_health_bar.value = 1.0
	target_health_bar.show_percentage = false
	var target_track := StyleBoxFlat.new()
	target_track.bg_color = Color("#202f40")
	target_track.set_corner_radius_all(5)
	var target_fill := StyleBoxFlat.new()
	target_fill.bg_color = Color("#c65d5d")
	target_fill.set_corner_radius_all(5)
	target_health_bar.add_theme_stylebox_override("background", target_track)
	target_health_bar.add_theme_stylebox_override("fill", target_fill)
	target_layout.add_child(target_health_bar)

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
	return WorldRegionCatalog.resolve(world_id, position)

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
		"修为 " + str(cultivation),
		"灵力 " + str(int(snapshot.get("mana", 0))) + " / " + str(int(snapshot.get("max_mana", 0)))
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
		compact_hud_panel.custom_minimum_size = Vector2(340.0, 112.0)
		compact_hud_label.custom_minimum_size = Vector2(316.0, 92.0)
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
	hud_label.text = "当前世界 · " + world_name + " · 所在区域 " + (current_region_name if not current_region_name.is_empty() else "区域载入中") + "\n" + character_name + "  |  WASD 移动 · 鼠标转向 · ESC 释放鼠标 · F1 隐藏/显示状态栏\nF NPC交互 · E 拾取 · I 背包 · Q 火球术（法杖/法器） · C 聊天 · 鼠标左键攻击 · F2 网络诊断"
	_update_compact_hud()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_entities_updated(entities: Array) -> void:
	var seen: Dictionary = {}
	var seen_monsters: Dictionary = {}
	var seen_drops: Dictionary = {}
	var seen_projectiles: Dictionary = {}
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
		if entity_type == "projectile":
			var projectile_id := str(entity.get("entity_id", ""))
			if projectile_id.is_empty():
				continue
			seen_projectiles[projectile_id] = true
			_upsert_projectile(entity)
			continue
		var character_id := str(entity.get("character_id", ""))
		if character_id.is_empty():
			continue
		var target := Vector3(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)), float(entity.get("z", 0.0)))
		if character_id == own_id:
			local_target_position = target
			if entity.has("mana"):
				HHSession.world_snapshot["mana"] = int(entity.get("mana", 0))
			if entity.has("max_mana"):
				HHSession.world_snapshot["max_mana"] = int(entity.get("max_mana", 0))
			if is_instance_valid(mana_label):
				var mana_now := int(HHSession.world_snapshot.get("mana", 0))
				var mana_max := int(HHSession.world_snapshot.get("max_mana", 0))
				mana_label.text = "灵力  " + str(mana_now) + " / " + str(mana_max)
				if is_instance_valid(mana_bar):
					mana_bar.max_value = maxf(1.0, float(mana_max))
					mana_bar.value = clampf(float(mana_now), 0.0, mana_bar.max_value)
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
	for projectile_id in projectiles.keys():
		if not seen_projectiles.has(projectile_id):
			projectiles[projectile_id].queue_free()
			projectiles.erase(projectile_id)
			projectile_targets.erase(projectile_id)

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
	var birth_data: Variant = entity.get("birth_inheritance", {})
	_apply_remote_birth_visuals(remote_players[character_id], birth_data if birth_data is Dictionary else {})
	var equipment_data: Variant = entity.get("equipment", [])
	_apply_remote_equipment_visuals(remote_players[character_id], equipment_data if equipment_data is Array else [])
	_set_player_poison_visual(remote_players[character_id], bool(entity.get("poisoned", false)))

func _apply_remote_equipment_visuals(remote: Node3D, items: Array) -> void:
	if not is_instance_valid(remote) or bool(remote.get_meta("is_underworld", false)):
		return
	var humanoid := remote.get_node_or_null("RemoteHumanoid") as Node3D
	if humanoid == null:
		return
	var signature := JSON.stringify(items)
	if str(remote.get_meta("remote_equipment_signature", "")) == signature:
		return
	remote.set_meta("remote_equipment_signature", signature)
	var slots := ["weapon", "offhand", "head", "chest", "legs", "boots", "accessory", "back"]
	for slot in slots:
		var socket := EquipmentVisualFactory.get_or_create_socket(humanoid, slot)
		if not is_instance_valid(socket):
			continue
		for old_visual in socket.get_children():
			if old_visual.name == "EquipmentVisual":
				old_visual.queue_free()
	for item_value in items:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var slot := str(item.get("slot", item.get("equipment_slot", "")))
		if slot not in slots:
			continue
		var socket := EquipmentVisualFactory.get_or_create_socket(humanoid, slot)
		if not is_instance_valid(socket):
			continue
		var equipment_visual := EquipmentVisualFactory.create_equipment_visual(
			slot,
			int(item.get("quality", 1)),
			str(item.get("item_id", ""))
		)
		if equipment_visual != null:
			socket.add_child(equipment_visual)


func _apply_remote_birth_visuals(remote: Node3D, birth: Dictionary) -> void:
	if not is_instance_valid(remote) or bool(remote.get_meta("is_underworld", false)):
		return
	var humanoid := remote.get_node_or_null("RemoteHumanoid") as Node3D
	if humanoid == null:
		return
	var resonance := humanoid.get_node_or_null("BirthResonanceVisuals") as Node3D
	if birth.is_empty():
		if resonance != null:
			resonance.visible = false
		return
	if resonance == null:
		resonance = Node3D.new()
		resonance.name = "BirthResonanceVisuals"
		humanoid.add_child(resonance)
		for index in range(3):
			var ring := MeshInstance3D.new()
			ring.name = "BirthResonanceRing" + str(index + 1)
			var torus := TorusMesh.new()
			torus.inner_radius = 0.46 + float(index) * 0.12
			torus.outer_radius = torus.inner_radius + 0.025
			torus.rings = 28
			torus.ring_segments = 6
			ring.mesh = torus
			ring.position.y = 0.48 + float(index) * 0.42
			ring.rotation.x = [PI * 0.5, 0.72, -0.72][index]
			resonance.add_child(ring)
		var aura := MeshInstance3D.new()
		aura.name = "BirthResonanceAura"
		var sphere := SphereMesh.new()
		sphere.radius = 0.48
		sphere.height = 1.45
		sphere.radial_segments = 20
		sphere.rings = 12
		aura.mesh = sphere
		resonance.add_child(aura)
	var dominant := str(birth.get("dominant_attribute", "vitality"))
	var colors := {
		"strength": Color("#e76a43"),
		"constitution": Color("#d5ad62"),
		"agility": Color("#65c995"),
		"spirit": Color("#9b82e8"),
		"vitality": Color("#55c9a5")
	}
	var tint: Color = colors.get(dominant, colors["vitality"])
	var stage := maxi(int(birth.get("source_growth_stage", 1)), 1)
	for child in resonance.get_children():
		if child is MeshInstance3D:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(tint.r, tint.g, tint.b, 0.24 if child.name == "BirthResonanceAura" else 0.62)
			material.emission_enabled = true
			material.emission = tint
			material.emission_energy_multiplier = 0.8 + minf(float(stage - 1) * 0.12, 1.8)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			child.material_override = material
			child.scale = Vector3.ONE * (1.0 + minf(float(stage - 1) * 0.035, 0.25))
	resonance.visible = true

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
	var monster_node := monsters[monster_id] as Node3D
	monster_node.set_meta("target_yaw", float(entity.get("yaw", monster_node.rotation.y)))
	monster_node.set_meta("server_mode", int(entity.get("mode", 0)))
	var slow_ring := monster_node.get_node_or_null("SlowStatusRing") as MeshInstance3D
	if slow_ring != null:
		slow_ring.visible = bool(entity.get("slowed", false))
	_set_monster_freeze_visual(monster_node, bool(entity.get("frozen", false)))
	monster_entities[monster_id] = entity.duplicate(true)
	if monster_id == selected_monster_id:
		_update_target_info()
	var nameplate := monster_node.get_node_or_null("Nameplate") as Label3D
	if nameplate != null:
		var base_text := str(entity.get("name", "野兽")) + " · Lv." + str(int(entity.get("level", 1)))
		if entity.has("health") and entity.has("max_health"):
			var hp := int(entity.get("health", 0))
			var max_hp := int(entity.get("max_health", 0))
			if max_hp > 0:
				base_text += "\n生命 " + str(maxi(hp, 0)) + " / " + str(max_hp)
		nameplate.text = base_text

func _create_monster(monster_name: String, monster_level: int) -> Node3D:
	var visual_root: Node3D = UnderworldVisualFactory.create_monster(monster_name, monster_level)
	var archetype := str(visual_root.get_meta("visual_archetype", ""))
	var is_wraith := archetype in ["life_soul", "wind_soul", "fire_soul", "frost_soul", "wraith"]
	var is_war_god := monster_name.contains("战神") or monster_name.contains("战魂")
	if archetype in ["fire_soul", "frost_soul"]:
		var elemental_telegraph := MeshInstance3D.new()
		elemental_telegraph.name = "ElementalTelegraph"
		var elemental_ring := TorusMesh.new()
		elemental_ring.inner_radius = 0.54
		elemental_ring.outer_radius = 0.62
		elemental_ring.rings = 36
		elemental_ring.ring_segments = 8
		elemental_telegraph.mesh = elemental_ring
		var elemental_material := StandardMaterial3D.new()
		var elemental_color := Color("#ff9b42") if archetype == "fire_soul" else Color("#72dfff")
		elemental_material.albedo_color = Color(elemental_color.r, elemental_color.g, elemental_color.b, 0.28)
		elemental_material.emission_enabled = true
		elemental_material.emission = elemental_color
		elemental_material.emission_energy_multiplier = 1.1
		elemental_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		elemental_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		elemental_telegraph.material_override = elemental_material
		elemental_telegraph.position.y = 0.07
		elemental_telegraph.visible = false
		visual_root.add_child(elemental_telegraph)
	if archetype == "iron_beast":
		var telegraph := MeshInstance3D.new()
		telegraph.name = "SlamTelegraph"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.94
		torus.outer_radius = 1.0
		torus.rings = 40
		torus.ring_segments = 8
		telegraph.mesh = torus
		var telegraph_material := StandardMaterial3D.new()
		telegraph_material.albedo_color = Color("#ff6547", 0.34)
		telegraph_material.emission_enabled = true
		telegraph_material.emission = Color("#ff3f2d")
		telegraph_material.emission_energy_multiplier = 1.2
		telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		telegraph.material_override = telegraph_material
		telegraph.position.y = 0.075
		telegraph.visible = false
		visual_root.add_child(telegraph)
	var slow_ring := MeshInstance3D.new()
	slow_ring.name = "SlowStatusRing"
	var slow_ring_mesh := TorusMesh.new()
	slow_ring_mesh.inner_radius = 0.58
	slow_ring_mesh.outer_radius = 0.66
	slow_ring_mesh.rings = 24
	slow_ring_mesh.ring_segments = 6
	slow_ring.mesh = slow_ring_mesh
	var slow_ring_material := StandardMaterial3D.new()
	slow_ring_material.albedo_color = Color("#70dfff", 0.72)
	slow_ring_material.emission_enabled = true
	slow_ring_material.emission = Color("#48cfff")
	slow_ring_material.emission_energy_multiplier = 1.6
	slow_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slow_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slow_ring.material_override = slow_ring_material
	slow_ring.position.y = 0.09
	slow_ring.visible = false
	visual_root.add_child(slow_ring)
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = monster_name + " · Lv." + str(monster_level)
	label.position.y = 2.05 if is_war_god else (1.85 if is_wraith else 1.75)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#ff9b55") if is_war_god else (Color("#b9d9ff") if is_wraith else Color("#ffd0a8"))
	visual_root.add_child(label)
	visual_root.set_meta("base_visual_scale", visual_root.scale)
	visual_root.set_meta("death_reaction_time", 0.0)
	visual_root.set_meta("hit_reaction_time", 0.0)
	add_child(visual_root)
	return visual_root

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

func _upsert_projectile(entity: Dictionary) -> void:
	var projectile_id := str(entity.get("entity_id", ""))
	var projectile_type := str(entity.get("projectile_type", ""))
	if projectile_id.is_empty() or projectile_type not in ["arrow", "fireball", "ice_bolt"]:
		return
	var target := Vector3(float(entity.get("x", 0.0)), float(entity.get("y", 1.15)), float(entity.get("z", 0.0)))
	var is_new := not projectiles.has(projectile_id)
	if is_new:
		if projectile_type == "fireball":
			projectiles[projectile_id] = _create_fireball_projectile()
		elif projectile_type == "ice_bolt":
			projectiles[projectile_id] = _create_ice_bolt_projectile()
		else:
			projectiles[projectile_id] = _create_arrow_projectile()
	projectile_targets[projectile_id] = target
	var direction := Vector3(float(entity.get("velocity_x", 0.0)), 0.0, float(entity.get("velocity_z", -1.0)))
	var projectile_node := projectiles[projectile_id] as Node3D
	if is_instance_valid(projectile_node):
		if is_new:
			projectile_node.position = target
		if direction.length_squared() > 0.001:
			projectile_node.look_at(projectile_node.global_position + direction, Vector3.UP)

func _create_fireball_projectile() -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoritativeFireball"
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 12
	sphere.rings = 6
	core.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ff8a32")
	material.emission_enabled = true
	material.emission = Color("#ff4b12")
	material.emission_energy_multiplier = 2.8
	material.roughness = 0.3
	core.material_override = material
	root.add_child(core)
	var glow := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.32
	glow_mesh.height = 0.64
	glow_mesh.radial_segments = 10
	glow_mesh.rings = 5
	glow.mesh = glow_mesh
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = Color(1.0, 0.28, 0.06, 0.28)
	glow_material.emission_enabled = true
	glow_material.emission = Color("#ff5b18")
	glow_material.emission_energy_multiplier = 1.4
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = glow_material
	root.add_child(glow)
	add_child(root)
	return root

func _create_ice_bolt_projectile() -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoritativeIceBolt"
	var core := MeshInstance3D.new()
	var crystal := SphereMesh.new()
	crystal.radius = 0.19
	crystal.height = 0.42
	crystal.radial_segments = 8
	crystal.rings = 4
	core.mesh = crystal
	core.rotation.z = PI * 0.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#a7efff")
	material.emission_enabled = true
	material.emission = Color("#54cfff")
	material.emission_energy_multiplier = 2.2
	material.metallic = 0.18
	material.roughness = 0.24
	core.material_override = material
	root.add_child(core)
	var halo := MeshInstance3D.new()
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.23
	halo_mesh.outer_radius = 0.29
	halo_mesh.rings = 16
	halo_mesh.ring_segments = 6
	halo.mesh = halo_mesh
	halo.rotation.x = PI * 0.5
	var halo_material := StandardMaterial3D.new()
	halo_material.albedo_color = Color("#80e4ff", 0.58)
	halo_material.emission_enabled = true
	halo_material.emission = Color("#4ccfff")
	halo_material.emission_energy_multiplier = 1.8
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override = halo_material
	root.add_child(halo)
	add_child(root)
	return root

func _create_arrow_projectile() -> Node3D:
	var root := Node3D.new()
	root.name = "AuthoritativeArrow"
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.035, 0.035, 0.78)
	shaft.mesh = shaft_mesh
	shaft.position.z = -0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#8a633b")
	wood.roughness = 0.8
	shaft.material_override = wood
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := ConeMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.085
	head_mesh.height = 0.22
	head.mesh = head_mesh
	head.position.z = -0.78
	head.rotation.x = -PI * 0.5
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#c5cbd1")
	metal.metallic = 0.72
	head.material_override = metal
	root.add_child(head)
	add_child(root)
	return root

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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and is_instance_valid(world_map_panel) and world_map_panel.visible:
		_toggle_world_map()
		get_viewport().set_input_as_handled()
		return
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
		if is_instance_valid(target_info_panel):
			target_info_panel.visible = hud_visible and not selected_monster_id.is_empty()
		if is_instance_valid(minimap_panel):
			minimap_panel.visible = hud_visible and get_viewport().get_visible_rect().size.x >= 520.0 and not (is_instance_valid(friend_panel) and friend_panel.visible)
		if is_instance_valid(world_map_panel) and not hud_visible:
			world_map_panel.visible = false
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
	# Do not trigger gameplay shortcuts while the player is typing in chat
	# (or another text editor). Letters such as I/C/F/E belong to the text field.
	var focused_control := get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit or focused_control is TextEdit:
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
	if event.keycode == KEY_Q:
		_request_fireball()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_R:
		_request_ice_bolt()
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
	chat_panel.offset_left = -438.0
	chat_panel.offset_top = -74.0
	chat_panel.offset_right = -20.0
	chat_panel.offset_bottom = -20.0
	chat_panel.custom_minimum_size = Vector2(418.0, 54.0)
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color("#101923")
	shell.border_color = Color("#35495c")
	shell.set_border_width_all(1)
	shell.set_corner_radius_all(12)
	shell.content_margin_left = 14
	shell.content_margin_right = 14
	shell.content_margin_top = 10
	shell.content_margin_bottom = 10
	chat_panel.add_theme_stylebox_override("panel", shell)
	hud.add_child(chat_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	chat_panel.add_child(layout)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	layout.add_child(heading)
	var brand := Label.new()
	brand.text = "✦"
	brand.add_theme_color_override("font_color", Color("#d9b879"))
	brand.add_theme_font_size_override("font_size", 20)
	heading.add_child(brand)
	chat_title_label = Label.new()
	chat_title_label.text = "万界传音"
	chat_title_label.add_theme_color_override("font_color", Color("#f0e4cc"))
	chat_title_label.add_theme_font_size_override("font_size", 15)
	chat_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(chat_title_label)
	chat_unread_badge = Label.new()
	chat_unread_badge.text = "0"
	chat_unread_badge.add_theme_color_override("font_color", Color("#ffffff"))
	chat_unread_badge.add_theme_font_size_override("font_size", 11)
	chat_unread_badge.visible = false
	heading.add_child(chat_unread_badge)
	var friends_button := Button.new()
	friends_button.text = "好友"
	friends_button.pressed.connect(func():
		if is_instance_valid(friend_panel):
			friend_panel.open_panel()
	)
	_style_chat_button(friends_button, false)
	heading.add_child(friends_button)
	chat_toggle_button = Button.new()
	chat_toggle_button.text = "展开"
	chat_toggle_button.pressed.connect(func(): _set_chat_expanded(not chat_expanded))
	_style_chat_button(chat_toggle_button, true)
	heading.add_child(chat_toggle_button)

	var channels := HBoxContainer.new()
	channels.add_theme_constant_override("separation", 6)
	layout.add_child(channels)
	chat_channel_buttons.clear()
	for channel_data in [["nearby", "附近"], ["world", "世界"], ["cross_world", "跨界"]]:
		var channel_button := Button.new()
		channel_button.text = str(channel_data[1])
		channel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		channel_button.pressed.connect(_select_chat_channel.bind(str(channel_data[0])))
		_style_chat_button(channel_button, str(channel_data[0]) == selected_chat_channel)
		channels.add_child(channel_button)
		chat_channel_buttons.append(channel_button)

	chat_scroll = ScrollContainer.new()
	chat_scroll.custom_minimum_size = Vector2(386.0, 230.0)
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(chat_scroll)
	chat_log = VBoxContainer.new()
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_constant_override("separation", 7)
	chat_scroll.add_child(chat_log)

	var input_shell := PanelContainer.new()
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("#182633")
	input_style.border_color = Color("#40566a")
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(8)
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	input_style.content_margin_top = 3
	input_style.content_margin_bottom = 3
	input_shell.add_theme_stylebox_override("panel", input_style)
	layout.add_child(input_shell)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	input_shell.add_child(input_row)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "说点什么……（Enter 发送）"
	chat_input.max_length = 200
	chat_input.flat = true
	chat_input.add_theme_color_override("font_color", Color("#edf2f6"))
	chat_input.add_theme_color_override("font_placeholder_color", Color("#8092a2"))
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(_on_chat_input_submitted)
	chat_input.gui_input.connect(_on_chat_input_gui_input)
	input_row.add_child(chat_input)
	var send_button := Button.new()
	send_button.text = "发送"
	send_button.custom_minimum_size = Vector2(58, 34)
	send_button.pressed.connect(func(): _on_chat_input_submitted(chat_input.text))
	_style_chat_button(send_button, true)
	input_row.add_child(send_button)
	chat_status = Label.new()
	chat_status.text = "附近频道 · 同一实例范围内可见"
	chat_status.add_theme_color_override("font_color", Color("#8295a6"))
	chat_status.add_theme_font_size_override("font_size", 10)
	layout.add_child(chat_status)
	friend_panel = FriendPanelScript.new()
	friend_panel.open_private_chat.connect(_open_friend_conversation)
	hud.add_child(friend_panel)
	_set_chat_expanded(false)

func _style_chat_button(button: Button, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#34485a") if active else Color("#1a2834")
	normal.border_color = Color("#b79a68") if active else Color("#34495b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#40566a")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("#f1e5cf") if active else Color("#b8c6d1"))
	button.add_theme_font_size_override("font_size", 11)

func is_gameplay_input_blocked() -> bool:
	# Modal map and social drawers own keyboard/mouse input while visible.
	if is_instance_valid(world_map_panel) and world_map_panel.visible:
		return true
	# Keep movement disabled for the entire time the chat drawer is open,
	# including Chinese IME candidate/composition states.
	if chat_expanded or (is_instance_valid(friend_panel) and friend_panel.visible):
		return true
	var focused_control := get_viewport().gui_get_focus_owner()
	return focused_control is LineEdit or focused_control is TextEdit

func _set_chat_expanded(expanded: bool) -> void:
	if expanded and not chat_expanded:
		# Release captured mouse before the player can interact with chat controls.
		chat_restore_mouse_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chat_expanded = expanded
	if expanded:
		chat_unread_count = 0
		_update_chat_unread_badge()
		call_deferred("_scroll_chat_to_bottom")
	elif is_instance_valid(chat_input):
		chat_input.release_focus()
		if chat_restore_mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		chat_restore_mouse_captured = false
	if not is_instance_valid(chat_panel):
		return
	for child in chat_panel.get_child(0).get_children():
		if child is Control and child != chat_panel.get_child(0).get_child(0):
			child.visible = expanded
	if is_instance_valid(chat_toggle_button):
		chat_toggle_button.text = "收起" if expanded else "展开"
	_layout_hud()

func _layout_hud() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	# Keep the character card and its controls in a single, non-overlapping
	# top-left stack. The original fixed Y=118 placed the button over the card.
	if is_instance_valid(compact_hud_panel):
		var is_underworld := str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu"
		var card_width := minf(420.0 if is_underworld else 340.0, maxf(260.0, viewport_size.x - 36.0))
		var card_height := compact_hud_panel.custom_minimum_size.y
		compact_hud_panel.position = Vector2(18.0, 18.0)
		compact_hud_panel.custom_minimum_size = Vector2(card_width, card_height)
		compact_hud_panel.size = Vector2(card_width, card_height)
		if is_instance_valid(compact_hud_label):
			compact_hud_label.custom_minimum_size = Vector2(card_width - 24.0, card_height - 20.0)
		var controls_y := 18.0 + card_height + 8.0
		if is_instance_valid(details_toggle_button):
			details_toggle_button.position = Vector2(18.0, controls_y)
		if is_instance_valid(soul_choice_button):
			soul_choice_button.position = Vector2(140.0, controls_y)

	# The chat drawer owns the lower-right corner. Its width and height adapt
	# to small windows, and the interaction prompt is placed above it.
	if is_instance_valid(friend_panel):
		friend_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		friend_panel.offset_left = -378.0
		friend_panel.offset_top = 72.0
		friend_panel.offset_right = -18.0
		friend_panel.offset_bottom = 548.0
	var chat_height := 54.0
	if chat_expanded:
		chat_height = minf(430.0, maxf(300.0, viewport_size.y - 48.0))
	if is_instance_valid(chat_panel):
		var chat_width := minf(430.0, maxf(290.0, viewport_size.x - 36.0))
		chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		chat_panel.offset_left = -chat_width - 18.0
		chat_panel.offset_right = -18.0
		chat_panel.offset_top = -chat_height - 18.0
		chat_panel.offset_bottom = -18.0
		chat_panel.custom_minimum_size = Vector2(chat_width, chat_height)
		if is_instance_valid(chat_scroll):
			chat_scroll.custom_minimum_size = Vector2(chat_width - 54.0, maxf(150.0, chat_height - 190.0))
	# Inventory is a centered modal rather than competing with the friend/chat drawers.
	if is_instance_valid(inventory_panel):
		var inventory_width := minf(620.0, maxf(260.0, viewport_size.x - 32.0))
		var inventory_height := minf(680.0, maxf(280.0, viewport_size.y - 36.0))
		inventory_panel.set_anchors_preset(Control.PRESET_CENTER)
		inventory_panel.offset_left = -inventory_width * 0.5
		inventory_panel.offset_right = inventory_width * 0.5
		inventory_panel.offset_top = -inventory_height * 0.5
		inventory_panel.offset_bottom = inventory_height * 0.5
		if is_instance_valid(inventory_items):
			var inventory_scroll := inventory_items.get_parent() as ScrollContainer
			if inventory_scroll != null:
				inventory_scroll.custom_minimum_size = Vector2(inventory_width - 44.0, maxf(120.0, inventory_height - 310.0))
	# NPC dialogue is also centered and sized against the active viewport.
	if is_instance_valid(npc_panel):
		var npc_width := minf(600.0, maxf(260.0, viewport_size.x - 28.0))
		var npc_height := minf(700.0, maxf(280.0, viewport_size.y - 28.0))
		npc_panel.set_anchors_preset(Control.PRESET_CENTER)
		npc_panel.offset_left = -npc_width * 0.5
		npc_panel.offset_right = npc_width * 0.5
		npc_panel.offset_top = -npc_height * 0.5
		npc_panel.offset_bottom = npc_height * 0.5
		if is_instance_valid(npc_dialogue_label):
			npc_dialogue_label.custom_minimum_size.x = npc_width - 44.0
		if is_instance_valid(exploration_container):
			var exploration_scroll := exploration_container.get_parent() as ScrollContainer
			if exploration_scroll != null:
				exploration_scroll.custom_minimum_size = Vector2(npc_width - 44.0, minf(150.0, maxf(72.0, npc_height * 0.2)))
	if is_instance_valid(npc_interact_button):
		npc_interact_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		npc_interact_button.offset_left = -minf(280.0, viewport_size.x - 36.0)
		npc_interact_button.offset_right = -18.0
		npc_interact_button.offset_top = -chat_height - 72.0
		npc_interact_button.offset_bottom = -chat_height - 26.0
	if is_instance_valid(world_map_panel):
		var map_width := minf(1040.0, maxf(320.0, viewport_size.x - 36.0))
		var map_height := minf(720.0, maxf(300.0, viewport_size.y - 36.0))
		world_map_panel.set_anchors_preset(Control.PRESET_CENTER)
		world_map_panel.offset_left = -map_width * 0.5
		world_map_panel.offset_right = map_width * 0.5
		world_map_panel.offset_top = -map_height * 0.5
		world_map_panel.offset_bottom = map_height * 0.5
		world_map_panel.custom_minimum_size = Vector2(map_width, map_height)
		if is_instance_valid(world_map_canvas):
			world_map_canvas.custom_minimum_size = Vector2(map_width - 48.0, map_height - 112.0)
	if is_instance_valid(minimap_panel):
		var map_visible := viewport_size.x >= 520.0 and hud_visible and not (is_instance_valid(friend_panel) and friend_panel.visible)
		minimap_panel.visible = map_visible
		minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		minimap_panel.offset_left = -202.0
		minimap_panel.offset_right = -18.0
		minimap_panel.offset_top = 18.0
		minimap_panel.offset_bottom = 318.0
	if is_instance_valid(target_info_panel):
		var target_width := minf(380.0, maxf(250.0, viewport_size.x - 32.0))
		target_info_panel.position = Vector2(-target_width * 0.5, 18.0)
		target_info_panel.custom_minimum_size.x = target_width
		if is_instance_valid(target_health_bar):
			target_health_bar.custom_minimum_size.x = target_width - 40.0
	if is_instance_valid(notification_panel):
		var notice_width := minf(520.0, maxf(250.0, viewport_size.x - 32.0))
		notification_panel.position = Vector2(-notice_width * 0.5, 112.0)
		notification_panel.custom_minimum_size.x = notice_width
	if is_instance_valid(vitals_panel):
		var vitals_width := minf(340.0, maxf(250.0, viewport_size.x - 36.0))
		vitals_panel.custom_minimum_size = Vector2(vitals_width, 154.0)
		vitals_panel.size = Vector2(vitals_width, 154.0)
		vitals_panel.offset_left = 18.0
		vitals_panel.offset_top = -172.0
		vitals_panel.offset_right = 18.0 + vitals_width
		vitals_panel.offset_bottom = -18.0
		if is_instance_valid(health_bar):
			health_bar.custom_minimum_size.x = vitals_width - 44.0
		if is_instance_valid(mana_bar):
			mana_bar.custom_minimum_size.x = vitals_width - 44.0
	if is_instance_valid(exploration_open_button):
		# Keep exploration below the vitals card at bottom-left.
		exploration_open_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		exploration_open_button.offset_left = 18.0
		exploration_open_button.offset_top = -218.0
		exploration_open_button.offset_right = 180.0
		exploration_open_button.offset_bottom = -172.0

func _on_chat_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_set_chat_expanded(false)
		get_viewport().set_input_as_handled()
		chat_input.accept_event()

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
		if selected_chat_channel == "whisper":
			error = HHChatNetwork.send_message("whisper", normalized, message_id, selected_friend_character_id)
		else:
			error = HHChatNetwork.send_message(selected_chat_channel, normalized, message_id)
	if error != OK:
		chat_status.text = "发送失败：" + str(error)
		return
	chat_input.clear()
	# Keep focus after sending so Enter can send consecutive messages;
	# Escape is the explicit way to leave chat input mode.
	chat_input.grab_focus()


func _active_chat_storage_key() -> String:
	if selected_chat_channel == "whisper":
		return "whisper:" + selected_friend_character_id
	return selected_chat_channel

func _open_friend_conversation(character_id: String, character_name: String) -> void:
	if character_id.is_empty():
		return
	selected_chat_channel = "whisper"
	selected_friend_character_id = character_id
	selected_friend_character_name = character_name
	chat_title_label.text = "私聊 · " + character_name
	chat_input.placeholder_text = "发送给 " + character_name + "（最多 200 字）"
	_set_chat_expanded(true)
	_render_chat_lines()
	if HHChatNetwork.socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		HHChatNetwork.fetch_conversation_history(character_id, 50)
		chat_status.text = "好友私聊 · 独立聊天连接已建立"
	else:
		chat_status.text = "好友私聊 · 正在连接聊天服务"

func _on_chat_conversation_history_received(character_id: String, messages: Array) -> void:
	if character_id != selected_friend_character_id:
		return
	for message in messages:
		if not message is Dictionary:
			continue
		var sender := str(message.get("sender_name", "未知玩家"))
		var content := str(message.get("content", ""))
		if not content.is_empty():
			_append_chat_line("[" + sender + "] " + content, "whisper:" + character_id, str(message.get("id", "")), str(message.get("created_at", "")))
	if selected_chat_channel == "whisper":
		_render_chat_lines()
		call_deferred("_scroll_chat_to_bottom")

func _select_chat_channel(channel: String) -> void:
	if channel not in ["nearby", "world", "cross_world"]:
		return
	selected_chat_channel = channel
	selected_friend_character_id = ""
	selected_friend_character_name = ""
	var names := {"nearby": "附近", "world": "世界", "cross_world": "跨界"}
	chat_title_label.text = "万界传音 · " + str(names[channel])
	for index in range(chat_channel_buttons.size()):
		_style_chat_button(chat_channel_buttons[index], index == ["nearby", "world", "cross_world"].find(channel))
	chat_input.placeholder_text = "输入" + str(names[channel]) + "消息（最多 200 字）"
	_render_chat_lines()
	if chat_expanded:
		call_deferred("_scroll_chat_to_bottom")
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
	if selected_chat_channel == "whisper" and not selected_friend_character_id.is_empty():
		HHChatNetwork.fetch_conversation_history(selected_friend_character_id, 50)
	if is_instance_valid(chat_status):
		if selected_chat_channel == "whisper":
			chat_status.text = "好友私聊 · 独立聊天连接已建立"
		elif selected_chat_channel != "nearby":
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
	if channel not in ["nearby", "world", "cross_world", "whisper"]:
		return
	var sender := str(message.get("sender_name", "未知玩家"))
	var content := str(message.get("content", ""))
	var message_id := str(message.get("id", ""))
	var is_duplicate := not message_id.is_empty() and chat_seen_ids.has(message_id)
	var target_channel := channel
	if channel == "whisper":
		var peer_id := str(message.get("sender_character_id", ""))
		if _is_local_chat_message(message):
			peer_id = str(message.get("recipient_character_id", ""))
		target_channel = "whisper:" + peer_id
	if not content.is_empty():
		_append_chat_line("[" + sender + "] " + content, target_channel, message_id, str(message.get("created_at", "")))
		var conversation_not_open := channel == "whisper" and (selected_chat_channel != "whisper" or target_channel != "whisper:" + selected_friend_character_id)
		if not is_duplicate and not _is_local_chat_message(message) and (not chat_expanded or conversation_not_open):
			chat_unread_count = mini(chat_unread_count + 1, 99)
			_update_chat_unread_badge()
		if is_instance_valid(chat_status) and target_channel == _active_chat_storage_key():
			chat_status.text = "聊天消息已送达"

func _is_local_chat_message(message: Dictionary) -> bool:
	var local_character_id := str(HHSession.world_snapshot.get("character_id", HHSession.world_snapshot.get("current_character_id", "")))
	var sender_character_id := str(message.get("sender_character_id", ""))
	if not local_character_id.is_empty() and not sender_character_id.is_empty():
		return local_character_id == sender_character_id
	var local_name := str(HHSession.world_snapshot.get("character_name", HHSession.world_snapshot.get("name", "")))
	return not local_name.is_empty() and str(message.get("sender_name", "")) == local_name

func _update_chat_unread_badge() -> void:
	if not is_instance_valid(chat_unread_badge):
		return
	chat_unread_badge.visible = chat_unread_count > 0 and not chat_expanded
	chat_unread_badge.text = str(chat_unread_count) if chat_unread_count > 0 else ""

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
	var target_channel := channel if not channel.is_empty() else _active_chat_storage_key()
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
	chat_order_sequence += 1
	var entry := {"text": line, "id": message_id, "created_at": timestamp, "sort_time": _chat_timestamp_sort_value(timestamp), "sequence": chat_order_sequence}
	lines.append(entry)
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time := int(a.get("sort_time", 0))
		var b_time := int(b.get("sort_time", 0))
		if a_time == b_time:
			return int(a.get("sequence", 0)) < int(b.get("sequence", 0))
		return a_time < b_time
	)
	while lines.size() > 40:
		lines.pop_front()
	chat_lines_by_channel[target_channel] = lines
	if target_channel == _active_chat_storage_key():
		_render_chat_lines()
		if chat_expanded:
			call_deferred("_scroll_chat_to_bottom")

func _chat_timestamp_sort_value(timestamp: String) -> int:
	if timestamp.is_empty() or timestamp.length() < 19:
		return int(Time.get_unix_time_from_system()) * 1000000
	var normalized := timestamp.substr(0, 19).replace("T", " ")
	var seconds := int(Time.get_unix_time_from_datetime_string(normalized))
	var fractional_microseconds := 0
	if timestamp.length() > 20 and timestamp.substr(19, 1) == ".":
		var fraction_text := timestamp.substr(20).split("Z")[0].split("+")[0].split("-")[0]
		fraction_text = fraction_text.substr(0, mini(6, fraction_text.length())).lpad(6, "0")
		if fraction_text.is_valid_int():
			fractional_microseconds = int(fraction_text)
	return seconds * 1000000 + fractional_microseconds

func _scroll_chat_to_bottom() -> void:
	if not is_instance_valid(chat_scroll):
		return
	await get_tree().process_frame
	if not is_instance_valid(chat_scroll):
		return
	var scroll_bar := chat_scroll.get_v_scroll_bar()
	if is_instance_valid(scroll_bar):
		chat_scroll.scroll_vertical = int(scroll_bar.max_value)

func _render_chat_lines() -> void:
	if not is_instance_valid(chat_log):
		return
	var visible_lines: Array = chat_lines_by_channel.get(_active_chat_storage_key(), [])
	for child in chat_log.get_children():
		child.queue_free()
	for entry in visible_lines:
		var raw_line := str(entry.get("text", ""))
		var split_at := raw_line.find("] ")
		var sender := "旅人"
		var body := raw_line
		if raw_line.begins_with("[") and split_at > 1:
			sender = raw_line.substr(1, split_at - 1)
			body = raw_line.substr(split_at + 2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chat_log.add_child(row)
		var avatar := PanelContainer.new()
		avatar.custom_minimum_size = Vector2(30, 30)
		var avatar_style := StyleBoxFlat.new()
		avatar_style.bg_color = Color("#30465a")
		avatar_style.set_corner_radius_all(15)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		row.add_child(avatar)
		var avatar_text := Label.new()
		avatar_text.text = sender.substr(0, 1)
		avatar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar_text.add_theme_color_override("font_color", Color("#e6c98e"))
		avatar_text.add_theme_font_size_override("font_size", 13)
		avatar.add_child(avatar_text)
		var message_column := VBoxContainer.new()
		message_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message_column.add_theme_constant_override("separation", 2)
		row.add_child(message_column)
		var meta := HBoxContainer.new()
		message_column.add_child(meta)
		var sender_label := Label.new()
		sender_label.text = sender
		sender_label.add_theme_color_override("font_color", Color("#d9bc85"))
		sender_label.add_theme_font_size_override("font_size", 11)
		sender_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta.add_child(sender_label)
		var timestamp := str(entry.get("created_at", ""))
		var time_label := Label.new()
		time_label.text = timestamp.substr(11, 5) if timestamp.length() >= 16 else ""
		time_label.add_theme_color_override("font_color", Color("#718596"))
		time_label.add_theme_font_size_override("font_size", 9)
		meta.add_child(time_label)
		var bubble := PanelContainer.new()
		var bubble_style := StyleBoxFlat.new()
		bubble_style.bg_color = Color("#1b2a37")
		bubble_style.set_corner_radius_all(7)
		bubble_style.content_margin_left = 9
		bubble_style.content_margin_right = 9
		bubble_style.content_margin_top = 5
		bubble_style.content_margin_bottom = 5
		bubble.add_theme_stylebox_override("panel", bubble_style)
		message_column.add_child(bubble)
		var message_text := RichTextLabel.new()
		message_text.text = body
		message_text.fit_content = true
		message_text.scroll_active = false
		message_text.selection_enabled = true
		message_text.context_menu_enabled = true
		message_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message_text.add_theme_color_override("default_color", Color("#e0e8ee"))
		message_text.add_theme_font_size_override("normal_font_size", 12)
		bubble.add_child(message_text)

func _on_pickup_event(event: Dictionary) -> void:
	if bool(event.get("pending", false)):
		_show_notification(str(event.get("reason", "正在结算拾取……")))
		return
	if bool(event.get("accepted", false)):
		_show_notification("拾取成功：" + str(event.get("item_id", "物品")) + " ×" + str(event.get("quantity", 1)))
		_refresh_inventory()
	else:
		_show_notification(str(event.get("reason", "拾取失败。")))

func _apply_panel_theme(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111c28")
	style.border_color = Color("#425466")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)

func _apply_button_theme(button: Button, primary: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#8d7047") if primary else Color("#172635")
	normal.border_color = Color("#d4b47b") if primary else Color("#354b5c")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(7)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#a08050") if primary else Color("#22394d")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("#f2e8d6"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_font_size_override("font_size", 14)

func _build_inventory_ui() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		return
	inventory_button = Button.new()
	inventory_button.text = "背包"
	_apply_button_theme(inventory_button, true)
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
	_apply_panel_theme(inventory_panel)
	hud.add_child(inventory_panel)
	var layout := VBoxContainer.new()
	inventory_panel.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "角色背包"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f2e8d6"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭"
	_apply_button_theme(close_button)
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
		_apply_button_theme(filter_button)
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
		row.add_theme_constant_override("separation", 8)
		inventory_items.add_child(row)
		var line := Label.new()
		var quality := int(item.get("quality", 1))
		var quality_names := ["普通", "优秀", "精良", "稀有", "传说"]
		var quality_name: String = quality_names[clampi(quality - 1, 0, quality_names.size() - 1)]
		line.text = str(item.get("name", item.get("item_id", "未知物品"))) + " · " + quality_name + " · ×" + str(item.get("quantity", 0))
		line.add_theme_color_override("font_color", Color("#e7dfd2"))
		line.add_theme_font_size_override("font_size", 14)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(line)
		var detail_button := Button.new()
		detail_button.text = "详情"
		_apply_button_theme(detail_button)
		detail_button.pressed.connect(_show_item_details.bind(item))
		row.add_child(detail_button)
		if str(item.get("item_type", "")) == "equipment":
			var equip_button := Button.new()
			equip_button.text = "穿戴"
			_apply_button_theme(equip_button, true)
			equip_button.pressed.connect(_on_equip_item_pressed.bind(str(item.get("item_id", "")), str(item.get("equipment_slot", ""))))
			row.add_child(equip_button)
		elif str(item.get("item_type", "")) == "consumable":
			var use_button := Button.new()
			use_button.text = "使用"
			_apply_button_theme(use_button, true)
			use_button.disabled = consumable_busy
			use_button.text = "结算中…" if consumable_busy else "使用"
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
		var current_hp := maxi(0, int(entity.get("health", 0)))
		var maximum_hp := maxi(1, int(entity.get("max_health", 1)))
		hp_line = "生命  " + str(current_hp) + " / " + str(maximum_hp) + "    ·    Tab 切换目标"
		if is_instance_valid(target_health_bar):
			target_health_bar.max_value = maximum_hp
			target_health_bar.value = clampi(current_hp, 0, maximum_hp)
			target_health_bar.visible = true
	else:
		if is_instance_valid(target_health_bar):
			target_health_bar.visible = false
		hp_line += "    ·    Tab 切换目标"
	target_info_label.text = title + "\n" + hp_line
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
	elif local_player.has_method("play_attack_animation"):
		# 本地挥剑只反馈输入；命中、伤害与攻击结果仍由 WorldServer 决定。
		local_player.call("play_attack_animation")

func _update_spell_cooldown_hud() -> void:
	for spell_id in spell_cooldown_labels:
		var label := spell_cooldown_labels[spell_id] as Label
		if not is_instance_valid(label):
			continue
		var spell_key := "Q" if spell_id == "fireball" else "R"
		var spell_name := "火球术" if spell_id == "fireball" else "冰锥术"
		var remaining := float(spell_cooldown_remaining.get(spell_id, 0.0))
		label.text = spell_key + " · " + spell_name + "：冷却 " + ("%.1f" % remaining) + " 秒" if remaining > 0.0 else spell_key + " · " + spell_name + "：就绪"


func _request_fireball() -> void:
	var network := HHSession.world_network
	if network == null or not network.is_world_ready() or not is_instance_valid(local_player):
		return
	var target_id := selected_monster_id if monsters.has(selected_monster_id) else ""
	var nearest_distance := 20.0
	if target_id.is_empty():
		for monster_id in monster_targets:
			var target: Vector3 = monster_targets[monster_id]
			var distance := Vector2(local_player.global_position.x, local_player.global_position.z).distance_to(Vector2(target.x, target.z))
			if distance <= nearest_distance:
				nearest_distance = distance
				target_id = str(monster_id)
	if target_id.is_empty():
		_show_notification("20 米内没有可施法的目标。")
		return
	var error: Error = network.send_spell_cast("fireball", target_id)
	if error != OK:
		_show_notification("火球术请求发送失败：" + str(error))

func _request_ice_bolt() -> void:
	var network := HHSession.world_network
	if network == null or not network.is_world_ready() or not is_instance_valid(local_player):
		return
	var target_id := selected_monster_id if monsters.has(selected_monster_id) else ""
	var nearest_distance := 18.0
	if target_id.is_empty():
		for monster_id in monster_targets:
			var target: Vector3 = monster_targets[monster_id]
			var distance := Vector2(local_player.global_position.x, local_player.global_position.z).distance_to(Vector2(target.x, target.z))
			if distance <= nearest_distance:
				nearest_distance = distance
				target_id = str(monster_id)
	if target_id.is_empty():
		_show_notification("18 米内没有可施法的目标。")
		return
	var error: Error = network.send_spell_cast("ice_bolt", target_id)
	if error != OK:
		_show_notification("冰锥术请求发送失败：" + str(error))

func _on_monster_action_event(event: Dictionary) -> void:
	var attacker_id := str(event.get("source_entity_id", ""))
	if attacker_id.is_empty() or not monsters.has(attacker_id):
		return
	var attacker := monsters[attacker_id] as Node3D
	if not is_instance_valid(attacker):
		return
	var phase := str(event.get("phase", ""))
	var attack_style := str(event.get("attack_style", "melee"))
	attacker.set_meta("attack_style", attack_style)
	if attack_style == "heavy_slam":
		attacker.set_meta("attack_radius", maxf(float(event.get("attack_radius", 3.6)), 0.5))
	if phase == "windup":
		attacker.set_meta("attack_phase", "windup")
		if attack_style == "heavy_slam":
			_set_iron_slam_telegraph(attacker, true)
		if attack_style == "soul_bolt" or attack_style == "frost_bolt" or attack_style == "poison_bolt":
			_set_elemental_telegraph(attacker, true)
		var windup := maxf(float(event.get("windup_ms", 520)) / 1000.0, 0.1)
		attacker.set_meta("attack_phase_duration", windup)
		attacker.set_meta("attack_phase_time", windup)
		attacker.set_meta("attack_recovery_duration", maxf(float(event.get("recovery_ms", 420)) / 1000.0, 0.1))
	elif phase == "cancelled":
		attacker.set_meta("attack_phase", "idle")
		attacker.set_meta("attack_phase_time", 0.0)
		_set_iron_slam_telegraph(attacker, false)
		_set_elemental_telegraph(attacker, false)
	elif phase == "impact":
		attacker.set_meta("attack_phase", "impact")
		attacker.set_meta("attack_phase_duration", 0.2)
		attacker.set_meta("attack_phase_time", 0.2)
		if attack_style == "heavy_slam":
			_set_iron_slam_telegraph(attacker, false)
			_spawn_iron_slam_impact_visual(attacker, float(attacker.get_meta("attack_radius", 3.6)))
		if attack_style == "soul_bolt" or attack_style == "poison_bolt":
			_set_elemental_telegraph(attacker, false)
			if str(event.get("target_character_id", "")) == str(HHSession.world_snapshot.get("character_id", "")):
				if attack_style == "poison_bolt":
					_spawn_poison_bolt_visual(attacker)
				else:
					_spawn_soul_bolt_visual(attacker)

func _set_elemental_telegraph(monster: Node3D, enabled: bool) -> void:
	var telegraph := monster.get_node_or_null("ElementalTelegraph") as MeshInstance3D
	if not is_instance_valid(telegraph):
		return
	telegraph.visible = enabled
	if enabled:
		var previous_tween: Variant = telegraph.get_meta("pulse_tween", null)
		if previous_tween is Tween and (previous_tween as Tween).is_running():
			(previous_tween as Tween).kill()
		telegraph.scale = Vector3.ONE * 0.88
		var tween := create_tween()
		tween.set_loops()
		tween.tween_property(telegraph, "scale", Vector3.ONE * 1.16, 0.32)
		tween.tween_property(telegraph, "scale", Vector3.ONE * 0.88, 0.32)
		telegraph.set_meta("pulse_tween", tween)
	else:
		var active_tween: Variant = telegraph.get_meta("pulse_tween", null)
		if active_tween is Tween and active_tween.is_running():
			(active_tween as Tween).kill()
		telegraph.scale = Vector3.ONE

func _set_iron_slam_telegraph(monster: Node3D, enabled: bool) -> void:
	var telegraph := monster.get_node_or_null("SlamTelegraph") as MeshInstance3D
	if not is_instance_valid(telegraph):
		return
	telegraph.visible = enabled
	if enabled:
		var radius := maxf(float(monster.get_meta("attack_radius", 3.6)), 0.5)
		var parent_scale := maxf(absf(monster.scale.x), 0.01)
		telegraph.scale = Vector3.ONE * (radius / parent_scale)
		var material := telegraph.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color.a = 0.34
			material.emission_energy_multiplier = 1.2

func _spawn_iron_slam_impact_visual(monster: Node3D, radius: float) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "IronSlamImpactRing"
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - 0.16, 0.2)
	torus.outer_radius = maxf(radius - 0.04, 0.24)
	torus.rings = 36
	torus.ring_segments = 8
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ff7048", 0.82)
	material.emission_enabled = true
	material.emission = Color("#ff4f32")
	material.emission_energy_multiplier = 2.4
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	add_child(ring)
	ring.global_position = monster.global_position + Vector3(0.0, 0.10, 0.0)
	ring.scale = Vector3.ONE * 0.72
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE, 0.34)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.34)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.34)
	tween.chain().tween_callback(Callable(ring, "queue_free"))

func _spawn_soul_bolt_visual(attacker: Node3D) -> void:
	if not is_instance_valid(local_player):
		return
	var bolt := MeshInstance3D.new()
	bolt.name = "SoulBoltImpactVisual"
	var orb := SphereMesh.new()
	orb.radius = 0.13
	orb.height = 0.26
	bolt.mesh = orb
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#9df5ff")
	material.emission_enabled = true
	material.emission = Color("#55dff5")
	material.emission_energy_multiplier = 2.8
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt.material_override = material
	add_child(bolt)
	bolt.global_position = attacker.global_position + Vector3(0.0, 1.05, 0.0)
	var destination: Vector3 = local_player.global_position + Vector3(0.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(bolt, "global_position", destination, 0.24)
	tween.tween_callback(Callable(bolt, "queue_free"))

func _spawn_poison_bolt_visual(attacker: Node3D) -> void:
	if not is_instance_valid(local_player):
		return
	var bolt := MeshInstance3D.new()
	bolt.name = "PoisonBoltImpactVisual"
	var orb := SphereMesh.new()
	orb.radius = 0.15
	orb.height = 0.30
	bolt.mesh = orb
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#8ee36b")
	material.emission_enabled = true
	material.emission = Color("#55c52d")
	material.emission_energy_multiplier = 2.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt.material_override = material
	add_child(bolt)
	bolt.global_position = attacker.global_position + Vector3(0.0, 1.05, 0.0)
	var destination: Vector3 = local_player.global_position + Vector3(0.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(bolt, "global_position", destination, 0.26)
	tween.tween_callback(Callable(bolt, "queue_free"))


func _set_player_poison_visual(player_node: Node3D, enabled: bool) -> void:
	if not is_instance_valid(player_node):
		return
	var ring := player_node.get_node_or_null("PlayerPoisonStatusRing") as MeshInstance3D
	if enabled and ring == null:
		ring = MeshInstance3D.new()
		ring.name = "PlayerPoisonStatusRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.58
		ring_mesh.outer_radius = 0.68
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#8bd65c", 0.76)
		material.emission_enabled = true
		material.emission = Color("#58b82f")
		material.emission_energy_multiplier = 1.9
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		ring.position.y = 0.09
		player_node.add_child(ring)
	if ring != null:
		ring.visible = enabled


func _set_player_slow_visual(enabled: bool) -> void:
	if not is_instance_valid(local_player):
		return
	var ring := local_player.get_node_or_null("PlayerSlowStatusRing") as MeshInstance3D
	if enabled and ring == null:
		ring = MeshInstance3D.new()
		ring.name = "PlayerSlowStatusRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.48
		ring_mesh.outer_radius = 0.56
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#70dfff", 0.72)
		material.emission_enabled = true
		material.emission = Color("#48cfff")
		material.emission_energy_multiplier = 1.6
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		ring.position.y = 0.08
		local_player.add_child(ring)
	if ring != null:
		ring.visible = enabled


func _set_monster_burn_visual(monster: Node3D, enabled: bool) -> void:
	if not is_instance_valid(monster):
		return
	var ring := monster.get_node_or_null("MonsterBurnStatusRing") as MeshInstance3D
	if enabled and ring == null:
		ring = MeshInstance3D.new()
		ring.name = "MonsterBurnStatusRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.52
		ring_mesh.outer_radius = 0.62
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#ff9a42", 0.78)
		material.emission_enabled = true
		material.emission = Color("#ff5b24")
		material.emission_energy_multiplier = 1.8
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		ring.position.y = 0.07
		monster.add_child(ring)
	if ring != null:
		ring.visible = enabled


func _set_monster_freeze_visual(monster: Node3D, enabled: bool) -> void:
	if not is_instance_valid(monster):
		return
	var ring := monster.get_node_or_null("MonsterFreezeStatusRing") as MeshInstance3D
	if enabled and ring == null:
		ring = MeshInstance3D.new()
		ring.name = "MonsterFreezeStatusRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.58
		ring_mesh.outer_radius = 0.70
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#9cecff", 0.88)
		material.emission_enabled = true
		material.emission = Color("#55cfff")
		material.emission_energy_multiplier = 2.2
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		ring.position.y = 0.10
		monster.add_child(ring)
	if ring != null:
		ring.visible = enabled


func _on_combat_event(event: Dictionary) -> void:
	if str(event.get("action", "")) == "equipment_refresh":
		if not bool(event.get("accepted", false)):
			return
		HHSession.world_snapshot["health"] = int(event.get("health", HHSession.world_snapshot.get("health", 0)))
		HHSession.world_snapshot["max_health"] = int(event.get("max_health", HHSession.world_snapshot.get("max_health", 0)))
		HHSession.world_snapshot["mana"] = int(event.get("mana", HHSession.world_snapshot.get("mana", 0)))
		HHSession.world_snapshot["max_mana"] = int(event.get("max_mana", HHSession.world_snapshot.get("max_mana", 0)))
		_update_vitals(int(HHSession.world_snapshot["health"]), int(HHSession.world_snapshot["max_health"]))
		if is_instance_valid(mana_label):
			mana_label.text = "灵力  " + str(int(HHSession.world_snapshot["mana"])) + " / " + str(int(HHSession.world_snapshot["max_mana"]))
		_update_compact_hud()
		inventory_status.text = "装备属性已同步。"
		_refresh_inventory()
		_refresh_equipment()
		_show_notification("装备属性已同步。")
		return
	if str(event.get("action", "")) == "consumable_use":
		if bool(event.get("pending", false)):
			inventory_status.text = str(event.get("reason", "正在结算消耗品……"))
			return
		consumable_busy = false
		if bool(event.get("accepted", false)):
			HHSession.world_snapshot["health"] = int(event.get("health", HHSession.world_snapshot.get("health", 0)))
			HHSession.world_snapshot["max_health"] = int(event.get("max_health", HHSession.world_snapshot.get("max_health", 0)))
			HHSession.world_snapshot["mana"] = int(event.get("mana", HHSession.world_snapshot.get("mana", 0)))
			HHSession.world_snapshot["max_mana"] = int(event.get("max_mana", HHSession.world_snapshot.get("max_mana", 0)))
			_update_vitals(int(HHSession.world_snapshot["health"]), int(HHSession.world_snapshot["max_health"]))
			if is_instance_valid(mana_label):
				mana_label.text = "灵力  " + str(int(HHSession.world_snapshot["mana"])) + " / " + str(int(HHSession.world_snapshot["max_mana"]))
			_update_compact_hud()
			if bool(event.get("applied", true)):
				_show_notification("消耗品使用成功：生命 +" + str(int(event.get("health_restored", 0))) + "，灵力 +" + str(int(event.get("mana_restored", 0))))
			else:
				_show_notification("该请求已结算，角色资源已重新同步。")
			_refresh_inventory()
		else:
			_show_notification(str(event.get("reason", "消耗品使用失败。")), 3.0)
			_refresh_inventory()
		return
	if str(event.get("action", "")) == "spell_cast":
		if event.has("mana"):
			HHSession.world_snapshot["mana"] = int(event.get("mana", 0))
		if event.has("max_mana"):
			HHSession.world_snapshot["max_mana"] = int(event.get("max_mana", 0))
		if is_instance_valid(mana_label):
			mana_label.text = "灵力  " + str(int(HHSession.world_snapshot.get("mana", 0))) + " / " + str(int(HHSession.world_snapshot.get("max_mana", 0)))
		_update_compact_hud()
		var spell_id := str(event.get("spell_id", ""))
		var spell_name := "冰锥术" if spell_id == "ice_bolt" else ("火球术" if spell_id == "fireball" else "法术")
		if bool(event.get("accepted", false)) and str(event.get("phase", "")) == "casting" and spell_cooldown_remaining.has(spell_id):
			spell_cooldown_remaining[spell_id] = maxf(float(event.get("cooldown_ms", 0)) / 1000.0, 0.0)
			_update_spell_cooldown_hud()
		if not bool(event.get("accepted", false)):
			_show_notification(str(event.get("reason", spell_name + "施展失败。")), 3.0)
		elif str(event.get("phase", "")) == "casting":
			_show_notification("正在凝聚" + spell_name + " · 灵力 -" + str(int(event.get("mana_cost", 18))), 1.5)
		elif str(event.get("phase", "")) == "released":
			_show_notification(spell_name + "已释放！", 1.5)
		return
	if not bool(event.get("accepted", true)):
		hud_label.text = str(event.get("reason", "攻击未命中。"))
		return
	if bool(event.get("projectile_spawned", false)):
		_show_notification("箭矢已发射，等待命中……")
		return
	if bool(event.get("visual_only", false)):
		var visual_target_id := str(event.get("target_entity_id", ""))
		if monsters.has(visual_target_id):
			var visual_target := monsters[visual_target_id] as Node3D
			if bool(event.get("burn_applied", false)):
				visual_target.set_meta("burn_visual_remaining", maxf(float(event.get("burn_duration_ms", 0)) / 1000.0, 0.0))
				_set_monster_burn_visual(visual_target, true)
			if str(event.get("status_effect", "")) == "burn":
				var visual_burn_remaining := maxf(float(event.get("status_duration_ms", 0)) / 1000.0, 0.0)
				visual_target.set_meta("burn_visual_remaining", visual_burn_remaining)
				_set_monster_burn_visual(visual_target, visual_burn_remaining > 0.0)
			if str(event.get("status_effect", "")) == "freeze":
				_set_monster_freeze_visual(visual_target, true)
			visual_target.set_meta("hit_reaction_time", 0.24)
			_spawn_monster_hit_visual(visual_target, false)
			if bool(event.get("defeated", false)):
				visual_target.set_meta("burn_visual_remaining", 0.0)
				_set_monster_burn_visual(visual_target, false)
				_set_monster_freeze_visual(visual_target, false)
				visual_target.set_meta("death_reaction_time", 1.15)
				visual_target.set_meta("defeated_visual", true)
				var visual_nameplate := visual_target.get_node_or_null("Nameplate") as Label3D
				if is_instance_valid(visual_nameplate):
					visual_nameplate.visible = false
		return
	if str(event.get("source", "")) == "monster":
		if str(event.get("status_effect", "")) == "slow":
			_set_player_slow_visual(true)
			player_slow_visual_remaining = maxf(float(event.get("status_duration_ms", 0)) / 1000.0, 0.0)
		if str(event.get("status_effect", "")) == "poison":
			player_poison_visual_remaining = maxf(float(event.get("status_duration_ms", 0)) / 1000.0, 0.0)
			_set_player_poison_visual(local_player, player_poison_visual_remaining > 0.0)
		var incoming_damage := int(event.get("damage", 0))
		if str(event.get("attack_style", "")) != "poison_tick" and is_instance_valid(local_player) and local_player.has_method("play_hit_reaction"):
			local_player.call("play_hit_reaction", incoming_damage, str(event.get("attack_style", "")))
		_spawn_combat_number(incoming_damage, true, false)
		var current_health := int(event.get("health", 0))
		var max_health := int(event.get("max_health", 0))
		_update_vitals(current_health, max_health)
		if bool(event.get("defeated", false)):
			player_slow_visual_remaining = 0.0
			_set_player_slow_visual(false)
			player_poison_visual_remaining = 0.0
			_set_player_poison_visual(local_player, false)
			local_player.is_dead = true
			local_target_position = local_player.position
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			death_message_label.text = "角色已倒地，无法继续行动。\n受到 " + str(incoming_damage) + " 点伤害，生命 " + str(current_health) + "/" + str(max_health) + "。\n确认后将结算复活并返回角色界面。"
			death_panel.visible = true
		else:
			var hit_message := "受到怪物攻击 -" + str(incoming_damage) + " 生命"
			if str(event.get("status_effect", "")) == "slow":
				hit_message += " · 冰霜减速"
			elif str(event.get("status_effect", "")) == "poison":
				hit_message += " · 中毒"
			elif str(event.get("attack_style", "")) == "poison_tick":
				hit_message = "毒素持续侵蚀 -" + str(incoming_damage) + " 生命"
			var resistance_bp := int(event.get("status_resistance_bp", 0))
			if resistance_bp > 0:
				hit_message += " · 体质抗性 " + str(int(round(float(resistance_bp) / 100.0))) + "%"
			_show_notification(hit_message)
		return
	var monster_name := str(event.get("target_name", "目标"))
	var hit_target_id := str(event.get("target_entity_id", ""))
	if monsters.has(hit_target_id):
		var hit_monster := monsters[hit_target_id] as Node3D
		if bool(event.get("burn_applied", false)):
			hit_monster.set_meta("burn_visual_remaining", maxf(float(event.get("burn_duration_ms", 0)) / 1000.0, 0.0))
			_set_monster_burn_visual(hit_monster, true)
		if str(event.get("status_effect", "")) == "burn":
			var hit_burn_remaining := maxf(float(event.get("status_duration_ms", 0)) / 1000.0, 0.0)
			hit_monster.set_meta("burn_visual_remaining", hit_burn_remaining)
			_set_monster_burn_visual(hit_monster, hit_burn_remaining > 0.0)
		if str(event.get("status_effect", "")) == "freeze":
			_set_monster_freeze_visual(hit_monster, true)
		if bool(event.get("defeated", false)):
			hit_monster.set_meta("burn_visual_remaining", 0.0)
			_set_monster_burn_visual(hit_monster, false)
			_set_monster_freeze_visual(hit_monster, false)
		hit_monster.set_meta("hit_reaction_time", 0.24)
		_spawn_monster_hit_visual(hit_monster, bool(event.get("critical", false)))
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
		var projectile_type := str(event.get("projectile_type", ""))
		var hit_prefix := "火球命中 " if projectile_type == "fireball" else ("冰锥命中 " if projectile_type == "ice_bolt" else "命中 ")
		var hit_suffix := " · 目标被冻结" if str(event.get("status_effect", "")) == "freeze" else (" · 目标减速" if str(event.get("status_effect", "")) == "slow" else "")
		_show_notification(hit_prefix + monster_name + " · 造成 " + str(damage) + " 点伤害" + hit_suffix)


func _spawn_monster_hit_visual(monster: Node3D, critical: bool) -> void:
	if not is_instance_valid(monster):
		return
	var archetype := str(monster.get_meta("visual_archetype", ""))
	var tint := Color("#ffdf9a")
	if archetype == "frost_soul":
		tint = Color("#9ceaff")
	elif archetype == "fire_soul":
		tint = Color("#ff9b55")
	elif archetype == "life_soul":
		tint = Color("#a7ffc0")
	elif archetype == "wind_soul":
		tint = Color("#9affed")
	var flash := MeshInstance3D.new()
	flash.name = "MonsterHitFlash"
	var mesh := SphereMesh.new()
	mesh.radius = 0.20 if critical else 0.14
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	flash.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.8 if critical else 1.8
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = material
	add_child(flash)
	flash.global_position = monster.global_position + Vector3(0.0, 1.0, 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * (2.3 if critical else 1.65), 0.22)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.22)
	tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.22)
	tween.chain().tween_callback(Callable(flash, "queue_free"))

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
			var distance: float = local_player.global_position.distance_to(target)
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
	label.text = ("受击 -" if incoming else ("暴击 +" if critical else "+")) + str(amount)
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

func _on_player_action_event(event: Dictionary) -> void:
	var character_id := str(event.get("character_id", ""))
	if character_id.is_empty() or not remote_players.has(character_id):
		return
	var action := str(event.get("action", ""))
	if action not in ["attack", "hit", "cast"]:
		return
	var remote := remote_players[character_id] as Node3D
	if not is_instance_valid(remote):
		return
	# Hit reactions outrank attacks. Lower-priority events cannot replace an active hit.
	var incoming_priority := 2 if action == "hit" else 1
	var current_time := float(remote.get_meta("remote_action_time", 0.0))
	var current_priority := int(remote.get_meta("remote_action_priority", 0))
	if current_time > 0.0 and current_priority > incoming_priority:
		return
	var duration := 0.42 if action == "cast" else (0.36 if action == "attack" else 0.32)
	remote.set_meta("remote_action_state", action)
	remote.set_meta("remote_action_priority", incoming_priority)
	remote.set_meta("remote_action_time", maxf(current_time, duration) if current_priority == incoming_priority else duration)
	remote.set_meta("remote_action_duration", duration)
	remote.set_meta("remote_action_style", str(event.get("attack_style", "")))

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
	var is_underworld := str(HHSession.world_snapshot.get("world_id", "")) == "underworld_fengdu"
	if is_underworld:
		var body := MeshInstance3D.new()
		body.name = "RemoteBody"
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
		remote.add_child(body)
		var halo := MeshInstance3D.new()
		halo.name = "RemoteHalo"
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
		var humanoid := VisualModelLibrary.instantiate_model(
			"player_humanoid",
			func() -> Node3D: return UnderworldVisualFactory.create_player_humanoid()
		)
		humanoid.name = "RemoteHumanoid"
		remote.add_child(humanoid)
	remote.set_meta("is_underworld", is_underworld)
	remote.set_meta("remote_animation_time", 0.0)
	var label := Label3D.new()
	label.text = character_name
	label.position.y = 1.15 if is_underworld else 2.25
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
	minimap_refresh_accumulator += delta
	if minimap_refresh_accumulator >= 0.2:
		minimap_refresh_accumulator = 0.0
		_update_minimap_data()
	var cooldown_changed := false
	for spell_id in spell_cooldown_remaining.keys():
		var remaining := maxf(float(spell_cooldown_remaining[spell_id]) - delta, 0.0)
		if not is_equal_approx(remaining, float(spell_cooldown_remaining[spell_id])):
			spell_cooldown_remaining[spell_id] = remaining
			cooldown_changed = true
	if cooldown_changed:
		_update_spell_cooldown_hud()
	for monster_value in monsters.values():
		var burning_monster := monster_value as Node3D
		if not is_instance_valid(burning_monster):
			continue
		var burn_remaining := float(burning_monster.get_meta("burn_visual_remaining", 0.0))
		if burn_remaining > 0.0:
			burn_remaining = maxf(0.0, burn_remaining - delta)
			burning_monster.set_meta("burn_visual_remaining", burn_remaining)
			if burn_remaining <= 0.0:
				_set_monster_burn_visual(burning_monster, false)
	if player_slow_visual_remaining > 0.0:
		player_slow_visual_remaining = maxf(0.0, player_slow_visual_remaining - delta)
		if player_slow_visual_remaining <= 0.0:
			_set_player_slow_visual(false)
	if player_poison_visual_remaining > 0.0:
		player_poison_visual_remaining = maxf(0.0, player_poison_visual_remaining - delta)
		if player_poison_visual_remaining <= 0.0:
			_set_player_poison_visual(local_player, false)
	for projectile_id in projectile_targets:
		var arrow := projectiles.get(projectile_id) as Node3D
		if is_instance_valid(arrow):
			var arrow_target: Vector3 = projectile_targets[projectile_id]
			arrow.position = arrow.position.lerp(arrow_target, minf(delta * 30.0, 1.0))
	if is_instance_valid(local_player):
		local_player.position = local_player.position.lerp(local_target_position, minf(delta * 14.0, 1.0))
	for character_id in remote_players:
		var remote: Node3D = remote_players[character_id]
		var target: Vector3 = remote_targets.get(character_id, remote.position)
		var remote_moving := remote.position.distance_to(target) > 0.035
		remote.position = remote.position.lerp(target, minf(delta * 14.0, 1.0))
		var target_yaw := float(remote_yaws.get(character_id, remote.rotation.y))
		remote.rotation.y = lerp_angle(remote.rotation.y, target_yaw, minf(delta * 12.0, 1.0))
		var remote_time := float(remote.get_meta("remote_animation_time", 0.0)) + delta
		remote.set_meta("remote_animation_time", remote_time)
		var action_time := maxf(float(remote.get_meta("remote_action_time", 0.0)) - delta, 0.0)
		remote.set_meta("remote_action_time", action_time)
		var action_state := str(remote.get_meta("remote_action_state", ""))
		if action_time <= 0.0:
			action_state = ""
			remote.set_meta("remote_action_state", "")
			remote.set_meta("remote_action_priority", 0)
			remote.set_meta("remote_action_style", "")
		var remote_animation_state := action_state if action_state != "" else ("walk" if remote_moving else "idle")
		var action_duration := maxf(float(remote.get_meta("remote_action_duration", 0.36)), 0.01)
		var action_weight := sin(clampf(1.0 - action_time / action_duration, 0.0, 1.0) * PI) if action_state != "" else 0.0
		var bob := sin(remote_time * (9.0 if remote_moving else 1.8)) * (0.035 if remote_moving else 0.012)
		if bool(remote.get_meta("is_underworld", false)):
			var remote_body := remote.get_node_or_null("RemoteBody") as MeshInstance3D
			if is_instance_valid(remote_body):
				remote_body.position.y = 0.42 + bob
				remote_body.scale = Vector3.ONE * (1.0 + action_weight * (0.30 if action_state == "attack" else 0.18))
		else:
			var remote_humanoid := remote.get_node_or_null("RemoteHumanoid") as Node3D
			if is_instance_valid(remote_humanoid):
				remote_humanoid.position.y = bob
				var native_animation := HumanoidAnimationDriver.apply_state(remote_humanoid, remote_animation_state, 0.16, str(remote.get_meta("remote_action_style", "")))
				if not native_animation:
					var remote_stride := sin(remote_time * (9.0 if remote_moving else 1.8)) * (0.38 if remote_moving else 0.012)
					var remote_left_arm := remote_humanoid.get_node_or_null("ArmPivotLeft") as Node3D
					var remote_right_arm := remote_humanoid.get_node_or_null("ArmPivotRight") as Node3D
					var remote_left_leg := remote_humanoid.get_node_or_null("LegPivotLeft") as Node3D
					var remote_right_leg := remote_humanoid.get_node_or_null("LegPivotRight") as Node3D
					var remote_style := str(remote.get_meta("remote_action_style", ""))
					var remote_left_lift := 0.20
					var remote_right_lift := 1.18
					var remote_sweep := 0.28
					match remote_style:
						"spear_thrust":
							remote_left_lift = 0.38
							remote_right_lift = 0.92
							remote_sweep = 0.04
						"staff_cast":
							remote_left_lift = 0.72
							remote_right_lift = 0.82
							remote_sweep = -0.12
						"ranged_shot":
							remote_left_lift = 0.58
							remote_right_lift = 1.02
							remote_sweep = -0.08
						"heavy_swing":
							remote_left_lift = 0.12
							remote_right_lift = 1.42
							remote_sweep = 0.62
					if is_instance_valid(remote_left_arm):
						remote_left_arm.rotation.x = remote_stride - action_weight * (remote_left_lift if action_state == "attack" else -0.34)
					if is_instance_valid(remote_right_arm):
						remote_right_arm.rotation.x = -remote_stride - action_weight * (remote_right_lift if action_state == "attack" else -0.48)
						remote_right_arm.rotation.z = -action_weight * remote_sweep if action_state == "attack" else action_weight * 0.16
					if is_instance_valid(remote_left_leg):
						remote_left_leg.rotation.x = -remote_stride * 0.82
					if is_instance_valid(remote_right_leg):
						remote_right_leg.rotation.x = remote_stride * 0.82
		var remote_halo := remote.get_node_or_null("RemoteHalo") as MeshInstance3D
		if is_instance_valid(remote_halo):
			remote_halo.rotation.y += delta * (1.05 if remote_moving else 0.34)
			remote_halo.scale = Vector3.ONE * (1.0 + action_weight * 0.24)
	for monster_id in monsters:
		var monster: Node3D = monsters[monster_id]
		var target: Vector3 = monster_targets.get(monster_id, monster.position)
		monster.position = monster.position.lerp(target, minf(delta * 10.0, 1.0))
		var target_yaw := float(monster.get_meta("target_yaw", monster.rotation.y))
		monster.rotation.y = lerp_angle(monster.rotation.y, target_yaw, minf(delta * 9.0, 1.0))
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
		var attack_phase := str(monster.get_meta("attack_phase", ""))
		var attack_phase_time := maxf(float(monster.get_meta("attack_phase_time", 0.0)) - delta, 0.0)
		var attack_phase_duration := maxf(float(monster.get_meta("attack_phase_duration", 0.2)), 0.1)
		monster.set_meta("attack_phase_time", attack_phase_time)
		if attack_phase_time <= 0.0:
			if attack_phase == "windup":
				if str(monster.get_meta("attack_style", "")) == "heavy_slam":
					_set_iron_slam_telegraph(monster, false)
				elif str(monster.get_meta("attack_style", "")) == "soul_bolt":
					_set_elemental_telegraph(monster, false)
			if attack_phase == "impact":
				attack_phase = "recovery"
				attack_phase_time = maxf(float(monster.get_meta("attack_recovery_duration", 0.42)), 0.1)
				attack_phase_duration = attack_phase_time
				monster.set_meta("attack_phase_time", attack_phase_time)
				monster.set_meta("attack_phase_duration", attack_phase_duration)
			elif attack_phase != "":
				attack_phase = ""
			monster.set_meta("attack_phase", attack_phase)
		var death_time := maxf(float(monster.get_meta("death_reaction_time", 0.0)) - delta, 0.0)
		monster.set_meta("hit_reaction_time", hit_time)
		monster.set_meta("death_reaction_time", death_time)
		var animation_state := "death" if death_time > 0.0 else ("hit" if hit_time > 0.0 else ("attack" if attack_phase != "" else ("move" if moving else "idle")))
		var defeated := bool(monster.get_meta("defeated_visual", false)) or bool(monster.get_meta("pending_corpse_cleanup", false))
		if defeated:
			animation_state = "death"
		monster.set_meta("animation_state", animation_state)
		var native_animation := MonsterAnimationDriver.apply_state(monster, animation_state)
		monster.set_meta("native_animation_active", native_animation)
		if not native_animation:
			match archetype:
				"wolf":
					_animate_wolf_monster(monster, stride, moving, phase)
				"iron_beast":
					_animate_iron_beast(monster, stride, moving, phase)
				"warrior":
					_animate_warrior_monster(monster, stride, moving, phase, animation_state)
				"life_soul", "wind_soul", "fire_soul", "frost_soul", "wraith":
					_animate_soul_monster(monster, delta, phase, moving, archetype)
			if attack_phase != "" and death_time <= 0.0:
				var attack_progress := 1.0 - attack_phase_time / attack_phase_duration
				_animate_monster_attack(monster, archetype, attack_phase, clampf(attack_progress, 0.0, 1.0))
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
		var is_soul_monster := archetype in ["life_soul", "wind_soul", "fire_soul", "frost_soul", "wraith"]
		if death_time > 0.0:
			var death_weight := 1.0 - death_time / 1.15
			if is_soul_monster:
				# Soul creatures dissolve upward instead of falling like physical beasts.
				monster.rotation.z = 0.0
				monster.rotation.y += delta * (0.7 + death_weight * 1.8)
				monster.position.y = lerpf(monster.position.y, target.y + death_weight * 0.9, minf(delta * 5.0, 1.0))
				monster.scale = base_scale * maxf(0.035, 1.0 - death_weight * 0.965)
			else:
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
				if is_soul_monster:
					monster.position.y = target.y + 0.9
					monster.rotation.z = 0.0
					monster.scale = base_scale * 0.035
					_apply_monster_death_fade(monster, 0.98)
				else:
					monster.rotation.z = 0.42
					monster.scale = base_scale * 0.28
					_apply_monster_death_fade(monster, 0.92)


func _animate_monster_attack(monster: Node3D, archetype: String, phase: String, progress: float) -> void:
	# Server-confirmed phases drive presentation only; damage is resolved by WorldServer.
	var anticipation := sin(clampf(progress, 0.0, 1.0) * PI * 0.5) if phase == "windup" else 0.0
	var strike := sin(clampf(progress, 0.0, 1.0) * PI) if phase == "impact" else 0.0
	var recovery := 1.0 - clampf(progress, 0.0, 1.0) if phase == "recovery" else 0.0
	match archetype:
		"wolf":
			var torso := monster.get_node_or_null("Torso") as Node3D
			if is_instance_valid(torso):
				torso.position.z = -anticipation * 0.06 - strike * 0.18 + recovery * 0.04
			var jaw := monster.get_node_or_null("JawPivot") as Node3D
			if is_instance_valid(jaw):
				jaw.rotation.x = -anticipation * 0.18 - strike * 0.42
			var front_left := monster.get_node_or_null("FrontLegLeft") as Node3D
			var front_right := monster.get_node_or_null("FrontLegRight") as Node3D
			if is_instance_valid(front_left):
				front_left.rotation.x = -anticipation * 0.12 - strike * 0.24
			if is_instance_valid(front_right):
				front_right.rotation.x = -anticipation * 0.12 - strike * 0.24
		"iron_beast":
			var core := monster.get_node_or_null("IronCore") as Node3D
			if is_instance_valid(core):
				core.position.z = -anticipation * 0.05 - strike * 0.16 + recovery * 0.03
			var skull := monster.get_node_or_null("SkullPivot") as Node3D
			if is_instance_valid(skull):
				skull.rotation.x = -anticipation * 0.16 - strike * 0.48
			var telegraph := monster.get_node_or_null("SlamTelegraph") as MeshInstance3D
			if is_instance_valid(telegraph) and phase == "windup":
				var telegraph_material := telegraph.material_override as StandardMaterial3D
				if telegraph_material != null:
					telegraph_material.albedo_color.a = lerpf(0.30, 0.62, progress)
					telegraph_material.emission_energy_multiplier = lerpf(1.0, 2.2, progress)
		"warrior":
			var arm := monster.get_node_or_null("ArmPivotRight") as Node3D
			if is_instance_valid(arm):
				arm.rotation.x = anticipation * 0.42 - strike * 1.05 + recovery * 0.12
				arm.rotation.z = -0.18 - anticipation * 0.16 - strike * 0.34
		"life_soul", "wind_soul", "wraith":
			var core := monster.get_node_or_null("SoulCore") as Node3D
			if is_instance_valid(core):
				core.scale = Vector3.ONE * (1.0 + anticipation * 0.18 + strike * 0.48 + recovery * 0.08)
			var spark := monster.get_node_or_null("SoulSpark") as Node3D
			if is_instance_valid(spark):
				spark.scale = Vector3.ONE * (1.0 + anticipation * 0.65 + strike * 1.8)
			var orbit := monster.get_node_or_null("SoulOrbit") as Node3D
			if is_instance_valid(orbit):
				orbit.scale = Vector3.ONE * (1.0 + anticipation * 0.08 + strike * 0.22)
		"fire_soul":
			var fire_core := monster.get_node_or_null("SoulCore") as Node3D
			if is_instance_valid(fire_core):
				fire_core.scale = Vector3.ONE * (1.0 + anticipation * 0.24 + strike * 0.62 + recovery * 0.10)
			var crest := monster.get_node_or_null("FlameCrest") as Node3D
			if is_instance_valid(crest):
				crest.scale = Vector3.ONE * (1.0 + anticipation * 0.35 + strike * 0.9)
			for side in [-1.0, 1.0]:
				var orb := monster.get_node_or_null("FlameOrb" + str(side)) as Node3D
				if is_instance_valid(orb):
					orb.position.x = side * (0.42 + anticipation * 0.12 + strike * 0.22)
					orb.scale = Vector3.ONE * (1.0 + anticipation * 0.45 + strike * 0.85)
		"frost_soul":
			var frost_core := monster.get_node_or_null("SoulCore") as Node3D
			if is_instance_valid(frost_core):
				frost_core.scale = Vector3.ONE * (1.0 + anticipation * 0.16 + strike * 0.42 + recovery * 0.06)
			var crown := monster.get_node_or_null("IceCrown") as Node3D
			if is_instance_valid(crown):
				crown.scale = Vector3.ONE * (1.0 + anticipation * 0.22 + strike * 0.58)
			var frost_ring := monster.get_node_or_null("FrostOrbit") as Node3D
			if is_instance_valid(frost_ring):
				frost_ring.scale = Vector3.ONE * (1.0 + anticipation * 0.10 + strike * 0.42)
			for side in [-1.0, 1.0]:
				var shard := monster.get_node_or_null("IceShard" + str(side)) as Node3D
				if is_instance_valid(shard):
					shard.rotation.x = anticipation * 0.28 + strike * 0.75
					shard.scale = Vector3.ONE * (1.0 + anticipation * 0.20 + strike * 0.55)


func _apply_monster_death_fade(monster: Node3D, weight: float) -> void:
	for child in monster.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.material_override is StandardMaterial3D:
				if not bool(mesh_instance.get_meta("death_fade_override_duplicated", false)):
					mesh_instance.material_override = (mesh_instance.material_override as StandardMaterial3D).duplicate(true)
					mesh_instance.set_meta("death_fade_override_duplicated", true)
				var override_material := mesh_instance.material_override as StandardMaterial3D
				_apply_death_fade_to_material(override_material, weight)
			elif mesh_instance.mesh != null:
				# Imported GLBs often use per-surface materials instead of material_override.
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var meta_key := "death_fade_surface_" + str(surface_index)
					if not bool(mesh_instance.get_meta(meta_key, false)):
						var source_material := mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
						if source_material == null:
							source_material = mesh_instance.get_active_material(surface_index) as StandardMaterial3D
						if source_material == null:
							continue
						var unique_material := source_material.duplicate(true) as StandardMaterial3D
						mesh_instance.set_surface_override_material(surface_index, unique_material)
						mesh_instance.set_meta(meta_key, true)
					var surface_material := mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
					_apply_death_fade_to_material(surface_material, weight)
		elif child is Node3D:
			_apply_monster_death_fade(child as Node3D, weight)


func _apply_death_fade_to_material(material: StandardMaterial3D, weight: float) -> void:
	if material == null:
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tint := material.albedo_color
	tint.a = 1.0 - weight
	material.albedo_color = tint
	material.emission_energy_multiplier = maxf(0.0, 1.0 - weight)


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
	var drift_speed := 1.0
	var amplitude := 0.075
	match archetype:
		"life_soul":
			drift_speed = 1.35
			amplitude = 0.12
		"wind_soul":
			drift_speed = 2.1
			amplitude = 0.20
		"fire_soul":
			drift_speed = 1.75
			amplitude = 0.16
		"frost_soul":
			drift_speed = 0.72
			amplitude = 0.055
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
		var orbit_speed := 0.72
		if archetype == "wind_soul":
			orbit_speed = 1.8
		elif archetype == "fire_soul":
			orbit_speed = 1.25
		elif archetype == "frost_soul":
			orbit_speed = 0.38
		orbit.rotation.y += delta * orbit_speed
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
		var flame := monster.get_node_or_null("FlameOrb" + str(side)) as Node3D
		if is_instance_valid(flame):
			flame.position.y = 0.66 + sin(monster_animation_time * 2.6 + phase + side) * 0.12
			flame.scale = Vector3.ONE * (0.85 + absf(sin(monster_animation_time * 3.1 + phase)) * 0.32)
		var ice_shard := monster.get_node_or_null("IceShard" + str(side)) as Node3D
		if is_instance_valid(ice_shard):
			ice_shard.rotation.y = sin(monster_animation_time * 0.8 + phase + side) * 0.12
			ice_shard.position.y = 0.70 + sin(monster_animation_time * 0.9 + phase + side) * 0.035
	var frost_orbit := monster.get_node_or_null("FrostOrbit") as Node3D
	if is_instance_valid(frost_orbit):
		frost_orbit.rotation.y -= delta * 0.28


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
	if is_instance_valid(local_player) and local_player.has_method("set_equipment_visuals"):
		local_player.call("set_equipment_visuals", items)
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
	inventory_status.text = "装备操作已完成，战斗属性自动同步。"
	_refresh_inventory()
	_refresh_equipment()

func _make_request_uuid() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return hex.substr(0,8) + "-" + hex.substr(8,4) + "-4" + hex.substr(13,3) + "-a" + hex.substr(17,3) + "-" + hex.substr(20,12)

func _on_use_consumable_pressed(item_id: String) -> void:
	if consumable_busy or item_id.is_empty():
		return
	if HHSession.world_network != null and HHSession.world_network.is_world_ready():
		consumable_busy = true
		inventory_status.text = "正在向世界服务器提交消耗品请求……"
		var send_error: Error = HHSession.world_network.send_consumable_use(item_id, 1)
		if send_error != OK:
			consumable_busy = false
			inventory_status.text = "消耗品请求发送失败，错误码：" + str(send_error)
		return
	if consumable_http == null:
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
		if response_code == 409:
			inventory_status.text = "为保护在线角色资源，请先退出世界，再使用恢复类物品。"
		else:
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
	_apply_button_theme(npc_interact_button, true)
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
	_apply_button_theme(exploration_open_button)
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
	_apply_panel_theme(npc_panel)
	hud.add_child(npc_panel)
	var npc_scroll := ScrollContainer.new()
	npc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	npc_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_scroll.custom_minimum_size = Vector2(260.0, 260.0)
	npc_panel.add_child(npc_scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	npc_scroll.add_child(layout)
	npc_title_label = Label.new()
	npc_title_label.add_theme_font_size_override("font_size", 22)
	npc_title_label.add_theme_color_override("font_color", Color("#d4b47b"))
	npc_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(npc_title_label)
	npc_dialogue_label = Label.new()
	npc_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_dialogue_label.add_theme_color_override("font_color", Color("#e7dfd2"))
	npc_dialogue_label.custom_minimum_size = Vector2(420.0, 120.0)
	npc_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(npc_dialogue_label)
	npc_status_label = Label.new()
	npc_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_status_label.add_theme_color_override("font_color", Color("#a9bac7"))
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
	_apply_button_theme(npc_trial_button, true)
	npc_trial_button.pressed.connect(_request_soul_trials)
	layout.add_child(npc_trial_button)
	npc_eligibility_button = Button.new()
	npc_eligibility_button.text = "查看投胎资格"
	_apply_button_theme(npc_eligibility_button)
	npc_eligibility_button.pressed.connect(_request_reincarnation_eligibility)
	layout.add_child(npc_eligibility_button)
	npc_fate_encounter_button = Button.new()
	npc_fate_encounter_button.text = "探查命格奇遇"
	_apply_button_theme(npc_fate_encounter_button, true)
	npc_fate_encounter_button.visible = false
	npc_fate_encounter_button.pressed.connect(_discover_npc_fate_encounter)
	layout.add_child(npc_fate_encounter_button)
	npc_soul_button = Button.new()
	npc_soul_button.text = "查看灵魂境界"
	_apply_button_theme(npc_soul_button)
	npc_soul_button.pressed.connect(_request_soul_progression)
	layout.add_child(npc_soul_button)
	npc_fusion_button = Button.new()
	npc_fusion_button.text = "查看魂质融合"
	_apply_button_theme(npc_fusion_button)
	npc_fusion_button.visible = false
	npc_fusion_button.pressed.connect(_request_soul_fusions)
	layout.add_child(npc_fusion_button)
	npc_soul_breakthrough_button = Button.new()
	npc_soul_breakthrough_button.text = "主动突破灵魂境界"
	_apply_button_theme(npc_soul_breakthrough_button, true)
	npc_soul_breakthrough_button.visible = false
	npc_soul_breakthrough_button.pressed.connect(_request_soul_breakthrough)
	layout.add_child(npc_soul_breakthrough_button)
	npc_reincarnation_leave_button = Button.new()
	npc_reincarnation_leave_button.text = "返回角色界面办理轮回"
	_apply_button_theme(npc_reincarnation_leave_button)
	npc_reincarnation_leave_button.visible = false
	npc_reincarnation_leave_button.pressed.connect(_leave_world_for_reincarnation)
	layout.add_child(npc_reincarnation_leave_button)
	var close_button := Button.new()
	close_button.text = "关闭"
	_apply_button_theme(close_button)
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
						_apply_button_theme(choice_button, true)
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
		_apply_button_theme(point_button)
		var danger := int(point.get("danger_level", 1))
		var target := Vector3(float(point.get("position_x", 0.0)), float(point.get("position_y", 0.0)), float(point.get("position_z", 0.0)))
		var distance: float = local_player.global_position.distance_to(target) if is_instance_valid(local_player) else INF
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
	var in_range: bool = distance <= float(event.get("interaction_radius", 4.0))
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
	heading.add_theme_color_override("font_color", Color("#d4b47b"))
	heading.add_theme_font_size_override("font_size", 17)
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
		var distance: float = local_player.global_position.distance_to(target) if is_instance_valid(local_player) else INF
		var in_range: bool = distance <= float(event.get("interaction_radius", 4.0))
		var status := str(event.get("status", "locked"))
		var state_text := _exploration_event_state_text(event, distance)
		var event_button := Button.new()
		_apply_button_theme(event_button, status == "available")
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
	var distance: float = local_player.global_position.distance_to(target) if is_instance_valid(local_player) else INF
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
			_apply_button_theme(choice_button, true)
			choice_button.text = str(choice.get("text", "作出回应"))
			choice_button.tooltip_text = str(choice.get("description", ""))
			choice_button.pressed.connect(_confirm_exploration_event.bind(choice_id))
			npc_choice_container.add_child(choice_button)
			choice_count += 1
	if choice_count == 0:
		npc_status_label.text = "此奇遇尚未配置有效分支，暂时无法回应。"
	var cancel_button := Button.new()
	_apply_button_theme(cancel_button)
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
		var distance: float = local_player.global_position.distance_to(target)
		var in_range: bool = distance <= float(point.get("interaction_radius", 4.0))
		point_button.disabled = not in_range or npc_request_busy
		var danger := int(point.get("danger_level", 1))
		point_button.text = str(point.get("region_name", "未知区域")) + " · " + ("调查" if in_range else "未抵达 · " + str(roundi(distance)) + "m") + " · " + str(point.get("name", "未知地点")) + "  | 危险 " + str(danger) + "/10"
	for event_id in exploration_event_buttons.keys():
		var event: Dictionary = exploration_event_data.get(event_id, {})
		var event_button: Button = exploration_event_buttons[event_id]
		if not is_instance_valid(event_button):
			continue
		var event_target := Vector3(float(event.get("position_x", 0.0)), float(event.get("position_y", 0.0)), float(event.get("position_z", 0.0)))
		var event_distance: float = local_player.global_position.distance_to(event_target)
		var event_in_range: bool = event_distance <= float(event.get("interaction_radius", 4.0))
		var event_status := str(event.get("status", "locked"))
		event_button.disabled = event_status != "available" or not event_in_range or npc_request_busy
		event_button.text = str(event.get("point_name", "探索地点")) + " · " + str(event.get("title", "未知奇遇")) + " · " + _exploration_event_state_text(event, event_distance)
