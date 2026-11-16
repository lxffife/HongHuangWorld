extends Node3D

@onready var hud_label: Label = $HUD/Panel/Margin/Content/Status
@onready var progression_label: Label = $HUD/Panel/Margin/Content/Progression
@onready var breakthrough_button: Button = $HUD/Panel/Margin/Content/Breakthrough
@onready var reconnect_button: Button = $HUD/Panel/Margin/Content/Reconnect

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

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_player()
	if HHSession.world_network != null:
		HHSession.world_network.entities_updated.connect(_on_entities_updated)
		HHSession.world_network.disconnected.connect(_on_world_disconnected)
		var spawn: Dictionary = HHSession.world_snapshot
		local_target_position = Vector3(float(spawn.get("position_x", 0.0)), float(spawn.get("position_y", 0.15)), float(spawn.get("position_z", 0.0)))
		local_player.position = local_target_position
	_update_hud()
	progression_http = HTTPRequest.new()
	progression_http.timeout = 10.0
	add_child(progression_http)
	progression_http.request_completed.connect(_on_progression_request_completed)
	breakthrough_button.pressed.connect(_on_breakthrough_pressed)
	reconnect_button.pressed.connect(_on_reconnect_pressed)
	reconnect_http = HTTPRequest.new()
	reconnect_http.timeout = 12.0
	add_child(reconnect_http)
	reconnect_http.request_completed.connect(_on_reconnect_request_completed)
	_refresh_character_status()

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

func _on_progression_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var context := progression_request_context
	progression_request_context = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		progression_label.text = "修炼服务连接失败，请检查中心服。"
		breakthrough_button.disabled = false
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
	if response_code < 200 or response_code >= 300:
		progression_label.text = "读取修炼状态失败：" + body.get_string_from_utf8()
		breakthrough_button.disabled = true
		return
	var progression: Dictionary = data.get("progression", {})
	var bloodlines: Array = data.get("bloodlines", [])
	var primary_bloodline := "未觉醒"
	var bloodline_purity := 0
	for bloodline_variant in bloodlines:
		if bloodline_variant is Dictionary and bool(bloodline_variant.get("is_primary", false)):
			primary_bloodline = str(bloodline_variant.get("name", "未知血脉"))
			bloodline_purity = int(bloodline_variant.get("purity", 0))
			break
	var system_name := str(progression.get("system_name", "未知体系"))
	var realm_name := str(progression.get("realm_name", "未知境界"))
	var stage_name := str(progression.get("realm_stage_name", ""))
	var cultivation := int(progression.get("cultivation", 0))
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
	hud_label.text = "洪荒 · " + world_id + "\n" + character_name + "  |  WASD 移动 · 鼠标转向 · ESC 释放鼠标\n服务器权威移动已启用 · 20Hz 实体快照 · 远端玩家同步"

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_entities_updated(entities: Array) -> void:
	var seen: Dictionary = {}
	var own_id := str(HHSession.world_snapshot.get("character_id", ""))
	for entity in entities:
		if not (entity is Dictionary):
			continue
		var character_id := str(entity.get("character_id", ""))
		if character_id.is_empty():
			continue
		var target := Vector3(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)), float(entity.get("z", 0.0)))
		if character_id == own_id:
			local_target_position = target
			continue
		seen[character_id] = true
		if not remote_players.has(character_id):
			remote_players[character_id] = _create_remote_player(str(entity.get("name", "修士")))
		remote_targets[character_id] = target
		remote_yaws[character_id] = float(entity.get("yaw", 0.0))
	for character_id in remote_players.keys():
		if not seen.has(character_id):
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


func _on_world_disconnected() -> void:
	hud_label.text = "与世界服务器的连接已断开。角色位置已由中心服周期保存，可重新连接继续游戏。"
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
	reconnect_button.visible = false
	reconnect_button.disabled = false
	hud_label.text = "已重新进入青云人界，角色已恢复到最近保存的位置。"
	_update_hud()
