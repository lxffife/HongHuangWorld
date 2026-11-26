extends RefCounted
class_name HHMonsterAnimationDriver

# Optional native-animation adapter for imported monster GLBs. The existing
# procedural archetype animation remains the fallback for missing clips.
const STATE_TOKENS := {
	"idle": ["idle", "stand", "breath", "wait", "rest"],
	"move": ["walk", "run", "move", "locomotion", "jog"],
	"attack": ["attack", "atk", "slash", "swing", "bite", "cast", "strike"],
	"hit": ["hit", "hurt", "damage", "react", "stagger"],
	"death": ["death", "die", "dead", "down", "fall"]
}

static func apply_state(root: Node3D, state: String, fade_seconds: float = 0.14) -> bool:
	if not is_instance_valid(root) or not STATE_TOKENS.has(state):
		return false
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return false
	var cache: Dictionary = root.get_meta("monster_animation_clip_cache", {})
	var selected_player: AnimationPlayer
	var selected_clip := str(cache.get(state, ""))
	if not selected_clip.is_empty():
		for candidate in players:
			var animation_player := candidate as AnimationPlayer
			if is_instance_valid(animation_player) and animation_player.has_animation(selected_clip):
				selected_player = animation_player
				break
	if not is_instance_valid(selected_player):
		var best_score := -1
		for candidate in players:
			var animation_player := candidate as AnimationPlayer
			if not is_instance_valid(animation_player):
				continue
			var clip := _find_clip(animation_player, state)
			if clip.is_empty():
				continue
			var score := _clip_score(clip, state)
			if score > best_score:
				best_score = score
				selected_player = animation_player
				selected_clip = clip
		if not is_instance_valid(selected_player) or selected_clip.is_empty():
			return false
		cache[state] = selected_clip
		root.set_meta("monster_animation_clip_cache", cache)
	if selected_player.current_animation == selected_clip:
		return true
	selected_player.play(selected_clip, maxf(fade_seconds, 0.0))
	return true


static func _find_clip(player: AnimationPlayer, state: String) -> String:
	var best_name := ""
	var best_score := -1
	for animation_name in player.get_animation_list():
		var clip := str(animation_name)
		var normalized := clip.to_lower().replace("_", "").replace("-", "").replace(" ", "")
		if normalized in ["reset", "default", "tpose", "bindpose"]:
			continue
		var score := _clip_score(clip, state)
		if score > best_score:
			best_score = score
			best_name = clip
	return best_name if best_score >= 0 else ""


static func _clip_score(clip_name: String, state: String) -> int:
	var normalized := clip_name.to_lower().replace("_", "").replace("-", "").replace(" ", "")
	var best_score := -1
	for token in STATE_TOKENS[state]:
		if normalized.contains(token):
			best_score = maxi(best_score, 10 + token.length())
	return best_score
