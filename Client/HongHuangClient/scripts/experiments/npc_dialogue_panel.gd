extends CanvasLayer
## Reusable local dialogue surface for Fengdu NPCs and interaction points.

signal closed

var _panel: PanelContainer
var _name_label: Label
var _authority_label: Label
var _body_label: Label
var _options_row: HBoxContainer
var _is_open := false


func _ready() -> void:
	_build_ui()


func is_open() -> bool:
	return _is_open


func present(data: Dictionary) -> void:
	if _panel == null:
		return
	_name_label.text = str(data.get("name", "阴司来客"))
	_authority_label.text = str(data.get("authority", "酆都 · 阴司"))
	_body_label.text = str(data.get("description", "此处暂时没有更多信息。"))
	_rebuild_options(_get_options(data))
	_panel.visible = true
	_is_open = true


func close_dialogue() -> void:
	if not _is_open:
		return
	_is_open = false
	_panel.visible = false
	closed.emit()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "DialogueOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "DialogueCard"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -390.0
	_panel.offset_top = -286.0
	_panel.offset_right = 390.0
	_panel.offset_bottom = -22.0
	_panel.custom_minimum_size = Vector2(780.0, 264.0)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 2)
	header.add_child(title_column)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color("#f0dfc2"))
	title_column.add_child(_name_label)

	_authority_label = Label.new()
	_authority_label.add_theme_font_size_override("font_size", 12)
	_authority_label.add_theme_color_override("font_color", Color("#b5a58e"))
	title_column.add_child(_authority_label)

	var close_button := Button.new()
	close_button.text = "关闭  ×"
	close_button.custom_minimum_size = Vector2(88.0, 38.0)
	close_button.pressed.connect(close_dialogue)
	header.add_child(close_button)

	column.add_child(HSeparator.new())

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 16)
	content_row.custom_minimum_size.y = 82.0
	column.add_child(content_row)

	var emblem := PanelContainer.new()
	emblem.custom_minimum_size = Vector2(82.0, 76.0)
	emblem.add_theme_stylebox_override("panel", _emblem_style())
	content_row.add_child(emblem)

	var emblem_label := Label.new()
	emblem_label.text = "阴司\n司录"
	emblem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem_label.add_theme_font_size_override("font_size", 16)
	emblem_label.add_theme_color_override("font_color", Color("#d6bd91"))
	emblem.add_child(emblem_label)

	_body_label = Label.new()
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.add_theme_color_override("font_color", Color("#ddd5c8"))
	content_row.add_child(_body_label)

	_options_row = HBoxContainer.new()
	_options_row.add_theme_constant_override("separation", 10)
	column.add_child(_options_row)


func _get_options(data: Dictionary) -> Array[Dictionary]:
	var kind := str(data.get("interaction_type", ""))
	match kind:
		"capture_and_escort":
			return [
				{"label": "查看拘魂文牒", "response": "拘魂文牒需记录亡魂姓名、阳寿终点与引魂凭据。未核实生死簿前，不可擅自拘魂。"},
				{"label": "了解押魂流程", "response": "押魂先验明魂籍，再由由引魂使押送至鬼籍司复核。此处仅展示流程，尚未生成真实差事。"},
				{"label": "暂不接差", "response": "范无救合上拘魂簿：时辰未到，不必急于领差。"}
			]
		"new_soul_guidance":
			return [
				{"label": "新魂登记须知", "response": "新魂入城后先核验来历，再登记魂籍、查验执念，最后由引魂使安排暂居或后续审理。"},
				{"label": "了解轮回去向", "response": "轮回去向需结合功过、因果与本人意愿审理，不能由接引使单方面决定。"},
				{"label": "暂不登记", "response": "谢必安温声说道：先熟悉酆都，不必急着决定去向。"}
			]
		"gate_inspection":
			return [
				{"label": "申请入城核验", "response": "南幽门核验流程：说明来处、出示魂籍凭据、接受阴兵查验。当前原型不会授予真实通行权限。"},
				{"label": "查看通行规矩", "response": "严禁携带未经登记的凶煞之物入城；有争议的魂籍须移交鬼籍司复核。"},
				{"label": "暂不通行", "response": "牛头将军横戟示意：未备齐凭据，可先到引魂驿站询问。"}
			]
		"pass_check":
			return [
				{"label": "查看巡防告示", "response": "南幽门巡防分为城门查验、桥面巡逻与夜间封控。特殊时段以阴司正式告示为准。"},
				{"label": "核验通行凭证", "response": "请准备魂籍、差牌或官署文牒。当前仅演示核验说明，不会读取或修改玩家权限。"},
				{"label": "稍后再说", "response": "马面将军收起名册，继续巡视城门。"}
			]
		_:
			return [
				{"label": "查看职责与规矩", "response": str(data.get("authority", "此处值守人员")) + "：" + str(data.get("access", "当前没有额外开放条件。"))},
				{"label": "了解更多", "response": str(data.get("description", "此处暂时没有更多信息。"))}
			]


func _rebuild_options(options: Array[Dictionary]) -> void:
	for child in _options_row.get_children():
		child.queue_free()
	for option in options:
		var button := Button.new()
		button.text = str(option.get("label", "继续"))
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal", _button_style(false))
		button.add_theme_stylebox_override("hover", _button_style(true))
		button.pressed.connect(_on_option_pressed.bind(option))
		_options_row.add_child(button)


func _on_option_pressed(option: Dictionary) -> void:
	_body_label.text = str(option.get("response", "暂时没有更多内容。"))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#171a22")
	style.border_color = Color("#786448")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 18
	return style


func _emblem_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#28252a")
	style.border_color = Color("#9b8057")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#4a3b31") if hovered else Color("#302d32")
	style.border_color = Color("#b08d5b") if hovered else Color("#615647")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style
