extends CanvasLayer
## Public task board and wallet UI for the Fengdu greybox.

signal closed

var _economy: Node
var _panel: PanelContainer
var _task_list: VBoxContainer
var _wallet_label: Label
var _feedback: Label
var _history_label: Label
var _title_input: LineEdit
var _description_input: LineEdit
var _reward_input: SpinBox
var _currency_option: OptionButton
var _active_currency_id := "nether_stone"
var _is_open := false


func configure(economy: Node) -> void:
	_economy = economy
	if _economy != null and not _economy.is_connected("board_changed", Callable(self, "refresh")):
		_economy.connect("board_changed", Callable(self, "refresh"))
	if _economy != null and not _economy.is_connected("economy_changed", Callable(self, "refresh")):
		_economy.connect("economy_changed", Callable(self, "refresh"))
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


func close_board() -> void:
	if not _is_open:
		return
	_is_open = false
	_panel.visible = false
	closed.emit()


func refresh() -> void:
	if _economy == null or _wallet_label == null:
		return
	var wallet: Dictionary = _economy.call("get_wallet_snapshot", "local_player", _active_currency_id)
	var currency_name := str(wallet.get("currency", "冥石"))
	_wallet_label.text = "%s账户：%s    城主府：%s    托管悬赏：%s" % [currency_name, _format_amount(int(wallet.get("balance", 0))), _format_amount(int(wallet.get("treasury", 0))), _format_amount(int(wallet.get("escrow", 0)))]
	if _task_list == null:
		return
	for child in _task_list.get_children():
		child.queue_free()
	var all_tasks: Array = _economy.call("get_board_tasks")
	var tasks: Array = []
	for task in all_tasks:
		if str(task.get("currency_id", "ghost_cash")) == _active_currency_id:
			tasks.append(task)
	if tasks.is_empty():
		var empty := Label.new()
		empty.text = "当前市场暂无委托。可以发布一份悬赏，或稍后再来查看。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_task_list.add_child(empty)
	for item in tasks:
		_add_task_card(item)
	if _history_label != null:
		var history: Array = _economy.call("get_transaction_history", 8)
		var history_lines: PackedStringArray = []
		for entry in history:
			var player_delta := int(entry.get("player_delta", 0))
			var treasury_delta := int(entry.get("treasury_delta", 0))
			var sign_text := "+" if player_delta > 0 else ""
			var treasury_sign := "+" if treasury_delta > 0 else ""
			history_lines.append("%s  玩家 %s%s  府库 %s%s  %s" % [_transaction_category_text(str(entry.get("category", ""))), sign_text, _format_amount(player_delta), treasury_sign, _format_amount(treasury_delta), str(entry.get("note", ""))])
		_history_label.text = "\n".join(history_lines) if not history_lines.is_empty() else "暂无交易流水。"
		_history_label.tooltip_text = "最近 8 笔经济流水（本地原型）"


func _publish_pressed() -> void:
	if _economy == null:
		return
	var reward := int(_reward_input.value)
	var result: Dictionary = _economy.call("publish_task", "local_player", _title_input.text, _description_input.text, reward, _active_currency_id)
	_feedback.text = str(result.get("reason", "委托已发布。"))
	if bool(result.get("ok", false)):
		_title_input.clear()
		_description_input.clear()
	refresh()


func _accept_pressed(task_id: String) -> void:
	var result: Dictionary = _economy.call("accept_task", task_id, "local_player")
	_feedback.text = str(result.get("reason", "已接取任务。"))
	refresh()


func _complete_pressed(task_id: String) -> void:
	var result: Dictionary = _economy.call("complete_task", task_id, "local_player")
	if bool(result.get("ok", false)):
		_feedback.text = "验收完成：到账 %s，城主府税收 %s。" % [_format_amount(int(result.get("payout", 0))), _format_amount(int(result.get("tax", 0)))]
	else:
		_feedback.text = str(result.get("reason", "结算失败。"))
	refresh()


func _cancel_pressed(task_id: String) -> void:
	var result: Dictionary = _economy.call("cancel_task", task_id, "local_player")
	_feedback.text = str(result.get("reason", "已取消委托并退回托管悬赏。"))
	refresh()


func _add_task_card(task: Dictionary) -> void:
	var card := PanelContainer.new()
	_task_list.add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = str(task.get("title", "无名委托"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	heading.add_child(title)
	var status := Label.new()
	status.text = _status_text(str(task.get("status", "")))
	heading.add_child(status)
	var details := Label.new()
	var currency_name := "冥石" if str(task.get("currency_id", "nether_stone")) == "nether_stone" else "冥币"
	details.text = "%s\n发布者：%s    悬赏：%s %s    发布费：%s %s" % [str(task.get("description", "")), str(task.get("publisher_name", "匿名")), _format_amount(int(task.get("reward", 0))), currency_name, _format_amount(int(task.get("listing_fee", 0))), currency_name]
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var status_value := str(task.get("status", ""))
	var publisher := str(task.get("publisher_id", ""))
	if status_value == "open" and publisher != "local_player":
		var accept := Button.new()
		accept.text = "接取悬赏"
		accept.pressed.connect(_accept_pressed.bind(str(task.get("id", ""))))
		actions.add_child(accept)
	if status_value == "accepted" and str(task.get("worker_id", "")) == "local_player":
		var complete := Button.new()
		complete.text = "提交完成（演示验收）"
		complete.pressed.connect(_complete_pressed.bind(str(task.get("id", ""))))
		actions.add_child(complete)
	if status_value == "open" and publisher == "local_player":
		var cancel := Button.new()
		cancel.text = "取消并退回悬赏"
		cancel.pressed.connect(_cancel_pressed.bind(str(task.get("id", ""))))
		actions.add_child(cancel)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -390.0
	_panel.offset_top = -300.0
	_panel.offset_right = 390.0
	_panel.offset_bottom = 300.0
	_panel.visible = false
	root.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "酆都悬赏任务大厅"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(close_board)
	header.add_child(close)
	_wallet_label = Label.new()
	column.add_child(_wallet_label)
	var market_row := HBoxContainer.new()
	column.add_child(market_row)
	var market_label := Label.new()
	market_label.text = "任务市场："
	market_row.add_child(market_label)
	_currency_option = OptionButton.new()
	_currency_option.add_item("修炼悬赏 · 冥石", 0)
	_currency_option.add_item("凡俗事务 · 冥币", 1)
	_currency_option.select(0)
	_currency_option.item_selected.connect(_on_market_selected)
	market_row.add_child(_currency_option)
	var audience_hint := Label.new()
	audience_hint.text = "修炼者优先：寻魂、除祟、护送灵材、探索险地。凡俗事务独立使用冥币结算。"
	audience_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	audience_hint.add_theme_font_size_override("font_size", 11)
	column.add_child(audience_hint)
	var policy := Label.new()
	policy.text = "规则：不同市场独立记账；发布时冻结全额悬赏；发布费 = 10 + 悬赏的 3%；完成结算时城主府收取 5% 税。发布费不退，未接取任务可取消并退回悬赏。冥石可交易及用于修炼，冥币仅用于凡俗交易。"
	policy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	policy.add_theme_font_size_override("font_size", 11)
	column.add_child(policy)
	column.add_child(HSeparator.new())
	var form_title := Label.new()
	form_title.text = "发布新委托"
	column.add_child(form_title)
	_title_input = LineEdit.new()
	_title_input.placeholder_text = "任务标题（2 至 32 字）"
	column.add_child(_title_input)
	_description_input = LineEdit.new()
	_description_input.placeholder_text = "任务说明（4 至 240 字）"
	column.add_child(_description_input)
	var form_row := HBoxContainer.new()
	column.add_child(form_row)
	var reward_label := Label.new()
	reward_label.text = "悬赏金额"
	form_row.add_child(reward_label)
	_reward_input = SpinBox.new()
	_reward_input.min_value = 50
	_reward_input.max_value = 1000000
	_reward_input.step = 10
	_reward_input.value = 200
	_reward_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_row.add_child(_reward_input)
	var publish := Button.new()
	publish.text = "支付费用并发布"
	publish.pressed.connect(_publish_pressed)
	form_row.add_child(publish)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_feedback)
	column.add_child(HSeparator.new())
	var board_title := Label.new()
	board_title.text = "全城公开悬赏"
	column.add_child(board_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_task_list = VBoxContainer.new()
	_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_task_list)
	var history_title := Label.new()
	history_title.text = "最近交易流水"
	column.add_child(history_title)
	_history_label = Label.new()
	_history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_label.add_theme_font_size_override("font_size", 10)
	column.add_child(_history_label)
	refresh()


func _on_market_selected(index: int) -> void:
	_active_currency_id = "ghost_cash" if index == 1 else "nether_stone"
	_feedback.text = "已切换至凡俗事务市场。" if index == 1 else "已切换至修炼悬赏市场。"
	refresh()


func _format_amount(value: int) -> String:
	return String.num_int64(value)


func _transaction_category_text(category: String) -> String:
	match category:
		"quest_reward":
			return "差事奖励"
		"task_listing_fee":
			return "任务发布费"
		"task_escrow_lock":
			return "悬赏托管"
		"task_payout":
			return "悬赏结算"
		"task_escrow_refund":
			return "悬赏退款"
		"system_escrow":
			return "城主府拨款"
		"opening_player_balance":
			return "玩家初始余额"
		"opening_treasury":
			return "府库初始库银"
	return "其他流水"


func _status_text(status: String) -> String:
	match status:
		"open":
			return "待接取"
		"accepted":
			return "履约中"
		"completed":
			return "已结算"
		"cancelled":
			return "已取消"
	return "未知状态"
