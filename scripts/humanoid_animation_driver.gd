extends RefCounted
class_name HHHumanoidAnimationDriver

# Drives imported humanoid GLBs from the existing player animation state machine.
# Procedural pivots remain the fallback when an asset has no compatible clip.
const STATE_TOKENS := {
	"idle": ["idle", "stand", "breath", "wait"],
	"walk": ["walk", "walking", "run", "move", "locomotion"],
	"attack": ["attack", "atk", "slash", "swing"],
	"hit": ["hit", "hurt", "damage", "react"]
}

const ATTACK_STYLE_TOKENS := {
	"sword_slash": ["slash", "sword", "blade", "swing"],
	"spear_thrust": ["thrust", "stab", "spear", "lance", "pierce"],
	"ranged_shot": ["shoot", "bow", "arrow", "crossbow", "ranged"],
	"staff_cast": ["cast", "spell", "magic", "staff", "wand", "channel"],
	"heavy_swing": ["heavy", "overhead", "smash", "axe", "hammer"]
}

static func apply_state(root: Node3D, state: String, fade_seconds: float = 0.16, attack_style: String = "") -> bool:
	if not is_instance_valid(root) or not STATE_TOKENS.has(state):
		return false
	var animation_player := _find_best_animation_player(root, state, attack_style)
	if not is_instance_valid(animation_player):
		root.set_meta("humanoid_animation_state_unavailable", state)
		return false
	var selected := _find_clip(animation_player, state, attack_style)
	if selected.is_empty():
		root.set_meta("humanoid_animation_state_unavailable", state)
		return false
	var animation := animation_player.get_animation(selected)
	if animation != null:
		# Locomotion must loop; combat reactions are one-shots. Some downloaded
		# packs author all clips as loops, so normalize this at the adapter edge.
		animation.loop_mode = Animation.LOOP_LINEAR if state in ["idle", "walk"] else Animation.LOOP_NONE
	var previous_state := str(root.get_meta("humanoid_animation_state", ""))
	if animation_player.current_animation == selected and previous_state == state:
		# A finished one-shot must not restart every frame while the gameplay
		# state remains active; a later transition away and back can replay it.
		return true
	animation_player.play(selected, maxf(fade_seconds, 0.0))
	root.set_meta("humanoid_animation_state", state)
	root.set_meta("humanoid_animation_clip", selected)
	return true


static func _find_best_animation_player(root: Node, state: String, attack_style: String) -> AnimationPlayer:
	var players := root.find_children("*", "AnimationPlayer", true, false)
	var best_player: AnimationPlayer
	var best_score := -1
	for candidate in players:
		var player := candidate as AnimationPlayer
		if not is_instance_valid(player):
			continue
		var score := _clip_match_score(player, state, attack_style)
		if score > best_score:
			best_score = score
			best_player = player
	return best_player if best_score >= 0 else null


static func _clip_match_score(player: AnimationPlayer, state: String, attack_style: String) -> int:
	var selected := _find_clip(player, state, attack_style)
	if selected.is_empty():
		return -1
	var normalized := selected.to_lower()
	if state == "attack" and ATTACK_STYLE_TOKENS.has(attack_style):
		for token in ATTACK_STYLE_TOKENS[attack_style]:
			if normalized.contains(token):
				return 200 + str(token).length()
	for token in STATE_TOKENS[state]:
		if normalized.contains(token):
			return 100 + str(token).length()
	return 0


static func _find_clip(player: AnimationPlayer, state: String, attack_style: String = "") -> String:
	var candidates: Array = []
	if state == "attack" and ATTACK_STYLE_TOKENS.has(attack_style):
		candidates.append(ATTACK_STYLE_TOKENS[attack_style])
	candidates.append(STATE_TOKENS[state])
	var best_name := ""
	var best_score := -1
	for animation_name in player.get_animation_list():
		var normalized := str(animation_name).to_lower().replace("_", "").replace("-", "").replace(" ", "")
		if normalized in ["reset", "default", "tpose", "bindpose"]:
			continue
		var score := -1
		for candidate_index in range(candidates.size()):
			var tokens: Array = candidates[candidate_index]
			for token in tokens:
				if normalized.contains(token):
					var candidate_score: int = (100 if candidate_index == 0 and candidates.size() > 1 else 10) + str(token).length()
					score = maxi(score, candidate_score)
		if score > best_score:
			best_score = score
			best_name = str(animation_name)
	return best_name if best_score >= 0 else ""
