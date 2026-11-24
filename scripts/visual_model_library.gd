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

static func instantiate_model(model_key: String, fallback_factory: Callable) -> Node3D:
	var model_path := str(MODEL_PATHS.get(model_key, ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed_scene := load(model_path) as PackedScene
		if packed_scene != null:
			var instance := packed_scene.instantiate()
			if instance is Node3D and _contains_renderable_mesh(instance):
				instance.set_meta("model_source", model_path)
				instance.set_meta("model_key", model_key)
				_attach_animation_driver(instance as Node3D)
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


static func _contains_renderable_mesh(root: Node) -> bool:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return true
	for child in root.get_children():
		if _contains_renderable_mesh(child):
			return true
	return false



static func _attach_animation_driver(model_root: Node3D) -> void:
	if model_root.get_node_or_null("ModelAnimationController") != null:
		return
	var controller := Node.new()
	controller.name = "ModelAnimationController"
	controller.set_script(load("res://scripts/model_animation_controller.gd"))
	model_root.add_child(controller)
