extends Node
## Optional animation driver for imported GLB visuals.
## It observes presentation-root movement only; it never changes gameplay state.

const MOVE_START_SPEED := 0.16
const TELEPORT_SPEED_LIMIT := 9.0

var _animation_player: AnimationPlayer
var _animation_players: Array[AnimationPlayer] = []
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
	_collect_animation_players(visual_root)
	_animation_player = _select_animation_player("idle")
	if _animation_player == null:
		set_process(false)
		return
	_last_world_position = visual_root.global_position
	_play_state("idle")


func _collect_animation_players(root: Node) -> void:
	if root is AnimationPlayer:
		_animation_players.append(root as AnimationPlayer)
	for child in root.get_children():
		_collect_animation_players(child)


func _process(delta: float) -> void:
	if _animation_players.is_empty():
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
	var normalized := action_name.strip_edges().to_lower()
	_animation_player = _select_animation_player(normalized)
	if _animation_player == null:
		return false
	var clip := _resolve_clip_in_player(_animation_player, normalized)
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
	_animation_player = _select_animation_player(normalized)
	if _animation_player == null:
		return false
	var clip := _resolve_clip_in_player(_animation_player, normalized)
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
	_animation_player = _select_animation_player(state_name)
	if _animation_player == null:
		return
	var clip := _resolve_clip_in_player(_animation_player, state_name)
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


func _select_animation_player(state_name: String) -> AnimationPlayer:
	var best_player: AnimationPlayer
	var best_score := -1
	for player in _animation_players:
		if not is_instance_valid(player):
			continue
		var clip := _resolve_clip_in_player(player, state_name)
		if clip.is_empty():
			continue
		var score := _clip_score(clip, state_name)
		if score > best_score:
			best_score = score
			best_player = player
	return best_player


func _resolve_clip_in_player(player: AnimationPlayer, state_name: String) -> String:
	var keywords := _keywords_for_state(state_name)
	var best_clip := ""
	var best_score := -1
	for clip_name in player.get_animation_list():
		var normalized := _normalize_clip_name(str(clip_name))
		if normalized in ["reset", "default", "tpose", "bindpose"]:
			continue
		for keyword_index in range(keywords.size()):
			var keyword: String = keywords[keyword_index]
			if normalized.contains(keyword):
				var score := _keyword_match_score(normalized, keyword) + (keywords.size() - keyword_index) * 8
				if score > best_score:
					best_score = score
					best_clip = str(clip_name)
	return best_clip


func _clip_score(clip_name: String, state_name: String) -> int:
	var keywords := _keywords_for_state(state_name)
	var normalized := _normalize_clip_name(clip_name)
	var best_score := 0
	for keyword_index in range(keywords.size()):
		var keyword: String = keywords[keyword_index]
		if normalized.contains(keyword):
			var score := _keyword_match_score(normalized, keyword) + (keywords.size() - keyword_index) * 8
			best_score = maxi(best_score, score)
	return best_score


func _keywords_for_state(state_name: String) -> Array[String]:
	var keywords: Array[String] = []
	var model_root := get_parent() as Node
	var model_key := str(model_root.get_meta("model_key", "")) if model_root != null else ""
	match state_name:
		"idle":
			keywords = ["idle", "stand", "breath", "wait"]
		"walk":
			keywords = ["walk", "walking", "locomotion"]
		"run":
			keywords = ["run", "sprint", "jog"]
		"attack":
			if model_key == "wolf":
				keywords = ["bite", "pounce", "lunge", "attack", "combat"]
			elif model_key == "iron_beast":
				keywords = ["smash", "charge", "stomp", "attack", "combat"]
			else:
				keywords = ["attack", "slash", "swing", "bite", "combat"]
		"hit":
			keywords = ["hit", "damage", "hurt", "react"]
		"death":
			keywords = ["death", "die", "dead"]
		_:
			keywords = [state_name]
	return keywords

func _normalize_clip_name(clip_name: String) -> String:
	return clip_name.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace(".", "").replace(":", "")


func _keyword_match_score(normalized_name: String, keyword: String) -> int:
	if normalized_name == keyword:
		return 1000 + keyword.length()
	if normalized_name.begins_with(keyword):
		return 700 + keyword.length()
	return 400 + keyword.length()

