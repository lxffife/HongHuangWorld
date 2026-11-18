extends CharacterBody3D
class_name HHPlayerController

@export var move_speed := 5.5
@export var acceleration := 18.0
@export var gravity := 18.0
@export var jump_velocity := 6.5
@export var mouse_sensitivity := 0.0025

var camera_pivot: Node3D
var camera: Camera3D
var visual: MeshInstance3D
var collision_shape: CollisionShape3D
var base_visual_mesh: Mesh
var base_visual_material: Material
var base_collision_shape: Shape3D
var soul_orb_core: MeshInstance3D
var soul_orb_halo: MeshInstance3D
var soul_form_enabled := false
var soul_form_time := 0.0
var soul_form_scale := 1.0
var yaw := 0.0
var pitch := -0.18
var input_send_accumulator := 0.0
var input_sequence := 0
var jump_pending := false
var is_dead := false
var current_move_input := Vector2.ZERO
var last_send_error: int = OK
var movement_network_ready := false
func _ready() -> void:
	_build_player()
	_ensure_input_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_player() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	visual = MeshInstance3D.new()
	visual.name = "PlaceholderBody"
	visual.mesh = capsule
	base_visual_mesh = capsule
	visual.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d5b47a")
	material.metallic = 0.12
	material.roughness = 0.48
	visual.material_override = material
	base_visual_material = material
	add_child(visual)

	collision_shape = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	collision_shape.shape = shape
	collision_shape.position.y = 0.9
	base_collision_shape = shape
	add_child(collision_shape)

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = 1.45
	add_child(camera_pivot)
	var spring := SpringArm3D.new()
	spring.spring_length = 4.2
	spring.margin = 0.2
	camera_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 72.0
	spring.add_child(camera)
	camera_pivot.rotation.x = pitch

func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("release_mouse", KEY_ESCAPE)

func _add_key_action(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# 同时注册物理键位和逻辑键位，兼容不同键盘布局与输入法状态。
	var physical_event := InputEventKey.new()
	physical_event.physical_keycode = keycode
	InputMap.action_add_event(action, physical_event)
	var logical_event := InputEventKey.new()
	logical_event.keycode = keycode
	InputMap.action_add_event(action, logical_event)


func _is_move_key_down(physical_key: Key, logical_key: Key) -> bool:
	# 直接查询当前键盘状态，按键松开后立即归零，不依赖释放事件是否被 UI/焦点吞掉。
	return Input.is_physical_key_pressed(physical_key) or Input.is_key_pressed(logical_key)

func is_move_key_pressed(direction: String) -> bool:
	match direction:
		"forward":
			return _is_move_key_down(KEY_W, KEY_W)
		"back":
			return _is_move_key_down(KEY_S, KEY_S)
		"left":
			return _is_move_key_down(KEY_A, KEY_A)
		"right":
			return _is_move_key_down(KEY_D, KEY_D)
	return false

func _get_move_input() -> Vector2:
	var x := float(_is_move_key_down(KEY_D, KEY_D)) - float(_is_move_key_down(KEY_A, KEY_A))
	var y := float(_is_move_key_down(KEY_S, KEY_S)) - float(_is_move_key_down(KEY_W, KEY_W))
	var input_vector := Vector2(x, y)
	return input_vector.normalized() if input_vector.length_squared() > 1.0 else input_vector

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if is_dead:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# 首次点击游戏画面只负责锁定鼠标，不误触发攻击。
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		var world := get_parent()
		if world != null and world.has_method("_request_nearest_monster_attack"):
			world.call("_request_nearest_monster_attack")
	elif event.is_action_pressed("jump"):
		jump_pending = true
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -0.9, 0.35)
		camera_pivot.rotation = Vector3(pitch, yaw, 0.0)

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3.ZERO
		return
	var input_2d := _get_move_input()
	current_move_input = input_2d
	if camera_pivot == null or not is_instance_valid(camera_pivot):
		return
	if visual == null or not is_instance_valid(visual):
		return
	var camera_basis := camera_pivot.global_transform.basis
	var direction := camera_basis.x * input_2d.x + camera_basis.z * input_2d.y
	direction.y = 0.0
	direction = direction.normalized()
	if direction.length_squared() > 0.001:
		var target_yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 12.0 * delta)

	input_send_accumulator += delta
	if input_send_accumulator >= 0.05:
		input_send_accumulator = 0.0
		var network := HHSession.world_network
		movement_network_ready = network != null and network.is_world_ready()
		last_send_error = OK
		if movement_network_ready:
			input_sequence += 1
			var send_error: Error = network.send_input(direction.x, direction.z, input_sequence, jump_pending)
			if send_error == OK:
				jump_pending = false
			last_send_error = send_error
			if send_error != OK:
				push_warning("World movement input send failed: " + str(send_error))


func set_soul_form(enabled: bool, stage: int = 1, visual_scale: float = 0.35) -> void:
	if not is_instance_valid(visual) or not is_instance_valid(collision_shape):
		return
	soul_form_enabled = enabled
	if not enabled:
		visual.mesh = base_visual_mesh
		visual.material_override = base_visual_material
		visual.position = Vector3(0.0, 0.9, 0.0)
		visual.scale = Vector3.ONE
		collision_shape.shape = base_collision_shape
		collision_shape.position = Vector3(0.0, 0.9, 0.0)
		camera_pivot.position.y = 1.45
		move_speed = 5.5
		if is_instance_valid(soul_orb_halo):
			soul_orb_halo.visible = false
		return

	var orb := SphereMesh.new()
	orb.radius = 0.34
	orb.height = 0.68
	orb.radial_segments = 24
	orb.rings = 12
	visual.mesh = orb
	visual.position = Vector3(0.0, 0.42, 0.0)
	visual.scale = Vector3.ONE * clampf(visual_scale / 0.35, 0.85, 3.8)
	var spirit_material := StandardMaterial3D.new()
	spirit_material.albedo_color = Color(0.30, 0.82, 1.0, 0.72)
	spirit_material.emission_enabled = true
	spirit_material.emission = Color(0.12, 0.62, 1.0)
	spirit_material.emission_energy_multiplier = 2.4 + float(maxi(stage - 1, 0)) * 0.35
	spirit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spirit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = spirit_material

	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.3 * clampf(visual_scale / 0.35, 0.85, 3.0)
	collision_shape.shape = sphere_shape
	collision_shape.position = Vector3(0.0, 0.36, 0.0)
	camera_pivot.position.y = 0.72
	move_speed = 4.8

	if not is_instance_valid(soul_orb_halo):
		soul_orb_halo = MeshInstance3D.new()
		soul_orb_halo.name = "SoulOrbHalo"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.48
		torus.rings = 32
		torus.ring_segments = 8
		soul_orb_halo.mesh = torus
		var halo_material := StandardMaterial3D.new()
		halo_material.albedo_color = Color(0.22, 0.72, 1.0, 0.55)
		halo_material.emission_enabled = true
		halo_material.emission = Color(0.08, 0.48, 1.0)
		halo_material.emission_energy_multiplier = 1.6
		halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		soul_orb_halo.material_override = halo_material
		soul_orb_halo.position = Vector3(0.0, 0.42, 0.0)
		add_child(soul_orb_halo)
	soul_orb_halo.visible = true
	soul_orb_halo.scale = Vector3.ONE * clampf(visual_scale / 0.35, 0.85, 3.8)

func _process(delta: float) -> void:
	if not soul_form_enabled or not is_instance_valid(visual):
		return
	soul_form_time += delta
	var bob := sin(soul_form_time * 2.4) * 0.055
	visual.position.y = 0.42 + bob
	if is_instance_valid(soul_orb_halo):
		soul_orb_halo.position.y = 0.42 + bob
		soul_orb_halo.rotation.y += delta * 0.65
		var pulse := 1.0 + sin(soul_form_time * 2.0) * 0.035
		soul_orb_halo.scale = Vector3.ONE * soul_form_scale * pulse
