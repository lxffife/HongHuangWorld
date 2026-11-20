extends RefCounted
class_name HHHumanoidAnimationDriver

# Optional animation adapter for imported GLB scenes. Procedural pivots remain
# the fallback when a model has no compatible AnimationPlayer/clip.
const STATE_TOKENS := {
	"idle": ["idle", "stand", "breath", "wait"],
	"walk": ["walk", "run", "move", "locomotion"],
	"attack": ["attack", "atk", "slash", "swing"],
	"hit": ["hit", "hurt", "damage", "react"]
}

static func apply_state(root: Node3D, state: String, fade_seconds: float = 0.16) -> bool:
	if not is_instance_valid(root) or not STATE_TOKENS.has(state):
		return false
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return false
	var animation_player := players[0] as AnimationPlayer
	if not is_instance_valid(animation_player):
		return false
	var selected := _find_clip(animation_player, state)
	if selected.is_empty():
		return false
	if animation_player.current_animation == selected and animation_player.is_playing():
		return true
	animation_player.play(selected, maxf(fade_seconds, 0.0))
	return true


static func _find_clip(player: AnimationPlayer, state: String) -> String:
	var tokens: Array = STATE_TOKENS[state]
	var best_name := ""
	var best_score := -1
	for animation_name in player.get_animation_list():
		var normalized := str(animation_name).to_lower().replace("_", "").replace("-", "").replace(" ", "")
		if normalized in ["reset", "default", "tpose", "bindpose"]:
			continue
		var score := 0
		for token in tokens:
			if normalized.contains(token):
				score = maxi(score, 10 + token.length())
		if score > best_score:
			best_score = score
			best_name = str(animation_name)
	return best_name if best_score >= 0 else ""
