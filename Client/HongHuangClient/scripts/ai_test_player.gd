extends SceneTree
## Headless companion player for real multiplayer / combat verification.
## Run with: godot --headless --path Client/HongHuangClient --script res://scripts/ai_test_player.gd
## Configure HH_API_BASE, HH_AI_BOT_USERNAME, HH_AI_BOT_PASSWORD, HH_AI_BOT_NAME.

const DEFAULT_API_BASE := "http://127.0.0.1:8787"
const BOT_CONFIG_PATH := "user://ai_test_player.cfg"
const CLIENT_BUILD := "0.1.0"
const WORLD_ID := "underworld_fengdu"
const FOLLOW_DISTANCE := 4.0
const ATTACK_DISTANCE := 2.6
const MONSTER_APPROACH_DISTANCE := 12.0
const ATTACK_INTERVAL := 1.25

var api_base := ""
var username := ""
var password := ""
var bot_name := ""
var bot_character_id := ""
var token := ""
var network: Node
var latest_entities: Array = []
var party_character_ids: Array[String] = []
var welcomed := false
var stopping := false
var input_sequence := 0
var last_attack_msec := 0
var last_party_poll_msec := 0
var last_party_warning := ""
var last_party_warning_msec := 0
var last_input_msec := 0
var connect_started_msec := 0
var status_text := "starting"

func _initialize() -> void:
	call_deferred("_main")

func _main() -> void:
	api_base = OS.get_environment("HH_API_BASE").strip_edges().trim_suffix("/")
	if api_base.is_empty():
		api_base = DEFAULT_API_BASE
	bot_name = OS.get_environment("HH_AI_BOT_NAME").strip_edges()
	if bot_name.is_empty():
		bot_name = "洪荒测试仙"
	_load_or_create_credentials()
	_log("AI 测试玩家启动；API=" + api_base)
	_log("测试玩家账号：" + username + "；角色：" + bot_name)
	if not await _prepare_account():
		quit(2)
		return
	if not await _prepare_soul_and_character():
		quit(3)
		return
	if not await _enter_world():
		quit(4)
		return
	_log("已进入世界，等待 ServerWelcome。准备好后请在游戏内邀请账号：" + username)
	connect_started_msec = Time.get_ticks_msec()
	while not stopping:
		await create_timer(0.1).timeout
		if not welcomed:
			if Time.get_ticks_msec() - connect_started_msec > 45000:
				_log("等待世界服务器握手超过 45 秒，停止本次启动。")
				stopping = true
			continue
		var now := Time.get_ticks_msec()
		if now - last_party_poll_msec >= 2000:
			last_party_poll_msec = now
			await _poll_and_accept_invites()
		if now - last_input_msec >= 100:
			last_input_msec = now
			_run_companion_brain()
		if not network.is_world_ready():
			_log("世界连接已断开，AI 暂停；请重新启动测试玩家进程。")
			stopping = true
	if network != null and network.has_method("close"):
		network.close()
		# Allow queued disconnect callbacks and deferred node cleanup to run
		# before SceneTree exits and destroys the native ENet extension.
		await create_timer(0.5).timeout
	await process_frame
	_log("AI 测试玩家已停止。")
	quit(0)

func _load_or_create_credentials() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(BOT_CONFIG_PATH)
	if err == OK:
		username = str(cfg.get_value("account", "username", ""))
		password = str(cfg.get_value("account", "password", ""))
	if username.is_empty() or password.is_empty():
		var suffix := Crypto.new().generate_random_bytes(4).hex_encode()
		username = OS.get_environment("HH_AI_BOT_USERNAME").strip_edges()
		if username.is_empty():
			username = "hhbot_" + suffix
		password = OS.get_environment("HH_AI_BOT_PASSWORD").strip_edges()
		if password.is_empty():
			password = Crypto.new().generate_random_bytes(24).hex_encode()
		cfg.set_value("account", "username", username)
		cfg.set_value("account", "password", password)
		var save_error := cfg.save(BOT_CONFIG_PATH)
		if save_error != OK:
			_log("无法保存本地测试账号凭据，错误码：" + str(save_error))

func _prepare_account() -> bool:
	var login := await _api("POST", "/api/v1/auth/login", {
		"username": username, "password": password
	})
	if login.code >= 200 and login.code < 300:
		token = str(login.data.get("access_token", ""))
		if not token.is_empty():
			_log("测试账号登录成功。")
			return true
	if login.code != 401:
		_log("登录请求失败 HTTP " + str(login.code) + "：" + login.body)
		return false
	var register := await _api("POST", "/api/v1/auth/register", {
		"username": username, "email": "", "password": password
	})
	if register.code >= 200 and register.code < 300:
		token = str(register.data.get("access_token", ""))
		if not token.is_empty():
			_log("已创建并登录测试账号。")
			return true
	_log("账号登录/注册失败 HTTP " + str(register.code) + "：" + register.body)
	return false

func _prepare_soul_and_character() -> bool:
	var soul := await _api("GET", "/api/v1/souls/current", {}, true)
	if soul.code == 404:
		soul = await _api("POST", "/api/v1/souls", {
			"name": bot_name, "origin": "AI 自动联机测试角色"
		}, true)
	if not (soul.code >= 200 and soul.code < 300):
		_log("创建/读取测试角色魂魄失败 HTTP " + str(soul.code) + "：" + soul.body)
		return false
	var character := await _api("GET", "/api/v1/characters/current", {}, true)
	if character.code == 404:
		character = await _api("POST", "/api/v1/characters/first-life", {
			"name": bot_name, "world_id": WORLD_ID, "race_id": "human"
		}, true)
	if not (character.code >= 200 and character.code < 300):
		_log("创建/读取测试角色失败 HTTP " + str(character.code) + "：" + character.body)
		return false
	_log("角色已准备完成，世界：" + WORLD_ID)
	return true

func _enter_world() -> bool:
	var entry := await _api("POST", "/api/v1/worlds/enter", {}, true)
	if not (entry.code >= 200 and entry.code < 300):
		_log("申请世界入口失败 HTTP " + str(entry.code) + "：" + entry.body)
		return false
	var host := str(entry.data.get("host", ""))
	var port := int(entry.data.get("udp_port", 0))
	var ticket := str(entry.data.get("ticket", ""))
	if host.is_empty() or port < 1 or ticket.is_empty():
		_log("世界入口响应缺少 host/udp_port/ticket：" + entry.body)
		return false
	var network_script: Script = load("res://scripts/world_network.gd")
	if network_script == null:
		_log("无法加载 world_network.gd")
		return false
	network = network_script.new()
	root.add_child(network)
	network.welcomed.connect(_on_welcomed)
	network.rejected.connect(func(reason: String): _log("世界服务器拒绝连接：" + reason))
	network.connection_error.connect(func(message: String): _log("网络错误：" + message))
	network.disconnected.connect(func(): _log("ENet 已断开。"))
	network.entities_updated.connect(_on_entities_updated)
	network.combat_event.connect(_on_combat_event)
	var connect_error: int = network.connect_with_ticket(host, port, ticket)
	if connect_error != OK:
		_log("初始化 ENet 连接失败，错误码：" + str(connect_error))
		return false
	return true

func _on_welcomed(snapshot: Dictionary) -> void:
	bot_character_id = str(snapshot.get("character_id", ""))
	welcomed = not bot_character_id.is_empty()
	_log("世界连接成功：角色=" + bot_character_id + "，世界=" + str(snapshot.get("world_id", "")))

func _on_entities_updated(entities: Array) -> void:
	latest_entities = entities

func _on_combat_event(event: Dictionary) -> void:
	var accepted := bool(event.get("accepted", false))
	var phase := str(event.get("phase", ""))
	var reason := str(event.get("reason", ""))
	_log("战斗服务器反馈：" + ("接受" if accepted else "未接受") + " · " + phase + (" · " + reason if not reason.is_empty() else ""))

func _poll_and_accept_invites() -> void:
	var result := await _api("GET", "/api/v1/party/invitations", {}, true)
	if result.code < 200 or result.code >= 300:
		_log_party_api_issue("读取组队邀请", result)
		return
	if not result.json_ok:
		_log_party_api_issue("读取组队邀请（响应不是有效 JSON）", result)
		return
	var invitations: Array = result.data.get("invitations", [])
	for invitation in invitations:
		var invitation_id := str(invitation.get("id", ""))
		if invitation_id.is_empty():
			continue
		var response := await _api("POST", "/api/v1/party/invitations/" + invitation_id + "/respond", {
			"decision": "accept"
		}, true)
		if response.code >= 200 and response.code < 300:
			_log("已接受组队邀请，正式加入你的队伍。")
		else:
			_log("接受组队邀请失败 HTTP " + str(response.code) + "：" + response.body)
	var party_result := await _api("GET", "/api/v1/party/current", {}, true)
	party_character_ids.clear()
	if party_result.code >= 200 and party_result.code < 300 and party_result.json_ok:
		for member in party_result.data.get("members", []):
			var member_id := str(member.get("character_id", ""))
			if not member_id.is_empty() and member_id != bot_character_id:
				party_character_ids.append(member_id)
	elif party_result.code != 404:
		_log_party_api_issue("读取当前队伍", party_result)

func _log_party_api_issue(action: String, result: Dictionary) -> void:
	var detail := "HTTP " + str(result.get("code", 0))
	var response_text := str(result.get("body", "")).strip_edges()
	if not response_text.is_empty():
		detail += " · " + response_text.substr(0, 240)
	var warning := action + "失败：" + detail
	var now := Time.get_ticks_msec()
	if warning == last_party_warning and now - last_party_warning_msec < 15000:
		return
	last_party_warning = warning
	last_party_warning_msec = now
	_log(warning)

func _run_companion_brain() -> void:
	if network == null or not network.is_world_ready():
		return
	var self_entity: Dictionary = {}
	var players: Array[Dictionary] = []
	var monsters: Array[Dictionary] = []
	for raw in latest_entities:
		if not raw is Dictionary:
			continue
		var entity: Dictionary = raw
		match str(entity.get("entity_type", "")):
			"player":
				if str(entity.get("character_id", "")) == bot_character_id:
					self_entity = entity
				elif party_character_ids.has(str(entity.get("character_id", ""))):
					players.append(entity)
			"monster":
				if int(entity.get("health", 0)) > 0 and not bool(entity.get("death_pending", false)):
					monsters.append(entity)
	if self_entity.is_empty():
		# The own-player entity can be absent from a transient snapshot; never issue blind movement.
		return
	var self_pos := Vector2(float(self_entity.get("x", 0.0)), float(self_entity.get("z", 0.0)))
	var target_player: Dictionary = {}
	var target_distance := INF
	for player in players:
		if not bool(player.get("alive", true)):
			continue
		var pos := Vector2(float(player.get("x", 0.0)), float(player.get("z", 0.0)))
		var distance := self_pos.distance_to(pos)
		if distance < target_distance:
			target_distance = distance
			target_player = player
	var target_monster: Dictionary = {}
	var monster_distance := INF
	for monster in monsters:
		var pos := Vector2(float(monster.get("x", 0.0)), float(monster.get("z", 0.0)))
		var distance := self_pos.distance_to(pos)
		if distance < monster_distance:
			monster_distance = distance
			target_monster = monster
	if not target_monster.is_empty() and monster_distance <= ATTACK_DISTANCE:
		var now := Time.get_ticks_msec()
		if now - last_attack_msec >= int(ATTACK_INTERVAL * 1000.0):
			var attack_error: int = network.send_attack(str(target_monster.get("entity_id", "")))
			if attack_error == OK:
				last_attack_msec = now
				_log("AI 发起攻击：" + str(target_monster.get("name", "怪物")))
			else:
				_log("AI 攻击指令发送失败，错误码：" + str(attack_error))
		_send_movement(Vector2.ZERO)
		return
	if not target_monster.is_empty() and monster_distance <= MONSTER_APPROACH_DISTANCE:
		var monster_pos := Vector2(float(target_monster.get("x", 0.0)), float(target_monster.get("z", 0.0)))
		_send_movement((monster_pos - self_pos).normalized())
	elif not target_player.is_empty() and target_distance > FOLLOW_DISTANCE:
		var player_pos := Vector2(float(target_player.get("x", 0.0)), float(target_player.get("z", 0.0)))
		_send_movement((player_pos - self_pos).normalized())
	else:
		_send_movement(Vector2.ZERO)

func _send_movement(direction: Vector2) -> void:
	input_sequence += 1
	var err: int = network.send_input(direction.x, direction.y, input_sequence, false)
	if err != OK:
		_log("AI 移动指令发送失败，错误码：" + str(err))

func _api(method: String, path: String, body: Dictionary = {}, authenticated: bool = false) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 15.0
	root.add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if authenticated and not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var payload := "" if method == "GET" else JSON.stringify(body)
	var error := request.request(api_base + path, headers, HTTPClient.METHOD_GET if method == "GET" else (HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET), payload)
	if error != OK:
		request.queue_free()
		return {"code": 0, "body": "request start failed: " + str(error), "data": {}}
	var completed: Array = await request.request_completed
	request.queue_free()
	var code := int(completed[1])
	var response_body: PackedByteArray = completed[3]
	var body_text := response_body.get_string_from_utf8()
	var parser := JSON.new()
	var parse_error: Error = parser.parse(body_text) if not body_text.strip_edges().is_empty() else ERR_PARSE_ERROR
	var parsed: Variant = parser.data if parse_error == OK else null
	return {
		"code": code,
		"body": body_text,
		"data": parsed if parsed is Dictionary else {},
		"json_ok": parse_error == OK and parsed is Dictionary
	}

func _log(message: String) -> void:
	print("[HH-AI-BOT] " + message)
