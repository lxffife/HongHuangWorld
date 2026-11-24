extends SceneTree

# Run after the first editor import:
# godot --headless --path . --script res://tools/validate_model_assets.gd
# Add --require-all to fail when any optional model file is missing.

const MODEL_FILES := {
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

func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var require_all := OS.get_cmdline_user_args().has("--require-all")
	var report: Dictionary = {
		"project": "HongHuangClient",
		"validator_version": 1,
		"require_all": require_all,
		"models": [],
		"summary": {"valid": 0, "missing": 0, "invalid": 0, "warnings": 0}
	}
	var exit_code := 0

	for model_key in MODEL_FILES:
		var path: String = MODEL_FILES[model_key]
		var item: Dictionary = {
			"key": model_key,
			"path": path,
			"status": "missing",
			"mesh_count": 0,
			"skeleton_count": 0,
			"animation_player_count": 0,
			"animations": [],
			"material_surface_count": 0,
			"largest_mesh_dimension": 0.0,
			"warnings": []
		}

		if not ResourceLoader.exists(path):
			report["summary"]["missing"] += 1
			if require_all:
				item["warnings"].append("Required model file is missing")
				exit_code = 1
			report["models"].append(item)
			continue

		var packed_scene := ResourceLoader.load(path) as PackedScene
		if packed_scene == null:
			item["status"] = "invalid"
			item["warnings"].append("File did not load as PackedScene")
			report["summary"]["invalid"] += 1
			exit_code = 1
			report["models"].append(item)
			continue

		var instance := packed_scene.instantiate()
		if not instance is Node3D:
			item["status"] = "invalid"
			item["warnings"].append("Scene root must inherit Node3D")
			report["summary"]["invalid"] += 1
			exit_code = 1
			if instance != null:
				instance.free()
			report["models"].append(item)
			continue

		_inspect_node(instance, item)
		if int(item["mesh_count"]) <= 0:
			item["status"] = "invalid"
			item["warnings"].append("No MeshInstance3D with a valid Mesh was found")
			report["summary"]["invalid"] += 1
			exit_code = 1
		else:
			item["status"] = "valid"
			report["summary"]["valid"] += 1
			if int(item["skeleton_count"]) == 0:
				item["warnings"].append("No Skeleton3D found; this may be intentional for a static or spirit model")
				report["summary"]["warnings"] += 1
			if int(item["animation_player_count"]) == 0:
				item["warnings"].append("No AnimationPlayer found; locomotion and action clips will not be available")
				report["summary"]["warnings"] += 1

		instance.free()
		report["models"].append(item)

	print("\n=== HongHuang GLB Asset Validation ===")
	print(JSON.stringify(report, "\t"))
	var output := FileAccess.open("user://model_asset_validation.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
		print("Report saved: user://model_asset_validation.json")
	else:
		push_warning("Could not write validation report to user://")

	print("Summary: valid=%d missing=%d invalid=%d warnings=%d" % [
		report["summary"]["valid"],
		report["summary"]["missing"],
		report["summary"]["invalid"],
		report["summary"]["warnings"]
	])
	quit(exit_code)


func _inspect_node(node: Node, item: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			item["mesh_count"] += 1
			item["material_surface_count"] += mesh_instance.mesh.get_surface_count()
			var mesh_size: Vector3 = mesh_instance.mesh.get_aabb().size
			var largest_dimension := maxf(mesh_size.x, maxf(mesh_size.y, mesh_size.z))
			item["largest_mesh_dimension"] = maxf(float(item["largest_mesh_dimension"]), largest_dimension)

	if node is Skeleton3D:
		item["skeleton_count"] += 1

	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		item["animation_player_count"] += 1
		for animation_name in player.get_animation_list():
			item["animations"].append(str(animation_name))

	for child in node.get_children():
		_inspect_node(child, item)
