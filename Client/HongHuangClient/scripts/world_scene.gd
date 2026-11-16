extends Node3D

@onready var hud_label: Label = $HUD/Panel/Margin/Content/Status

var local_player: HHPlayerController
var local_target_position := Vector3.ZERO
var remote_players: Dictionary = {}
var remote_targets: Dictionary = {}
var remote_yaws: Dictionary = {}

func _ready() -> void:
	_build_environment()
	_build_terrain()
	_build_player()
	if HHSession.world_network != null:
		HHSession.world_network.entities_updated.connect(_on_entities_updated)
		var spawn: Dictionary = HHSession.world_snapshot
		local_target_position = Vector3(float(spawn.get("position_x", 0.0)), float(spawn.get("position_y", 0.15)), float(spawn.get("position_z", 0.0)))
		local_player.position = local_target_position
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
	local_player = HHPlayerController.new()
	local_player.name = "LocalPlayer"
	local_player.position = Vector3(0.0, 0.15, 0.0)
	add_child(local_player)

func _update_hud() -> void:
	var snapshot: Dictionary = HHSession.world_snapshot
	var world_id := str(snapshot.get("world_id", "青云人界"))
	var character_name := str(snapshot.get("name", "初入洪荒"))
	hud_label.text = "洪荒 · " + world_id + "\n" + character_name + "  |  WASD 移动 · 鼠标转向 · ESC 释放鼠标\n服务器权威移动已启用 · 20Hz 实体快照 · 远端玩家同步"

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_entities_updated(entities: Array) -> void:
	var seen: Dictionary = {}
	var own_id := str(HHSession.world_snapshot.get("character_id", ""))
	for entity in entities:
		if not entity is Dictionary:
			continue
		var character_id := str(entity.get("character_id", ""))
		if character_id.is_empty():
			continue
		var target := Vector3(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)), float(entity.get("z", 0.0)))
		if character_id == own_id:
			local_target_position = target
			continue
		seen[character_id] = true
		if not remote_players.has(character_id):
			remote_players[character_id] = _create_remote_player(str(entity.get("name", "修士")))
		remote_targets[character_id] = target
		remote_yaws[character_id] = float(entity.get("yaw", 0.0))
	for character_id in remote_players.keys():
		if not seen.has(character_id):
			remote_players[character_id].queue_free()
			remote_players.erase(character_id)
			remote_targets.erase(character_id)
			remote_yaws.erase(character_id)

func _create_remote_player(character_name: String) -> Node3D:
	var remote := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.75
	body.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#79a9c9")
	body.material_override = material
	body.position.y = 0.88
	remote.add_child(body)
	var label := Label3D.new()
	label.text = character_name
	label.position.y = 2.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	remote.add_child(label)
	add_child(remote)
	return remote

func _process(delta: float) -> void:
	if is_instance_valid(local_player):
		local_player.position = local_player.position.lerp(local_target_position, minf(delta * 14.0, 1.0))
	for character_id in remote_players:
		var remote: Node3D = remote_players[character_id]
		var target: Vector3 = remote_targets.get(character_id, remote.position)
		remote.position = remote.position.lerp(target, minf(delta * 14.0, 1.0))
		var target_yaw := float(remote_yaws.get(character_id, remote.rotation.y))
		remote.rotation.y = lerp_angle(remote.rotation.y, target_yaw, minf(delta * 12.0, 1.0))
