extends Control

const DEFAULT_API := "http://127.0.0.1:8787"
const CLIENT_BUILD := "0.1.0"

var api_base := DEFAULT_API
var access_token := ""
var worlds: Array = []
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
	panel.custom_minimum_size = Vector2(520, 560)
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
	var world_id := str(world_select.get_item_metadata(world_select.selected))
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/characters/first-life", {
		"name": name,
		"world_id": world_id,
		"race_id": ""
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
	_set_status("世界服务器验证成功！\n角色：" + str(snapshot.get("name", "")) +
		"\n世界：" + str(snapshot.get("world_id", "")) +
		"\n角色 ID：" + str(snapshot.get("character_id", "")) +
		"\n初始位置：" + str(snapshot.get("position_x", 0.0)) + ", " +
		str(snapshot.get("position_y", 0.0)) + ", " + str(snapshot.get("position_z", 0.0)) +
		"\n\n网络握手已完成；游戏场景、移动同步和 AOI 尚在开发。")

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
