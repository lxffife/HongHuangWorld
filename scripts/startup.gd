extends Control

const DEFAULT_API := "http://127.0.0.1:8787"
const CLIENT_BUILD := "0.1.0"

var api_base := DEFAULT_API
var access_token := ""
var worlds: Array = []
var cultivation_races: Array = []
var current_character: Dictionary = {}
var entry_data: Dictionary = {}
var request_queue: Array[Dictionary] = []
var request_busy := false
var world_network: HHWorldNetwork

var http: HTTPRequest
var status_label: Label
var api_input: LineEdit
var username_input: LineEdit
var email_input: LineEdit
var password_input: LineEdit
var character_input: LineEdit
var world_select: OptionButton
var race_select: OptionButton
var cultivation_preview: Label
var action_button: Button
var login_button: Button
var content_box: VBoxContainer

func _ready() -> void:
	_build_ui()
	_set_status("请输入中心服地址并登录。默认本机地址：" + DEFAULT_API)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#101522")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 660)
	center.add_child(panel)

	content_box = VBoxContainer.new()
	content_box.add_theme_constant_override("separation", 14)
	panel.add_child(content_box)

	var title := Label.new()
	title.text = "洪荒：诸天轮回"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	content_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "中心服登录 · 灵魂档案 · 转世角色 · 世界入口"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#aab6cc"))
	content_box.add_child(subtitle)

	api_input = _add_line_edit("中心服 API 地址", DEFAULT_API)
	username_input = _add_line_edit("账号", "")
	email_input = _add_line_edit("邮箱（注册时填写）", "")
	password_input = _add_line_edit("密码", "")
	password_input.secret = true

	login_button = Button.new()
	login_button.text = "登录"
	login_button.custom_minimum_size.y = 44
	login_button.pressed.connect(_on_login_pressed)
	content_box.add_child(login_button)
	var register_button := Button.new()
	register_button.text = "注册新账号并登录"
	register_button.pressed.connect(_on_register_pressed)
	content_box.add_child(register_button)

	content_box.add_child(HSeparator.new())

	var character_title := Label.new()
	character_title.text = "首次进入：创建角色"
	character_title.add_theme_font_size_override("font_size", 18)
	content_box.add_child(character_title)

	character_input = _add_line_edit("角色名（2–24 个字符）", "")
	var race_label := Label.new()
	race_label.text = "选择种族与修炼道路"
	content_box.add_child(race_label)
	race_select = OptionButton.new()
	race_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_select.item_selected.connect(_on_race_selected)
	content_box.add_child(race_select)
	cultivation_preview = Label.new()
	cultivation_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cultivation_preview.add_theme_color_override("font_color", Color("#aab6cc"))
	content_box.add_child(cultivation_preview)
	world_select = OptionButton.new()
	world_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(world_select)

	action_button = Button.new()
	action_button.text = "创建角色并进入世界"
	action_button.disabled = true
	action_button.custom_minimum_size.y = 44
	action_button.pressed.connect(_on_create_character_pressed)
	content_box.add_child(action_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 110
	content_box.add_child(status_label)

	http = HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_http_completed)

func _add_line_edit(placeholder: String, value: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(field)
	return field

func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
	print("[HongHuangClient] ", message)

func _enqueue(method: int, path: String, body: Dictionary = {}, authenticated := true, context := "") -> void:
	request_queue.append({
		"method": method,
		"path": path,
		"body": body,
		"authenticated": authenticated,
		"context": context
	})
	_process_queue()

func _process_queue() -> void:
	if request_busy or request_queue.is_empty():
		return
	request_busy = true
	var item: Dictionary = request_queue.pop_front()
	var headers := PackedStringArray(["Content-Type: application/json"])
	if item.authenticated and not access_token.is_empty():
		headers.append("Authorization: Bearer " + access_token)
	var body_text := JSON.stringify(item.body) if not item.body.is_empty() else ""
	var error := http.request(api_base + item.path, headers, item.method, body_text)
	if error != OK:
		request_busy = false
		_set_status("无法发起请求，错误码：" + str(error))
		_process_queue()
		return
	http.set_meta("request_context", item.context)

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	request_busy = false
	var context := str(http.get_meta("request_context", ""))
	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	var data: Dictionary = parsed if parsed is Dictionary else {}

	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("网络请求失败，请检查中心服地址和服务状态。")
		_process_queue()
		return

	if response_code == 404 and context == "soul_check":
		_enqueue(HTTPClient.METHOD_POST, "/api/v1/souls", {
			"name": username_input.text.strip_edges(),
			"origin": "冥界·酆都"
		}, true, "soul_create")
		_process_queue()
		return

	if response_code == 404 and context == "character_check":
		current_character = {}
		action_button.disabled = false
		action_button.text = "创建角色并进入世界"
		_set_status("灵魂档案已存在，但尚无转世肉身。请选择出生世界并填写角色名。")
		_process_queue()
		return

	if response_code < 200 or response_code >= 300:
		_set_status("请求失败 HTTP " + str(response_code) + "：" + body_text)
		_process_queue()
		return

	match context:
		"login", "register":
			access_token = str(data.get("access_token", ""))
			if access_token.is_empty():
				_set_status("认证响应缺少 access_token。")
			else:
				_set_status("账号认证成功，正在读取灵魂档案……")
				_enqueue(HTTPClient.METHOD_GET, "/api/v1/souls/current", {}, true, "soul_check")
		"soul_check":
			_set_status("灵魂档案已存在，正在读取世界列表……")
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/worlds", {}, false, "worlds")
		"soul_create":
			_set_status("灵魂档案创建成功，正在读取世界列表……")
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/worlds", {}, false, "worlds")
		"worlds":
			worlds = data.get("items", [])
			_populate_worlds()
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/cultivation/systems", {}, false, "cultivation_catalog")
		"cultivation_catalog":
			cultivation_races = data.get("races", [])
			_populate_cultivation_races()
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current", {}, true, "character_check")
		"character_check":
			current_character = data
			character_input.text = str(data.get("name", ""))
			action_button.disabled = false
			action_button.text = "进入世界"
			_set_status("角色已存在：" + character_input.text + "。可以进入世界。")
		"character_create":
			current_character = data
			_set_status("角色创建成功，正在申请世界入口……")
			_enqueue(HTTPClient.METHOD_POST, "/api/v1/worlds/enter", {}, true, "enter")
		"enter":
			entry_data = data
			_start_world_connection(
				str(data.get("host", "")),
				int(data.get("udp_port", 0)),
				str(data.get("ticket", ""))
			)
	_process_queue()

func _on_login_pressed() -> void:
	api_base = api_input.text.strip_edges().trim_suffix("/")
	if not api_base.begins_with("http://") and not api_base.begins_with("https://"):
		_set_status("中心服地址必须以 http:// 或 https:// 开头。")
		return
	if username_input.text.strip_edges().is_empty() or password_input.text.is_empty():
		_set_status("请输入账号和密码。")
		return
	if request_busy:
		return
	access_token = ""
	current_character = {}
	worlds.clear()
	_set_status("正在登录中心服……")
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/auth/login", {
		"username": username_input.text.strip_edges(),
		"password": password_input.text
	}, false, "login")

func _populate_worlds() -> void:
	world_select.clear()
	for world in worlds:
		if world is Dictionary:
			world_select.add_item(str(world.get("name", world.get("id", "未知世界"))))
			world_select.set_item_metadata(world_select.item_count - 1, str(world.get("id", "")))
	if world_select.item_count > 0:
		world_select.select(0)

func _populate_cultivation_races() -> void:
	race_select.clear()
	for race in cultivation_races:
		if race is Dictionary:
			race_select.add_item(str(race.get("race_name", race.get("race_id", "未知种族"))))
			race_select.set_item_metadata(race_select.item_count - 1, str(race.get("race_id", "")))
	if race_select.item_count > 0:
		var default_index := 0
		for index in range(race_select.item_count):
			if str(race_select.get_item_metadata(index)) == "human":
				default_index = index
				break
		race_select.select(default_index)
		_on_race_selected(default_index)
	else:
		cultivation_preview.text = "无法读取种族修炼体系目录，请检查中心服数据库迁移。"

func _on_race_selected(index: int) -> void:
	if index < 0 or index >= race_select.item_count:
		return
	var selected_race_id := str(race_select.get_item_metadata(index))
	for race in cultivation_races:
		if race is Dictionary and str(race.get("race_id", "")) == selected_race_id:
			var realm_names: Array[String] = []
			for realm in race.get("realms", []):
				if realm is Dictionary:
					realm_names.append(str(realm.get("name", "")))
			cultivation_preview.text = str(race.get("system_name", "")) + "\n修炼境界：" + " → ".join(realm_names) + "\n实力层级仅供跨种族比较，不代表战斗力完全相等。"
			return

func _on_create_character_pressed() -> void:
	if access_token.is_empty():
		_set_status("请先登录。")
		return
	if not current_character.is_empty():
		_enqueue(HTTPClient.METHOD_POST, "/api/v1/worlds/enter", {}, true, "enter")
		return
	var name := character_input.text.strip_edges()
	if name.length() < 2 or name.length() > 24:
		_set_status("角色名长度必须为 2–24 个字符。")
		return
	if world_select.item_count == 0:
		_set_status("当前没有可选世界。")
		return
	if race_select.item_count == 0:
		_set_status("没有可用的种族修炼体系，请检查中心服数据库迁移。")
		return
	var world_id := str(world_select.get_item_metadata(world_select.selected))
	var race_id := str(race_select.get_item_metadata(race_select.selected))
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/characters/first-life", {
		"name": name,
		"world_id": world_id,
		"race_id": race_id
	}, true, "character_create")

func _start_world_connection(host: String, port: int, ticket: String) -> void:
	if host.is_empty() or port < 1 or ticket.is_empty():
		_set_status("中心服返回的世界入口信息不完整。")
		return
	if world_network != null and is_instance_valid(world_network):
		world_network.close()
		world_network.queue_free()
	world_network = HHWorldNetwork.new()
	add_child(world_network)
	world_network.welcomed.connect(_on_world_welcomed)
	world_network.rejected.connect(func(reason: String): _set_status("进入世界失败：" + reason))
	world_network.connection_error.connect(func(message: String): _set_status(message))
	world_network.disconnected.connect(func(): _set_status("与世界服务器的连接已断开。"))
	_set_status("票据已签发，正在连接世界服务器 " + host + ":" + str(port) + "……")
	var error := world_network.connect_with_ticket(host, port, ticket)
	if error != OK:
		_set_status("世界网络连接初始化失败，错误码：" + str(error))

func _on_world_welcomed(snapshot: Dictionary) -> void:
	_set_status("世界服务器验证成功，正在进入青云人界……")
	HHSession.world_snapshot = snapshot
	if world_network != null and is_instance_valid(world_network):
		remove_child(world_network)
		HHSession.add_child(world_network)
		HHSession.world_network = world_network
	var error := get_tree().change_scene_to_file("res://scenes/World.tscn")
	if error != OK:
		_set_status("游戏场景加载失败，错误码：" + str(error))
		push_error("Failed to load Qingyun world scene: " + str(error))

func _on_register_pressed() -> void:
	api_base = api_input.text.strip_edges().trim_suffix("/")
	if not api_base.begins_with("http://") and not api_base.begins_with("https://"):
		_set_status("中心服地址必须以 http:// 或 https:// 开头。")
		return
	if username_input.text.strip_edges().is_empty() or email_input.text.strip_edges().is_empty() or password_input.text.is_empty():
		_set_status("注册需要填写账号、邮箱和密码。")
		return
	if request_busy:
		return
	access_token = ""
	current_character = {}
	worlds.clear()
	_set_status("正在注册账号……")
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/auth/register", {
		"username": username_input.text.strip_edges(),
		"email": email_input.text.strip_edges(),
		"password": password_input.text
	}, false, "register")
