extends Node
## Local narrative state for Fengdu. The server remains authoritative for durable progress.

signal flag_changed(flag_id: String, value: bool)
signal choice_made(choice_id: String, choice_data: Dictionary)
signal reputation_changed(faction_id: String, value: int)

var _flags: Dictionary = {}
var _choices: Dictionary = {}
var _reputation: Dictionary = {}


func has_flag(flag_id: String) -> bool:
	return bool(_flags.get(flag_id, false))


func get_flag(flag_id: String, default_value: bool = false) -> bool:
	return bool(_flags.get(flag_id, default_value))


func set_flag(flag_id: String, value: bool = true) -> void:
	if flag_id.is_empty() or bool(_flags.get(flag_id, false)) == value:
		return
	_flags[flag_id] = value
	flag_changed.emit(flag_id, value)


func get_choice(choice_key: String) -> String:
	return str(_choices.get(choice_key, ""))


func get_reputation(faction_id: String) -> int:
	return int(_reputation.get(faction_id, 0))


func add_reputation(faction_id: String, amount: int) -> void:
	if faction_id.is_empty() or amount == 0:
		return
	var value := clampi(get_reputation(faction_id) + amount, -100, 100)
	_reputation[faction_id] = value
	reputation_changed.emit(faction_id, value)


func get_choices_for_npc(npc_id: String, quest_manager: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if npc_id != "white_impermanence" or quest_manager == null:
		return result
	var quest: Dictionary = quest_manager.call("get_quest", "white_soul_registration")
	if str(quest.get("status", "")) == "completed" and get_choice("new_soul_registration").is_empty():
		result.append({
			"id": "register_by_the_book",
			"label": "按章登记",
			"response": "谢必安展开魂籍簿：先核实来历、登记执念，再交由轮回司审理。此举维护阴司秩序。",
			"choice_key": "new_soul_registration"
		})
		result.append({
			"id": "comfort_the_soul",
			"label": "先安抚亡魂",
			"response": "谢必安沉吟片刻：先听亡魂说完心愿，再补录魂籍。规矩不可废，但也不该让新魂带着恐惧受审。",
			"choice_key": "new_soul_registration"
		})
	return result


func make_choice(choice_id: String) -> bool:
	if choice_id.is_empty() or get_choice("new_soul_registration") != "":
		return false
	match choice_id:
		"register_by_the_book":
			_choices["new_soul_registration"] = choice_id
			set_flag("supported_yin_official_order")
			add_reputation("yin_officials", 5)
			choice_made.emit(choice_id, {"label": "按章登记", "branch": "official_order"})
			return true
		"comfort_the_soul":
			_choices["new_soul_registration"] = choice_id
			set_flag("protected_new_soul")
			add_reputation("new_souls", 5)
			choice_made.emit(choice_id, {"label": "先安抚亡魂", "branch": "protect_new_soul"})
			return true
	return false


func get_npc_description(npc_id: String, default_description: String) -> String:
	if npc_id != "white_impermanence":
		return default_description
	match get_choice("new_soul_registration"):
		"register_by_the_book":
			return "谢必安记得你选择按章登记。鬼籍司已将你列为可信的协办者，后续可协助核验官署文牒。"
		"comfort_the_soul":
			return "谢必安记得你曾主张先安抚新魂。驿站的新魂对你多了几分信任，也愿意向你倾诉未了心愿。"
	return default_description


func get_story_log() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if has_flag("supported_yin_official_order"):
		entries.append({"title": "按章登记", "detail": "你选择先完成魂籍核验，获得阴司官署的认可。"})
	if has_flag("protected_new_soul"):
		entries.append({"title": "先安抚亡魂", "detail": "你选择先倾听新魂心愿，获得新魂群体的信任。"})
	return entries
