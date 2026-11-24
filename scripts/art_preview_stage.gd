extends Node3D
## Isolated visual review stage for comparing the current replaceable blockout models.
## This scene is intentionally separate from the live multiplayer world.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")

func _ready() -> void:
	_build_stage()
	_build_gallery()

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
	_add_model("转世人形", VisualFactory.create_player_humanoid(), Vector3(-5.2, 0.0, 1.0), 0.0)
	_add_model("荒原狼", VisualFactory.create_monster("荒原狼", 1), Vector3(-2.4, 0.0, 0.0), 0.0)
	_add_model("铁骨兽魂", VisualFactory.create_monster("铁骨兽魂", 1), Vector3(0.4, 0.0, 0.0), 0.0)
	_add_model("炽战残魂", VisualFactory.create_monster("炽战残魂", 1), Vector3(3.1, 0.0, 0.0), 0.0)
	_add_model("游祟", VisualFactory.create_monster("游祟", 1), Vector3(5.7, 0.0, 0.0), 0.0)

	var gate := VisualFactory.create_fengdu_gate()
	gate.name = "FengduGatePreview"
	gate.position = Vector3(0.0, 0.0, 8.0)
	add_child(gate)
	_add_label("酆都鬼门关 · 建筑灰盒", Vector3(0.0, 2.1, -14.0), 0.32)

func _add_model(label_text: String, model: Node3D, at: Vector3, yaw: float) -> void:
	if model == null:
		return
	model.position = at
	model.rotation.y = yaw
	add_child(model)
	_add_label(label_text, at + Vector3(0.0, 2.25, 0.0), 0.24)

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
