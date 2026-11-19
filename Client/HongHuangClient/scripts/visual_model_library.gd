extends RefCounted
class_name VisualModelLibrary

# Optional GLB overrides live under res://assets/models/. Missing assets always
# fall back to the procedural model, so a clean checkout remains playable.
const MODEL_PATHS := {
	"player_humanoid": "res://assets/models/player_humanoid.glb",
	"wasteland_wolf": "res://assets/models/wasteland_wolf.glb",
	"iron_beast": "res://assets/models/iron_beast.glb",
	"fire_soul": "res://assets/models/fire_soul.glb",
	"frost_soul": "res://assets/models/frost_soul.glb"
}

static func instantiate_model(model_key: String, fallback_factory: Callable) -> Node3D:
	var model_path := str(MODEL_PATHS.get(model_key, ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed_scene := load(model_path) as PackedScene
		if packed_scene != null:
			var instance := packed_scene.instantiate()
			if instance is Node3D:
				instance.set_meta("model_source", model_path)
				return instance as Node3D
			if instance != null:
				instance.queue_free()
	if fallback_factory.is_valid():
		var fallback: Variant = fallback_factory.call()
		if fallback is Node3D:
			(fallback as Node3D).set_meta("model_source", "procedural_fallback")
			return fallback as Node3D
	push_error("No model or fallback available for visual key: " + model_key)
	return Node3D.new()
