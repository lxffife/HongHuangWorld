extends CanvasLayer
## Compact always-on local quest tracker.

var _manager: Node
var _panel: PanelContainer
var _title_label: Label
var _objective_label: Label
var _progress_label: Label


func configure(manager: Node) -> void:
	_manager = manager
	if not _manager.is_connected("tracked_quest_changed", Callable(self, "refresh")):
		_manager.connect("tracked_quest_changed", Callable(self, "refresh"))
	refresh()


func _ready() -> void:
	_build_ui()


func refresh(_quest_data: Dictionary = {}) -> void:
	if _panel == null or _manager == null:
		return
	var quest: Dictionary = _manager.call("get_tracked_quest")
	var visible := not quest.is_empty()
	_panel.visible = visible
	if not visible:
		return
	_title_label.text = str(quest.get("title", "当前差事"))
	var objectives: Array = quest.get("objectives", [])
	var progress := int(quest.get("progress", 0))
	var status := str(quest.get("status", ""))
	if status == "completed":
		_objective_label.text = "差事已完成 · 返回委托人处查看"
		_progress_label.text = "已完成"
		return
	if progress < 0 or progress >= objectives.size():
		_objective_label.text = "当前没有待办目标"
		_progress_label.text = ""
		return
	var objective: Dictionary = objectives[progress]
	var required := maxi(1, int(objective.get("required_count", 1)))
	var current := int(quest.get("objective_progress", 0))
	_objective_label.text = str(objective.get("label", "完成当前目标"))
	_progress_label.text = "目标 %d/%d  ·  进度 %d/%d" % [progress + 1, objectives.size(), current, required]


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "QuestTracker"
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -340.0
	_panel.offset_top = 22.0
	_panel.offset_right = -20.0
	_panel.offset_bottom = 126.0
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var eyebrow := Label.new()
	eyebrow.text = "当前追踪差事"
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", Color("#b99a68"))
	header.add_child(eyebrow)
	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 11)
	_progress_label.add_theme_color_override("font_color", Color("#c8bdab"))
	header.add_child(_progress_label)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color("#f0dfc2"))
	column.add_child(_title_label)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 12)
	_objective_label.add_theme_color_override("font_color", Color("#d1c7b7"))
	column.add_child(_objective_label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#171a22", 0.94)
	style.border_color = Color("#786448")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
