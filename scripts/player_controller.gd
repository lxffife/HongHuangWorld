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
