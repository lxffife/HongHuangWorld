extends CanvasLayer
## Local quest journal for the Fengdu greybox.

var _manager: Node
var _panel: PanelContainer
var _list: VBoxContainer
var _summary_label: Label
var _is_open := false


func configure(manager: Node) -> void:
	_manager = manager
	if not _manager.is_connected("quest_log_changed", Callable(self, "refresh")):
		_manager.connect("quest_log_changed", Callable(self, "refresh"))
	refresh()


func _ready() -> void:
	_build_ui()


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _panel == null:
		return
	_is_open = not _is_open
	_panel.visible = _is_open
	if _is_open:
		refresh()


func close_journal() -> void:
	if not _is_open:
		return
	_is_open = false
	_panel.visible = false


func refresh() -> void:
	if _list == null or _manager == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var all_quests: Array = _manager.call("get_all_quests")
	var active_count := 0
	var completed_count := 0
	for item in all_quests:
		var quest: Dictionary = item
		match str(quest.get("status", "")):
			"active":
				active_count += 1
			"completed":
				completed_count += 1
	_summary_label.text = "差事 %d 项  ·  进行中 %d  ·  已完成 %d" % [all_quests.size(), active_count, completed_count]
	for item in all_quests:
		_add_quest_card(item)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "QuestJournalOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "QuestJournal"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -330.0
	_panel.offset_top = -260.0
	_panel.offset_right = 330.0
	_panel.offset_bottom = 260.0
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_column)
	var title := Label.new()
	title.text = "阴司差事簿"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("#f0dfc2"))
	title_column.add_child(title)
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 12)
	_summary_label.add_theme_color_override("font_color", Color("#b5a58e"))
	title_column.add_child(_summary_label)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(72.0, 38.0)
	close_button.pressed.connect(close_journal)
	header.add_child(close_button)

	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(580.0, 390.0)
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var footer := Label.new()
	footer.text = "当前为本地演示：任务进度仅保存在本次场景运行期间，奖励不会发放。"
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color("#a99c89"))
	column.add_child(footer)


func _add_quest_card(quest: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	_list.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = str(quest.get("title", "未命名差事"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#e8d7b8"))
	header.add_child(title)
	var status := Label.new()
	status.text = _status_text(str(quest.get("status", "")))
	status.add_theme_color_override("font_color", _status_color(str(quest.get("status", ""))))
	header.add_child(status)

	var giver := Label.new()
	giver.text = "委托人：" + str(quest.get("giver_name", "阴司"))
	giver.add_theme_font_size_override("font_size", 12)
	giver.add_theme_color_override("font_color", Color("#b5a58e"))
	column.add_child(giver)
	var summary := Label.new()
	summary.text = str(quest.get("summary", ""))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 13)
	column.add_child(summary)

	var objectives: Array = quest.get("objectives", [])
	var progress := int(quest.get("progress", 0))
	for index in range(objectives.size()):
		var objective: Dictionary = objectives[index]
		var objective_label := Label.new()
		var prefix := "✓" if index < progress else ("▶" if index == progress and str(quest.get("status", "")) == "active" else "○")
		objective_label.text = "%s  %s" % [prefix, str(objective.get("label", "待办事项"))]
		objective_label.add_theme_font_size_override("font_size", 12)
		objective_label.add_theme_color_override("font_color", Color("#a9c6a7") if index < progress else Color("#d2c9bb"))
		column.add_child(objective_label)

	var reward := Label.new()
	reward.text = "预期记录：" + str(quest.get("reward_preview", "无"))
	reward.add_theme_font_size_override("font_size", 11)
	reward.add_theme_color_override("font_color", Color("#b99a68"))
	column.add_child(reward)


func _status_text(status: String) -> String:
	match status:
		"available":
			return "待领取"
		"active":
			return "进行中"
		"completed":
			return "已完成 · 待结算"
	return "未知"


func _status_color(status: String) -> Color:
	match status:
		"active":
			return Color("#d6b46e")
		"completed":
			return Color("#9fc49d")
	return Color("#b5a58e")


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#171a22")
	style.border_color = Color("#786448")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 20
	return style


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#23252c")
	style.border_color = Color("#51483d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style
