extends Node3D
## Isolated visual review stage for imported models, materials and animation clips.
## Keyboard: 1-9 select; 0 selects slot 10; [ / ] previous/next; I/W/R/A/H/D play actions.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")
const VisualModelLibrary = preload("res://scripts/visual_model_library.gd")
const EquipmentVisualFactory = preload("res://scripts/equipment_visual_factory.gd")

var _preview_models: Array[Node3D] = []
var _selected_model_index := 0
var _status_label: Label


func _ready() -> void:
	_build_stage()
	_build_gallery()
	_build_controls()
	_update_status(_selection_status())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_selected_model_index = clampi(key_event.keycode - KEY_1, 0, _preview_models.size() - 1)
			_update_status(_selection_status())
			get_viewport().set_input_as_handled()
		KEY_0:
			_selected_model_index = clampi(9, 0, _preview_models.size() - 1)
			_update_status(_selection_status())
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var direction := -1 if key_event.keycode == KEY_BRACKETLEFT else 1
			_selected_model_index = posmod(_selected_model_index + direction, _preview_models.size())
			_update_status(_selection_status())
			get_viewport().set_input_as_handled()
		KEY_I:
			_play_selected_action("idle")
		KEY_W:
			_play_selected_action("walk")
		KEY_R:
			_play_selected_action("run")
		KEY_A:
			_play_selected_action("attack")
		KEY_H:
			_play_selected_action("hit")
		KEY_D:
			_play_selected_action("death")
		KEY_Q, KEY_E:
			_rotate_selected_model(-1.0 if key_event.keycode == KEY_Q else 1.0)
			get_viewport().set_input_as_handled()
		KEY_F:
			_reset_selected_model_rotation()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_play_selected_action("idle")


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#111827")
	sky_material.sky_horizon_color = Color("#59616a")
	sky_material.ground_bottom_color = Color("#10131c")
	sky_material.ground_horizon_color = Color("#343b48")
	sky.sky_material = sky_material
	world_environment.sky = sky
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color("#9aa9c2")
	world_environment.ambient_light_energy = 0.62
	world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.fog_enabled = true
	world_environment.fog_light_color = Color("#566071")
	world_environment.fog_density = 0.008
	environment.environment = world_environment
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "PreviewKeyLight"
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "PreviewColdFill"
	fill.position = Vector3(-5.0, 4.0, 3.0)
	fill.light_color = Color("#8aa9df")
	fill.light_energy = 1.2
	fill.omni_range = 18.0
	add_child(fill)

	var ground := MeshInstance3D.new()
	ground.name = "PreviewGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(48.0, 54.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.04, -12.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#34343d")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	add_child(ground)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(0.0, 9.0, 24.0)
	camera.fov = 58.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.4, -10.0), Vector3.UP)
	camera.current = true


func _build_gallery() -> void:
	_add_model("转世人形", VisualModelLibrary.instantiate_model("player_humanoid", func() -> Node3D: return VisualFactory.create_player_humanoid()), Vector3(-5.2, 0.0, 1.0), 0.0, 2.35)
	_add_model("荒原狼", VisualFactory.create_monster("荒原狼", 1), Vector3(-2.4, 0.0, 0.0), 0.0, 1.55)
	_add_model("铁骨兽魂", VisualFactory.create_monster("铁骨兽魂", 1), Vector3(0.4, 0.0, 0.0), 0.0, 3.15)
	_add_model("炽战残魂", VisualFactory.create_monster("炽战残魂", 1), Vector3(3.1, 0.0, 0.0), 0.0, 2.45)
	_add_model("游祟", VisualFactory.create_monster("游祟", 1), Vector3(5.7, 0.0, 0.0), 0.0, 2.35)

	# Second review row: imported NPC overrides are visible in the same stage.
	_add_model("孟婆", VisualFactory.create_npc("soup_keeper", "孟婆"), Vector3(-6.0, 0.0, -10.0), 0.0, 2.1)
	_add_model("阴司判官", VisualFactory.create_npc("judge", "阴司判官"), Vector3(-3.6, 0.0, -10.0), 0.0, 2.1)
	_add_model("阴兵守卫", VisualFactory.create_npc("guard", "阴兵守卫"), Vector3(-1.2, 0.0, -10.0), 0.0, 2.1)
	_add_model("试炼使者", VisualFactory.create_npc("trial_master", "试炼使者"), Vector3(1.2, 0.0, -10.0), 0.0, 2.1)
	_add_model("鬼市铁匠", VisualFactory.create_npc("blacksmith", "鬼市铁匠"), Vector3(3.6, 0.0, -10.0), 0.0, 2.1)
	_add_model("酆都城民", VisualFactory.create_npc("generic", "酆都城民"), Vector3(6.0, 0.0, -10.0), 0.0, 2.1)

	# Imported Fengdu architecture is reviewed in a dedicated two-row gallery.
	# Bracket keys continue cycling through all entries, including these static props.
	var environment_gallery := [
		{"key": "fengdu_wall", "label": "酆都城墙", "x": -7.5, "z": -21.0, "height": 4.8, "size": Vector3(4.2, 2.0, 1.2)},
		{"key": "fengdu_watchtower", "label": "酆都望楼", "x": -4.5, "z": -21.0, "height": 8.5, "size": Vector3(2.0, 5.0, 2.0)},
		{"key": "fengdu_hall", "label": "阴司殿堂", "x": -1.5, "z": -21.0, "height": 8.0, "size": Vector3(3.4, 5.0, 3.4)},
		{"key": "fengdu_house", "label": "酆都民居", "x": 1.5, "z": -21.0, "height": 4.2, "size": Vector3(2.5, 2.7, 2.5)},
		{"key": "fengdu_tree", "label": "冥界古树", "x": 4.5, "z": -21.0, "height": 5.5, "size": Vector3(2.0, 4.0, 2.0)},
		{"key": "fengdu_rock", "label": "冥界山岩", "x": 7.5, "z": -21.0, "height": 2.2, "size": Vector3(2.0, 1.5, 1.8)},
		{"key": "fengdu_lantern", "label": "引魂灯模型", "x": -6.0, "z": -31.0, "height": 2.4, "size": Vector3(0.8, 2.0, 0.8)},
		{"key": "fengdu_bell", "label": "镇魂铜钟", "x": -3.0, "z": -31.0, "height": 3.6, "size": Vector3(1.8, 3.0, 1.8)},
		{"key": "fengdu_east_asian_roof", "label": "中式飞檐屋顶", "x": 0.0, "z": -31.0, "height": 2.2, "size": Vector3(3.4, 1.2, 3.0)},
		{"key": "fengdu_east_asian_wall", "label": "中式院墙", "x": 3.0, "z": -31.0, "height": 3.0, "size": Vector3(3.0, 2.2, 0.5)},
		{"key": "fengdu_column_base", "label": "宫殿柱础", "x": 6.0, "z": -31.0, "height": 0.45, "size": Vector3(1.2, 0.4, 1.2)}
	]
	for item in environment_gallery:
		var model_key := str(item["key"])
		var model := VisualModelLibrary.instantiate_model(
			model_key,
			func() -> Node3D: return _create_environment_preview_fallback(item)
		)
		_add_model(str(item["label"]), model, Vector3(float(item["x"]), 0.0, float(item["z"])), 0.0, float(item["height"]))


	var gate := VisualFactory.create_fengdu_gate()
	gate.name = "FengduGatePreview"
	gate.position = Vector3(0.0, 0.0, 8.0)
	add_child(gate)
	_add_label("酆都鬼门关 · 建筑灰盒", Vector3(0.0, 11.15, -10.8), 0.32)
	var wall := VisualFactory.create_fengdu_wall_segment()
	wall.position = Vector3(-7.0, 0.0, -5.8)
	add_child(wall)
	_add_label("酆都城墙模块", Vector3(-7.0, 5.8, -5.8), 0.20)
	var lantern := VisualFactory.create_ghost_lantern()
	lantern.position = Vector3(7.0, 0.0, 0.0)
	add_child(lantern)
	_add_label("引魂灯", Vector3(7.0, 4.2, 0.0), 0.20)
	var tombstone := VisualFactory.create_soul_tombstone()
	tombstone.position = Vector3(7.0, 0.0, -6.0)
	add_child(tombstone)
	_add_label("镇魂碑", Vector3(7.0, 2.2, -6.0), 0.20)
	var pillar := VisualFactory.create_soul_pillar()
	pillar.position = Vector3(-7.0, 0.0, 1.0)
	add_child(pillar)
	_add_label("镇界石柱", Vector3(-7.0, 5.7, 1.0), 0.20)

	var city_block := VisualFactory.create_fengdu_city_block()
	city_block.position = Vector3(0.0, 0.0, -46.0)
	add_child(city_block)
	_add_label("酆都街区模块 · 内城街门 / 阴司 / 六道轮回殿 / 鬼市", Vector3(0.0, 7.0, -46.0), 0.22)


func _create_environment_preview_fallback(item: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "EnvironmentModelFallback"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FallbackMesh"
	var box := BoxMesh.new()
	box.size = item.get("size", Vector3.ONE)
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#56515f")
	material.roughness = 0.9
	mesh_instance.material_override = material
	mesh_instance.position.y = box.size.y * 0.5
	root.add_child(mesh_instance)
	root.set_meta("preview_fallback_reason", "optional_glb_missing")
	return root


func _add_model(label_text: String, model: Node3D, at: Vector3, yaw: float, label_height: float) -> void:
	if model == null:
		return
	model.position = at
	model.rotation.y = yaw
	model.set_meta("preview_label", label_text)
	model.set_meta("preview_base_yaw", yaw)
	var source_path := str(model.get_meta("model_source", "procedural_fallback"))
	var source_label := "GLB" if source_path != "procedural_fallback" else "程序化回退"
	model.set_meta("preview_source_label", source_label)
	_preview_models.append(model)
	add_child(model)
	_add_label("%s · %s" % [label_text, source_label], at + Vector3(0.0, label_height, 0.0), 0.24)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewControls"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(440.0, 88.0)
	layer.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "美术资源预览台 · 1-9 / 0 选择 · [ ] 切换 · Q/E 旋转 · F 复位"
	title.add_theme_font_size_override("font_size", 17)
	layout.add_child(title)
	_status_label = Label.new()
	_status_label.text = "I 待机  W 行走  R 奔跑  A 攻击  H 受击  D 死亡  Q/E 检查模型  F 复位  Esc 待机"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)


func _rotate_selected_model(direction: float) -> void:
	if _preview_models.is_empty():
		return
	var model := _preview_models[_selected_model_index]
	model.rotation.y += deg_to_rad(15.0 * direction)
	_update_status("%s：当前朝向 %.0f° · Q/E 每次旋转 15°" % [
		_model_label(_selected_model_index), rad_to_deg(wrapf(model.rotation.y, -PI, PI))
	])


func _reset_selected_model_rotation() -> void:
	if _preview_models.is_empty():
		return
	var model := _preview_models[_selected_model_index]
	model.rotation.y = float(model.get_meta("preview_base_yaw", 0.0))
	_update_status("%s：已恢复初始朝向" % _model_label(_selected_model_index))


func _play_selected_action(action_name: String) -> void:
	if _preview_models.is_empty():
		return
	var model := _preview_models[_selected_model_index]
	var controller := model.get_node_or_null("ModelAnimationController")
	if controller != null and controller.has_method("play_action"):
		var played := false
		if action_name in ["idle", "walk", "run"] and controller.has_method("play_preview_state"):
			played = bool(controller.call("play_preview_state", action_name))
		else:
			played = bool(controller.call("play_action", action_name))
		if played:
			if action_name in ["idle", "walk", "run"]:
				_update_status("%s：循环播放 %s" % [_model_label(_selected_model_index), action_name])
			else:
				_update_status("%s：播放 %s" % [_model_label(_selected_model_index), action_name])
		else:
			_update_status("%s：没有匹配的 %s 动画" % [_model_label(_selected_model_index), action_name])
		get_viewport().set_input_as_handled()
		return

	var player := _find_animation_player(model)
	if player == null:
		_update_status("%s：没有 AnimationPlayer，当前为静态占位模型" % _model_label(_selected_model_index))
		get_viewport().set_input_as_handled()
		return
	var clip := _find_animation_clip(player, action_name)
	if clip.is_empty():
		_update_status("%s：未找到 %s 动画" % [_model_label(_selected_model_index), action_name])
		get_viewport().set_input_as_handled()
		return
	var animation := player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if action_name in ["idle", "walk", "run"] else Animation.LOOP_NONE
	player.play(clip, 0.12)
	_update_status("%s：播放 %s（%s）" % [_model_label(_selected_model_index), action_name, clip])
	get_viewport().set_input_as_handled()


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_animation_clip(player: AnimationPlayer, action_name: String) -> String:
	var keywords: Array[String] = []
	match action_name:
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
	for keyword in keywords:
		for clip_name in player.get_animation_list():
			if str(clip_name).to_lower().contains(keyword):
				return str(clip_name)
	return ""


func _model_label(index: int) -> String:
	if index < 0 or index >= _preview_models.size():
		return "未知模型"
	return str(_preview_models[index].get_meta("preview_label", "模型"))


func _selection_status() -> String:
	if _preview_models.is_empty():
		return "预览库暂无模型"
	var model: Node3D = _preview_models[_selected_model_index]
	var source_label := str(model.get_meta("preview_source_label", "来源未知"))
	var model_key := str(model.get_meta("model_key", "unknown"))
	var diagnostics := _collect_model_diagnostics(model)
	var clip_names: Array = diagnostics["clips"]
	var clip_summary := "无动画片段" if clip_names.is_empty() else "动画 %d 段" % clip_names.size()
	var humanoid_summary := ""
	if model.has_meta("humanoid_rig_ready"):
		var rig_ready := bool(model.get_meta("humanoid_rig_ready", false))
		var animation_ready := bool(model.get_meta("humanoid_animation_ready", false))
		var bone_count := int(model.get_meta("humanoid_bone_count", 0))
		humanoid_summary = "\\n人形验收：%s · %d骨骼 · 动画片段：%s" % [
			"骨架通过" if rig_ready else "骨架未通过", bone_count,
			"已发现" if animation_ready else "未发现"
		]
	if model_key == "wolf" or model_key == "iron_beast":
		var bone_names: Array = diagnostics["bone_names"]
		var front_matches := _count_named_bones(bone_names, ["front", "fore"], ["leg", "limb", "paw", "foot", "shoulder"])
		var rear_matches := _count_named_bones(bone_names, ["hind", "back", "rear"], ["leg", "limb", "paw", "foot", "thigh", "hip"])
		humanoid_summary = "\\n四足骨架线索：前肢 %d · 后肢 %d · 骨骼名 %d（仅初筛）" % [
			front_matches, rear_matches, bone_names.size()
		]
	if model_key == "player_humanoid":
		var socket_states: Array[String] = []
		for slot in ["weapon", "offhand", "back"]:
			EquipmentVisualFactory.get_or_create_socket(model, slot)
			var binding := EquipmentVisualFactory.inspect_socket_binding(model, slot)
			socket_states.append("%s:%s" % [slot, "骨骼挂接" if bool(binding.get("follows_bone", false)) else "非骨骼挂接"])
		var socket_summary := ""
		for socket_state in socket_states:
			if not socket_summary.is_empty():
				socket_summary += " / "
			socket_summary += socket_state
		humanoid_summary += "\\n装备挂点：" + socket_summary
	var bounds_size: Vector3 = diagnostics["bounds_size"]
	var dimension_summary := "尺寸 %.2f × %.2f × %.2f m" % [bounds_size.x, bounds_size.y, bounds_size.z]
	var normalization_summary := ""
	if model.has_meta("model_normalization_factor"):
		normalization_summary = " · 归一化 %.3f" % float(model.get_meta("model_normalization_factor"))
	elif bool(model.get_meta("model_scale_review_required", false)):
		normalization_summary = " · 尺度需复核"
	var fallback_reason := str(model.get_meta("preview_fallback_reason", ""))
	if not fallback_reason.is_empty():
		normalization_summary += " · 回退原因：" + fallback_reason
	return "当前：%s · %s · key=%s\\n%s%s\\n网格 %d · 骨骼 %d · 动画播放器 %d · %s%s" % [
		_model_label(_selected_model_index), source_label, model_key, dimension_summary,
		normalization_summary, int(diagnostics["meshes"]), int(diagnostics["skeletons"]),
		int(diagnostics["players"]), clip_summary, humanoid_summary
	]

func _collect_model_diagnostics(root: Node) -> Dictionary:
	var result := {
		"meshes": 0, "skeletons": 0, "players": 0, "clips": [], "bone_names": [],
		"bounds_found": false, "bounds_min": Vector3.ZERO, "bounds_max": Vector3.ZERO,
		"bounds_size": Vector3.ZERO
	}
	_collect_model_diagnostics_recursive(root, Transform3D.IDENTITY, result)
	if bool(result["bounds_found"]):
		result["bounds_size"] = (result["bounds_max"] as Vector3) - (result["bounds_min"] as Vector3)
	return result


func _collect_model_diagnostics_recursive(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result["meshes"] = int(result["meshes"]) + 1
		var mesh := (node as MeshInstance3D).mesh
		var mesh_bounds: AABB = mesh.get_aabb() * current_transform
		var mesh_minimum := mesh_bounds.position
		var mesh_maximum := mesh_bounds.position + mesh_bounds.size
		if not bool(result["bounds_found"]):
			result["bounds_min"] = mesh_minimum
			result["bounds_max"] = mesh_maximum
			result["bounds_found"] = true
		else:
			result["bounds_min"] = (result["bounds_min"] as Vector3).min(mesh_minimum)
			result["bounds_max"] = (result["bounds_max"] as Vector3).max(mesh_maximum)
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		result["skeletons"] = int(result["skeletons"]) + 1
		var bone_names: Array = result["bone_names"]
		for bone_index in range(skeleton.get_bone_count()):
			bone_names.append(skeleton.get_bone_name(bone_index))
		result["bone_names"] = bone_names
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		result["players"] = int(result["players"]) + 1
		var clips: Array = result["clips"]
		for clip_name in player.get_animation_list():
			clips.append(str(clip_name))
		result["clips"] = clips
	for child in node.get_children():
		_collect_model_diagnostics_recursive(child, current_transform, result)


func _update_status(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = message


func _add_label(label_text: String, at: Vector3, font_size: float) -> void:
	var label := Label3D.new()
	label.text = label_text
	label.position = at
	label.font_size = int(48.0 * font_size)
	label.pixel_size = 0.008
	label.modulate = Color("#e4d7b8")
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _count_named_bones(bone_names: Array, side_tokens: Array[String], limb_tokens: Array[String]) -> int:
	var matches := 0
	for raw_name in bone_names:
		var normalized := str(raw_name).to_lower().replace("_", "").replace("-", "").replace(" ", "").replace(":", "")
		var has_side := false
		var has_limb := false
		for token in side_tokens:
			if normalized.contains(token):
				has_side = true
				break
		for token in limb_tokens:
			if normalized.contains(token):
				has_limb = true
				break
		if has_side and has_limb:
			matches += 1
	return matches
