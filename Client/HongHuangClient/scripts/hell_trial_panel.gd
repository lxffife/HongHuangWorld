extends PanelContainer
## Server-authoritative eighteen-floor selection and ticket request UI.

signal entry_ticket_received(floor: int, host: String, port: int, ticket: String)
signal return_to_fengdu_requested

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const FLOOR_COUNT := 18

var _progress_http: HTTPRequest
var _entry_http: HTTPRequest
var _rows: VBoxContainer
var _status: Label
var _return_button: Button
var _refresh_button: Button
var _busy := false
var _current_floor := 0
var _highest_unlocked_floor := 0
var _floor_progress: Dictionary = {}
var _pending_floor := 0

func _ready() -> void:
	name = "HellTrialPanel"
	visible = false
	z_index = 120
	custom_minimum_size = Vector2(560.0, 520.0)
	_build_ui()
	_progress_http = HTTPRequest.new()
	_progress_http.timeout = 12.0
	add_child(_progress_http)
	_progress_http.request_completed.connect(_on_progress_request_completed)
	_entry_http = HTTPRequest.new()
	_entry_http.timeout = 12.0
	add_child(_entry_http)
	_entry_http.request_completed.connect(_on_entry_request_completed)


func _build_ui() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111722")
	style.border_color = Color("#8b6f4d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	add_theme_stylebox_override("panel", style)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "幽冥刑狱 · 十八层试炼"
	title.add_theme_color_override("font_color", Color("#e7c995"))
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_refresh_button = Button.new()
	_refresh_button.text = "刷新"
	_refresh_button.pressed.connect(refresh_progress)
	header.add_child(_refresh_button)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)

	var subtitle := Label.new()
	subtitle.text = "依次挑战十八层。每层需完成三项刑狱目标，并击败本层守将。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color("#b8c2ce"))
	layout.add_child(subtitle)

	_status = Label.new()
	_status.text = "正在读取阴司试炼名册……"
	_status.add_theme_color_override("font_color", Color("#d9b879"))
	layout.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	var footer := HBoxContainer.new()
	layout.add_child(footer)
	_return_button = Button.new()
	_return_button.text = "返回酆都"
	_return_button.visible = false
	_return_button.pressed.connect(func(): return_to_fengdu_requested.emit())
	footer.add_child(_return_button)
	var note := Label.new()
	note.text = "楼层权限由中心服校验，客户端不能跳层。"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_color_override("font_color", Color("#8492a4"))
	footer.add_child(note)


func set_current_floor(floor_number: int) -> void:
	_current_floor = clampi(floor_number, 0, FLOOR_COUNT)
	if is_instance_valid(_return_button):
		_return_button.visible = _current_floor > 0


func open_panel() -> void:
	visible = true
	refresh_progress()


func close_panel() -> void:
	visible = false


func refresh_progress() -> void:
	if _busy:
		return
	if HHSession.access_token.is_empty():
		_status.text = "登录凭证已失效，请重新登录。"
		return
	_refresh_button.disabled = true
	_status.text = "正在读取十八层试炼进度……"
	var headers := PackedStringArray(["Authorization: Bearer " + HHSession.access_token])
	var error := _progress_http.request(
		HHSession.api_base + "/api/v1/characters/current/hell-trials",
		headers,
		HTTPClient.METHOD_GET
	)
	if error != OK:
		_refresh_button.disabled = false
		_status.text = "无法请求试炼进度，错误码：" + str(error)


func _on_progress_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_refresh_button.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_status.text = "读取试炼进度失败（HTTP " + str(response_code) + "）：" + body.get_string_from_utf8()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_status.text = "中心服返回的试炼进度格式无效。"
		return
	var data: Dictionary = parsed
	_highest_unlocked_floor = int(data.get("highest_unlocked_floor", 1))
	_floor_progress.clear()
	for item in data.get("floors", []):
		if item is Dictionary:
			_floor_progress[int(item.get("floor", 0))] = item
	_render_floor_rows()
	var completed_count := 0
	for item in _floor_progress.values():
		if str(item.get("status", "")) == "completed":
			completed_count += 1
	_status.text = "已通关 %d / 18 层 · 当前最高开放第 %02d 层" % [completed_count, maxi(1, _highest_unlocked_floor)]


func _render_floor_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for floor_number in range(1, FLOOR_COUNT + 1):
		var metadata: Dictionary = WorldMapCatalog.get_hell_floor_data(floor_number)
		var progress: Dictionary = _floor_progress.get(floor_number, {})
		var state := str(progress.get("status", "locked"))
		var unlocked := state in ["unlocked", "completed"] or floor_number <= _highest_unlocked_floor
		var completed := state == "completed"
		var row := PanelContainer.new()
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color("#1a2431") if unlocked else Color("#151a22")
		row_style.border_color = Color("#8b6f4d") if completed else Color("#344252")
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(7)
		row_style.content_margin_left = 10.0
		row_style.content_margin_right = 10.0
		row_style.content_margin_top = 7.0
		row_style.content_margin_bottom = 7.0
		row.add_theme_stylebox_override("panel", row_style)
		_rows.add_child(row)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var number := Label.new()
		number.text = "%02d" % floor_number
		number.custom_minimum_size.x = 30.0
		number.add_theme_color_override("font_color", Color("#d9b879") if unlocked else Color("#687483"))
		line.add_child(number)

		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(details)
		var name_label := Label.new()
		name_label.text = str(metadata.get("name", "第 %02d 层" % floor_number))
		name_label.add_theme_color_override("font_color", Color("#f0e5d2") if unlocked else Color("#84909e"))
		details.add_child(name_label)
		var objective := str(metadata.get("objective", "完成本层试炼并击败守将"))
		var guardian := str(metadata.get("guardian", "本层守将"))
		var subline := Label.new()
		subline.text = "目标：" + objective + "  ·  守将：" + guardian
		subline.add_theme_color_override("font_color", Color("#a9b5c2"))
		subline.add_theme_font_size_override("font_size", 11)
		subline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(subline)

		var action := Button.new()
		var entry_count := int(progress.get("entry_count", 0))
		if completed:
			action.text = "已通关 · 重返"
		elif unlocked:
			action.text = "进入试炼" + (" · %d 次" % entry_count if entry_count > 0 else "")
		else:
			action.text = "尚未解锁"
		action.disabled = not unlocked or _busy
		action.pressed.connect(_request_enter.bind(floor_number))
		line.add_child(action)


func _request_enter(floor_number: int) -> void:
	if _busy or HHSession.access_token.is_empty():
		return
	if floor_number < 1 or floor_number > FLOOR_COUNT or floor_number > _highest_unlocked_floor:
		_status.text = "该层尚未解锁。"
		return
	_busy = true
	_pending_floor = floor_number
	_set_floor_buttons_disabled(true)
	_status.text = "正在申请第 %02d 层专属入口……" % floor_number
	var headers := PackedStringArray([
		"Authorization: Bearer " + HHSession.access_token,
		"Content-Type: application/json"
	])
	var error := _entry_http.request(
		HHSession.api_base + "/api/v1/worlds/hell-trials/" + str(floor_number) + "/enter",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	if error != OK:
		_busy = false
		_set_floor_buttons_disabled(false)
		_status.text = "申请楼层入口失败，错误码：" + str(error)


func _set_floor_buttons_disabled(disabled: bool) -> void:
	for row in _rows.get_children():
		for child in row.get_children():
			if child is HBoxContainer:
				for item in child.get_children():
					if item is Button:
						item.disabled = disabled or item.text == "尚未解锁"


func _on_entry_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	_set_floor_buttons_disabled(false)
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_status.text = "暂时无法进入该层（HTTP " + str(response_code) + "）：" + body.get_string_from_utf8()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_status.text = "中心服返回的楼层入口信息无效。"
		return
	var data: Dictionary = parsed
	var host := str(data.get("host", ""))
	var port := int(data.get("udp_port", 0))
	var ticket := str(data.get("ticket", ""))
	if host.is_empty() or port < 1 or ticket.is_empty():
		_status.text = "楼层入口信息不完整，请刷新后重试。"
		return
	var floor_number := _requested_floor_from_response()
	_status.text = "入口已签发，正在连接专属刑狱……"
	entry_ticket_received.emit(floor_number, host, port, ticket)


func _requested_floor_from_response() -> int:
	return _pending_floor
