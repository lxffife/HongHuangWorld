extends Node3D
## Isolated visual review stage for imported models, materials and animation clips.
## Keyboard: 1-5 select model; I/W/R/A/H/D play idle/walk/run/attack/hit/death.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")
const VisualModelLibrary = preload("res://scripts/visual_model_library.gd")

var _preview_models: Array[Node3D] = []
var _selected_model_index := 0
var _status_label: Label


func _ready() -> void:
	_build_stage()
	_build_gallery()
	_build_controls()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_selected_model_index = clampi(key_event.keycode - KEY_1, 0, _preview_models.size() - 1)
			_update_status("已选择：" + _model_label(_selected_model_index))
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
	plane.size = Vector2(32.0, 28.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.04, -3.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#34343d")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	add_child(ground)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(0.0, 5.2, 15.5)
	camera.fov = 48.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.6, -2.0), Vector3.UP)
	camera.current = true


func _build_gallery() -> void:
	_add_model("转世人形", VisualModelLibrary.instantiate_model("player_humanoid", func() -> Node3D: return VisualFactory.create_player_humanoid()), Vector3(-5.2, 0.0, 1.0), 0.0, 2.35)
	_add_model("荒原狼", VisualFactory.create_monster("荒原狼", 1), Vector3(-2.4, 0.0, 0.0), 0.0, 1.55)
	_add_model("铁骨兽魂", VisualFactory.create_monster("铁骨兽魂", 1), Vector3(0.4, 0.0, 0.0), 0.0, 3.15)
	_add_model("炽战残魂", VisualFactory.create_monster("炽战残魂", 1), Vector3(3.1, 0.0, 0.0), 0.0, 2.45)
	_add_model("游祟", VisualFactory.create_monster("游祟", 1), Vector3(5.7, 0.0, 0.0), 0.0, 2.35)

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


func _add_model(label_text: String, model: Node3D, at: Vector3, yaw: float, label_height: float) -> void:
	if model == null:
		return
	model.position = at
	model.rotation.y = yaw
	model.set_meta("preview_label", label_text)
	_preview_models.append(model)
	add_child(model)
	_add_label(label_text, at + Vector3(0.0, label_height, 0.0), 0.24)


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
	title.text = "美术资源预览台 · 1-5 选择模型"
	title.add_theme_font_size_override("font_size", 17)
	layout.add_child(title)
	_status_label = Label.new()
	_status_label.text = "I 待机  W 行走  R 奔跑  A 攻击  H 受击  D 死亡  Esc 待机"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status_label)


func _play_selected_action(action_name: String) -> void:
	if _preview_models.is_empty():
		return
	var model := _preview_models[_selected_model_index]
	var controller := model.get_node_or_null("ModelAnimationController")
	if controller != null and controller.has_method("play_action"):
		if bool(controller.call("play_action", action_name)):
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
