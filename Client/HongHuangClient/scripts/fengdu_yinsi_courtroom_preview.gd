extends Node3D
## Standalone review scene for the Yinsi judgment hall graybox.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")


func _ready() -> void:
	var courtroom := VisualFactory.create_yinsi_courtroom_interior()
	courtroom.name = "YinsiCourtroomInteriorKit"
	add_child(courtroom)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -26.0, 0.0)
	key_light.light_energy = 1.2
	add_child(key_light)

	var warm_fill := OmniLight3D.new()
	warm_fill.position = Vector3(0.0, 4.0, 2.0)
	warm_fill.light_color = Color("#d4b38b")
	warm_fill.light_energy = 1.15
	warm_fill.omni_range = 24.0
	add_child(warm_fill)

	for x in [-6.5, 6.5]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 3.6, 5.0)
		lamp.light_color = Color("#83b9ad")
		lamp.light_energy = 0.65
		lamp.omni_range = 10.0
		add_child(lamp)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#201d27")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a0938a")
	environment.ambient_light_energy = 0.72
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.position = Vector3(22.0, 18.0, -25.0)
	camera.fov = 58.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.5, 0.0), Vector3.UP)
