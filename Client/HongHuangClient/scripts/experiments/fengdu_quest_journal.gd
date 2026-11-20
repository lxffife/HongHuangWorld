extends CanvasLayer
## Local quest journal for the Fengdu greybox.

var _manager: Node
var _story_state: Node
var _panel: PanelContainer
var _list: VBoxContainer
var _summary_label: Label
var _is_open := false


func configure(manager: Node, story_state: Node = null) -> void:
	_manager = manager
	_story_state = story_state
	if _story_state != null:
		if not _story_state.is_connected("choice_made", Callable(self, "_on_story_state_changed")):
			_story_state.connect("choice_made", Callable(self, "_on_story_state_changed"))
		if not _story_state.is_connected("reputation_changed", Callable(self, "_on_story_reputation_changed")):
			_story_state.connect("reputation_changed", Callable(self, "_on_story_reputation_changed"))
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
	_add_story_log()


func _on_story_state_changed(_choice_id: String, _choice_data: Dictionary) -> void:
	refresh()


func _on_story_reputation_changed(_faction_id: String, _value: int) -> void:
	refresh()


func _add_story_log() -> void:
	if _story_state == null:
		return
	var entries: Array = _story_state.call("get_story_log")
	var heading := Label.new()
	heading.text = "剧情记录 · 已作出的选择"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("#e8d7b8"))
	_list.add_child(heading)
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "尚无关键剧情选择。完成白无常的引魂差事后，可决定如何对待新入城的亡魂。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color("#a99c89"))
		_list.add_child(empty_label)
		return
	for entry in entries:
		var label := Label.new()
		label.text = "◆ %s\n  %s" % [str(entry.get("title", "未命名选择")), str(entry.get("detail", ""))]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color("#cbb58f"))
		_list.add_child(label)


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
		var objective_text := str(objective.get("label", "待办事项"))
		if index == progress and str(quest.get("status", "")) == "active":
			var required := maxi(1, int(objective.get("required_count", 1)))
			var current := int(quest.get("objective_progress", 0))
			if required > 1:
				objective_text += "  (%d/%d)" % [current, required]
		objective_label.text = "%s  %s" % [prefix, objective_text]
		objective_label.add_theme_font_size_override("font_size", 12)
		objective_label.add_theme_color_override("font_color", Color("#a9c6a7") if index < progress else Color("#d2c9bb"))
		column.add_child(objective_label)

	var reward := Label.new()
	var reward_amount := int(quest.get("reward_amount", 0))
	var reward_text := "完成奖励：%d 冥币" % reward_amount if reward_amount > 0 else "完成奖励：待设定"
	if str(quest.get("status", "")) == "completed" and int(quest.get("last_reward_paid", 0)) > 0:
		reward_text += " · 已到账"
	reward.text = reward_text + "    记录：" + str(quest.get("reward_preview", "无"))
	reward.add_theme_font_size_override("font_size", 11)
	reward.add_theme_color_override("font_color", Color("#b99a68"))
	column.add_child(reward)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var status_value := str(quest.get("status", ""))
	if status_value == "active" or status_value == "completed":
		var track_button := Button.new()
		track_button.text = "追踪此差事"
		track_button.custom_minimum_size = Vector2(112.0, 32.0)
		track_button.pressed.connect(_on_track_pressed.bind(str(quest.get("id", ""))))
		actions.add_child(track_button)
	if status_value == "active":
		var abandon_button := Button.new()
		abandon_button.text = "放弃差事"
		abandon_button.custom_minimum_size = Vector2(100.0, 32.0)
		abandon_button.pressed.connect(_on_abandon_pressed.bind(str(quest.get("id", ""))))
		actions.add_child(abandon_button)


func _on_track_pressed(quest_id: String) -> void:
	if _manager != null:
		_manager.call("track_quest", quest_id)


func _on_abandon_pressed(quest_id: String) -> void:
	if _manager != null:
		_manager.call("abandon_quest", quest_id)




func _status_text(status: String) -> String:
	match status:
		"available":
			return "待领取"
		"active":
			return "进行中"
		"completed":
			return "已完成 · 待结算"
		"failed":
			return "已失败"
		"abandoned":
			return "已放弃"
	return "未知"


func _status_color(status: String) -> Color:
	match status:
		"active":
			return Color("#d6b46e")
		"completed":
			return Color("#9fc49d")
		"failed":
			return Color("#d98d83")
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
