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
var right_panel_control: PanelContainer
var login_brand_controls: Array[Control] = []
var details_container: VBoxContainer
var details_toggle_button: Button
var details_expanded := false
var lobby_root: Control
var lobby_name_label: Label
var lobby_race_label: Label
var lobby_realm_label: Label
var lobby_world_label: Label
var lobby_status_label: Label
var lobby_level_label: Label
var lobby_progress_label: Label
var lobby_cultivation_label: Label
var lobby_cultivation_bar: ProgressBar
var lobby_points_label: Label
var lobby_stats_grid: GridContainer
var lobby_details_host: VBoxContainer
var lobby_body_container: HBoxContainer
var lobby_enter_button: Button
var lobby_preview_root: Node3D
var lobby_equipment: Array = []
var lobby_inventory: Array = []
var lobby_selected_equipment: Dictionary = {}
var lobby_equipment_detail: Dictionary = {}
var lobby_equipment_panel: PanelContainer
var lobby_equipment_list: VBoxContainer
var lobby_equipment_busy := false
var lobby_equipment_status_label: Label
var lobby_preview_dragging := false
var lobby_preview_last_mouse := Vector2.ZERO
var reincarnation_name_input: LineEdit
var reincarnation_race_select: OptionButton
var reincarnation_route_select: OptionButton
var reincarnation_route_label: Label
var reincarnation_route_description: Label
var reincarnation_inheritance_label: Label
var reincarnation_routes: Array = []
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
	_build_lobby_ui()
	if not HHSession.access_token.is_empty():
		api_base = HHSession.api_base
		access_token = HHSession.access_token
		api_input.text = api_base
		_show_authenticated_workspace()
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
	panel.custom_minimum_size = Vector2(900, 580)
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
	right_panel_control = right_panel
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
	login_brand_controls.append(title)

	var subtitle := Label.new()
	subtitle.text = "中心服登录 · 灵魂档案 · 转世角色 · 世界入口"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("#aab6cc"))
	content_box.add_child(subtitle)
	login_brand_controls.append(subtitle)

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
	status_label.custom_minimum_size.y = 42
	content_box.add_child(status_label)

	http = HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_http_completed)

func _build_reincarnation_ui() -> void:
	details_toggle_button = Button.new()
	details_toggle_button.text = "展开灵魂档案与轮回功能"
	details_toggle_button.visible = false
	details_toggle_button.pressed.connect(_toggle_soul_details)
	content_box.add_child(details_toggle_button)
	details_container = VBoxContainer.new()
	details_container.add_theme_constant_override("separation", 10)
	content_box.add_child(details_container)
	details_container.hide()
	var separator := HSeparator.new()
	details_container.add_child(separator)
	var title := Label.new()
	title.text = "主动轮回 · 创建下一世肉身"
	title.add_theme_font_size_override("font_size", 18)
	details_container.add_child(title)
	reincarnation_status_label = Label.new()
	reincarnation_status_label.text = "完成冥界试炼并达到聚灵境后，可在轮回殿申请投胎。"
	reincarnation_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_container.add_child(reincarnation_status_label)
	reincarnation_name_input = LineEdit.new()
	reincarnation_name_input.placeholder_text = "新肉身名称（2–24 个字符）"
	reincarnation_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_container.add_child(reincarnation_name_input)
	reincarnation_race_select = OptionButton.new()
	reincarnation_race_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reincarnation_race_select.item_selected.connect(_on_reincarnation_race_selected)
	details_container.add_child(reincarnation_race_select)
	reincarnation_route_label = Label.new()
	reincarnation_route_label.text = "选择出生路线（由中心服配置）"
	details_container.add_child(reincarnation_route_label)
	reincarnation_route_select = OptionButton.new()
	reincarnation_route_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reincarnation_route_select.item_selected.connect(_update_reincarnation_route_description)
	details_container.add_child(reincarnation_route_select)
	reincarnation_route_description = Label.new()
	reincarnation_route_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reincarnation_route_description.add_theme_color_override("font_color", Color("#aab6cc"))
	details_container.add_child(reincarnation_route_description)
	reincarnation_inheritance_label = Label.new()
	reincarnation_inheritance_label.text = "选择种族后，将显示灵魂吞噬资质对下一世出生属性的影响。"
	reincarnation_inheritance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reincarnation_inheritance_label.add_theme_color_override("font_color", Color("#d7c59a"))
	details_container.add_child(reincarnation_inheritance_label)
	reincarnation_check_button = Button.new()
	reincarnation_check_button.text = "查询投胎资格"
	reincarnation_check_button.pressed.connect(_check_reincarnation_eligibility)
	details_container.add_child(reincarnation_check_button)
	reincarnation_submit_button = Button.new()
	reincarnation_submit_button.text = "确认创建新肉身"
	reincarnation_submit_button.disabled = true
	reincarnation_submit_button.pressed.connect(func(): reincarnation_confirm.popup_centered())
	details_container.add_child(reincarnation_submit_button)
	reincarnation_confirm = ConfirmationDialog.new()
	reincarnation_confirm.title = "确认主动轮回"
	reincarnation_confirm.dialog_text = "此操作不可撤销：当前肉身将归档为前世，并为同一灵魂创建新的肉身。灵魂经验、功德、业力会保留。是否继续？"
	reincarnation_confirm.confirmed.connect(_submit_reincarnation)
	add_child(reincarnation_confirm)
	for control in [title, reincarnation_status_label, reincarnation_name_input, reincarnation_race_select, reincarnation_route_label, reincarnation_route_select, reincarnation_route_description, reincarnation_inheritance_label, reincarnation_check_button, reincarnation_submit_button]:
		control.hide()
	life_history_title = Label.new()
	life_history_title.text = "灵魂历世档案"
	life_history_title.add_theme_font_size_override("font_size", 18)
	details_container.add_child(life_history_title)
	life_history_status = Label.new()
	life_history_status.text = "登录后读取同一灵魂的历世记录。"
	life_history_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_container.add_child(life_history_status)
	life_history_box = VBoxContainer.new()
	life_history_box.add_theme_constant_override("separation", 8)
	details_container.add_child(life_history_box)
	life_history_refresh_button = Button.new()
	life_history_refresh_button.text = "刷新历世档案"
	life_history_refresh_button.pressed.connect(_request_life_history)
	details_container.add_child(life_history_refresh_button)
	for control in [life_history_title, life_history_status, life_history_box, life_history_refresh_button]:
		control.hide()
	soul_memory_title = Label.new()
	soul_memory_title.text = "前世记忆 · 灵魂深处"
	soul_memory_title.add_theme_font_size_override("font_size", 18)
	details_container.add_child(soul_memory_title)
	soul_memory_status = Label.new()
	soul_memory_status.text = "部分前世记忆需要更高的灵魂境界才能稳定显现。"
	soul_memory_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_container.add_child(soul_memory_status)
	soul_memory_box = VBoxContainer.new()
	soul_memory_box.add_theme_constant_override("separation", 8)
	details_container.add_child(soul_memory_box)
	soul_memory_refresh_button = Button.new()
	soul_memory_refresh_button.text = "感知前世记忆"
	soul_memory_refresh_button.pressed.connect(_request_soul_memories)
	details_container.add_child(soul_memory_refresh_button)
	for control in [soul_memory_title, soul_memory_status, soul_memory_box, soul_memory_refresh_button]:
		control.hide()
	soul_fate_title = Label.new()
	soul_fate_title.text = "因果簿 · 功德与业力"
	soul_fate_title.add_theme_font_size_override("font_size", 18)
	details_container.add_child(soul_fate_title)
	soul_fate_status = Label.new()
	soul_fate_status.text = "功德与业力属于灵魂，轮回后不会清零。"
	soul_fate_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_container.add_child(soul_fate_status)
	soul_fate_box = VBoxContainer.new()
	soul_fate_box.add_theme_constant_override("separation", 4)
	details_container.add_child(soul_fate_box)
	soul_fate_refresh_button = Button.new()
	soul_fate_refresh_button.text = "查看因果记录"
	soul_fate_refresh_button.pressed.connect(_request_soul_fate)
	details_container.add_child(soul_fate_refresh_button)
	for control in [soul_fate_title, soul_fate_status, soul_fate_box, soul_fate_refresh_button]:
		control.hide()

func _toggle_soul_details() -> void:
	details_expanded = not details_expanded
	details_container.visible = details_expanded
	details_toggle_button.text = "收起灵魂档案与轮回功能" if details_expanded else "展开灵魂档案与轮回功能"

func _show_authenticated_workspace() -> void:
	for control in auth_controls:
		control.hide()
	for control in login_brand_controls:
		control.hide()
	if is_instance_valid(right_panel_control):
		right_panel_control.hide()
	account_label.text = "当前账号  ·  " + username_input.text.strip_edges()
	account_label.show()
	if is_instance_valid(details_toggle_button):
		details_toggle_button.hide()
	if is_instance_valid(details_container):
		details_container.hide()
	details_expanded = false

func _show_login_screen() -> void:
	for control in auth_controls:
		control.show()
	for control in login_brand_controls:
		control.show()
	if is_instance_valid(right_panel_control):
		right_panel_control.show()
	if is_instance_valid(lobby_root):
		lobby_root.hide()
	account_label.hide()
	character_title_label.hide()
	character_input.hide()
	race_label_control.hide()
	race_select.hide()
	cultivation_preview.hide()
	world_label_control.hide()
	world_select.hide()
	action_button.hide()
	if is_instance_valid(details_toggle_button):
		details_toggle_button.hide()
	if is_instance_valid(details_container):
		details_container.hide()


func _process(delta: float) -> void:
	if is_instance_valid(lobby_root) and lobby_root.visible and is_instance_valid(lobby_preview_root) and not lobby_preview_dragging:
		lobby_preview_root.rotation.y += delta * 0.12

func _build_lobby_ui() -> void:
	lobby_root = Control.new()
	lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_root.hide()
	add_child(lobby_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#090e18")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_root.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 520)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var heading := Label.new()
	heading.text = "洪荒：诸天轮回"
	heading.add_theme_font_size_override("font_size", 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var account := Label.new()
	account.text = "角色大厅"
	account.add_theme_color_override("font_color", Color("#b8c5d8"))
	header.add_child(account)
	var separator := HSeparator.new()
	layout.add_child(separator)
	var body := HBoxContainer.new()
	lobby_body_container = body
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	layout.add_child(body)
	var preview_container := SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(300, 340)
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_container.gui_input.connect(_on_lobby_preview_input)
	body.add_child(preview_container)
	var preview_viewport := SubViewport.new()
	preview_viewport.size = Vector2i(480, 560)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.transparent_bg = false
	preview_container.add_child(preview_viewport)
	lobby_preview_root = Node3D.new()
	lobby_preview_root.name = "CharacterPreview"
	preview_viewport.add_child(lobby_preview_root)
	var preview_world := WorldEnvironment.new()
	var preview_environment := Environment.new()
	preview_environment.background_mode = Environment.BG_COLOR
	preview_environment.background_color = Color("#101a2a")
	preview_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	preview_environment.ambient_light_color = Color("#8294ad")
	preview_environment.ambient_light_energy = 0.65
	preview_world.environment = preview_environment
	lobby_preview_root.add_child(preview_world)
	var preview_camera := Camera3D.new()
	preview_camera.position = Vector3(0.0, 1.45, 4.4)
	preview_camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	preview_camera.current = true
	lobby_preview_root.add_child(preview_camera)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28.0, -32.0, 0.0)
	key_light.light_energy = 1.4
	lobby_preview_root.add_child(key_light)
	var rim_light := OmniLight3D.new()
	rim_light.position = Vector3(-1.6, 2.2, -1.0)
	rim_light.light_color = Color("#4b9acb")
	rim_light.light_energy = 1.8
	rim_light.omni_range = 5.0
	lobby_preview_root.add_child(rim_light)
	_build_lobby_preview_model()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 14)
	body.add_child(info)
	var section := Label.new()
	section.text = "此世命格"
	section.add_theme_color_override("font_color", Color("#c5a76d"))
	section.add_theme_font_size_override("font_size", 16)
	info.add_child(section)
	lobby_name_label = Label.new()
	lobby_name_label.text = "尚未创建角色"
	lobby_name_label.add_theme_font_size_override("font_size", 30)
	info.add_child(lobby_name_label)
	lobby_race_label = Label.new()
	lobby_race_label.text = "种族：待定"
	info.add_child(lobby_race_label)
	lobby_realm_label = Label.new()
	lobby_realm_label.text = "修炼境界：待载入"
	info.add_child(lobby_realm_label)
	lobby_world_label = Label.new()
	lobby_world_label.text = "出生世界：待载入"
	info.add_child(lobby_world_label)
	lobby_level_label = Label.new()
	lobby_level_label.text = "等级：—"
	lobby_level_label.add_theme_color_override("font_color", Color("#e4d2ad"))
	info.add_child(lobby_level_label)
	lobby_progress_label = Label.new()
	lobby_progress_label.text = "经验：—  ·  修为：—"
	lobby_progress_label.add_theme_font_size_override("font_size", 12)
	lobby_progress_label.add_theme_color_override("font_color", Color("#9eafc5"))
	info.add_child(lobby_progress_label)
	lobby_cultivation_label = Label.new()
	lobby_cultivation_label.text = "境界修炼进度：等待载入"
	lobby_cultivation_label.add_theme_font_size_override("font_size", 12)
	lobby_cultivation_label.add_theme_color_override("font_color", Color("#c5a76d"))
	info.add_child(lobby_cultivation_label)
	lobby_cultivation_bar = ProgressBar.new()
	lobby_cultivation_bar.custom_minimum_size = Vector2(0, 12)
	lobby_cultivation_bar.min_value = 0
	lobby_cultivation_bar.max_value = 100
	lobby_cultivation_bar.value = 0
	lobby_cultivation_bar.show_percentage = false
	info.add_child(lobby_cultivation_bar)
	lobby_points_label = Label.new()
	lobby_points_label.text = "可分配属性点：—"
	lobby_points_label.add_theme_font_size_override("font_size", 12)
	lobby_points_label.add_theme_color_override("font_color", Color("#9ed6b1"))
	info.add_child(lobby_points_label)
	lobby_stats_grid = GridContainer.new()
	lobby_stats_grid.columns = 3
	lobby_stats_grid.add_theme_constant_override("h_separation", 8)
	lobby_stats_grid.add_theme_constant_override("v_separation", 6)
	info.add_child(lobby_stats_grid)
	var preview_hint := Label.new()
	preview_hint.text = "角色预览 · 按住鼠标左键拖动旋转"
	preview_hint.add_theme_color_override("font_color", Color("#8fa4bd"))
	preview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(preview_hint)
	lobby_status_label = Label.new()
	lobby_status_label.text = "角色资料已准备就绪。"
	lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_status_label.add_theme_color_override("font_color", Color("#aab6cc"))
	lobby_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(lobby_status_label)
	lobby_equipment_status_label = Label.new()
	lobby_equipment_status_label.text = "装备外观：正在读取……"
	lobby_equipment_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_equipment_status_label.add_theme_color_override("font_color", Color("#c5a76d"))
	info.add_child(lobby_equipment_status_label)
	var footer_separator := HSeparator.new()
	layout.add_child(footer_separator)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)
	var archive_button := Button.new()
	archive_button.text = "灵魂档案 / 轮回"
	archive_button.custom_minimum_size = Vector2(180, 48)
	archive_button.pressed.connect(_toggle_lobby_details)
	footer.add_child(archive_button)
	var equipment_button := Button.new()
	equipment_button.text = "装备管理"
	equipment_button.custom_minimum_size = Vector2(140, 48)
	equipment_button.pressed.connect(_toggle_lobby_equipment_panel)
	footer.add_child(equipment_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	lobby_enter_button = Button.new()
	lobby_enter_button.text = "进入世界"
	lobby_enter_button.custom_minimum_size = Vector2(240, 52)
	lobby_enter_button.pressed.connect(_on_create_character_pressed)
	footer.add_child(lobby_enter_button)
	lobby_details_host = VBoxContainer.new()
	lobby_details_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_details_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_details_host.add_theme_constant_override("separation", 8)
	lobby_equipment_panel = PanelContainer.new()
	lobby_equipment_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_equipment_panel.custom_minimum_size.y = 180
	lobby_equipment_panel.hide()
	layout.add_child(lobby_equipment_panel)
	var equipment_scroll := ScrollContainer.new()
	equipment_scroll.custom_minimum_size.y = 180
	equipment_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_equipment_panel.add_child(equipment_scroll)
	lobby_equipment_list = VBoxContainer.new()
	lobby_equipment_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_scroll.add_child(lobby_equipment_list)
	lobby_details_host.hide()
	layout.add_child(lobby_details_host)
	if is_instance_valid(details_toggle_button):
		if details_toggle_button.get_parent() != null:
			details_toggle_button.get_parent().remove_child(details_toggle_button)
		lobby_details_host.add_child(details_toggle_button)
	if is_instance_valid(details_container):
		if details_container.get_parent() != null:
			details_container.get_parent().remove_child(details_container)
		lobby_details_host.add_child(details_container)


func _build_lobby_preview_model() -> void:
	if not is_instance_valid(lobby_preview_root):
		return
	for child in lobby_preview_root.get_children():
		if child is MeshInstance3D or child.name == "CharacterModel":
			child.queue_free()
	var model := Node3D.new()
	model.name = "CharacterModel"
	lobby_preview_root.add_child(model)
	var robe_color := Color("#243d59")
	var trim_color := Color("#c9a86b")
	var skin_color := Color("#d6b59a")
	var race_id := str(current_character.get("race_id", "human")).to_lower()
	var race_kind := "human"
	if race_id == "demon" or race_id.contains("yao"):
		race_kind = "demon"
		robe_color = Color("#512d3d")
		trim_color = Color("#d18a58")
		skin_color = Color("#a97870")
	elif race_id == "dragon" or race_id.contains("long"):
		race_kind = "dragon"
		robe_color = Color("#24504b")
		trim_color = Color("#d7bd72")
		skin_color = Color("#8bb8a7")
	elif race_id == "witch" or race_id.contains("wu"):
		race_kind = "witch"
		robe_color = Color("#493b2b")
		trim_color = Color("#b58b50")
		skin_color = Color("#b99579")
	elif race_id.contains("spirit") or race_id.contains("ling"):
		race_kind = "spirit"
		robe_color = Color("#344b67")
		trim_color = Color("#80c9df")
		skin_color = Color("#b8d3dc")
	var robe_material := StandardMaterial3D.new()
	robe_material.albedo_color = robe_color
	robe_material.metallic = 0.22
	robe_material.roughness = 0.42
	var skin_material := StandardMaterial3D.new()
	skin_material.albedo_color = skin_color
	skin_material.roughness = 0.72
	var trim_material := StandardMaterial3D.new()
	trim_material.albedo_color = trim_color
	trim_material.metallic = 0.48
	trim_material.roughness = 0.3
	var hair_material := StandardMaterial3D.new()
	hair_material.albedo_color = Color("#171c2b")
	var robe := MeshInstance3D.new()
	var robe_mesh := CylinderMesh.new()
	robe_mesh.top_radius = 0.28
	robe_mesh.bottom_radius = 0.48
	robe_mesh.height = 1.25
	robe.mesh = robe_mesh
	robe.position.y = 0.78
	robe.material_override = robe_material
	model.add_child(robe)
	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.31
	torso_mesh.height = 0.9
	if race_kind == "witch":
		torso_mesh.radius = 0.39
		torso_mesh.height = 0.98
	elif race_kind == "dragon":
		torso_mesh.radius = 0.34
	torso.mesh = torso_mesh
	torso.position.y = 1.36
	torso.material_override = robe_material
	model.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head.mesh = head_mesh
	head.position.y = 2.0
	head.material_override = skin_material
	model.add_child(head)
	var hair := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.235
	hair_mesh.height = 0.25
	hair.mesh = hair_mesh
	hair.position = Vector3(0.0, 2.16, -0.025)
	hair.material_override = hair_material
	model.add_child(hair)
	if race_kind == "demon" or race_kind == "dragon":
		for side in [-1.0, 1.0]:
			var horn := MeshInstance3D.new()
			var horn_mesh := CylinderMesh.new()
			horn_mesh.top_radius = 0.015
			horn_mesh.bottom_radius = 0.105 if race_kind == "demon" else 0.085
			horn_mesh.height = 0.42 if race_kind == "demon" else 0.32
			horn.mesh = horn_mesh
			horn.position = Vector3(side * 0.16, 2.34, -0.015)
			horn.rotation.z = side * -0.32
			horn.material_override = trim_material
			model.add_child(horn)
	if race_kind == "dragon":
		for side in [-1.0, 1.0]:
			var scale_plate := MeshInstance3D.new()
			var scale_mesh := SphereMesh.new()
			scale_mesh.radius = 0.16
			scale_mesh.height = 0.09
			scale_plate.mesh = scale_mesh
			scale_plate.position = Vector3(side * 0.29, 1.55, 0.12)
			scale_plate.material_override = trim_material
			model.add_child(scale_plate)
		var tail := MeshInstance3D.new()
		var tail_mesh := CapsuleMesh.new()
		tail_mesh.radius = 0.11
		tail_mesh.height = 0.92
		tail.mesh = tail_mesh
		tail.position = Vector3(0.0, 0.42, -0.52)
		tail.rotation.x = -0.9
		tail.material_override = robe_material
		model.add_child(tail)
	if race_kind == "witch":
		for side in [-1.0, 1.0]:
			var shoulder := MeshInstance3D.new()
			var shoulder_mesh := SphereMesh.new()
			shoulder_mesh.radius = 0.25
			shoulder_mesh.height = 0.22
			shoulder.mesh = shoulder_mesh
			shoulder.position = Vector3(side * 0.34, 1.63, 0.0)
			shoulder.material_override = trim_material
			model.add_child(shoulder)
	if race_kind == "spirit":
		var spirit_aura := MeshInstance3D.new()
		var aura_mesh := TorusMesh.new()
		aura_mesh.inner_radius = 0.52
		aura_mesh.outer_radius = 0.56
		spirit_aura.mesh = aura_mesh
		spirit_aura.position.y = 1.28
		spirit_aura.rotation.x = 0.35
		spirit_aura.material_override = trim_material
		model.add_child(spirit_aura)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.105
		arm_mesh.height = 0.78
		arm.mesh = arm_mesh
		arm.position = Vector3(side * 0.39, 1.32, 0.0)
		arm.rotation.z = side * -0.18
		arm.material_override = robe_material
		model.add_child(arm)
		var cuff := MeshInstance3D.new()
		var cuff_mesh := SphereMesh.new()
		cuff_mesh.radius = 0.12
		cuff_mesh.height = 0.12
		cuff.mesh = cuff_mesh
		cuff.position = Vector3(side * 0.45, 0.98, 0.0)
		cuff.material_override = trim_material
		model.add_child(cuff)
	var sash := MeshInstance3D.new()
	var sash_mesh := TorusMesh.new()
	sash_mesh.inner_radius = 0.285
	sash_mesh.outer_radius = 0.32
	sash.mesh = sash_mesh
	sash.position.y = 1.05
	sash.rotation.x = PI / 2.0
	sash.material_override = trim_material
	model.add_child(sash)
	var platform := MeshInstance3D.new()
	var platform_mesh := CylinderMesh.new()
	platform_mesh.top_radius = 0.82
	platform_mesh.bottom_radius = 0.82
	platform_mesh.height = 0.08
	platform.mesh = platform_mesh
	platform.position.y = 0.02
	platform.material_override = trim_material
	model.add_child(platform)

	# Equipment is a visual-only lobby representation. Server inventory/equipment
	# remains authoritative; no combat attributes are changed by this preview.
	for equipped_variant in lobby_equipment:
		if not (equipped_variant is Dictionary):
			continue
		var equipped: Dictionary = equipped_variant
		var slot := str(equipped.get("slot", ""))
		var quality := clampi(int(equipped.get("quality", 1)), 1, 5)
		var item_material := StandardMaterial3D.new()
		item_material.albedo_color = _equipment_quality_color(quality)
		item_material.metallic = 0.58
		item_material.roughness = 0.28
		match slot:
			"weapon":
				var weapon := MeshInstance3D.new()
				var blade := BoxMesh.new()
				blade.size = Vector3(0.075, 0.92, 0.035)
				weapon.mesh = blade
				weapon.position = Vector3(0.67, 1.18, 0.02)
				weapon.rotation.z = -0.28
				weapon.material_override = item_material
				model.add_child(weapon)
				var guard := MeshInstance3D.new()
				var guard_mesh := BoxMesh.new()
				guard_mesh.size = Vector3(0.28, 0.055, 0.07)
				guard.mesh = guard_mesh
				guard.position = Vector3(0.67, 0.73, 0.02)
				guard.rotation.z = -0.28
				guard.material_override = trim_material
				model.add_child(guard)
			"head":
				var helm := MeshInstance3D.new()
				var helm_mesh := SphereMesh.new()
				helm_mesh.radius = 0.255
				helm_mesh.height = 0.19
				helm.mesh = helm_mesh
				helm.position.y = 2.22
				helm.material_override = item_material
				model.add_child(helm)
			"chest":
				var chest_guard := MeshInstance3D.new()
				var chest_mesh := SphereMesh.new()
				chest_mesh.radius = 0.34
				chest_mesh.height = 0.68
				chest_guard.mesh = chest_mesh
				chest_guard.position = Vector3(0.0, 1.42, 0.17)
				chest_guard.material_override = item_material
				model.add_child(chest_guard)
			"legs":
				for side in [-1.0, 1.0]:
					var leg_guard := MeshInstance3D.new()
					var leg_mesh := CapsuleMesh.new()
					leg_mesh.radius = 0.14
					leg_mesh.height = 0.62
					leg_guard.mesh = leg_mesh
					leg_guard.position = Vector3(side * 0.17, 0.39, 0.015)
					leg_guard.material_override = item_material
					model.add_child(leg_guard)
			"boots":
				for side in [-1.0, 1.0]:
					var boot := MeshInstance3D.new()
					var boot_mesh := BoxMesh.new()
					boot_mesh.size = Vector3(0.25, 0.2, 0.38)
					boot.mesh = boot_mesh
					boot.position = Vector3(side * 0.19, 0.12, 0.06)
					boot.material_override = item_material
					model.add_child(boot)
			"accessory":
				var accessory := MeshInstance3D.new()
				var accessory_mesh := TorusMesh.new()
				accessory_mesh.inner_radius = 0.37
				accessory_mesh.outer_radius = 0.405
				accessory.mesh = accessory_mesh
				accessory.position.y = 1.55
				accessory.rotation.x = 0.45
				accessory.material_override = item_material
				model.add_child(accessory)

func _toggle_lobby_equipment_panel() -> void:
	if not is_instance_valid(lobby_equipment_panel):
		return
	lobby_equipment_panel.visible = not lobby_equipment_panel.visible
	if lobby_equipment_panel.visible:
		_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/inventory", {}, true, "lobby_inventory")
		_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/equipment", {}, true, "lobby_equipment")

func _render_lobby_equipment_manager() -> void:
	if not is_instance_valid(lobby_equipment_list):
		return
	for child in lobby_equipment_list.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = "装备与背包 · 更换装备需要先退出当前世界"
	heading.add_theme_color_override("font_color", Color("#d8bd83"))
	lobby_equipment_list.add_child(heading)
	var slot_names := {"weapon": "武器", "head": "头饰", "chest": "护甲", "legs": "护腿", "boots": "靴子", "accessory": "饰品"}
	var equipped_by_slot := {}
	for value in lobby_equipment:
		if value is Dictionary:
			var item: Dictionary = value
			equipped_by_slot[str(item.get("slot", ""))] = item
	var slots_grid := GridContainer.new()
	slots_grid.columns = 2
	slots_grid.add_theme_constant_override("h_separation", 8)
	slots_grid.add_theme_constant_override("v_separation", 8)
	lobby_equipment_list.add_child(slots_grid)
	for slot in ["weapon", "head", "chest", "legs", "boots", "accessory"]:
		var equipped: Dictionary = equipped_by_slot.get(slot, {})
		var slot_card := PanelContainer.new()
		slot_card.custom_minimum_size = Vector2(220, 82)
		slots_grid.add_child(slot_card)
		var card_content := VBoxContainer.new()
		card_content.add_theme_constant_override("separation", 3)
		slot_card.add_child(card_content)
		var slot_title := Label.new()
		slot_title.text = str(slot_names[slot])
		slot_title.add_theme_font_size_override("font_size", 11)
		slot_title.add_theme_color_override("font_color", Color("#9eafc5"))
		card_content.add_child(slot_title)
		var item_name := Label.new()
		item_name.text = str(equipped.get("name", "尚未装备")) + "  ·  " + _equipment_quality_name(int(equipped.get("quality", 0))) if not equipped.is_empty() else "尚未装备"
		item_name.add_theme_font_size_override("font_size", 14)
		item_name.add_theme_color_override("font_color", _equipment_quality_color(int(equipped.get("quality", 0))) if not equipped.is_empty() else Color("#748196"))
		item_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_content.add_child(item_name)
		var detail_row := HBoxContainer.new()
		card_content.add_child(detail_row)
		var detail_label := Label.new()
		detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail_label.add_theme_font_size_override("font_size", 10)
		detail_label.add_theme_color_override("font_color", Color("#9ed6b1"))
		detail_label.text = _format_equipment_stat_summary(equipped.get("base_stats", {})) if not equipped.is_empty() else "等待装备"
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_row.add_child(detail_label)
		if not equipped.is_empty():
			var detail_button := Button.new()
			detail_button.text = "详情"
			detail_button.disabled = lobby_equipment_busy
			detail_button.pressed.connect(_show_lobby_equipment_detail.bind(equipped))
			detail_row.add_child(detail_button)
			var remove_button := Button.new()
			remove_button.text = "卸下"
			remove_button.disabled = lobby_equipment_busy
			remove_button.pressed.connect(_request_lobby_unequip.bind(slot))
			detail_row.add_child(remove_button)
	var divider := HSeparator.new()
	lobby_equipment_list.add_child(divider)
	var inventory_heading := Label.new()
	inventory_heading.text = "背包装备"
	lobby_equipment_list.add_child(inventory_heading)
	var found := false
	for value in lobby_inventory:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		if str(item.get("item_type", "")) != "equipment":
			continue
		found = true
		var item_row := HBoxContainer.new()
		lobby_equipment_list.add_child(item_row)
		var item_label := Label.new()
		item_label.text = str(item.get("name", "未知装备")) + " ×" + str(item.get("quantity", 1)) + "  " + str(slot_names.get(str(item.get("equipment_slot", "")), "装备"))
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_row.add_child(item_label)
		var detail_button := Button.new()
		detail_button.text = "详情"
		detail_button.disabled = lobby_equipment_busy
		detail_button.pressed.connect(_show_lobby_equipment_detail.bind(item))
		item_row.add_child(detail_button)
		var compare_button := Button.new()
		compare_button.text = "属性对比"
		compare_button.disabled = lobby_equipment_busy
		compare_button.pressed.connect(_select_lobby_equipment.bind(str(item.get("item_id", ""))))
		item_row.add_child(compare_button)
	if not found:
		var empty := Label.new()
		empty.text = "背包中暂无可穿戴装备。"
		lobby_equipment_list.add_child(empty)
	_render_lobby_equipment_comparison(equipped_by_slot)
	_render_lobby_equipment_detail()

func _show_lobby_equipment_detail(item: Dictionary) -> void:
	lobby_equipment_detail = item.duplicate(true)
	_render_lobby_equipment_manager()

func _render_lobby_equipment_detail() -> void:
	if lobby_equipment_detail.is_empty():
		return
	lobby_equipment_list.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "装备详情"
	title.add_theme_color_override("font_color", Color("#d8bd83"))
	title.add_theme_font_size_override("font_size", 16)
	lobby_equipment_list.add_child(title)
	var item_name := Label.new()
	item_name.text = str(lobby_equipment_detail.get("name", "未知装备")) + " · " + _equipment_quality_name(int(lobby_equipment_detail.get("quality", 0)))
	item_name.add_theme_color_override("font_color", _equipment_quality_color(int(lobby_equipment_detail.get("quality", 0))))
	item_name.add_theme_font_size_override("font_size", 15)
	lobby_equipment_list.add_child(item_name)
	var slot_names := {"weapon": "武器", "head": "头饰", "chest": "护甲", "legs": "护腿", "boots": "靴子", "accessory": "饰品"}
	var slot := str(lobby_equipment_detail.get("slot", lobby_equipment_detail.get("equipment_slot", "")))
	var meta := Label.new()
	meta.text = "部位：" + str(slot_names.get(slot, "装备")) + "    图标标识：" + str(lobby_equipment_detail.get("icon_key", "未配置"))
	meta.add_theme_color_override("font_color", Color("#9eafc5"))
	lobby_equipment_list.add_child(meta)
	var description := Label.new()
	var description_text := str(lobby_equipment_detail.get("description", "")).strip_edges()
	description.text = description_text if not description_text.is_empty() else "暂无装备描述。"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("#c2ccda"))
	lobby_equipment_list.add_child(description)
	var stats_title := Label.new()
	stats_title.text = "完整属性"
	stats_title.add_theme_color_override("font_color", Color("#d8bd83"))
	lobby_equipment_list.add_child(stats_title)
	var stats: Variant = lobby_equipment_detail.get("base_stats", {})
	if stats is Dictionary and not stats.is_empty():
		var keys: Array = stats.keys()
		keys.sort()
		for key_variant in keys:
			var key := str(key_variant)
			var value := int(stats[key_variant])
			var stat_line := Label.new()
			var prefix := "+" if value > 0 else ""
			stat_line.text = _equipment_stat_display_name(key) + "：" + prefix + str(value)
			stat_line.add_theme_color_override("font_color", Color("#77c99a") if value > 0 else (Color("#e07878") if value < 0 else Color("#aeb8c8")))
			lobby_equipment_list.add_child(stat_line)
	else:
		var empty_stats := Label.new()
		empty_stats.text = "此装备没有配置数值属性。"
		empty_stats.add_theme_color_override("font_color", Color("#9eafc5"))
		lobby_equipment_list.add_child(empty_stats)
	var close_button := Button.new()
	close_button.text = "收起详情"
	close_button.pressed.connect(_clear_lobby_equipment_detail)
	lobby_equipment_list.add_child(close_button)

func _clear_lobby_equipment_detail() -> void:
	lobby_equipment_detail = {}
	_render_lobby_equipment_manager()

func _equipment_stat_display_name(key: String) -> String:
	var labels := {
		"attack": "攻击", "defense": "防御", "health": "生命", "max_health": "生命上限",
		"mana": "灵力", "max_mana": "灵力上限", "spirit": "灵识", "strength": "力量",
		"constitution": "体质", "agility": "敏捷", "vitality": "气血",
		"intelligence": "灵识", "critical": "暴击", "critical_rate": "暴击率",
		"speed": "速度", "move_speed": "移动速度"
	}
	return str(labels.get(key, key))

func _select_lobby_equipment(item_id: String) -> void:
	if lobby_equipment_busy:
		return
	lobby_selected_equipment = {}
	for value in lobby_inventory:
		if value is Dictionary and str(value.get("item_id", "")) == item_id and str(value.get("item_type", "")) == "equipment":
			lobby_selected_equipment = value.duplicate(true)
			break
	_render_lobby_equipment_manager()

func _render_lobby_equipment_comparison(equipped_by_slot: Dictionary) -> void:
	if lobby_selected_equipment.is_empty():
		return
	var candidate := lobby_selected_equipment
	var slot := str(candidate.get("equipment_slot", ""))
	var slot_names := {"weapon": "武器", "head": "头饰", "chest": "护甲", "legs": "护腿", "boots": "靴子", "accessory": "饰品"}
	var current: Dictionary = equipped_by_slot.get(slot, {})
	lobby_equipment_list.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "装备属性对比 · " + str(slot_names.get(slot, "装备"))
	title.add_theme_color_override("font_color", Color("#d8bd83"))
	lobby_equipment_list.add_child(title)
	var names := Label.new()
	names.text = "当前：" + str(current.get("name", "未装备")) + "    →    候选：" + str(candidate.get("name", "未知装备"))
	names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_equipment_list.add_child(names)
	var current_stats: Dictionary = current.get("base_stats", {}) if current.get("base_stats", {}) is Dictionary else {}
	var candidate_stats: Dictionary = candidate.get("base_stats", {}) if candidate.get("base_stats", {}) is Dictionary else {}
	var stat_keys: Array = []
	for key in current_stats.keys():
		stat_keys.append(str(key))
	for key in candidate_stats.keys():
		if not stat_keys.has(str(key)):
			stat_keys.append(str(key))
	stat_keys.sort()
	if stat_keys.is_empty():
		var no_stats := Label.new()
		no_stats.text = "暂无属性数据，无法计算数值差异。"
		no_stats.add_theme_color_override("font_color", Color("#aeb8c8"))
		lobby_equipment_list.add_child(no_stats)
	else:
		for key in stat_keys:
			var old_value := int(current_stats.get(key, 0))
			var new_value := int(candidate_stats.get(key, 0))
			var delta := new_value - old_value
			var line := Label.new()
			var delta_text := "持平" if delta == 0 else ("+" + str(delta) if delta > 0 else str(delta))
			line.text = _equipment_stat_display_name(key) + "： " + str(old_value) + "  →  " + str(new_value) + "    (" + delta_text + ")"
			line.add_theme_color_override("font_color", Color("#55c98a") if delta > 0 else (Color("#e07878") if delta < 0 else Color("#aeb8c8")))
			lobby_equipment_list.add_child(line)
	var actions := HBoxContainer.new()
	lobby_equipment_list.add_child(actions)
	var confirm_button := Button.new()
	confirm_button.text = "确认穿戴"
	confirm_button.disabled = lobby_equipment_busy
	confirm_button.pressed.connect(_request_lobby_equip.bind(str(candidate.get("item_id", "")), slot))
	actions.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.text = "取消对比"
	cancel_button.disabled = lobby_equipment_busy
	cancel_button.pressed.connect(_clear_lobby_equipment_selection)
	actions.add_child(cancel_button)

func _clear_lobby_equipment_selection() -> void:
	lobby_selected_equipment = {}
	_render_lobby_equipment_manager()

func _request_lobby_equip(item_id: String, slot: String) -> void:
	if lobby_equipment_busy or item_id.is_empty() or slot.is_empty():
		return
	lobby_equipment_busy = true
	lobby_selected_equipment = {}
	lobby_equipment_detail = {}
	lobby_equipment_status_label.text = "正在穿戴装备……"
	_render_lobby_equipment_manager()
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/characters/current/equipment/equip", {"item_id": item_id, "slot": slot}, true, "lobby_equip_action")

func _request_lobby_unequip(slot: String) -> void:
	if lobby_equipment_busy or slot.is_empty():
		return
	lobby_equipment_busy = true
	lobby_selected_equipment = {}
	lobby_equipment_detail = {}
	lobby_equipment_status_label.text = "正在卸下装备……"
	_render_lobby_equipment_manager()
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/characters/current/equipment/unequip", {"slot": slot}, true, "lobby_unequip_action")

func _format_equipment_stat_summary(raw_stats: Variant) -> String:
	if not (raw_stats is Dictionary) or raw_stats.is_empty():
		return "暂无属性加成"
	var labels := {
		"attack": "攻击", "defense": "防御", "strength": "力量",
		"constitution": "体质", "agility": "敏捷", "spirit": "灵识",
		"vitality": "气血", "max_health": "生命上限", "max_mana": "灵力上限"
	}
	var parts := PackedStringArray()
	var keys: Array = raw_stats.keys()
	keys.sort()
	for key_variant in keys:
		var key := str(key_variant)
		var value := int(raw_stats[key_variant])
		if value == 0:
			continue
		var prefix := "+" if value > 0 else ""
		parts.append(str(labels.get(key, key)) + " " + prefix + str(value))
	if parts.is_empty():
		return "暂无属性加成"
	return "  ·  ".join(parts)

func _equipment_quality_name(quality: int) -> String:
	match quality:
		1: return "普通"
		2: return "优秀"
		3: return "精良"
		4: return "稀有"
		_: return "传说"

func _equipment_quality_color(quality: int) -> Color:
	match quality:
		1: return Color("#b8c0cc")
		2: return Color("#55b879")
		3: return Color("#4b91dc")
		4: return Color("#a66be0")
		_: return Color("#e7ad4d")

func _format_lobby_equipment_summary() -> String:
	if lobby_equipment.is_empty():
		return "装备外观：当前未穿戴装备"
	var slot_names := {"weapon": "武器", "head": "头饰", "chest": "护甲", "legs": "护腿", "boots": "靴子", "accessory": "饰品"}
	var names := PackedStringArray()
	for item_variant in lobby_equipment:
		if item_variant is Dictionary:
			var item: Dictionary = item_variant
			names.append(str(slot_names.get(str(item.get("slot", "")), "装备")) + "·" + str(item.get("name", "未知")))
	return "已穿戴：" + " / ".join(names)

func _on_lobby_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		lobby_preview_dragging = event.pressed
		lobby_preview_last_mouse = event.position
	elif event is InputEventMouseMotion and lobby_preview_dragging and is_instance_valid(lobby_preview_root):
		var delta := event.position - lobby_preview_last_mouse
		lobby_preview_root.rotation.y += delta.x * 0.012
		lobby_preview_last_mouse = event.position

func _toggle_lobby_details() -> void:
	lobby_details_host.visible = not lobby_details_host.visible
	if lobby_details_host.visible:
		details_toggle_button.show()
		details_container.hide()
	else:
		details_container.hide()
		details_toggle_button.hide()

func _show_character_lobby() -> void:
	if not is_instance_valid(lobby_root):
		return
	if is_instance_valid(lobby_body_container):
		lobby_body_container.show()
	for control in auth_controls:
		control.hide()
	for control in login_brand_controls:
		control.hide()
	if is_instance_valid(right_panel_control):
		right_panel_control.hide()
	account_label.hide()
	character_title_label.hide()
	character_input.hide()
	race_label_control.hide()
	race_select.hide()
	cultivation_preview.hide()
	world_label_control.hide()
	world_select.hide()
	action_button.hide()
	details_toggle_button.hide()
	details_container.hide()
	lobby_details_host.hide()
	var character_name := str(current_character.get("name", character_input.text.strip_edges()))
	lobby_name_label.text = character_name if not character_name.is_empty() else "无名灵身"
	var race_id := str(current_character.get("race_id", ""))
	_build_lobby_preview_model()
	var race_name := race_id if not race_id.is_empty() else "未知种族"
	for race in cultivation_races:
		if race is Dictionary and str(race.get("race_id", "")) == race_id:
			race_name = str(race.get("race_name", race_id))
			break
	lobby_race_label.text = "种族：" + race_name
	var progression: Dictionary = current_character.get("progression", {})
	var realm_text := str(progression.get("system_name", "")) + " · " + str(progression.get("realm_name", "待载入")) + str(progression.get("realm_stage_name", ""))
	lobby_realm_label.text = "修炼境界：" + realm_text
	var world_id := str(current_character.get("world_id", current_character.get("birth_world_id", "qingyun_human")))
	var world_name := world_id
	for world in worlds:
		if world is Dictionary and str(world.get("id", "")) == world_id:
			world_name = str(world.get("name", world_id))
			break
	lobby_world_label.text = "当前世界：" + world_name
	var level := int(current_character.get("level", 1))
	lobby_level_label.text = "角色等级  Lv." + str(level)
	var progression_data: Dictionary = current_character.get("progression", {})
	lobby_progress_label.text = "经验：" + _lobby_number_text(progression_data.get("experience", 0)) + "  ·  修为：" + _lobby_number_text(progression_data.get("cultivation", 0)) + "  ·  " + str(progression_data.get("power_tier_name", "未定阶"))
	_render_lobby_cultivation_progress(progression_data)
	lobby_points_label.text = "可分配属性点：" + str(int(progression_data.get("unspent_attribute_points", 0)))
	_render_lobby_character_stats(current_character.get("attributes", {}))
	lobby_status_label.text = "角色资料已载入。准备好后，进入此世洪荒。"
	lobby_equipment = []
	lobby_inventory = []
	lobby_equipment_panel.hide()
	lobby_equipment_status_label.text = "装备外观：正在读取当前穿戴……"
	lobby_enter_button.disabled = false
	lobby_root.show()
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/equipment", {}, true, "lobby_equipment")
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/inventory", {}, true, "lobby_inventory")

func _render_lobby_cultivation_progress(progression: Dictionary) -> void:
	if not is_instance_valid(lobby_cultivation_bar) or not is_instance_valid(lobby_cultivation_label):
		return
	var cultivation := int(progression.get("cultivation", 0))
	var next_stage_value: Variant = progression.get("required_for_next_stage", null)
	var next_realm_value: Variant = progression.get("required_for_next_realm", null)
	var target := 0
	var target_name := ""
	if next_stage_value != null and int(next_stage_value) > 0:
		target = int(next_stage_value)
		target_name = "下一境界阶段"
	elif next_realm_value != null and int(next_realm_value) > 0:
		target = int(next_realm_value)
		target_name = "下一修炼境界"
	if target <= 0:
		lobby_cultivation_label.text = "境界修炼进度：当前境界已达最高阶段"
		lobby_cultivation_bar.max_value = 100
		lobby_cultivation_bar.value = 100
		return
	var ratio := clampf(float(cultivation) / float(target), 0.0, 1.0)
	lobby_cultivation_bar.max_value = 100
	lobby_cultivation_bar.value = ratio * 100.0
	var remaining := maxi(0, target - cultivation)
	lobby_cultivation_label.text = target_name + "：" + _lobby_number_text(cultivation) + " / " + _lobby_number_text(target) + "（还需 " + _lobby_number_text(remaining) + "）"

func _lobby_number_text(value: Variant) -> String:
	if value is float:
		return str(int(value))
	if value is int:
		return str(value)
	return str(value)

func _render_lobby_character_stats(raw_attributes: Variant) -> void:
	if not is_instance_valid(lobby_stats_grid):
		return
	for child in lobby_stats_grid.get_children():
		child.queue_free()
	var attributes: Dictionary = raw_attributes if raw_attributes is Dictionary else {}
	var cards := [
		{"key": "health", "label": "生命", "suffix": ""},
		{"key": "mana", "label": "灵力", "suffix": ""},
		{"key": "attack", "label": "攻击", "suffix": ""},
		{"key": "defense", "label": "防御", "suffix": ""},
		{"key": "strength", "label": "力量", "suffix": ""},
		{"key": "constitution", "label": "体质", "suffix": ""},
		{"key": "agility", "label": "敏捷", "suffix": ""},
		{"key": "spirit", "label": "灵识", "suffix": ""},
		{"key": "vitality", "label": "气血", "suffix": ""}
	]
	for card in cards:
		var key := str(card["key"])
		var value_text := "—"
		if attributes.has(key):
			value_text = _lobby_number_text(attributes[key])
		if key == "health" and attributes.has("max_health"):
			value_text += " / " + _lobby_number_text(attributes["max_health"])
		elif key == "mana" and attributes.has("max_mana"):
			value_text += " / " + _lobby_number_text(attributes["max_mana"])
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(92, 48)
		lobby_stats_grid.add_child(tile)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 1)
		tile.add_child(content)
		var name_label := Label.new()
		name_label.text = str(card["label"])
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color("#9eafc5"))
		content.add_child(name_label)
		var value_label := Label.new()
		value_label.text = value_text
		value_label.add_theme_font_size_override("font_size", 16)
		value_label.add_theme_color_override("font_color", Color("#e7d4ae"))
		content.add_child(value_label)
		var equipment_bonus := _lobby_equipment_bonus_for(key) if key != "health" and key != "mana" else 0
		if equipment_bonus != 0:
			var bonus_label := Label.new()
			bonus_label.text = "基础 " + _lobby_number_text(attributes.get(key, 0)) + "  ·  装备 +" + _lobby_number_text(equipment_bonus)
			bonus_label.add_theme_font_size_override("font_size", 10)
			bonus_label.add_theme_color_override("font_color", Color("#77c99a"))
			content.add_child(bonus_label)
		elif key == "health" or key == "mana":
			var max_key := "max_health" if key == "health" else "max_mana"
			var max_bonus := _lobby_equipment_bonus_for(max_key)
			if max_bonus != 0:
				var bonus_label := Label.new()
				bonus_label.text = "装备上限 +" + _lobby_number_text(max_bonus)
				bonus_label.add_theme_font_size_override("font_size", 10)
				bonus_label.add_theme_color_override("font_color", Color("#77c99a"))
				content.add_child(bonus_label)

func _lobby_equipment_bonus_for(stat_key: String) -> int:
	var total := 0
	for item in lobby_equipment:
		if not (item is Dictionary):
			continue
		var stats: Variant = item.get("base_stats", {})
		if stats is Dictionary:
			total += int(stats.get(stat_key, 0))
	return total

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
		details.text = "种族：" + str(item.get("race_name", "未知")) + "    世界：" + str(item.get("world_name", item.get("world_id", "未知"))) + "\n境界：" + str(item.get("realm_name", "尚未记录")) + " · " + str(item.get("realm_stage", 1)) + "阶    等级：" + str(item.get("level", 1)) + "\n状态：" + str(item.get("status", "未知")) + "    初生：" + str(item.get("created_at", "未知")) + "\n命格：" + str(item.get("fate_aspect", "因果未定")) + "    功德：" + str(item.get("fate_merit", 0)) + "    业力：" + str(item.get("fate_karma", 0)) + "\n命格特性：" + str(item.get("fate_trait_name", "因果未定")) + "——" + str(item.get("fate_trait_description", ""))
		layout.add_child(details)
		if not str(item.get("reincarnated_at", "")).is_empty():
			var transition := Label.new()
			transition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			transition.text = "转入此世的轮回时间：" + str(item.get("reincarnated_at", "")) + "\n前世出生世界：" + str(item.get("previous_world_id", "未知")) + " → 今世出生世界：" + str(item.get("next_world_id", "未知")) + "\n出生路线：" + str(item.get("birth_route_name", "未记录"))
			layout.add_child(transition)
		life_history_box.add_child(card)

func _render_reincarnation_routes() -> void:
	_on_reincarnation_race_selected(reincarnation_race_select.selected)

func _on_reincarnation_race_selected(_index: int) -> void:
	if reincarnation_route_select == null:
		return
	reincarnation_route_select.clear()
	if reincarnation_race_select.item_count == 0:
		return
	var race_id := str(reincarnation_race_select.get_item_metadata(reincarnation_race_select.selected))
	for route_variant in reincarnation_routes:
		if not (route_variant is Dictionary):
			continue
		var route: Dictionary = route_variant
		var route_race := str(route.get("race_id", ""))
		if not route_race.is_empty() and route_race != race_id:
			continue
		var display_name := str(route.get("name", route.get("id", "未知路线")))
		display_name += " · " + str(route.get("world_name", route.get("world_id", "未知世界")))
		reincarnation_route_select.add_item(display_name)
		reincarnation_route_select.set_item_metadata(reincarnation_route_select.item_count - 1, str(route.get("id", "")))
	if reincarnation_route_select.item_count > 0:
		reincarnation_route_select.select(0)
	_update_reincarnation_route_description(reincarnation_route_select.selected)
	if access_token.is_empty():
		reincarnation_inheritance_label.text = "登录后可读取灵魂来世资质。"
	else:
		var preview_race_id := str(reincarnation_race_select.get_item_metadata(reincarnation_race_select.selected))
		reincarnation_inheritance_label.text = "正在计算 " + preview_race_id + " 种族的来世继承……"
		_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/reincarnation-preview?race_id=" + preview_race_id, {}, true, "reincarnation_preview")
	if reincarnation_eligible:
		reincarnation_submit_button.disabled = reincarnation_route_select.item_count == 0

func _render_reincarnation_inheritance(inheritance: Dictionary) -> void:
	var growth_name := str(inheritance.get("source_growth_name", "初生魂团"))
	var growth_stage := int(inheritance.get("source_growth_stage", 1))
	var absorbed_count := int(inheritance.get("source_absorbed_count", 0))
	var dominant := str(inheritance.get("dominant_attribute", ""))
	var attribute_names := {
		"strength": "力量", "constitution": "体质", "agility": "敏捷",
		"spirit": "灵力", "vitality": "气血"
	}
	var applied_lines := PackedStringArray()
	for key in ["strength", "constitution", "agility", "spirit", "vitality"]:
		var bonus := int(inheritance.get("applied_" + key, 0))
		applied_lines.append(str(attribute_names[key]) + " +" + str(bonus))
	var summary := "【灵魂继承预览】吞噬 " + str(absorbed_count) + " 次 · " + growth_name + "（阶段 " + str(growth_stage) + "）"
	if not dominant.is_empty():
		summary += "\n主导魂质：" + str(attribute_names.get(dominant, dominant))
	summary += "\n出生五维：" + " / ".join(applied_lines)
	summary += "\n初始属性：力 " + str(inheritance.get("initial_strength", 5))
	summary += " · 体 " + str(inheritance.get("initial_constitution", 5))
	summary += " · 敏 " + str(inheritance.get("initial_agility", 5))
	summary += " · 灵 " + str(inheritance.get("initial_spirit", 5))
	summary += " · 血 " + str(inheritance.get("initial_vitality", 5))
	summary += "\n衍生：攻击 " + str(inheritance.get("initial_attack", 10))
	summary += " · 防御 " + str(inheritance.get("initial_defense", 5))
	summary += " · 生命 " + str(inheritance.get("initial_max_health", 100))
	summary += " · 灵力 " + str(inheritance.get("initial_max_mana", 50))
	summary += " · 移速 " + str(inheritance.get("initial_movement_speed", 5.0))
	reincarnation_inheritance_label.text = summary

func _update_reincarnation_route_description(_index: int) -> void:
	if reincarnation_route_description == null:
		return
	if reincarnation_route_select.item_count == 0:
		reincarnation_route_description.text = "当前种族暂无可用出生路线。"
		return
	var selected_id := str(reincarnation_route_select.get_item_metadata(reincarnation_route_select.selected))
	var selected_race_id := str(reincarnation_race_select.get_item_metadata(reincarnation_race_select.selected)) if reincarnation_race_select.item_count > 0 else ""
	for route_variant in reincarnation_routes:
		if route_variant is Dictionary and str(route_variant.get("id", "")) == selected_id:
			var route: Dictionary = route_variant
			var danger := int(route.get("danger_level", 1))
			var danger_text := "低" if danger <= 2 else ("中" if danger <= 4 else ("高" if danger <= 7 else "极高"))
			var tags_value: Variant = route.get("resource_tags", [])
			var tags: Array = tags_value if tags_value is Array else []
			var points_value: Variant = route.get("exploration_points", [])
			var points: Array = points_value if points_value is Array else []
			var affinity_value: Variant = route.get("race_affinity", {})
			var affinity: Dictionary = affinity_value if affinity_value is Dictionary else {}
			var race_note := "暂无该种族适应性资料。"
			if affinity.has(selected_race_id) and affinity[selected_race_id] is Dictionary:
				var race_data: Dictionary = affinity[selected_race_id]
				race_note = str(race_data.get("rating", "未知")) + " · " + str(race_data.get("description", ""))
			var point_lines := PackedStringArray()
			for point_value in points:
				if point_value is Dictionary:
					point_lines.append("· " + str(point_value.get("name", "未命名探索点")) + "：" + str(point_value.get("description", "")))
			var description_lines := PackedStringArray()
			description_lines.append(str(route.get("description", "")))
			description_lines.append("区域：" + str(route.get("region_name", "未知区域")) + " · 危险等级：" + danger_text + "（" + str(danger) + "/10）")
			description_lines.append("区域概况：" + str(route.get("region_description", "")))
			description_lines.append("资源：" + (", ".join(PackedStringArray(tags)) if not tags.is_empty() else "暂无资料"))
			description_lines.append("种族适应性：" + race_note)
			description_lines.append("探索点：")
			for point_line in point_lines:
				description_lines.append(point_line)
			if point_lines.is_empty():
				description_lines.append("暂无探索点资料")
			description_lines.append("出生坐标由中心服分配，客户端不能修改。")
			reincarnation_route_description.text = "\n".join(description_lines)
			return

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
	if reincarnation_route_select.item_count == 0:
		reincarnation_status_label.text = "当前种族没有可用的出生路线，请检查世界配置。"
		return
	var race_id := str(reincarnation_race_select.get_item_metadata(reincarnation_race_select.selected))
	var route_id := str(reincarnation_route_select.get_item_metadata(reincarnation_route_select.selected))
	reincarnation_submit_button.disabled = true
	reincarnation_check_button.disabled = true
	reincarnation_status_label.text = "正在由中心服事务创建新肉身……"
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/characters/current/reincarnate", {"name": name, "race_id": race_id, "route_id": route_id}, true, "reincarnate")

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
	var response_json := JSON.new()
	var parse_error := response_json.parse(body_text)
	var parsed: Variant = response_json.data if parse_error == OK else null
	var data: Dictionary = parsed if parsed is Dictionary else {}

	if result != HTTPRequest.RESULT_SUCCESS:
		login_button.disabled = false
		login_button.text = "登录"
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
		character_title_label.text = "创建第一世角色"
		character_input.editable = true
		race_label_control.show()
		race_select.show()
		cultivation_preview.show()
		world_label_control.show()
		world_select.show()
		action_button.disabled = false
		action_button.text = "创建角色并进入世界"
		_set_status("灵魂档案已建立。设置角色名、种族与出生世界后，即可踏入洪荒。")
		_process_queue()
		return

	if response_code < 200 or response_code >= 300:
		if context == "login" or context == "register":
			login_button.disabled = false
			login_button.text = "登录"
		if context == "register" and response_code == 400:
			_set_status("注册失败：账号必须为 3–32 位英文字母、数字或下划线；密码必须为 12–72 个字符。邮箱可以填写有效邮箱。")
		elif context == "soul_check" and response_code == 401:
			access_token = ""
			HHSession.access_token = ""
			_show_login_screen()
			_set_status("登录会话已过期，请重新登录后继续办理轮回。")
		elif context == "life_history":
			life_history_status.text = "历世档案读取失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "soul_memories":
			soul_memory_status.text = "前世记忆读取失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "soul_fate":
			soul_fate_status.text = "因果簿读取失败（HTTP " + str(response_code) + "）：" + body_text
		elif context == "lobby_equipment":
			lobby_equipment_status_label.text = "装备外观读取失败；暂时显示基础服饰。"
		elif context == "lobby_inventory":
			lobby_equipment_status_label.text = "背包读取失败（HTTP " + str(response_code) + "）"
		elif context == "lobby_equip_action" or context == "lobby_unequip_action":
			lobby_equipment_busy = false
			var action_error := "角色仍在世界中，请先退出世界后再更换装备。" if response_code == 409 else "装备操作失败（HTTP " + str(response_code) + "）：" + body_text
			lobby_equipment_status_label.text = action_error
			_render_lobby_equipment_manager()
		elif context == "reincarnation_routes":
			reincarnation_route_select.clear()
			reincarnation_status_label.text = "出生路线读取失败（HTTP " + str(response_code) + "）：" + body_text
			reincarnation_submit_button.disabled = true
		elif context == "reincarnation_preview":
			reincarnation_inheritance_label.text = "来世资质预览失败（HTTP " + str(response_code) + "）：" + body_text
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
		"lobby_inventory":
			lobby_inventory = data.get("items", []) if data.get("items", []) is Array else []
			_render_lobby_equipment_manager()
		"lobby_equipment":
			lobby_equipment = data.get("items", []) if data.get("items", []) is Array else []
			_build_lobby_preview_model()
			_render_lobby_character_stats(current_character.get("attributes", {}))
			lobby_equipment_status_label.text = _format_lobby_equipment_summary()
		"lobby_equip_action", "lobby_unequip_action":
			lobby_equipment_busy = false
			lobby_selected_equipment = {}
			lobby_equipment_status_label.text = "装备已更新，正在刷新背包与外观……"
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/equipment", {}, true, "lobby_equipment")
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/inventory", {}, true, "lobby_inventory")
		"login", "register":
			access_token = str(data.get("access_token", ""))
			if access_token.is_empty():
				_set_status("认证响应缺少 access_token。")
			else:
				login_button.disabled = false
				login_button.text = "登录"
				_save_client_config()
				_show_authenticated_workspace()
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
			var status_character: Dictionary = data.get("character", {})
			var progression: Dictionary = data.get("progression", {})
			current_character["attributes"] = data.get("attributes", {})
			current_character["progression"] = progression
			if not status_character.is_empty():
				current_character["level"] = int(status_character.get("level", current_character.get("level", 1)))
				current_character["world_id"] = str(status_character.get("world_id", current_character.get("world_id", "")))
				current_character["race_id"] = str(status_character.get("race_id", current_character.get("race_id", "")))
			var tier_text := str(progression.get("power_tier_name", "未知层级"))
			var realm_text := str(progression.get("system_name", "")) + " · " + str(progression.get("realm_name", "")) + str(progression.get("realm_stage_name", ""))
			character_title_label.text = "当前角色"
			character_input.editable = false
			race_label_control.hide()
			race_select.hide()
			cultivation_preview.hide()
			world_label_control.hide()
			world_select.hide()
			current_character["progression"] = progression
			_set_status("角色：" + character_input.text + "  ·  " + realm_text + "  ·  " + tier_text + "\n准备就绪，可以进入世界。")
			_show_reincarnation_controls()
			_show_character_lobby()
		"life_history":
			_render_life_history(data.get("items", []))
		"soul_memories":
			_render_soul_memories(data.get("items", []))
		"soul_fate":
			_render_soul_fate(data)
		"reincarnation_routes":
			reincarnation_routes = data.get("routes", [])
			_render_reincarnation_routes()
		"reincarnation_preview":
			var inheritance: Variant = data.get("inheritance", {})
			if inheritance is Dictionary:
				_render_reincarnation_inheritance(inheritance)
		"reincarnation_eligibility":
			reincarnation_check_button.disabled = false
			reincarnation_eligible = bool(data.get("eligible", false))
			var reasons: Array = data.get("reasons", [])
			var realm_name := str(data.get("current_realm_name", "未知"))
			var required_name := str(data.get("required_realm_name", "聚灵境"))
			var trial_done := bool(data.get("trial_completed", false))
			if reincarnation_eligible:
				reincarnation_status_label.text = "投胎资格已满足。灵魂境界：" + realm_name + "；引魂试炼：已完成。选择新肉身名称与种族后确认即可。"
				reincarnation_submit_button.disabled = reincarnation_route_select.item_count == 0
			else:
				reincarnation_status_label.text = "暂不具备投胎资格。当前境界：" + realm_name + "；要求：" + required_name + "；引魂试炼：" + ("已完成" if trial_done else "未完成") + "。\n待完成：" + ", ".join(PackedStringArray(reasons))
				reincarnation_submit_button.disabled = true
		"reincarnate":
			current_character = data
			reincarnation_eligible = false
			reincarnation_status_label.text = "新肉身创建成功，前世肉身已归档。出生路线：" + str(data.get("birth_route_name", "未记录")) + "。此世因果命格：" + str(data.get("fate_aspect", "因果未定")) + "；特性：" + str(data.get("fate_trait_name", "因果未定")) + "（" + str(data.get("fate_trait_description", "")) + "）（功德 " + str(data.get("fate_merit", 0)) + "，业力 " + str(data.get("fate_karma", 0)) + "）。正在申请新出生世界入口……"
			_enqueue(HTTPClient.METHOD_POST, "/api/v1/worlds/enter", {}, true, "enter")
		"character_create":
			current_character = data
			_set_status("角色创建成功，正在载入角色大厅……")
			_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/status", {}, true, "character_status")
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
	login_button.disabled = true
	login_button.text = "正在登录…"
	_set_status("正在登录中心服……")
	_enqueue(HTTPClient.METHOD_POST, "/api/v1/auth/login", {
		"username": username_input.text.strip_edges(),
		"password": password_input.text
	}, false, "login")

func _show_reincarnation_controls() -> void:
	for control in [reincarnation_status_label, reincarnation_name_input, reincarnation_race_select, reincarnation_route_label, reincarnation_route_select, reincarnation_route_description, reincarnation_inheritance_label, reincarnation_check_button, reincarnation_submit_button, life_history_title, life_history_status, life_history_box, life_history_refresh_button, soul_memory_title, soul_memory_status, soul_memory_box, soul_memory_refresh_button, soul_fate_title, soul_fate_status, soul_fate_box, soul_fate_refresh_button]:
		control.show()
	details_toggle_button.show()
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
	_enqueue(HTTPClient.METHOD_GET, "/api/v1/characters/current/reincarnation-routes", {}, true, "reincarnation_routes")
	_request_life_history()
	_request_soul_memories()
	_request_soul_fate()

func _show_character_setup() -> void:
	if is_instance_valid(lobby_root):
		lobby_root.hide()
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
	_set_status("世界服务器验证成功，正在载入当前世界……")
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
