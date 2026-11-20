extends Node
## Local Fengdu economy prototype. Durable balances and escrow must move server-side before multiplayer release.

signal economy_changed
signal board_changed

const CURRENCY_NAME := "冥币"
const STARTING_BALANCE := 5000
const BASE_LISTING_FEE := 10
const LISTING_FEE_RATE := 0.03
const COMPLETION_TAX_RATE := 0.05
const MIN_REWARD := 50
const MAX_REWARD := 1000000

var _wallets: Dictionary = {"local_player": STARTING_BALANCE}
var _treasury := 10000
var _escrow_total := 0
var _tasks: Dictionary = {}
var _next_task_number := 1


func _ready() -> void:
	_seed_city_notices()


func _seed_city_notices() -> void:
	var notices := [
		{"id": "city_notice_001", "title": "鬼市寻回遗失魂灯", "description": "协助鬼市商贩找回遗失在东侧巷道的魂灯。", "publisher_id": "ghost_market_vendor", "publisher_name": "鬼市灵材商", "reward": 180},
		{"id": "city_notice_002", "title": "魂坊运送安魂木", "description": "将一批安魂木从城西仓房送至引魂驿站。", "publisher_id": "soul_district_craftsman", "publisher_name": "魂坊工匠", "reward": 260}
	]
	for notice in notices:
		var reward := int(notice["reward"])
		if _treasury < reward:
			continue
		_treasury -= reward
		_escrow_total += reward
		_tasks[str(notice["id"])] = {
			"id": str(notice["id"]),
			"title": str(notice["title"]),
			"description": str(notice["description"]),
			"publisher_id": str(notice["publisher_id"]),
			"publisher_name": str(notice["publisher_name"]),
			"reward": reward,
			"listing_fee": 0,
			"status": "open",
			"worker_id": "",
			"created_at": int(Time.get_unix_time_from_system()),
			"system_notice": true
		}


func get_wallet_snapshot(player_id: String = "local_player") -> Dictionary:
	return {
		"player_id": player_id,
		"balance": int(_wallets.get(player_id, 0)),
		"currency": CURRENCY_NAME,
		"treasury": _treasury,
		"escrow": _escrow_total
	}


func get_board_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task_id in _tasks:
		var task: Dictionary = _tasks[task_id]
		result.append(task.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("created_at", 0)) > int(b.get("created_at", 0)))
	return result


func get_listing_fee(reward: int) -> int:
	return BASE_LISTING_FEE + ceili(float(maxi(0, reward)) * LISTING_FEE_RATE)


func publish_task(publisher_id: String, title: String, description: String, reward: int) -> Dictionary:
	var clean_title := title.strip_edges()
	var clean_description := description.strip_edges()
	if publisher_id.is_empty() or clean_title.length() < 2 or clean_title.length() > 32:
		return {"ok": false, "reason": "任务标题需为 2 至 32 个字。"}
	if clean_description.length() < 4 or clean_description.length() > 240:
		return {"ok": false, "reason": "任务说明需为 4 至 240 个字。"}
	if reward < MIN_REWARD or reward > MAX_REWARD:
		return {"ok": false, "reason": "悬赏金额范围为 50 至 1,000,000 冥币。"}
	var fee := get_listing_fee(reward)
	var balance := int(_wallets.get(publisher_id, 0))
	if balance < reward + fee:
		return {"ok": false, "reason": "余额不足，需要 %d 冥币（悬赏 %d + 发布费 %d）。" % [reward + fee, reward, fee]}
	_wallets[publisher_id] = balance - reward - fee
	_treasury += fee
	_escrow_total += reward
	var task_id := "public_job_%06d" % _next_task_number
	_next_task_number += 1
	_tasks[task_id] = {
		"id": task_id,
		"title": clean_title,
		"description": clean_description,
		"publisher_id": publisher_id,
		"publisher_name": "城中委托人" if publisher_id == "local_player" else publisher_id,
		"reward": reward,
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
	var tax := ceili(float(gross) * COMPLETION_TAX_RATE)
	var payout := gross - tax
	_wallets[worker_id] = int(_wallets.get(worker_id, 0)) + payout
	_treasury += tax
	_escrow_total = maxi(0, _escrow_total - gross)
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
	_wallets[publisher_id] = int(_wallets.get(publisher_id, 0)) + reward
	_escrow_total = maxi(0, _escrow_total - reward)
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
