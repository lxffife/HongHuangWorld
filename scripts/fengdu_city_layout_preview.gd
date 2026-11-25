extends Node3D
## Standalone, navigable-scale layout review for the major districts of Fengdu.
## This is a visual planning scene, not a production streamed world or gameplay spawn map.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")

const CITY_HALF_EXTENT := 36.0
const WALL_SEGMENTS := 9
const WALL_STEP := 8.0

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_roads_and_plaza()
	_build_perimeter()
	_build_districts()
	_build_signage()


func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#11131c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a1a8bd")
	environment.ambient_light_energy = 0.72
	environment.fog_enabled = true
	environment.fog_light_color = Color("#444354")
	environment.fog_density = 0.004
	environment_node.environment = environment
	add_child(environment_node)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-54.0, -32.0, 0.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	add_child(key_light)

	var camera := Camera3D.new()
	camera.name = "FengduOverviewCamera"
	camera.position = Vector3(0.0, 78.0, 72.0)
	camera.fov = 58.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.current = true


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "CityGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(100.0, 100.0)
	ground.mesh = plane
	ground.position.y = -0.12
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#292a34")
	material.roughness = 0.96
	ground.material_override = material
	add_child(ground)


func _build_roads_and_plaza() -> void:
	_add_paving("NorthSouthAvenue", Vector3(7.0, 0.16, 70.0), Vector3(0.0, 0.0, 0.0), Color("#625b61"))
	_add_paving("EastWestAvenue", Vector3(70.0, 0.16, 7.0), Vector3(0.0, 0.01, 0.0), Color("#625b61"))
	_add_paving("CentralPlaza", Vector3(17.0, 0.20, 17.0), Vector3(0.0, 0.03, 0.0), Color("#71656a"))
	for x in [-6.0, 6.0]:
		for z in [-6.0, 6.0]:
			var lantern := VisualFactory.create_ghost_lantern()
			lantern.position = Vector3(x, 0.0, z)
			add_child(lantern)
	for x in [-4.0, 4.0]:
		var pillar := VisualFactory.create_soul_pillar()
		pillar.position = Vector3(x, 0.0, 0.0)
		pillar.scale = Vector3.ONE * 0.55
		add_child(pillar)


func _add_paving(node_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var tile := MeshInstance3D.new()
	tile.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	tile.mesh = mesh
	tile.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	tile.material_override = material
	add_child(tile)


func _build_perimeter() -> void:
	for index in range(WALL_SEGMENTS):
		var offset := -CITY_HALF_EXTENT + WALL_STEP * 0.5 + float(index) * WALL_STEP
		if index != 4:
			_add_wall(Vector3(offset, 0.0, -CITY_HALF_EXTENT), 0.0, "North")
			_add_wall(Vector3(offset, 0.0, CITY_HALF_EXTENT), 0.0, "South")
		_add_wall(Vector3(-CITY_HALF_EXTENT, 0.0, offset), PI * 0.5, "West")
		_add_wall(Vector3(CITY_HALF_EXTENT, 0.0, offset), PI * 0.5, "East")

	for x in [-CITY_HALF_EXTENT, CITY_HALF_EXTENT]:
		for z in [-CITY_HALF_EXTENT, CITY_HALF_EXTENT]:
			var tower := VisualFactory.create_fengdu_watchtower()
			tower.position = Vector3(x, 0.0, z)
			add_child(tower)

	var gate := VisualFactory.create_fengdu_inner_gate()
	gate.position = Vector3(0.0, 0.0, CITY_HALF_EXTENT)
	add_child(gate)


func _add_wall(at: Vector3, yaw: float, side: String) -> void:
	var wall := VisualFactory.create_fengdu_wall_segment()
	wall.name = side + "WallSegment"
	wall.position = at
	wall.rotation.y = yaw
	add_child(wall)


func _build_districts() -> void:
	# Administrative quarter: records, judgments and official business.
	var office := VisualFactory.create_yinsi_office_facade()
	office.position = Vector3(-19.0, 0.0, -19.0)
	add_child(office)
	var second_office := VisualFactory.create_yinsi_office_facade()
	second_office.scale = Vector3.ONE * 0.72
	second_office.position = Vector3(-19.0, 0.0, -28.0)
	add_child(second_office)

	# Reincarnation quarter: the hall is set back from the main avenue.
	var hall := VisualFactory.create_reincarnation_hall()
	hall.position = Vector3(19.0, 0.0, -20.0)
	add_child(hall)
	for x in [13.0, 25.0]:
		var marker := VisualFactory.create_soul_tombstone()
		marker.position = Vector3(x, 0.0, -11.0)
		add_child(marker)

	# Ghost market: stalls face the cross street, leaving a clear pedestrian lane.
	for x in [-25.0, -16.0, -7.0]:
		var stall := VisualFactory.create_ghost_market_stall()
		stall.position = Vector3(x, 0.0, 18.0)
		add_child(stall)
		var second_stall := VisualFactory.create_ghost_market_stall()
		second_stall.rotation.y = PI
		second_stall.scale = Vector3.ONE * 0.82
		second_stall.position = Vector3(x, 0.0, 27.0)
		add_child(second_stall)

	# Residential ward: restrained courtyard houses are deliberately low-rise.
	for x in [12.0, 22.0]:
		for z in [13.0, 25.0]:
			_add_residence(Vector3(x, 0.0, z))

	# Lanterns mark the district thresholds and the southern gate approach.
	for at in [
		Vector3(-5.5, 0.0, 12.0), Vector3(-5.5, 0.0, 29.0),
		Vector3(5.5, 0.0, -29.0), Vector3(5.5, 0.0, -12.0),
		Vector3(0.0, 0.0, 31.0)
	]:
		var lantern := VisualFactory.create_ghost_lantern()
		lantern.position = at
		lantern.scale = Vector3.ONE * 0.72
		add_child(lantern)


func _add_residence(at: Vector3) -> void:
	var root := StaticBody3D.new()
	root.name = "FengduResidence"
	_add_box(root, "Foundation", Vector3(7.0, 0.5, 6.0), Vector3(0.0, 0.25, 0.0), Color("#393641"))
	_add_box(root, "Walls", Vector3(5.8, 3.0, 4.8), Vector3(0.0, 1.95, 0.0), Color("#514650"))
	_add_box(root, "Roof", Vector3(7.0, 0.45, 6.0), Vector3(0.0, 3.65, 0.0), Color("#292a39"))
	_add_box(root, "Door", Vector3(1.35, 2.2, 0.12), Vector3(0.0, 1.35, -2.46), Color("#211f2a"))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 3.6, 5.0)
	collision.shape = shape
	collision.position = Vector3(0.0, 1.9, 0.0)
	root.add_child(collision)
	root.position = at
	add_child(root)


func _add_box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	part.material_override = material
	parent.add_child(part)


func _build_signage() -> void:
	_add_sign("酆都 · 内城总览", Vector3(0.0, 8.0, 0.0), 34)
	_add_sign("阴司官署区", Vector3(-19.0, 6.2, -34.0), 22)
	_add_sign("六道轮回区", Vector3(19.0, 6.2, -34.0), 22)
	_add_sign("鬼市坊区", Vector3(-19.0, 4.0, 32.0), 22)
	_add_sign("居民坊区", Vector3(19.0, 4.0, 32.0), 22)
	_add_sign("中央主街 · 轮回大道", Vector3(0.0, 2.2, 12.0), 18)


func _add_sign(text_value: String, at: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.position = at
	label.font_size = font_size
	label.outline_size = 7
	label.modulate = Color("#ead7b2")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
