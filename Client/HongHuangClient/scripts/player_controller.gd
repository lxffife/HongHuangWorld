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
var yaw := 0.0
var pitch := -0.18
var input_send_accumulator := 0.0
var input_sequence := 0
var jump_pending := false
var is_dead := false
var current_move_input := Vector2.ZERO
var last_send_error: int = OK
var movement_network_ready := false
var move_key_states := {"forward": false, "back": false, "left": false, "right": false}

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
	visual.position.y = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d5b47a")
	material.metallic = 0.12
	material.roughness = 0.48
	visual.material_override = material
	add_child(visual)

	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)

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

func _input(event: InputEvent) -> void:
	# 直接采集物理键盘事件，避免 InputMap/键盘布局或 UI 焦点导致 WASD 状态丢失。
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_W or key_event.keycode == KEY_W:
			move_key_states["forward"] = key_event.pressed
		elif key_event.physical_keycode == KEY_S or key_event.keycode == KEY_S:
			move_key_states["back"] = key_event.pressed
		elif key_event.physical_keycode == KEY_A or key_event.keycode == KEY_A:
			move_key_states["left"] = key_event.pressed
		elif key_event.physical_keycode == KEY_D or key_event.keycode == KEY_D:
			move_key_states["right"] = key_event.pressed

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for key_name in move_key_states.keys():
			move_key_states[key_name] = false

func is_move_key_pressed(direction: String) -> bool:
	return bool(move_key_states.get(direction, false))

func _get_move_input() -> Vector2:
	var x := float(move_key_states["right"]) - float(move_key_states["left"])
	var y := float(move_key_states["back"]) - float(move_key_states["forward"])
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
