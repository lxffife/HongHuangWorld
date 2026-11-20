extends Node
## Local quest prototype. Server authority and durable persistence are intentionally absent.

signal quest_updated(quest_data: Dictionary)
signal quest_log_changed
signal tracked_quest_changed(quest_data: Dictionary)

const OBJECTIVE_TYPES := ["interact", "collect", "defeat", "escort", "investigate", "deliver"]
const ACTIVE_STATUS := "active"
const COMPLETED_STATUS := "completed"

var _quests: Dictionary = {}
var _tracked_quest_id := ""


func _ready() -> void:
	_seed_quests()


func _seed_quests() -> void:
	_quests = {
		"black_soul_document": {
			"id": "black_soul_document", "giver_id": "black_impermanence",
			"giver_name": "黑无常 · 范无救", "title": "拘魂文牒核验",
			"summary": "协助核对一份新到亡魂的拘魂文牒，确认魂籍与功过记录。",
			"reward_preview": "阴司差役资历记录（演示奖励）", "status": "available",
			"prerequisites": [], "repeatable": false,
			"objectives": [
				{"type": "interact", "target_id": "ghost_registry", "label": "前往鬼籍司核对亡魂身份", "required_count": 1},
				{"type": "investigate", "target_id": "merit_bureau", "label": "前往功过司复核功过记录", "required_count": 1}
			], "progress": 0, "objective_progress": 0
		},
		"white_soul_registration": {
			"id": "white_soul_registration", "giver_id": "white_impermanence",
			"giver_name": "白无常 · 谢必安", "title": "新魂引登记",
			"summary": "陪同一名初入酆都的新魂完成登记，并确认后续引导去向。",
			"reward_preview": "引魂使信任记录（演示奖励）", "status": "available",
			"prerequisites": [], "repeatable": false,
			"objectives": [
				{"type": "interact", "target_id": "soul_waystation", "label": "前往引魂驿站登记来历", "required_count": 1},
				{"type": "interact", "target_id": "reincarnation_bureau", "label": "前往轮回司了解后续审理流程", "required_count": 1}
			], "progress": 0, "objective_progress": 0
		},
		"ox_gate_records": {
			"id": "ox_gate_records", "giver_id": "ox_head",
			"giver_name": "牛头将军", "title": "南幽门巡检记录",
			"summary": "协助整理南门来魂核验记录，排查异常魂籍与治安隐患。",
			"reward_preview": "南门守备认可（演示奖励）", "status": "available",
			"prerequisites": [], "repeatable": false,
			"objectives": [
				{"type": "interact", "target_id": "ghost_registry", "label": "向鬼籍司核对入城魂籍样本", "required_count": 1},
				{"type": "deliver", "target_id": "patrol_office", "label": "向巡城司提交异常巡检记录", "required_count": 1}
			], "progress": 0, "objective_progress": 0
		},
		"horse_patrol_report": {
			"id": "horse_patrol_report", "giver_id": "horse_face",
			"giver_name": "马面将军", "title": "南门巡防回报",
			"summary": "巡查城内治安联络点，确认南门周边巡防情报。",
			"reward_preview": "巡防贡献记录（演示奖励）", "status": "available",
			"prerequisites": [], "repeatable": false,
			"objectives": [
				{"type": "interact", "target_id": "patrol_office", "label": "前往巡城司领取巡防简报", "required_count": 1},
				{"type": "investigate", "target_id": "ghost_market", "label": "前往万魂鬼市核实街区情报", "required_count": 1}
			], "progress": 0, "objective_progress": 0
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


func get_tracked_quest() -> Dictionary:
	return get_quest(_tracked_quest_id)


func can_accept_quest(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	var status := str(quest.get("status", ""))
	if status == "available":
		return _prerequisites_met(quest)
	if status == COMPLETED_STATUS and bool(quest.get("repeatable", false)):
		return _prerequisites_met(quest)
	return false


func accept_quest(quest_id: String) -> bool:
	if not can_accept_quest(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	quest["status"] = ACTIVE_STATUS
	quest["progress"] = 0
	quest["objective_progress"] = 0
	_quests[quest_id] = quest
	if _tracked_quest_id.is_empty():
		_tracked_quest_id = quest_id
	_emit_quest_update(quest_id)
	_emit_tracked_quest()
	return true


func report_objective_event(event_type: String, target_id: String, amount: int = 1) -> bool:
	if not OBJECTIVE_TYPES.has(event_type) or target_id.is_empty() or amount <= 0:
		return false
	var changed := false
	for quest_id in _quests:
		var quest: Dictionary = _quests[quest_id]
		if str(quest.get("status", "")) != ACTIVE_STATUS:
			continue
		var objectives: Array = quest.get("objectives", [])
		var objective_index := int(quest.get("progress", 0))
		if objective_index < 0 or objective_index >= objectives.size():
			continue
		var objective: Dictionary = objectives[objective_index]
		if str(objective.get("type", "interact")) != event_type:
			continue
		if str(objective.get("target_id", "")) != target_id:
			continue
		var required := maxi(1, int(objective.get("required_count", 1)))
		var current := int(quest.get("objective_progress", 0))
		current = mini(required, current + amount)
		quest["objective_progress"] = current
		if current >= required:
			quest["progress"] = objective_index + 1
			quest["objective_progress"] = 0
			if int(quest["progress"]) >= objectives.size():
				quest["status"] = COMPLETED_STATUS
		_quests[quest_id] = quest
		_emit_quest_update(quest_id)
		changed = true
	return changed


func notify_interaction(target_id: String) -> bool:
	var changed := false
	for event_type in ["interact", "investigate", "deliver"]:
		if report_objective_event(event_type, target_id):
			changed = true
	return changed


func track_quest(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	if str(quest.get("status", "")) != ACTIVE_STATUS and str(quest.get("status", "")) != COMPLETED_STATUS:
		return false
	_tracked_quest_id = quest_id
	_emit_tracked_quest()
	return true


func abandon_quest(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	if str(quest.get("status", "")) != ACTIVE_STATUS:
		return false
	quest["status"] = "abandoned"
	_quests[quest_id] = quest
	if _tracked_quest_id == quest_id:
		_tracked_quest_id = ""
	_emit_quest_update(quest_id)
	_emit_tracked_quest()
	return true


func fail_quest(quest_id: String, reason: String = "") -> bool:
	if not _quests.has(quest_id):
		return false
	var quest: Dictionary = _quests[quest_id]
	if str(quest.get("status", "")) != ACTIVE_STATUS:
		return false
	quest["status"] = "failed"
	quest["failure_reason"] = reason
	_quests[quest_id] = quest
	if _tracked_quest_id == quest_id:
		_tracked_quest_id = ""
	_emit_quest_update(quest_id)
	_emit_tracked_quest()
	return true


func _prerequisites_met(quest: Dictionary) -> bool:
	var prerequisites: Array = quest.get("prerequisites", [])
	for prerequisite_id in prerequisites:
		if not _quests.has(str(prerequisite_id)):
			return false
		var prerequisite: Dictionary = _quests[str(prerequisite_id)]
		if str(prerequisite.get("status", "")) != COMPLETED_STATUS:
			return false
	return true


func _emit_quest_update(quest_id: String) -> void:
	quest_updated.emit(get_quest(quest_id))
	quest_log_changed.emit()
	if quest_id == _tracked_quest_id:
		_emit_tracked_quest()


func _emit_tracked_quest() -> void:
	tracked_quest_changed.emit(get_tracked_quest())
