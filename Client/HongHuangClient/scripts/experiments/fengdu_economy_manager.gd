extends Node
## Local Fengdu economy prototype. Durable balances and escrow must move server-side before multiplayer release.

signal economy_changed
signal board_changed

const FIAT_CURRENCY_ID := "ghost_cash"
const FIAT_CURRENCY_NAME := "冥币"
const CULTIVATION_CURRENCY_ID := "nether_stone"
const CULTIVATION_CURRENCY_NAME := "冥石"
const STARTING_BALANCE := 5000
const BASE_LISTING_FEE := 10
const LISTING_FEE_RATE := 0.03
const COMPLETION_TAX_RATE := 0.05
const MIN_REWARD := 50
const MAX_REWARD := 1000000

var _wallets: Dictionary = {"local_player": STARTING_BALANCE}
var _stone_wallets: Dictionary = {"local_player": 500}
var _treasury := 10000
var _stone_treasury := 2000
var _escrow_total := 0
var _stone_escrow_total := 0
var _tasks: Dictionary = {}
var _next_task_number := 1
var _transactions: Array[Dictionary] = []
var _reward_claims: Dictionary = {}
var _next_transaction_number := 1


func _ready() -> void:
	_record_transaction("opening_player_balance", "local_player", STARTING_BALANCE, 0, 0, "本地演示账户初始余额", FIAT_CURRENCY_ID)
	_record_transaction("opening_stone_balance", "local_player", int(_stone_wallets.get("local_player", 0)), 0, 0, "本地演示账户初始冥石", CULTIVATION_CURRENCY_ID)
	_record_transaction("opening_treasury", "city_treasury", 0, _treasury, 0, "城主府初始库银", FIAT_CURRENCY_ID)
	_record_transaction("opening_stone_treasury", "city_treasury", 0, _stone_treasury, 0, "城主府初始冥石储备", CULTIVATION_CURRENCY_ID)
	_seed_city_notices()


func _seed_city_notices() -> void:
	var notices := [
		{"id": "city_notice_001", "title": "鬼市寻回遗失魂灯", "description": "协助鬼市商贩找回遗失在东侧巷道的魂灯。", "publisher_id": "ghost_market_vendor", "publisher_name": "鬼市灵材商", "reward": 180, "currency_id": FIAT_CURRENCY_ID},
		{"id": "city_notice_002", "title": "魂坊运送安魂木", "description": "将一批安魂木从城西仓房送至引魂驿站。", "publisher_id": "soul_district_craftsman", "publisher_name": "魂坊工匠", "reward": 260, "currency_id": FIAT_CURRENCY_ID},
		{"id": "cultivation_notice_001", "title": "清理鬼市阴煞残迹", "description": "清理鬼市旧巷残留阴煞，需具备基础幽冥修为。", "publisher_id": "yin_market_guard", "publisher_name": "鬼市巡检", "reward": 12, "currency_id": CULTIVATION_CURRENCY_ID},
		{"id": "cultivation_notice_002", "title": "寻回失落的幽冥灵材", "description": "前往城外采集幽冥灵材并交付鬼市灵材商。", "publisher_id": "nether_material_vendor", "publisher_name": "冥材商", "reward": 20, "currency_id": CULTIVATION_CURRENCY_ID}
	]
	for notice in notices:
		var reward := int(notice["reward"])
		var currency_id := str(notice.get("currency_id", FIAT_CURRENCY_ID))
		var is_stone := currency_id == CULTIVATION_CURRENCY_ID
		var treasury_balance := _stone_treasury if is_stone else _treasury
		if treasury_balance < reward:
			continue
		if is_stone:
			_stone_treasury -= reward
			_stone_escrow_total += reward
		else:
			_treasury -= reward
			_escrow_total += reward
		_record_transaction("system_escrow", "city_treasury", 0, -reward, reward, "城主府拨付示范悬赏：" + str(notice["title"]), currency_id)
		_tasks[str(notice["id"])] = {
			"id": str(notice["id"]),
			"title": str(notice["title"]),
			"description": str(notice["description"]),
			"publisher_id": str(notice["publisher_id"]),
			"publisher_name": str(notice["publisher_name"]),
			"reward": reward,
			"currency_id": currency_id,
			"listing_fee": 0,
			"status": "open",
			"worker_id": "",
			"created_at": int(Time.get_unix_time_from_system()),
			"system_notice": true
		}


func get_wallet_snapshot(player_id: String = "local_player", currency_id: String = FIAT_CURRENCY_ID) -> Dictionary:
	var is_stone := currency_id == CULTIVATION_CURRENCY_ID
	return {"player_id": player_id, "balance": int((_stone_wallets if is_stone else _wallets).get(player_id, 0)), "currency": CULTIVATION_CURRENCY_NAME if is_stone else FIAT_CURRENCY_NAME, "currency_id": currency_id, "treasury": _stone_treasury if is_stone else _treasury, "escrow": _stone_escrow_total if is_stone else _escrow_total}


func get_transaction_history(limit: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index := maxi(0, _transactions.size() - maxi(1, limit))
	for index in range(_transactions.size() - 1, start_index - 1, -1):
		result.append(_transactions[index].duplicate(true))
	return result


func get_treasury_snapshot(currency_id: String = FIAT_CURRENCY_ID) -> Dictionary:
	var is_stone := currency_id == CULTIVATION_CURRENCY_ID
	return {"balance": _stone_treasury if is_stone else _treasury, "escrow": _stone_escrow_total if is_stone else _escrow_total, "currency": CULTIVATION_CURRENCY_NAME if is_stone else FIAT_CURRENCY_NAME}


func _record_transaction(category: String, player_id: String, player_delta: int, treasury_delta: int, escrow_delta: int, note: String, currency_id: String = FIAT_CURRENCY_ID) -> void:
	var transaction_id := "fengdu_tx_%08d" % _next_transaction_number
	_next_transaction_number += 1
	_transactions.append({
		"id": transaction_id,
		"category": category,
		"player_id": player_id,
		"player_delta": player_delta,
		"treasury_delta": treasury_delta,
		"escrow_delta": escrow_delta,
		"currency_id": currency_id,
		"currency_name": CULTIVATION_CURRENCY_NAME if currency_id == CULTIVATION_CURRENCY_ID else FIAT_CURRENCY_NAME,
		"balance_after": int((_stone_wallets if currency_id == CULTIVATION_CURRENCY_ID else _wallets).get(player_id, 0)),
		"treasury_after": _stone_treasury if currency_id == CULTIVATION_CURRENCY_ID else _treasury,
		"escrow_after": _stone_escrow_total if currency_id == CULTIVATION_CURRENCY_ID else _escrow_total,
		"note": note,
		"created_at": int(Time.get_unix_time_from_system())
	})


func grant_quest_reward(player_id: String, quest_id: String, reward_key: String, amount: int, currency_id: String = CULTIVATION_CURRENCY_ID) -> Dictionary:
	if player_id.is_empty() or quest_id.is_empty() or reward_key.is_empty() or amount <= 0:
		return {"ok": false, "reason": "任务奖励参数无效。"}
	if _reward_claims.has(reward_key):
		return {"ok": false, "reason": "该轮任务奖励已经结算。"}
	var balances: Dictionary = _stone_wallets if currency_id == CULTIVATION_CURRENCY_ID else _wallets
	var before := int(balances.get(player_id, 0))
	balances[player_id] = before + amount
	_reward_claims[reward_key] = true
	_record_transaction("quest_reward", player_id, amount, 0, 0, "完成差事：" + quest_id, currency_id)
	economy_changed.emit()
	return {"ok": true, "amount": amount, "balance": int(balances[player_id]), "currency_id": currency_id}


func get_board_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task_id in _tasks:
		var task: Dictionary = _tasks[task_id]
		result.append(task.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("created_at", 0)) > int(b.get("created_at", 0)))
	return result


func get_listing_fee(reward: int) -> int:
	return BASE_LISTING_FEE + ceili(float(maxi(0, reward)) * LISTING_FEE_RATE)


func publish_task(publisher_id: String, title: String, description: String, reward: int, currency_id: String = CULTIVATION_CURRENCY_ID) -> Dictionary:
	var clean_title := title.strip_edges()
	var clean_description := description.strip_edges()
	if publisher_id.is_empty() or clean_title.length() < 2 or clean_title.length() > 32:
		return {"ok": false, "reason": "任务标题需为 2 至 32 个字。"}
	if clean_description.length() < 4 or clean_description.length() > 240:
		return {"ok": false, "reason": "任务说明需为 4 至 240 个字。"}
	if currency_id != FIAT_CURRENCY_ID and currency_id != CULTIVATION_CURRENCY_ID:
		return {"ok": false, "reason": "任务货币类型无效。"}
	if reward < MIN_REWARD or reward > MAX_REWARD:
		return {"ok": false, "reason": "悬赏金额范围为 50 至 1,000,000。"}
	var fee := get_listing_fee(reward)
	var is_stone := currency_id == CULTIVATION_CURRENCY_ID
	var balances: Dictionary = _stone_wallets if is_stone else _wallets
	var balance := int(balances.get(publisher_id, 0))
	if balance < reward + fee:
		return {"ok": false, "reason": "余额不足，需要 %d %s（悬赏 %d + 发布费 %d）。" % [reward + fee, CULTIVATION_CURRENCY_NAME if is_stone else FIAT_CURRENCY_NAME, reward, fee]}
	balances[publisher_id] = balance - fee
	if is_stone:
		_stone_treasury += fee
	else:
		_treasury += fee
	_record_transaction("task_listing_fee", publisher_id, -fee, fee, 0, "发布公共委托手续费", currency_id)
	balances[publisher_id] = int(balances.get(publisher_id, 0)) - reward
	if is_stone:
		_stone_escrow_total += reward
	else:
		_escrow_total += reward
	_record_transaction("task_escrow_lock", publisher_id, -reward, 0, reward, "公共委托悬赏托管", currency_id)
	var task_id := "public_job_%06d" % _next_task_number
	_next_task_number += 1
	_tasks[task_id] = {
		"id": task_id,
		"title": clean_title,
		"description": clean_description,
		"publisher_id": publisher_id,
		"publisher_name": "城中委托人" if publisher_id == "local_player" else publisher_id,
		"reward": reward,
		"currency_id": currency_id,
		"listing_fee": fee,
		"status": "open",
		"worker_id": "",
		"created_at": int(Time.get_unix_time_from_system())
	}
	economy_changed.emit()
	board_changed.emit()
	var published_task: Dictionary = _tasks[task_id]
	return {"ok": true, "task": published_task.duplicate(true)}


func accept_task(task_id: String, worker_id: String) -> Dictionary:
	if not _tasks.has(task_id) or worker_id.is_empty():
		return {"ok": false, "reason": "任务不存在或接取者无效。"}
	var task: Dictionary = _tasks[task_id]
	if str(task.get("status", "")) != "open":
		return {"ok": false, "reason": "该任务已被接取或关闭。"}
	if str(task.get("publisher_id", "")) == worker_id:
		return {"ok": false, "reason": "不能接取自己发布的任务。"}
	task["worker_id"] = worker_id
	task["status"] = "accepted"
	_tasks[task_id] = task
	board_changed.emit()
	return {"ok": true, "task": task.duplicate(true)}


func complete_task(task_id: String, worker_id: String) -> Dictionary:
	if not _tasks.has(task_id):
		return {"ok": false, "reason": "任务不存在。"}
	var task: Dictionary = _tasks[task_id]
	if str(task.get("status", "")) != "accepted" or str(task.get("worker_id", "")) != worker_id:
		return {"ok": false, "reason": "只有当前接取者可以提交完成。"}
	var gross := int(task.get("reward", 0))
	var currency_id := str(task.get("currency_id", FIAT_CURRENCY_ID))
	var is_stone := currency_id == CULTIVATION_CURRENCY_ID
	var balances: Dictionary = _stone_wallets if is_stone else _wallets
	var tax := ceili(float(gross) * COMPLETION_TAX_RATE)
	var payout := gross - tax
	balances[worker_id] = int(balances.get(worker_id, 0)) + payout
	if is_stone:
		_stone_treasury += tax
		_stone_escrow_total = maxi(0, _stone_escrow_total - gross)
	else:
		_treasury += tax
		_escrow_total = maxi(0, _escrow_total - gross)
	_record_transaction("task_payout", worker_id, payout, tax, -gross, "完成公共委托：" + task_id, currency_id)
	task["status"] = "completed"
	task["tax_paid"] = tax
	task["paid_out"] = payout
	_tasks[task_id] = task
	economy_changed.emit()
	board_changed.emit()
	return {"ok": true, "payout": payout, "tax": tax}


func cancel_task(task_id: String, publisher_id: String) -> Dictionary:
	if not _tasks.has(task_id):
		return {"ok": false, "reason": "任务不存在。"}
	var task: Dictionary = _tasks[task_id]
	if str(task.get("publisher_id", "")) != publisher_id or str(task.get("status", "")) != "open":
		return {"ok": false, "reason": "仅发布者可以取消尚未接取的任务。"}
	var reward := int(task.get("reward", 0))
	var currency_id := str(task.get("currency_id", FIAT_CURRENCY_ID))
	var is_stone := currency_id == CULTIVATION_CURRENCY_ID
	var balances: Dictionary = _stone_wallets if is_stone else _wallets
	balances[publisher_id] = int(balances.get(publisher_id, 0)) + reward
	if is_stone: _stone_escrow_total = maxi(0, _stone_escrow_total - reward)
	else: _escrow_total = maxi(0, _escrow_total - reward)
	_record_transaction("task_escrow_refund", publisher_id, reward, 0, -reward, "取消公共委托退回悬赏：" + task_id, currency_id)
	task["status"] = "cancelled"
	_tasks[task_id] = task
	economy_changed.emit()
	board_changed.emit()
	return {"ok": true, "refund": reward}


func get_task(task_id: String) -> Dictionary:
	if not _tasks.has(task_id):
		return {}
	var task: Dictionary = _tasks[task_id]
	return task.duplicate(true)
