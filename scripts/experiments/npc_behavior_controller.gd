extends Node
## Small reusable local NPC state machine. Gameplay authority remains server-side.

signal state_changed(previous_state: int, current_state: int, reason: String)

enum State {
	IDLE,
	PATROL,
	INTERACT,
	ALERT,
	CHASE,
	RETURNING
}

var behavior_profile := "ambient"
var current_state: int = State.IDLE


func configure(profile: String, has_patrol_route: bool) -> void:
	behavior_profile = profile
	current_state = State.PATROL if has_patrol_route else State.IDLE


func transition_to(next_state: int, reason: String = "") -> bool:
	if next_state < State.IDLE or next_state > State.RETURNING:
		return false
	if next_state == current_state:
		return true
	if not _is_transition_allowed(next_state):
		return false
	var previous := current_state
	current_state = next_state
	state_changed.emit(previous, current_state, reason)
	return true


func get_state_label() -> String:
	match current_state:
		State.IDLE:
			return "待命中"
		State.PATROL:
			match behavior_profile:
				"soul_capture":
					return "拘魂巡查中"
				"soul_guidance":
					return "接引新魂中"
				"gate_guard":
					return "南门盘查中"
				"gate_patrol":
					return "南门巡防中"
				_:
					return "巡逻中"
		State.INTERACT:
			return "交涉中"
		State.ALERT:
			return "警戒中"
		State.CHASE:
			return "追击中"
		State.RETURNING:
			return "归位中"
	return "待命中"


func _is_transition_allowed(next_state: int) -> bool:
	match current_state:
		State.IDLE:
			return next_state in [State.PATROL, State.INTERACT, State.ALERT]
		State.PATROL:
			return next_state in [State.IDLE, State.INTERACT, State.ALERT, State.RETURNING]
		State.INTERACT:
			return next_state in [State.IDLE, State.PATROL, State.ALERT]
		State.ALERT:
			return next_state in [State.PATROL, State.CHASE, State.RETURNING]
		State.CHASE:
			return next_state in [State.INTERACT, State.ALERT, State.RETURNING]
		State.RETURNING:
			return next_state in [State.PATROL, State.IDLE]
	return false
