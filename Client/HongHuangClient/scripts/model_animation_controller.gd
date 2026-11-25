extends Node
## Optional animation driver for imported GLB visuals.
## It observes presentation-root movement only; it never changes gameplay state.

const MOVE_START_SPEED := 0.16
const TELEPORT_SPEED_LIMIT := 9.0

var _animation_player: AnimationPlayer
var _clips: Array[String] = []
var _last_world_position := Vector3.ZERO
var _current_state := ""
var _locked_action := ""
var _action_lock_remaining := 0.0
var _preview_state_override := false


func _ready() -> void:
	var visual_root := get_parent() as Node3D
	if visual_root == null:
		set_process(false)
		return
	_animation_player = _find_animation_player(visual_root)
	if _animation_player == null:
		set_process(false)
		return
	for animation_name in _animation_player.get_animation_list():
		_clips.append(str(animation_name))
	_last_world_position = visual_root.global_position
	_play_state("idle")


func _process(delta: float) -> void:
	if _animation_player == null or not is_instance_valid(_animation_player):
		return
	var visual_root := get_parent() as Node3D
	if visual_root == null:
		return
	if _action_lock_remaining > 0.0:
		_action_lock_remaining = maxf(0.0, _action_lock_remaining - delta)
		if _action_lock_remaining <= 0.0:
			_locked_action = ""
	var current_position := visual_root.global_position
	var speed := 0.0
	if delta > 0.0001:
		speed = current_position.distance_to(_last_world_position) / delta
	_last_world_position = current_position
	if not _locked_action.is_empty():
		return
	# Static preview models must keep the requested locomotion clip instead of
	# being forced back to idle by the zero-displacement gameplay observer.
	if _preview_state_override:
		return
	# Ignore large snapshot corrections/teleports rather than playing a false run cycle.
	if speed > TELEPORT_SPEED_LIMIT:
		_play_state("idle")
	elif speed >= MOVE_START_SPEED:
		_play_state("run" if speed >= 3.2 else "walk")
	else:
		_play_state("idle")


func play_action(action_name: String) -> bool:
	if _animation_player == null or not is_instance_valid(_animation_player):
		return false
	var normalized := action_name.strip_edges().to_lower()
	var clip := _resolve_clip(normalized)
	if clip.is_empty():
		return false
	_preview_state_override = false
	_set_clip_looping(clip, false)
	_animation_player.play(clip, 0.12)
	_current_state = normalized
	_locked_action = normalized
	if normalized == "death":
		_action_lock_remaining = 999999.0
	else:
		# Imported clips vary in length. Keep the action locked for the real clip
		# duration instead of cutting long attacks/hit reactions off at a fixed timer.
		var animation := _animation_player.get_animation(clip)
		_action_lock_remaining = maxf(0.18, animation.length if animation != null else 0.5)
	return true


func play_preview_state(state_name: String) -> bool:
	# Preview locomotion must loop and must not use the one-shot combat lock.
	var normalized := state_name.strip_edges().to_lower()
	if normalized not in ["idle", "walk", "run"]:
		return false
	if _animation_player == null or not is_instance_valid(_animation_player):
		return false
	var clip := _resolve_clip(normalized)
	if clip.is_empty():
		return false
	_preview_state_override = true
	_locked_action = ""
	_action_lock_remaining = 0.0
	_set_clip_looping(clip, true)
	_animation_player.play(clip, 0.12)
	_current_state = normalized
	return true


func clear_action() -> void:
	_locked_action = ""
	_action_lock_remaining = 0.0
	_current_state = ""


func _play_state(state_name: String) -> void:
	if state_name == _current_state:
		return
	var clip := _resolve_clip(state_name)
	if clip.is_empty():
		return
	_set_clip_looping(clip, true)
	_animation_player.play(clip, 0.18)
	_current_state = state_name


func _set_clip_looping(clip_name: String, should_loop: bool) -> void:
	var animation := _animation_player.get_animation(clip_name)
	if animation == null:
		return
	animation.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE


func _resolve_clip(state_name: String) -> String:
	var keywords: Array[String] = []
	match state_name:
		"idle":
			keywords = ["idle", "stand", "breath", "wait"]
		"walk":
			keywords = ["walk", "walking", "locomotion"]
		"run":
			keywords = ["run", "sprint", "jog"]
		"attack":
			keywords = ["attack", "slash", "swing", "bite", "combat"]
		"hit":
			keywords = ["hit", "damage", "hurt", "react"]
		"death":
			keywords = ["death", "die", "dead"]
		_:
			keywords = [state_name]
	for keyword in keywords:
		for clip_name in _clips:
			if clip_name.to_lower().contains(keyword):
				return clip_name
	return ""


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
