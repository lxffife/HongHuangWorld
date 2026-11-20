extends Node
## Local prototype only. Quest completion/rewards are not authoritative or persistent.

signal quest_updated(quest_data: Dictionary)
signal quest_log_changed

var _quests: Dictionary = {}


func _ready() -> void:
	_seed_quests()


func _seed_quests() -> void:
	_quests = {
		"black_soul_document": {
			"id": "black_soul_document",
			"giver_id": "black_impermanence",
			"giver_name": "黑无常 · 范无救",
			"title": "拘魂文牒核验",
			"summary": "协助核对一份新到亡魂的拘魂文牒，确认魂籍与功过记录。",
			"reward_preview": "阴司差役资历记录（演示奖励）",
			"status": "available",
			"objectives": [
				{"target_id": "ghost_registry", "label": "前往鬼籍司核对亡魂身份"},
				{"target_id": "merit_bureau", "label": "前往功过司复核功过记录"}
			],
			"progress": 0
		},
		"white_soul_registration": {
			"id": "white_soul_registration",
			"giver_id": "white_impermanence",
			"giver_name": "白无常 · 谢必安",
			"title": "新魂引登记",
			"summary": "陪同一名初入酆都的新魂完成登记，并确认后续引导去向。",
			"reward_preview": "引魂使信任记录（演示奖励）",
			"status": "available",
			"objectives": [
				{"target_id": "soul_waystation", "label": "前往引魂驿站登记来历"},
				{"target_id": "reincarnation_bureau", "label": "前往轮回司了解后续审理流程"}
			],
			"progress": 0
		},
		"ox_gate_records": {
			"id": "ox_gate_records",
			"giver_id": "ox_head",
			"giver_name": "牛头将军",
			"title": "南幽门巡检记录",
			"summary": "协助整理南门来魂核验记录，排查异常魂籍与治安隐患。",
			"reward_preview": "南门守备认可（演示奖励）",
			"status": "available",
			"objectives": [
				{"target_id": "ghost_registry", "label": "向鬼籍司核对入城魂籍样本"},
				{"target_id": "patrol_office", "label": "向巡城司提交异常巡检记录"}
			],
			"progress": 0
		},
		"horse_patrol_report": {
			"id": "horse_patrol_report",
			"giver_id": "horse_face",
			"giver_name": "马面将军",
			"title": "南门巡防回报",
			"summary": "巡查城内治安联络点，确认南门周边巡防情报。",
			"reward_preview": "巡防贡献记录（演示奖励）",
			"status": "available",
			"objectives": [
				{"target_id": "patrol_office", "label": "前往巡城司领取巡防简报"},
				{"target_id": "ghost_market", "label": "前往万魂鬼市核实街区情报"}
			],
			"progress": 0
		}
	}
	quest_log_changed.emit()


func get_quest(quest_id: String) -> Dictionary:
	if not _quests.has(quest_id):
		return {}
	var quest: Dictionary = _quests[quest_id]
	return quest.duplicate(true)


func get_quest_for_giver(giver_id: String) -> Dictionary:
	for quest_id in _quests:
		var quest: Dictionary = _quests[quest_id]
		if str(quest.get("giver_id", "")) == giver_id:
			return quest.duplicate(true)
	return {}


func get_all_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in _quests:
		var quest: Dictionary = _quests[quest_id]
		result.append(quest.duplicate(true))
	return result


func accept_quest(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	if str(quest.get("status", "")) != "available":
		return false
	quest["status"] = "active"
	quest["progress"] = 0
	_quests[quest_id] = quest
	_emit_quest_update(quest_id)
	return true


func notify_interaction(target_id: String) -> bool:
	if target_id.is_empty():
		return false
	var changed := false
	for quest_id in _quests:
		var quest: Dictionary = _quests[quest_id]
		if str(quest.get("status", "")) != "active":
			continue
		var objectives: Array = quest.get("objectives", [])
		var progress := int(quest.get("progress", 0))
		if progress >= objectives.size():
			continue
		var objective: Dictionary = objectives[progress]
		if str(objective.get("target_id", "")) != target_id:
			continue
		quest["progress"] = progress + 1
		if int(quest["progress"]) >= objectives.size():
			quest["status"] = "completed"
		_quests[quest_id] = quest
		_emit_quest_update(quest_id)
		changed = true
	return changed


func _emit_quest_update(quest_id: String) -> void:
	quest_updated.emit(get_quest(quest_id))
	quest_log_changed.emit()
