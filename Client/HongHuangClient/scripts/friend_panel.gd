extends PanelContainer

signal open_private_chat(character_id: String, character_name: String)

var status_label: Label
var search_input: LineEdit
var results_list: VBoxContainer
var requests_list: VBoxContainer
var friends_list: VBoxContainer
var allow_requests_toggle: CheckButton
var refresh_timer: Timer

func _ready() -> void:
	custom_minimum_size = Vector2(360.0, 460.0)
	size = custom_minimum_size
	_build_ui()
	refresh_timer = Timer.new()
	refresh_timer.wait_time = 30.0
	refresh_timer.timeout.connect(_refresh_presence)
	add_child(refresh_timer)
	visible = false

func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.085, 0.97)
	style.border_color = Color("#526783")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "好友与私聊"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_close_panel)
	header.add_child(close_button)

	allow_requests_toggle = CheckButton.new()
	allow_requests_toggle.text = "允许陌生人发送好友申请"
	allow_requests_toggle.toggled.connect(_on_allow_requests_toggled)
	root.add_child(allow_requests_toggle)

	var search_row := HBoxContainer.new()
	root.add_child(search_row)
	search_input = LineEdit.new()
	search_input.placeholder_text = "输入角色名搜索（至少 2 个字）"
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_submitted.connect(func(_value): _search())
	search_row.add_child(search_input)
	var search_button := Button.new()
	search_button.text = "搜索"
	search_button.pressed.connect(_search)
	search_row.add_child(search_button)

	status_label = Label.new()
	status_label.text = "正在读取好友信息……"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	_add_section(content, "好友申请")
	requests_list = VBoxContainer.new()
	content.add_child(requests_list)
	_add_section(content, "搜索结果")
	results_list = VBoxContainer.new()
	content.add_child(results_list)
	_add_section(content, "我的好友")
	friends_list = VBoxContainer.new()
	content.add_child(friends_list)

func _add_section(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("#9fc7ff"))
	parent.add_child(label)

func open_panel() -> void:
	visible = true
	_refresh()
	refresh_timer.start()

func _close_panel() -> void:
	visible = false
	refresh_timer.stop()

func _refresh_presence() -> void:
	if visible:
		_api_request(HTTPClient.METHOD_GET, "/api/v1/chat/friends", "", "friends")
		_api_request(HTTPClient.METHOD_GET, "/api/v1/chat/friends/requests", "", "requests")

func _refresh() -> void:
	_api_request(HTTPClient.METHOD_GET, "/api/v1/chat/friends", "", "friends")
	_api_request(HTTPClient.METHOD_GET, "/api/v1/chat/friends/requests", "", "requests")
	_api_request(HTTPClient.METHOD_GET, "/api/v1/chat/preferences/friends", "", "preference")

func _search() -> void:
	var query := search_input.text.strip_edges()
	if query.length() < 2:
		status_label.text = "请输入至少 2 个字符。"
		return
	_api_request(HTTPClient.METHOD_GET, "/api/v1/chat/friends/search?q=" + query.uri_encode(), "", "search")

func _api_request(method: int, path: String, body: String, context: String) -> void:
	if HHSession.access_token.is_empty():
		status_label.text = "登录状态已失效，请重新登录。"
		return
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.set_meta("social_context", context)
	request.request_completed.connect(_on_request_completed.bind(request))
	add_child(request)
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	if not body.is_empty():
		headers.append("Content-Type: application/json")
	var url := HHSession.get_chat_api_base().trim_suffix("/") + path
	var error := request.request(url, headers, method, body)
	if error != OK:
		request.queue_free()
		status_label.text = "请求无法发送：" + str(error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	var context := str(request.get_meta("social_context", ""))
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		status_label.text = "网络请求失败，请检查聊天服务连接。"
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var reason := body.get_string_from_utf8().strip_edges()
		status_label.text = reason if not reason.is_empty() else "操作失败（HTTP " + str(response_code) + "）"
		return
	if not (parsed is Dictionary):
		status_label.text = "服务器返回格式不正确。"
		return
	match context:
		"friends":
			_render_friends(parsed.get("items", []))
		"requests":
			_render_requests(parsed.get("items", []))
		"search":
			_render_search(parsed.get("items", []))
		"preference":
			allow_requests_toggle.set_pressed_no_signal(bool(parsed.get("allow_friend_requests", true)))
		"create_request":
			status_label.text = "好友申请已发送。"
			_refresh()
		"accept_request", "reject_request", "remove_friend":
			status_label.text = "好友信息已更新。"
			_refresh()
		"save_preference":
			status_label.text = "陌生人好友申请设置已保存。"

func _render_friends(items: Array) -> void:
	_clear(friends_list)
	for value in items:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var row := HBoxContainer.new()
		friends_list.add_child(row)
		var label := Label.new()
		var state := "游戏中" if bool(item.get("in_game", false)) else ("聊天在线" if bool(item.get("chat_online", false)) else "离线")
		label.text = str(item.get("name", "未知角色")) + " · " + state
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var chat_button := Button.new()
		chat_button.text = "私聊"
		chat_button.pressed.connect(_open_friend_from_row.bind(str(item.get("character_id", "")), str(item.get("name", "好友"))))
		row.add_child(chat_button)
		var remove_button := Button.new()
		remove_button.text = "删除"
		remove_button.pressed.connect(_remove_friend.bind(str(item.get("character_id", ""))))
		row.add_child(remove_button)
	if items.is_empty():
		_add_empty(friends_list, "还没有好友，搜索角色名添加吧。")

func _render_requests(items: Array) -> void:
	_clear(requests_list)
	for value in items:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var row := VBoxContainer.new()
		requests_list.add_child(row)
		var label := Label.new()
		label.text = str(item.get("name", "未知角色")) + "： " + str(item.get("message", "申请成为好友"))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var actions := HBoxContainer.new()
		row.add_child(actions)
		var accept := Button.new()
		accept.text = "同意"
		accept.pressed.connect(_respond_to_request.bind(str(item.get("id", "")), "accept"))
		actions.add_child(accept)
		var reject := Button.new()
		reject.text = "拒绝"
		reject.pressed.connect(_respond_to_request.bind(str(item.get("id", "")), "reject"))
		actions.add_child(reject)
	if items.is_empty():
		_add_empty(requests_list, "暂无待处理申请。")

func _render_search(items: Array) -> void:
	_clear(results_list)
	for value in items:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var row := HBoxContainer.new()
		results_list.add_child(row)
		var label := Label.new()
		label.text = str(item.get("name", "未知角色")) + " · " + str(item.get("world_id", ""))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var add_button := Button.new()
		var is_friend := bool(item.get("is_friend", false))
		var is_pending := bool(item.get("request_pending", false))
		add_button.text = "已是好友" if is_friend else ("已申请" if is_pending else "添加")
		add_button.disabled = is_friend or is_pending
		add_button.pressed.connect(_send_friend_request.bind(str(item.get("character_id", ""))))
		row.add_child(add_button)
	if items.is_empty():
		_add_empty(results_list, "没有找到符合条件的角色。")

func _on_allow_requests_toggled(allowed: bool) -> void:
	_api_request(HTTPClient.METHOD_PUT, "/api/v1/chat/preferences/friends", JSON.stringify({"allow_friend_requests": allowed}), "save_preference")

func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

func _add_empty(container: VBoxContainer, message: String) -> void:
	var label := Label.new()
	label.text = message
	label.modulate = Color(0.68, 0.73, 0.81)
	container.add_child(label)

func _open_friend_from_row(character_id: String, character_name: String) -> void:
	open_private_chat.emit(character_id, character_name)
	_close_panel()

func _remove_friend(character_id: String) -> void:
	_api_request(HTTPClient.METHOD_DELETE, "/api/v1/chat/friends/" + character_id, "", "remove_friend")

func _respond_to_request(request_id: String, decision: String) -> void:
	_api_request(HTTPClient.METHOD_POST, "/api/v1/chat/friends/requests/" + request_id + "/" + decision, "{}", decision + "_request")

func _send_friend_request(character_id: String) -> void:
	_api_request(HTTPClient.METHOD_POST, "/api/v1/chat/friends/requests", JSON.stringify({"character_id": character_id, "message": "希望与你成为好友"}), "create_request")
