extends RefCounted
class_name VisualModelLibrary

# Optional GLB overrides live under res://assets/models/. Missing assets always
# fall back to the procedural model, so a clean checkout remains playable.
const MODEL_PATHS := {
	"player_humanoid": "res://assets/models/player_humanoid.glb",
	"wolf": "res://assets/models/wasteland_wolf.glb",
	"iron_beast": "res://assets/models/iron_beast.glb",
	"warrior": "res://assets/models/warrior_soul.glb",
	"life_soul": "res://assets/models/life_soul.glb",
	"wind_soul": "res://assets/models/wind_soul.glb",
	"fire_soul": "res://assets/models/fire_soul.glb",
	"frost_soul": "res://assets/models/frost_soul.glb",
	"wraith": "res://assets/models/wraith.glb"
}

# Target visual heights in metres. These affect presentation only; gameplay
# collision and server reach remain independent of imported mesh dimensions.
const TARGET_HEIGHTS := {
	"player_humanoid": 1.8,
	"wolf": 1.15,
	"iron_beast": 2.8,
	"warrior": 1.9,
	"life_soul": 1.65,
	"wind_soul": 1.65,
	"fire_soul": 1.65,
	"frost_soul": 1.65,
	"wraith": 1.85
}
const MIN_SCALE_FACTOR := 0.25
const MAX_SCALE_FACTOR := 4.0

static func instantiate_model(model_key: String, fallback_factory: Callable) -> Node3D:
	var model_path := str(MODEL_PATHS.get(model_key, ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed_scene := load(model_path) as PackedScene
		if packed_scene != null:
			var instance := packed_scene.instantiate()
			if instance is Node3D and _contains_renderable_mesh(instance):
				instance.set_meta("model_source", model_path)
				instance.set_meta("model_key", model_key)
				_normalize_visual_height(instance as Node3D, model_key)
				_attach_animation_driver(instance as Node3D, model_key)
				return instance as Node3D
			if instance != null:
				instance.queue_free()
			push_warning("Model override has no usable MeshInstance3D; using procedural fallback: " + model_path)
	if fallback_factory.is_valid():
		var fallback: Variant = fallback_factory.call()
		if fallback is Node3D:
			(fallback as Node3D).set_meta("model_source", "procedural_fallback")
			(fallback as Node3D).set_meta("model_key", model_key)
			return fallback as Node3D
	push_error("No model or fallback available for visual key: " + model_key)
	return Node3D.new()


static func _normalize_visual_height(model_root: Node3D, model_key: String) -> void:
	var target_height := float(TARGET_HEIGHTS.get(model_key, 0.0))
	if target_height <= 0.0:
		return
	var bounds_state := {
		"found": false,
		"minimum": Vector3.ZERO,
		"maximum": Vector3.ZERO
	}
	_collect_mesh_bounds(model_root, Transform3D.IDENTITY, true, bounds_state)
	if not bool(bounds_state["found"]):
		return
	var bounds_size: Vector3 = bounds_state["maximum"] - bounds_state["minimum"]
	var current_height := bounds_size.y * absf(model_root.scale.y)
	if current_height < 0.05:
		push_warning("Imported model has an unusable height; keeping source scale: " + model_key)
		return
	var factor := target_height / current_height
	if factor < MIN_SCALE_FACTOR or factor > MAX_SCALE_FACTOR:
		push_warning("Imported model scale is outside safe normalization limits; review source units: " + model_key)
		model_root.set_meta("model_height_before_normalization", current_height)
		model_root.set_meta("model_height_target", target_height)
		model_root.set_meta("model_scale_review_required", true)
		return
	model_root.scale *= factor
	model_root.set_meta("model_height_before_normalization", snappedf(current_height, 0.001))
	model_root.set_meta("model_height_target", target_height)
	model_root.set_meta("model_normalization_factor", snappedf(factor, 0.001))


static func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, is_root: bool, state: Dictionary) -> void:
	var local_transform := Transform3D.IDENTITY if is_root else node.transform
	var current_transform := parent_transform * local_transform
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			var transformed_bounds: AABB = mesh.get_aabb() * current_transform
			var minimum: Vector3 = transformed_bounds.position
			var maximum: Vector3 = transformed_bounds.position + transformed_bounds.size
			if not bool(state["found"]):
				state["minimum"] = minimum
				state["maximum"] = maximum
				state["found"] = true
			else:
				var current_minimum: Vector3 = state["minimum"]
				var current_maximum: Vector3 = state["maximum"]
				state["minimum"] = current_minimum.min(minimum)
				state["maximum"] = current_maximum.max(maximum)
	for child in node.get_children():
		_collect_mesh_bounds(child, current_transform, false, state)


static func _contains_renderable_mesh(root: Node) -> bool:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return true
	for child in root.get_children():
		if _contains_renderable_mesh(child):
			return true
	return false


static func _attach_animation_driver(model_root: Node3D, model_key: String) -> void:
	# Humanoid player scenes already use HHHumanoidAnimationDriver from world_scene.
	# Avoid two AnimationPlayers competing to change the same imported character.
	if model_key == "player_humanoid" or model_root.get_node_or_null("ModelAnimationController") != null:
		return
	var controller := Node.new()
	controller.name = "ModelAnimationController"
	controller.set_script(load("res://scripts/model_animation_controller.gd"))
	model_root.add_child(controller)
