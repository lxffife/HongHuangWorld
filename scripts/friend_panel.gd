extends PanelContainer

signal open_private_chat(character_id: String, character_name: String)
signal panel_closed

var status_label: Label
var search_input: LineEdit
var results_list: VBoxContainer
var requests_list: VBoxContainer
var friends_list: VBoxContainer
var friend_items: Array = []
var friend_filter := "all"
var friend_filter_buttons: Array[Button] = []
var allow_requests_toggle: CheckButton
var refresh_timer: Timer

func _ready() -> void:
	custom_minimum_size = Vector2(520.0, 620.0)
	size = custom_minimum_size
	_build_ui()
	refresh_timer = Timer.new()
	refresh_timer.wait_time = 30.0
	refresh_timer.timeout.connect(_refresh_presence)
	add_child(refresh_timer)
	visible = false

func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b1420")
	style.border_color = Color("#a88956")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
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

	var subtitle := Label.new()
	subtitle.text = "在线状态 · 好友管理 · 私聊"
	subtitle.add_theme_color_override("font_color", Color("#91a7ba"))
	subtitle.add_theme_font_size_override("font_size", 11)
	root.add_child(subtitle)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	root.add_child(filter_row)
	friend_filter_buttons.clear()
	for filter_data in [["all", "全部"], ["game", "游戏中"], ["online", "在线"], ["offline", "离线"]]:
		var filter_button := Button.new()
		filter_button.text = str(filter_data[1])
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_button.pressed.connect(_set_friend_filter.bind(str(filter_data[0])))
		_style_filter_button(filter_button, str(filter_data[0]) == friend_filter)
		filter_row.add_child(filter_button)
		friend_filter_buttons.append(filter_button)

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
	panel_closed.emit()

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
	friend_items = items.duplicate(true)
	_render_friend_cards()

func _render_friend_cards() -> void:
	_clear(friends_list)
	var visible_count := 0
	for value in friend_items:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var in_game := bool(item.get("in_game", false))
		var online := in_game or bool(item.get("chat_online", false))
		if friend_filter == "game" and not in_game:
			continue
		if friend_filter == "online" and not online:
			continue
		if friend_filter == "offline" and online:
			continue
		visible_count += 1
		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color("#172635")
		card_style.border_color = Color("#31495c")
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(10)
		card_style.content_margin_left = 10
		card_style.content_margin_right = 10
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_style)
		friends_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var avatar := PanelContainer.new()
		avatar.custom_minimum_size = Vector2(42, 42)
		var avatar_style := StyleBoxFlat.new()
		avatar_style.bg_color = Color("#594b36") if in_game else Color("#294052")
		avatar_style.set_corner_radius_all(12)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		row.add_child(avatar)
		var avatar_label := Label.new()
		avatar_label.text = str(item.get("name", "友")).substr(0, 1)
		avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar_label.add_theme_color_override("font_color", Color("#f0d49a"))
		avatar.add_child(avatar_label)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		var name_label := Label.new()
		name_label.text = str(item.get("name", "未知角色"))
		name_label.add_theme_color_override("font_color", Color("#f0e6d5"))
		name_label.add_theme_font_size_override("font_size", 13)
		info.add_child(name_label)
		var state_label := Label.new()
		state_label.text = "● 游戏中" if in_game else ("● 聊天在线" if online else "● 离线")
		state_label.add_theme_color_override("font_color", Color("#72c99a") if online else Color("#788999"))
		state_label.add_theme_font_size_override("font_size", 10)
		info.add_child(state_label)
		var actions := VBoxContainer.new()
		actions.add_theme_constant_override("separation", 4)
		row.add_child(actions)
		var chat_button := Button.new()
		chat_button.text = "私聊"
		chat_button.custom_minimum_size = Vector2(62, 28)
		chat_button.pressed.connect(_open_friend_from_row.bind(str(item.get("character_id", "")), str(item.get("name", "好友"))))
		actions.add_child(chat_button)
		var remove_button := Button.new()
		remove_button.text = "移除"
		remove_button.custom_minimum_size = Vector2(62, 24)
		remove_button.pressed.connect(_remove_friend.bind(str(item.get("character_id", ""))))
		actions.add_child(remove_button)
	if visible_count == 0:
		_add_empty(friends_list, "这个分类暂时没有好友。")

func _set_friend_filter(next_filter: String) -> void:
	friend_filter = next_filter
	for index in range(friend_filter_buttons.size()):
		var filter_ids := ["all", "game", "online", "offline"]
		_style_filter_button(friend_filter_buttons[index], index < filter_ids.size() and filter_ids[index] == friend_filter)
	_render_friend_cards()

func _style_filter_button(button: Button, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#5b4a30") if active else Color("#182735")
	normal.border_color = Color("#c3a16a") if active else Color("#34495b")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color("#6c5837") if active else Color("#243b4d")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color("#f4e5c7") if active else Color("#aebdca"))

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
