extends SceneTree

# Run after the first editor import:
# godot --headless --path . --script res://tools/validate_model_assets.gd
# Add -- --require-all to fail when any optional model file is missing.
# Add -- --strict-animations to fail when required clips are absent.
# Add -- --strict-rig to fail when a character has no usable rig; wolves also need named quadruped anatomy.

const EquipmentVisualFactory = preload("res://scripts/equipment_visual_factory.gd")

const MODEL_FILES := {
	"player_humanoid": "res://assets/models/player_humanoid.glb",
	"wolf": "res://assets/models/wasteland_wolf.glb",
	"iron_beast": "res://assets/models/iron_beast.glb",
	"warrior": "res://assets/models/warrior_soul.glb",
	"life_soul": "res://assets/models/life_soul.glb",
	"wind_soul": "res://assets/models/wind_soul.glb",
	"fire_soul": "res://assets/models/fire_soul.glb",
	"frost_soul": "res://assets/models/frost_soul.glb",
	"wraith": "res://assets/models/wraith.glb",
	"npc_judge": "res://assets/models/npc_judge.glb",
	"npc_trial_master": "res://assets/models/npc_trial_master.glb",
	"npc_guard": "res://assets/models/npc_guard.glb",
	"npc_soup_keeper": "res://assets/models/npc_soup_keeper.glb",
	"npc_blacksmith": "res://assets/models/npc_blacksmith.glb",
	"npc_generic": "res://assets/models/npc_generic.glb"
}

# Animation requirements are model-specific: floating souls do not need
# quadruped locomotion, and the player uses its existing humanoid driver.
const RIG_REQUIRED_MODELS := [
	"player_humanoid", "wolf", "iron_beast", "warrior",
	"npc_judge", "npc_trial_master", "npc_guard", "npc_soup_keeper", "npc_blacksmith", "npc_generic"
]

const REQUIRED_ANIMATIONS := {
	"player_humanoid": ["idle", "walk", "attack", "hit"],
	"wolf": ["idle", "walk", "run", "attack", "death"],
	"iron_beast": ["idle", "walk", "attack", "death"],
	"warrior": ["idle", "walk", "attack", "death"],
	"life_soul": ["idle", "attack", "death"],
	"wind_soul": ["idle", "attack", "death"],
	"fire_soul": ["idle", "attack", "death"],
	"frost_soul": ["idle", "attack", "death"],
	"wraith": ["idle", "attack", "death"],
	"npc_judge": ["idle"],
	"npc_trial_master": ["idle"],
	"npc_guard": ["idle"],
	"npc_soup_keeper": ["idle"],
	"npc_blacksmith": ["idle"],
	"npc_generic": ["idle"]
}

func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var args := OS.get_cmdline_user_args()
	var require_all := args.has("--require-all")
	var strict_animations := args.has("--strict-animations")
	var strict_rig := args.has("--strict-rig")
	var report: Dictionary = {
		"project": "HongHuangClient",
		"validator_version": 4,
		"require_all": require_all,
		"strict_animations": strict_animations,
		"strict_rig": strict_rig,
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
			"bone_count": 0,
			"rig_anatomy": {},
			"equipment_bone_bindings": {},
			"equipment_bindings_passed": model_key != "player_humanoid",
			"animation_player_count": 0,
			"rig_validation": {"required": model_key in RIG_REQUIRED_MODELS, "skeleton_required": model_key in RIG_REQUIRED_MODELS, "animation_player_required": model_key in RIG_REQUIRED_MODELS, "minimum_bones": 12 if model_key == "wolf" else 15, "passed": false, "profile": "quadruped" if model_key == "wolf" else "humanoid_or_creature", "anatomy": {}},
			"animations": [],
			"animation_clips": [],
			"required_animation_categories": REQUIRED_ANIMATIONS.get(model_key, []),
			"missing_required_animation_categories": [],
			"animation_categories": {"idle": false, "walk": false, "run": false, "attack": false, "hit": false, "death": false},
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
		if model_key == "wolf":
			item["rig_anatomy"] = _inspect_quadruped_anatomy(instance)
		if model_key == "player_humanoid":
			_validate_player_equipment_bindings(instance as Node3D, item)
		_classify_animation_coverage(item)
		var has_skeleton := int(item["skeleton_count"]) > 0
		var has_animation_player := int(item["animation_player_count"]) > 0
		var has_usable_bone_count := int(item["bone_count"]) >= int(item["rig_validation"]["minimum_bones"])
		var rig_required := bool(item["rig_validation"]["required"])
		item["rig_validation"]["bone_count"] = int(item["bone_count"])
		var anatomy_passed := true
		if model_key == "wolf":
			anatomy_passed = bool(item["rig_anatomy"].get("passed", false))
			item["rig_validation"]["anatomy"] = item["rig_anatomy"]
		item["rig_validation"]["passed"] = not rig_required or (has_skeleton and has_animation_player and has_usable_bone_count and anatomy_passed)
		if model_key == "wolf" and not anatomy_passed:
			item["warnings"].append("Quadruped rig anatomy is incomplete; review root/spine/head and front/hind limb bone names")
		if rig_required and not has_skeleton:
			item["warnings"].append("Rigged character asset has no Skeleton3D")
		if rig_required and not has_animation_player:
			item["warnings"].append("Rigged character asset has no AnimationPlayer")
		if rig_required and has_skeleton and not has_usable_bone_count:
			item["warnings"].append("Rigged character has fewer than 15 bones; review whether it is a full humanoid/creature rig")
		if strict_rig and rig_required and not bool(item["rig_validation"]["passed"]):
			exit_code = 1
		if strict_rig and model_key == "player_humanoid" and not bool(item["equipment_bindings_passed"]):
			exit_code = 1
		var missing_animations := _apply_animation_requirements(model_key, item)
		if not missing_animations.is_empty():
			for category in missing_animations:
				item["warnings"].append("Required animation missing: " + category)
			report["summary"]["warnings"] += missing_animations.size()
			if strict_animations:
				exit_code = 1

		if int(item["mesh_count"]) <= 0:
			item["status"] = "invalid"
			item["warnings"].append("No MeshInstance3D with a valid Mesh was found")
			report["summary"]["invalid"] += 1
			exit_code = 1
		else:
			item["status"] = "valid"
			report["summary"]["valid"] += 1
			if rig_required and not has_skeleton:
				report["summary"]["warnings"] += 1
			if rig_required and not has_animation_player:
				report["summary"]["warnings"] += 1
			if rig_required and has_skeleton and not has_usable_bone_count:
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


func _validate_player_equipment_bindings(model_root: Node3D, item: Dictionary) -> void:
	var bindings: Dictionary = {}
	var all_required_bound := true
	for slot in ["weapon", "offhand", "back"]:
		var socket := EquipmentVisualFactory.get_or_create_socket(model_root, slot)
		if not is_instance_valid(socket):
			bindings[slot] = {"valid": false, "reason": "socket_unavailable"}
			all_required_bound = false
			continue
		var binding := EquipmentVisualFactory.inspect_socket_binding(model_root, slot)
		bindings[slot] = binding
		if not bool(binding.get("follows_bone", false)):
			all_required_bound = false
			item["warnings"].append("Equipment slot does not follow an animated bone: " + slot)
	item["equipment_bone_bindings"] = bindings
	item["equipment_bindings_passed"] = all_required_bound


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
		var skeleton := node as Skeleton3D
		item["skeleton_count"] += 1
		item["bone_count"] += skeleton.get_bone_count()

	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		item["animation_player_count"] += 1
		for animation_name in player.get_animation_list():
			var clip_name := str(animation_name)
			item["animations"].append(clip_name)
			var animation := player.get_animation(clip_name)
			if animation != null:
				item["animation_clips"].append({
					"name": clip_name,
					"length_seconds": snappedf(animation.length, 0.001),
					"loop_mode": int(animation.loop_mode),
					"track_count": animation.get_track_count()
				})

	for child in node.get_children():
		_inspect_node(child, item)


func _classify_animation_coverage(item: Dictionary) -> void:
	var keywords := {
		"idle": ["idle", "stand", "breath", "wait"],
		"walk": ["walk", "walking", "locomotion"],
		"run": ["run", "sprint", "jog"],
		"attack": ["attack", "slash", "swing", "bite", "combat"],
		"hit": ["hit", "damage", "hurt", "react"],
		"death": ["death", "die", "dead"]
	}
	for animation_name in item["animations"]:
		var normalized := str(animation_name).to_lower()
		for category in keywords:
			if item["animation_categories"][category]:
				continue
			for keyword in keywords[category]:
				if normalized.contains(keyword):
					item["animation_categories"][category] = true
					break


func _apply_animation_requirements(model_key: String, item: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for category in REQUIRED_ANIMATIONS.get(model_key, []):
		if not bool(item["animation_categories"].get(category, false)):
			missing.append(str(category))
	item["missing_required_animation_categories"] = missing
	item["animation_requirements_passed"] = missing.is_empty()
	return missing


func _inspect_quadruped_anatomy(root: Node) -> Dictionary:
	# Bone names vary between Blender, Mixamo and asset-pack exports. Normalize
	# punctuation/case first, then use broad semantic aliases rather than fixed indices.
	var names: Array[String] = []
	_collect_bone_names(root, names)
	var normalized_names: Array[String] = []
	for bone_name in names:
		normalized_names.append(bone_name.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace(":", ""))
	var has_root := _names_contain_any(normalized_names, ["root", "armature", "hips", "pelvis"])
	var has_spine := _names_contain_any(normalized_names, ["spine", "back", "torso", "chest"])
	var has_head := _names_contain_any(normalized_names, ["head", "skull"])
	var front_count := _count_limb_bones(normalized_names, ["front", "fore"], ["leg", "limb", "paw", "foot", "shoulder"])
	var hind_count := _count_limb_bones(normalized_names, ["hind", "back", "rear"], ["leg", "limb", "paw", "foot", "thigh", "hip"])
	var passed := has_root and has_spine and has_head and front_count >= 2 and hind_count >= 2
	return {
		"bone_names": names,
		"bone_count": names.size(),
		"has_root_or_pelvis": has_root,
		"has_spine_or_back": has_spine,
		"has_head": has_head,
		"front_limb_bone_matches": front_count,
		"hind_limb_bone_matches": hind_count,
		"passed": passed
	}


func _collect_bone_names(node: Node, output: Array[String]) -> void:
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		for bone_index in range(skeleton.get_bone_count()):
			output.append(skeleton.get_bone_name(bone_index))
	for child in node.get_children():
		_collect_bone_names(child, output)


func _names_contain_any(names: Array[String], tokens: Array[String]) -> bool:
	for bone_name in names:
		for token in tokens:
			if bone_name.contains(token):
				return true
	return false


func _count_limb_bones(names: Array[String], side_tokens: Array[String], limb_tokens: Array[String]) -> int:
	var matches := 0
	for bone_name in names:
		var has_side := false
		var has_limb := false
		for token in side_tokens:
			if bone_name.contains(token):
				has_side = true
				break
		for token in limb_tokens:
			if bone_name.contains(token):
				has_limb = true
				break
		if has_side and has_limb:
			matches += 1
	return matches
