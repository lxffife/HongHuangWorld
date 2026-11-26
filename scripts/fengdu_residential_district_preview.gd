extends Node3D
## District-scale review scene for modular Fengdu residential streets.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")


func _ready() -> void:
	var district := VisualFactory.create_fengdu_residential_district()
	district.name = "ResidentialDistrictKit"
	add_child(district)

	var key_light := DirectionalLight3D.new()
	key_light.name = "ReviewKeyLight"
	key_light.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	key_light.light_energy = 1.2
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "CoolFill"
	fill_light.position = Vector3(0.0, 12.0, 8.0)
	fill_light.light_color = Color("#9bb8c5")
	fill_light.light_energy = 0.75
	fill_light.omni_range = 58.0
	add_child(fill_light)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#87909f")
	environment.ambient_light_energy = 0.58
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.name = "DistrictReviewCamera"
	camera.position = Vector3(48.0, 42.0, 54.0)
	camera.fov = 55.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, 1.0), Vector3.UP)
