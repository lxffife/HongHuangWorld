extends Node3D

@onready var hud_label: Label = $HUD/Panel/Margin/Content/Status

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_player()
	_update_hud()

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#142b49")
	sky_material.sky_horizon_color = Color("#d3a878")
	sky_material.ground_bottom_color = Color("#182333")
	sky_material.ground_horizon_color = Color("#a58b6b")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9fb4d0")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#9ba9b8")
	environment.fog_density = 0.0018
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

func _build_terrain() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(240.0, 240.0)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#354c43")
	material.roughness = 0.94
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(240.0, 0.2, 240.0)
	collision.shape = shape
	collision.position.y = -0.1
	ground.add_child(collision)
	add_child(ground)

	for i in range(12):
		var rock := MeshInstance3D.new()
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = randf_range(0.7, 2.0)
		rock_mesh.height = rock_mesh.radius * 1.5
		rock.mesh = rock_mesh
		rock.position = Vector3(randf_range(-28.0, 28.0), rock_mesh.radius * 0.35, randf_range(-28.0, 28.0))
		var rock_material := StandardMaterial3D.new()
		rock_material.albedo_color = Color("#53645d")
		rock_material.roughness = 1.0
		rock.material_override = rock_material
		add_child(rock)

func _build_player() -> void:
	var player := HHPlayerController.new()
	player.name = "LocalPlayer"
	player.position = Vector3(0.0, 0.15, 0.0)
	add_child(player)

func _update_hud() -> void:
	var snapshot: Dictionary = HHSession.world_snapshot
	var world_id := str(snapshot.get("world_id", "青云人界"))
	var character_name := str(snapshot.get("name", "初入洪荒"))
	hud_label.text = "洪荒 · " + world_id + "\n" + character_name + "  |  WASD 移动 · 空格跳跃 · 鼠标转向 · ESC 释放鼠标\n当前为本地角色控制原型，服务器权威移动同步正在接入。"

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
