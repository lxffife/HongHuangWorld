extends Node3D

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
var progression_request_context := ""
var reconnect_http: HTTPRequest
var reconnect_network: HHWorldNetwork
var reconnect_request_busy := false

var local_player: HHPlayerController
var local_target_position := Vector3.ZERO
var remote_players: Dictionary = {}
var remote_targets: Dictionary = {}
var remote_yaws: Dictionary = {}
var monsters: Dictionary = {}
var monster_targets: Dictionary = {}
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
var npc_panel: PanelContainer
var npc_title_label: Label
var npc_dialogue_label: Label
var npc_status_label: Label
var npc_interact_button: Button
var npc_trial_button: Button
var npc_eligibility_button: Button
var npc_selected_id := ""
var npc_request_busy := false

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_player()
	if HHSession.world_network != null:
		HHSession.world_network.entities_updated.connect(_on_entities_updated)
		HHSession.world_network.player_joined.connect(_on_player_joined)
		HHSession.world_network.player_left.connect(_on_player_left)
		HHSession.world_network.combat_event.connect(_on_combat_event)
		HHSession.world_network.pickup_event.connect(_on_pickup_event)
		HHSession.world_network.disconnected.connect(_on_world_disconnected)
		var spawn: Dictionary = HHSession.world_snapshot
		local_target_position = Vector3(float(spawn.get("position_x", 0.0)), float(spawn.get("position_y", 0.15)), float(spawn.get("position_z", 0.0)))
		local_player.position = local_target_position
	_update_hud()
	progression_http = HTTPRequest.new()
	progression_http.timeout = 10.0
	add_child(progression_http)
	progression_http.request_completed.connect(_on_progression_request_completed)
	respawn_http = HTTPRequest.new()
	respawn_http.timeout = 12.0
	add_child(respawn_http)
	respawn_http.request_completed.connect(_on_respawn_request_completed)
	respawn_button = Button.new()
	respawn_button.text = "返回冥界·酆都复活"
	respawn_button.visible = false
	$HUD/Panel/Margin/Content.add_child(respawn_button)
	respawn_button.pressed.connect(_on_respawn_pressed)
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
	_request_world_npcs()

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
	progression_label.text = system_name + " · " + realm_name + stage_name + "\n累计修为：" + str(cultivation) + "  |  跨族参考：" + tier_name + "\n主血脉：" + primary_bloodline + "（纯度 " + str(bloodline_purity) + "/10000）\n" + threshold_text
	breakthrough_button.disabled = next_stage == null and next_realm == null

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#142b49")
	sky_material.sky_horizon_color = Color("#d3a878")
	sky_material.ground_bottom_color = Color("#182333")
	sky_material.ground_horizon_color = Color("#a58b6b")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9fb4d0")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#9ba9b8")
	environment.fog_density = 0.0018
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

func _build_terrain() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(240.0, 240.0)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#354c43")
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
	local_player = HHPlayerController.new()
	local_player.name = "LocalPlayer"
	local_player.position = Vector3(0.0, 0.15, 0.0)
	add_child(local_player)

func _update_hud() -> void:
	var snapshot: Dictionary = HHSession.world_snapshot
	var world_id := str(snapshot.get("world_id", "青云人界"))
	var character_name := str(snapshot.get("name", "初入洪荒"))
	hud_label.text = "洪荒 · " + world_id + "\n" + character_name + "  |  WASD 移动 · 鼠标转向 · ESC 释放鼠标 · E 拾取\n服务器权威移动已启用 · 左键攻击附近怪物 · 20Hz 实体快照"

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
			monsters[monster_id].queue_free()
			monsters.erase(monster_id)
			monster_targets.erase(monster_id)
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

func _create_monster(monster_name: String, monster_level: int) -> Node3D:
	var monster := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.52
	capsule.height = 1.25
	body.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#8b5140")
	material.roughness = 0.9
	body.material_override = material
	body.position.y = 0.62
	monster.add_child(body)
	var label := Label3D.new()
	label.text = monster_name + " · Lv." + str(monster_level)
	label.position.y = 1.55
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#ffd0a8")
	monster.add_child(label)
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
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F:
		_try_interact_nearest_npc()
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

func _on_pickup_event(event: Dictionary) -> void:
	if bool(event.get("pending", false)):
		hud_label.text = str(event.get("reason", "正在结算拾取……"))
		return
	if bool(event.get("accepted", false)):
		hud_label.text = "拾取成功：" + str(event.get("item_id", "物品")) + " ×" + str(event.get("quantity", 1))
		_refresh_inventory()
	else:
		hud_label.text = str(event.get("reason", "拾取失败。"))

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

func _request_nearest_monster_attack() -> void:
	var network := HHSession.world_network
	if network == null or not network.is_world_ready() or not is_instance_valid(local_player):
		return
	var nearest_id := ""
	var nearest_distance := 4.5
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

func _on_combat_event(event: Dictionary) -> void:
	if not bool(event.get("accepted", true)):
		hud_label.text = str(event.get("reason", "攻击未命中。"))
		return
	if str(event.get("source", "")) == "monster":
		var incoming_damage := int(event.get("damage", 0))
		var current_health := int(event.get("health", 0))
		var max_health := int(event.get("max_health", 0))
		if bool(event.get("defeated", false)):
			respawn_button.visible = true
			hud_label.text = "你已死亡。受到 " + str(incoming_damage) + " 点伤害，生命归零。可返回冥界·酆都复活。 " + str(current_health) + "/" + str(max_health)
		else:
			hud_label.text = "受到怪物攻击，损失 " + str(incoming_damage) + " 点生命。当前生命 " + str(current_health) + "/" + str(max_health)
		return
	var monster_name := str(event.get("target_name", "目标"))
	var damage := int(event.get("damage", 0))
	if bool(event.get("defeated", false)):
		var experience := int(event.get("experience_reward", 0))
		var cultivation := int(event.get("cultivation_reward", 0))
		hud_label.text = monster_name + " 已被击败！伤害 " + str(damage) + "，奖励结算中：经验 +" + str(experience) + "，修为 +" + str(cultivation) + "。"
		_refresh_reward_status_later()
	else:
		hud_label.text = "命中 " + monster_name + "，造成 " + str(damage) + " 点伤害。"

func _refresh_reward_status_later() -> void:
	await get_tree().create_timer(1.5).timeout
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
	label.position.y = 2.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	remote.add_child(label)
	add_child(remote)
	return remote

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
	for drop_id in drops:
		var drop: Node3D = drops[drop_id]
		var target: Vector3 = drop_targets.get(drop_id, drop.position)
		drop.position = drop.position.lerp(target, minf(delta * 12.0, 1.0))
	_update_nearest_npc_prompt()


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
	if not reconnect_network.pickup_event.is_connected(_on_pickup_event):
		reconnect_network.pickup_event.connect(_on_pickup_event)
	local_target_position = Vector3(
		float(snapshot.get("position_x", 0.0)),
		float(snapshot.get("position_y", 0.15)),
		float(snapshot.get("position_z", 0.0))
	)
	local_player.position = local_target_position
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
		hud_label.text = "复活失败：" + body.get_string_from_utf8()
		return
	respawn_button.visible = false
	hud_label.text = "已返回冥界·酆都，生命与灵力已恢复。请返回主界面重新进入世界。"


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
	npc_trial_button = Button.new()
	npc_trial_button.text = "查看冥界试炼"
	npc_trial_button.pressed.connect(_request_soul_trials)
	layout.add_child(npc_trial_button)
	npc_eligibility_button = Button.new()
	npc_eligibility_button.text = "查看投胎资格"
	npc_eligibility_button.pressed.connect(_request_reincarnation_eligibility)
	layout.add_child(npc_eligibility_button)
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
	if npc_http == null or npc_request_busy or HHSession.access_token.is_empty():
		return
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var http_method := HTTPClient.METHOD_GET
	var body := ""
	if method == "POST":
		http_method = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)
	npc_request_context = context
	var error := npc_http.request(HHSession.api_base + path, headers, http_method, body)
	if error != OK:
		npc_request_context = ""
		npc_status_label.text = "无法向中心服发送 NPC 请求，错误码：" + str(error)
	else:
		npc_request_busy = true

func _on_npc_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	npc_request_busy = false
	var context := npc_request_context
	npc_request_context = ""
	var raw := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if result != HTTPRequest.RESULT_SUCCESS:
		if npc_status_label != null:
			npc_status_label.text = "NPC 服务连接失败，请检查中心服。"
		return
	if response_code < 200 or response_code >= 300:
		if npc_status_label != null:
			npc_status_label.text = "请求未完成（HTTP " + str(response_code) + "）：" + raw
		return
	match context:
		"list":
			npc_definitions = data.get("npcs", [])
			_render_world_npcs()
		"interact":
			var npc_data: Dictionary = data.get("npc", {})
			var dialogue: Dictionary = data.get("dialogue", {})
			npc_title_label.text = str(npc_data.get("name", "冥界来者")) + " · " + str(npc_data.get("title", ""))
			var lines: Array[String] = []
			lines.append(str(dialogue.get("greeting", "这位道友，有何事？")))
			var topics: Variant = dialogue.get("topics", [])
			if topics is Array:
				for topic in topics:
					lines.append("· " + str(topic))
			npc_dialogue_label.text = PackedStringArray(lines).join("\n")
			npc_status_label.text = "交互已由中心服验证。"
			npc_trial_button.visible = str(npc_data.get("interaction_type", "")) == "soul_trials"
			npc_eligibility_button.visible = str(npc_data.get("interaction_type", "")) == "reincarnation_guidance"
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
			npc_dialogue_label.text = "\n".join(lines)
			npc_status_label.text = "任务进度来自中心服，不使用客户端本地计数。"
			npc_panel.visible = true
		"eligibility":
			var realm := str(data.get("current_realm_name", "未知"))
			var required := str(data.get("required_realm_name", "聚灵境"))
			var completed := bool(data.get("trial_completed", false))
			var reasons: Array = data.get("reasons", [])
			npc_title_label.text = "轮回殿 · 投胎资格"
			npc_dialogue_label.text = "当前灵魂境界：" + realm + "\n要求灵魂境界：" + required + "\n引魂试炼：" + ("已完成" if completed else "尚未完成")
			npc_status_label.text = "已满足首次投胎条件，可以申请创建新肉身。" if bool(data.get("eligible", false)) else "尚未满足条件：" + ", ".join(PackedStringArray(reasons))
			npc_panel.visible = true

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
		var marker := Node3D.new()
		marker.name = "NPC_" + npc_id
		marker.position = Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
		marker.rotation.y = float(npc_data.get("rotation_y", 0.0))
		var orb := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.38
		mesh.height = 1.65
		orb.mesh = mesh
		orb.position.y = 0.82
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#8c7bd1") if str(npc_data.get("npc_type", "")) == "judge" else Color("#d6b16b")
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.12
		orb.material_override = material
		marker.add_child(orb)
		var label := Label3D.new()
		label.text = str(npc_data.get("name", "NPC")) + "\nF 交互"
		label.position.y = 2.0
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("#f3dfb6")
		marker.add_child(label)
		add_child(marker)
		npc_nodes[npc_id] = marker
	_update_nearest_npc_prompt()

func _update_nearest_npc_prompt() -> void:
	if npc_interact_button == null or not is_instance_valid(local_player):
		return
	var nearest_distance := INF
	var nearest_name := ""
	for npc_variant in npc_definitions:
		if not (npc_variant is Dictionary):
			continue
		var npc_data: Dictionary = npc_variant
		var target := Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		var radius := float(npc_data.get("interaction_radius", 3.0))
		if distance <= radius and distance < nearest_distance:
			nearest_distance = distance
			nearest_name = str(npc_data.get("name", "NPC"))
	npc_interact_button.visible = not nearest_name.is_empty()
	if npc_interact_button.visible:
		npc_interact_button.text = "F · 与 " + nearest_name + " 交互"

func _try_interact_nearest_npc() -> void:
	if npc_request_busy or not is_instance_valid(local_player):
		return
	var nearest_id := ""
	var nearest_distance := INF
	for npc_variant in npc_definitions:
		if not (npc_variant is Dictionary):
			continue
		var npc_data: Dictionary = npc_variant
		var target := Vector3(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_y", 0.0)), float(npc_data.get("position_z", 0.0)))
		var distance := Vector2(target.x - local_player.position.x, target.z - local_player.position.z).length()
		if distance <= float(npc_data.get("interaction_radius", 3.0)) and distance < nearest_distance:
			nearest_distance = distance
			nearest_id = str(npc_data.get("id", ""))
	if nearest_id.is_empty():
		return
	npc_selected_id = nearest_id
	npc_status_label.text = "正在与 NPC 建立交互……"
	_send_npc_request("POST", "/api/v1/worlds/current/npcs/interact", "interact", {"npc_id": nearest_id})

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
