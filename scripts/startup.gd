extends Control

const DEFAULT_API := "http://192.168.124.13:8787"
const CLIENT_CONFIG_PATH := "user://honghuang_client.cfg"
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
var character_title_label: Label
var race_label_control: Label
var world_label_control: Label
var auth_controls: Array[Control] = []
var account_label: Label
var right_info_label: Label
var reincarnation_name_input: LineEdit
var reincarnation_race_select: OptionButton
var reincarnation_status_label: Label
var reincarnation_check_button: Button
var reincarnation_submit_button: Button
var reincarnation_confirm: ConfirmationDialog
var reincarnation_eligible := false
var life_history_box: VBoxContainer
var life_history_status: Label
var life_history_title: Label
var life_history_refresh_button: Button
var soul_memory_title: Label
var soul_memory_status: Label
var soul_memory_box: VBoxContainer
var soul_memory_refresh_button: Button
var soul_fate_title: Label
var soul_fate_status: Label
var soul_fate_box: VBoxContainer
var soul_fate_refresh_button: Button

func _ready() -> void:
	_build_ui()
	_load_client_config()
	_build_reincarnation_ui()
	if not HHSession.access_token.is_empty():
		api_base = HHSession.api_base
		access_token = HHSession.access_token
		api_input.text = api_base
		for control in auth_controls:
			control.hide()
		account_label.text = "已登录账号：" + username_input.text.strip_edges()
		account_label.show()
		_set_status("已恢复登录会话，正在重新读取灵魂与角色数据……")
		_enqueue(HTTPClient.METHOD_GET, "/api/v1/souls/current", {}, true, "soul_check")
	else:
		_set_status("已读取本机登录配置，请登录中心服。")

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#101522")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 600)
	center.add_child(panel)

	var main_layout := HBoxContainer.new()
	main_layout.add_theme_constant_override("separation", 18)
	panel.add_child(main_layout)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(430, 0)
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_layout.add_child(left_scroll)

	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 12)
	left_scroll.add_child(content_box)

	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_layout.add_child(right_panel)
	var right_content := VBoxContainer.new()
	right_content.add_theme_constant_override("separation", 16)
	right_panel.add_child(right_content)
	var right_title := Label.new()
	right_title.text = "轮回之门"
	right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_title.add_theme_font_size_override("font_size", 26)
	right_content.add_child(right_title)
	right_info_label = Label.new()
	right_info_label.text = "登录中心服后，这里将显示灵魂档案、角色信息与世界入口。"
	right_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_content.add_child(right_info_label)
	account_label = Label.new()
	account_label.hide()
	content_box.add_child(account_label)

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
	auth_controls.append_array([api_input, username_input, email_input, password_input])

	login_button = Button.new()
	login_button.text = "登录"
	login_button.custom_minimum_size.y = 44
	login_button.pressed.connect(_on_login_pressed)
	content_box.add_child(login_button)
	auth_controls.append(login_button)
	var register_button := Button.new()
	register_button.text = "注册新账号并登录"
	register_button.pressed.connect(_on_register_pressed)
	content_box.add_child(register_button)
	auth_controls.append(register_button)
	var auth_separator := HSeparator.new()
	content_box.add_child(auth_separator)
	auth_controls.append(auth_separator)

	var character_title := Label.new()
	character_title.text = "首次进入：创建角色"
	character_title.add_theme_font_size_override("font_size", 18)
	content_box.add_child(character_title)
	character_title_label = character_title
	character_title_label.hide()

	character_input = _add_line_edit("角色名（2–24 个字符）", "")
	character_input.hide()
	var race_label := Label.new()
	race_label.text = "选择种族与修炼道路"
	content_box.add_child(race_label)
	race_label_control = race_label
	race_label_control.hide()
	race_select = OptionButton.new()
	race_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_select.item_selected.connect(_on_race_selected)
	content_box.add_child(race_select)
	race_select.hide()
	cultivation_preview = Label.new()
	cultivation_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cultivation_preview.add_theme_color_override("font_color", Color("#aab6cc"))
	content_box.add_child(cultivation_preview)
	cultivation_preview.hide()
	var world_label := Label.new()
	world_label.text = "出生世界（当前联调阶段仅开放：青云人界）"
	content_box.add_child(world_label)
	world_label_control = world_label
	world_label_control.hide()
	world_select = OptionButton.new()
	world_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(world_select)
	world_select.hide()

	action_button = Button.new()
	action_button.text = "创建角色并进入世界"
	action_button.disabled = true
	action_button.custom_minimum_size.y = 44
	action_button.pressed.connect(_on_create_character_pressed)
	content_box.add_child(action_button)
	action_button.hide()

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 110
	content_box.add_child(status_label)

	http = HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_http_completed)

func _build_reincarnation_ui() -> void:
	var separator := HSeparator.new()
	content_box.add_child(separator)
	var title := Label.new()
	title.text = "主动轮回 · 创建下一世肉身"
	title.add_theme_font_size_override("font_size", 18)
	content_box.add_child(title)
	reincarnation_status_label = Label.new()
	reincarnation_status_label.text = "完成冥界试炼并达到聚灵境后，可在轮回殿申请投胎。"
	reincarnation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_box.add_child(reincarnation_status_label)
	reincarnation_name_input = LineEdit.new()
	reincarnation_name_input.placeholder_text = "新肉身名称（2–24 个字符）"
	reincarnation_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(reincarnation_name_input)
	reincarnation_race_select = OptionButton.new()
	reincarnation_race_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(reincarnation_race_select)
	reincarnation_check_button = Button.new()
	reincarnation_check_button.text = "查询投胎资格"
	reincarnation_check_button.pressed.connect(_check_reincarnation_eligibility)
	content_box.add_child(reincarnation_check_button)
	reincarnation_submit_button = Button.new()
	reincarnation_submit_button.text = "确认创建新肉身"
	reincarnation_submit_button.disabled = true
	reincarnation_submit_button.pressed.connect(func(): reincarnation_confirm.popup_centered())
	content_box.add_child(reincarnation_submit_button)
	reincarnation_confirm = ConfirmationDialog.new()
	reincarnation_confirm.title = "确认主动轮回"
	reincarnation_confirm.dialog_text = "此操作不可撤销：当前肉身将归档为前世，并为同一灵魂创建新的肉身。灵魂经验、功德、业力会保留。是否继续？"
	reincarnation_confirm.confirmed.connect(_submit_reincarnation)
	add_child(reincarnation_confirm)
	for control in [title, reincarnation_status_label, reincarnation_name_input, reincarnation_race_select, reincarnation_check_button, reincarnation_submit_button]:
		control.hide()
	life_history_title = Label.new()
	life_history_title.text = "灵魂历世档案"
	life_history_title.add_theme_font_size_override("font_size", 18)
	content_box.add_child(life_history_title)
	life_history_status = Label.new()
	life_history_status.text = "登录后读取同一灵魂的历世记录。"
	life_history_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_box.add_child(life_history_status)
	life_history_box = VBoxContainer.new()
	life_history_box.add_theme_constant_override("separation", 8)
	content_box.add_child(life_history_box)
	life_history_refresh_button = Button.new()
	life_history_refresh_button.text = "刷新历世档案"
	life_history_refresh_button.pressed.connect(_request_life_history)
	content_box.add_child(life_history_refresh_button)
	for control in [life_history_title, life_history_status, life_history_box, life_history_refresh_button]:
		control.hide()
	soul_memory_title = Label.new()
	soul_memory_title.text = "前世记忆 · 灵魂深处"
	soul_memory_title.add_theme_font_size_override("font_size", 18)
	content_box.add_child(soul_memory_title)
	soul_memory_status = Label.new()
	soul_memory_status.text = "部分前世记忆需要更高的灵魂境界才能稳定显现。"
	soul_memory_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_box.add_child(soul_memory_status)
	soul_memory_box = VBoxContainer.new()
	soul_memory_box.add_theme_constant_override("separation", 8)
	content_box.add_child(soul_memory_box)
	soul_memory_refresh_button = Button.new()
	soul_memory_refresh_button.text = "感知前世记忆"
	soul_memory_refresh_button.pressed.connect(_request_soul_memories)
	content_box.add_child(soul_memory_refresh_button)
	for control in [soul_memory_title, soul_memory_status, soul_memory_box, soul_memory_refresh_button]:
		control.hide()
	soul_fate_title = Label.new()
	soul_fate_title.text = "因果簿 · 功德与业力"
	soul_fate_title.add_theme_font_size_override("font_size", 18)
	content_box.add_child(soul_fate_title)
	soul_fate_status = Label.new()
	soul_fate_status.text = "功德与业力属于灵魂，轮回后不会清零。"
	soul_fate_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_box.add_child(soul_fate_status)
	soul_fate_box = VBoxContainer.new()
	soul_fate_box.add_theme_constant_override("separation", 4)
	content_box.add_child(soul_fate_box)
	soul_fate_refresh_button = Button.new()
	soul_fate_refresh_button.text = "查看因果记录"
	soul_fate_refresh_button.pressed.connect(_request_soul_fate)
	content_box.add_child(soul_fate_refresh_button)
	for control in [soul_fate_title, soul_fate_status, soul_fate_box, soul_fate_refresh_button]:
		control.hide()

func _request_soul_fate() -> void:
	if access_token.is_empty():
		soul_fate_status.text = "请先登录后查看因果簿。"
		return
	soul_fate_status.text = "正在读取功德、业力与因果记录……"
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/souls/current/fate", {}, true, "soul_fate")

func _render_soul_fate(data: Dictionary) -> void:
	for child in soul_fate_box.get_children():
		child.queue_free()
	soul_fate_status.text = "累计功德：" + str(data.get("merit", 0)) + "    累计业力：" + str(data.get("karma", 0))
	var events: Variant = data.get("recent_events", [])
	if not (events is Array) or events.is_empty():
		var empty := Label.new()
		empty.text = "尚无已记录的因果事件。"
		soul_fate_box.add_child(empty)
		return
	for event_variant in events:
		if not (event_variant is Dictionary):
			continue
		var event: Dictionary = event_variant
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var merit_delta := int(event.get("merit_delta", 0))
		var karma_delta := int(event.get("karma_delta", 0))
		var change_text := ""
		if merit_delta > 0:
			change_text += "功德 +" + str(merit_delta)
		elif merit_delta < 0:
			change_text += "功德 " + str(merit_delta)
		if karma_delta > 0:
			if not change_text.is_empty():
				change_text += " · "
			change_text += "业力 +" + str(karma_delta)
		elif karma_delta < 0:
			if not change_text.is_empty():
				change_text += " · "
			change_text += "业力 " + str(karma_delta)
		row.text = str(event.get("created_at", "")) + "  " + str(event.get("source", "未知因果")) + "  " + change_text
		soul_fate_box.add_child(row)

func _request_soul_memories() -> void:
	if access_token.is_empty():
		soul_memory_status.text = "请先登录后感知前世记忆。"
		return
	soul_memory_status.text = "正在感知灵魂深处的记忆……"
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/souls/current/memories", {}, true, "soul_memories")

func _render_soul_memories(items: Array) -> void:
	for child in soul_memory_box.get_children():
		child.queue_free()
	if items.is_empty():
		soul_memory_status.text = "尚无可供回忆的前世片段。每次主动轮回后，灵魂都会留下记忆印记。"
		return
	var unlocked_count := 0
	for item_variant in items:
		if item_variant is Dictionary and bool(item_variant.get("unlocked", false)):
			unlocked_count += 1
	soul_memory_status.text = "记忆印记 " + str(items.size()) + " 条 · 已显现 " + str(unlocked_count) + " 条。灵魂境界越高，可稳定回忆的前世越多。"
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
		var card := PanelContainer.new()
		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", 4)
		card.add_child(layout)
		var heading := Label.new()
		heading.text = str(item.get("title", "无名记忆"))
		heading.add_theme_font_size_override("font_size", 16)
		layout.add_child(heading)
		var body := Label.new()
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if bool(item.get("unlocked", false)):
			body.text = str(item.get("summary", "记忆片段已显现。"))
			var details: Variant = item.get("details", {})
			if details is Dictionary:
				body.text += "\n种族：" + str(details.get("race_name", "未知")) + "    世界：" + str(details.get("world_name", "未知"))
				body.text += "\n境界：" + str(details.get("realm_name", "未知")) + " · " + str(details.get("realm_stage", 1)) + "阶    等级：" + str(details.get("level", 1))
				body.text += "\n修为：" + str(details.get("cultivation_value", 0)) + "    肉身经验：" + str(details.get("cultivation_experience", 0))
		else:
			body.text = "记忆尚未解封。需要灵魂达到 " + str(item.get("required_realm_name", "更高境界")) + "（境界序号 " + str(item.get("min_realm_order", 5)) + "）后，才能稳定读取。"
		layout.add_child(body)
		soul_memory_box.add_child(card)

func _request_life_history() -> void:
	if access_token.is_empty():
		life_history_status.text = "请先登录后查看历世档案。"
		return
	life_history_status.text = "正在读取灵魂历世记录……"
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/souls/current/lives", {}, true, "life_history")

func _render_life_history(items: Array) -> void:
	for child in life_history_box.get_children():
		child.queue_free()
	if items.is_empty():
		life_history_status.text = "当前灵魂尚无肉身记录。"
		return
	life_history_status.text = "共 " + str(items.size()) + " 世。历世肉身分别保存，灵魂身份持续延续。"
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var item: Dictionary = item_variant
		var card := PanelContainer.new()
		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", 4)
		card.add_child(layout)
		var heading := Label.new()
		var life_number := int(item.get("life_index", 0))
		heading.text = "第 " + str(life_number) + " 世 · " + str(item.get("name", "无名"))
		if bool(item.get("is_current", false)):
			heading.text += "  【当前肉身】"
		heading.add_theme_font_size_override("font_size", 16)
		layout.add_child(heading)
		var details := Label.new()
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.text = "种族：" + str(item.get("race_name", "未知")) + "    世界：" + str(item.get("world_name", item.get("world_id", "未知"))) + "\n境界：" + str(item.get("realm_name", "尚未记录")) + " · " + str(item.get("realm_stage", 1)) + "阶    等级：" + str(item.get("level", 1)) + "\n状态：" + str(item.get("status", "未知")) + "    初生：" + str(item.get("created_at", "未知"))
		layout.add_child(details)
		if not str(item.get("reincarnated_at", "")).is_empty():
			var transition := Label.new()
			transition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			transition.text = "转入此世的轮回时间：" + str(item.get("reincarnated_at", "")) + "\n前世出生世界：" + str(item.get("previous_world_id", "未知")) + " → 今世出生世界：" + str(item.get("next_world_id", "未知"))
			layout.add_child(transition)
		life_history_box.add_child(card)

func _check_reincarnation_eligibility() -> void:
	if access_token.is_empty() or current_character.is_empty():
		reincarnation_status_label.text = "请先登录并载入当前肉身。"
		return
	reincarnation_check_button.disabled = true
	reincarnation_status_label.text = "正在向中心服查询灵魂境界与冥界试炼……"
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/souls/current/reincarnation-eligibility", {}, true, "reincarnation_eligibility")

func _submit_reincarnation() -> void:
	if not reincarnation_eligible or request_busy:
		return
	var name := reincarnation_name_input.text.strip_edges()
	if name.length() < 2 or name.length() > 24:
		reincarnation_status_label.text = "新肉身名称长度必须为 2–24 个字符。"
		return
	if reincarnation_race_select.item_count == 0:
		reincarnation_status_label.text = "种族目录为空，暂时无法创建新肉身。"
		return
	var race_id := str(reincarnation_race_select.get_item_metadata(reincarnation_race_select.selected))
	reincarnation_submit_button.disabled = true
	reincarnation_check_button.disabled = true
	reincarnation_status_label.text = "正在由中心服事务创建新肉身……"
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/characters/current/reincarnate", {"name": name, "race_id": race_id}, true, "reincarnate")

func _load_client_config() -> void:
	var config := ConfigFile.new()
	var error := config.load(CLIENT_CONFIG_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("无法读取本机客户端配置，将使用默认值。")
	api_input.text = str(config.get_value("connection", "api_base", DEFAULT_API))
	username_input.text = str(config.get_value("login", "username", "test_player"))
	email_input.text = str(config.get_value("login", "email", ""))
	password_input.text = str(config.get_value("login", "password", ""))
	# Create the local config on first launch. The password remains blank until
	# the user successfully logs in and explicitly saves a working credential.
	if error == ERR_FILE_NOT_FOUND:
		config.set_value("connection", "api_base", DEFAULT_API)
		config.set_value("login", "username", "test_player")
		config.set_value("login", "email", "")
		config.set_value("login", "password", "")
		var save_error := config.save(CLIENT_CONFIG_PATH)
		if save_error != OK:
			push_warning("无法创建本机客户端配置文件。")

func _save_client_config() -> void:
	var config := ConfigFile.new()
	config.set_value("connection", "api_base", api_input.text.strip_edges().trim_suffix("/"))
	config.set_value("login", "username", username_input.text.strip_edges())
	config.set_value("login", "email", email_input.text.strip_edges())
	config.set_value("login", "password", password_input.text)
	var error := config.save(CLIENT_CONFIG_PATH)
	if error != OK:
		push_warning("登录成功，但无法保存本机登录配置。")

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
		if context == "register" and response_code == 400:
			_set_status("注册失败：账号必须为 3–32 位英文字母、数字或下划线；密码必须为 12–72 个字符。邮箱可以填写有效邮箱。")
		elif context == "soul_check" and response_code == 401:
			access_token = ""
			HHSession.access_token = ""
			for control in auth_controls:
				control.show()
			account_label.hide()
			_set_status("登录会话已过期，请重新登录后继续办理轮回。")
		elif context == "life_history":
			life_history_status.text = "历世档案读取失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "soul_memories":
			soul_memory_status.text = "前世记忆读取失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "soul_fate":
			soul_fate_status.text = "因果簿读取失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "reincarnation_eligibility":
			reincarnation_check_button.disabled = false
			reincarnation_eligible = false
			reincarnation_submit_button.disabled = true
			reincarnation_status_label.text = "资格查询失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "reincarnate":
			reincarnation_check_button.disabled = false
			reincarnation_submit_button.disabled = true
			reincarnation_status_label.text = "创建新肉身失败（HTTP " + str(response_code) + "）：" + body_text + "。请重新查询资格后再试。"
		else:
			_set_status("请求失败 HTTP " + str(response_code) + "：" + body_text)
		_process_queue()
		return

	match context:
		"login", "register":
			access_token = str(data.get("access_token", ""))
			if access_token.is_empty():
				_set_status("认证响应缺少 access_token。")
			else:
				_save_client_config()
				for control in auth_controls:
					control.hide()
				account_label.text = "已登录账号：" + username_input.text.strip_edges()
				account_label.show()
				right_info_label.text = "身份验证成功。正在读取灵魂档案与世界目录……"
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
			_show_character_setup()
			_populate_cultivation_races()
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current", {}, true, "character_check")
		"character_check":
			current_character = data
			race_select.disabled = true
			character_input.text = str(data.get("name", ""))
			action_button.disabled = false
			action_button.text = "进入世界"
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/status", {}, true, "character_status")
		"character_status":
			var progression: Dictionary = data.get("progression", {})
			var tier_text := str(progression.get("power_tier_name", "未知层级"))
			var realm_text := str(progression.get("system_name", "")) + " · " + str(progression.get("realm_name", "")) + str(progression.get("realm_stage_name", ""))
			_set_status("角色已存在：" + character_input.text + "\n修炼体系：" + realm_text + "\n跨族参考：" + tier_text + "。可以进入世界。")
			_show_reincarnation_controls()
		"life_history":
			_render_life_history(data.get("items", []))
		"soul_memories":
			_render_soul_memories(data.get("items", []))
		"soul_fate":
			_render_soul_fate(data)
		"reincarnation_eligibility":
			reincarnation_check_button.disabled = false
			reincarnation_eligible = bool(data.get("eligible", false))
			var reasons: Array = data.get("reasons", [])
			var realm_name := str(data.get("current_realm_name", "未知"))
			var required_name := str(data.get("required_realm_name", "聚灵境"))
			var trial_done := bool(data.get("trial_completed", false))
			if reincarnation_eligible:
				reincarnation_status_label.text = "投胎资格已满足。灵魂境界：" + realm_name + "；引魂试炼：已完成。选择新肉身名称与种族后确认即可。"
				reincarnation_submit_button.disabled = false
			else:
				reincarnation_status_label.text = "暂不具备投胎资格。当前境界：" + realm_name + "；要求：" + required_name + "；引魂试炼：" + ("已完成" if trial_done else "未完成") + "。\n待完成：" + ", ".join(PackedStringArray(reasons))
				reincarnation_submit_button.disabled = true
		"reincarnate":
			current_character = data
			reincarnation_eligible = false
			reincarnation_status_label.text = "新肉身创建成功，前世肉身已归档。正在申请冥界入口……"
			_enqueue(HTTPClient.METHOD_POST, "/api/v1/worlds/enter", {}, true, "enter")
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

func _show_reincarnation_controls() -> void:
	for control in [reincarnation_status_label, reincarnation_name_input, reincarnation_race_select, reincarnation_check_button, reincarnation_submit_button, life_history_title, life_history_status, life_history_box, life_history_refresh_button, soul_memory_title, soul_memory_status, soul_memory_box, soul_memory_refresh_button, soul_fate_title, soul_fate_status, soul_fate_box, soul_fate_refresh_button]:
		control.show()
	reincarnation_name_input.text = ""
	reincarnation_eligible = false
	reincarnation_submit_button.disabled = true
	reincarnation_check_button.disabled = false
	reincarnation_race_select.clear()
	for race in cultivation_races:
		if race is Dictionary:
			reincarnation_race_select.add_item(str(race.get("race_name", race.get("race_id", "未知种族"))))
			reincarnation_race_select.set_item_metadata(reincarnation_race_select.item_count - 1, str(race.get("race_id", "")))
	for index in range(reincarnation_race_select.item_count):
		if str(reincarnation_race_select.get_item_metadata(index)) == "human":
			reincarnation_race_select.select(index)
			break
	_request_life_history()
	_request_soul_memories()
	_request_soul_fate()

func _show_character_setup() -> void:
	right_info_label.text = "灵魂档案已载入。请在左侧完成角色名、种族修炼体系与出生世界的选择。"
	character_title_label.show()
	character_input.show()
	race_label_control.show()
	race_select.show()
	cultivation_preview.show()
	world_label_control.show()
	world_select.show()
	action_button.show()

func _populate_worlds() -> void:
	world_select.clear()
	for world in worlds:
		if not (world is Dictionary):
			continue
		var world_id := str(world.get("id", ""))
		# P0 currently deploys one authoritative instance; do not offer worlds
		# that have no matching live WorldServer yet.
		if world_id != "qingyun_human":
			continue
		world_select.add_item(str(world.get("name", world_id)))
		world_select.set_item_metadata(world_select.item_count - 1, world_id)
	if world_select.item_count > 0:
		world_select.select(0)
	else:
		_set_status("当前没有已部署的可进入世界服务器，请先启动青云人界 WorldServer 并确认心跳成功。")

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
			var realm_path := ""
			for realm in race.get("realms", []):
				if realm is Dictionary:
					if not realm_path.is_empty():
						realm_path += " → "
					realm_path += str(realm.get("name", ""))
			cultivation_preview.text = str(race.get("system_name", "")) + "\n修炼境界：" + realm_path + "\n实力层级仅供跨种族比较，不代表战斗力完全相等。"
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
	HHSession.api_base = api_base
	HHSession.access_token = access_token
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
	var username := username_input.text.strip_edges()
	var username_regex := RegEx.new()
	username_regex.compile("^[A-Za-z0-9_]{3,32}$")
	if username_regex.search(username) == null:
		_set_status("账号格式不正确：请输入 3–32 位英文字母、数字或下划线。")
		return
	if password_input.text.length() < 12 or password_input.text.length() > 72:
		_set_status("密码长度必须为 12–72 个字符。")
		return
	if not email_input.text.strip_edges().is_empty() and (not email_input.text.contains("@") or email_input.text.length() > 254):
		_set_status("邮箱格式不正确，或留空。")
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
