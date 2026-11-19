extends CharacterBody3D

const UnderworldVisualFactory = preload("res://scripts/underworld_visual_factory.gd")
const VisualModelLibrary = preload("res://scripts/visual_model_library.gd")

@export var move_speed := 5.5
@export var acceleration := 18.0
@export var gravity := 18.0
@export var jump_velocity := 6.5
@export var mouse_sensitivity := 0.0025

var camera_pivot: Node3D
var camera_pivot_base_position := Vector3(0.0, 1.45, 0.0)
var hit_reaction_time := 0.0
var hit_reaction_strength := 0.0
var camera: Camera3D
var visual: MeshInstance3D
var player_humanoid: Node3D
var humanoid_animation_time := 0.0
var attack_animation_time := 0.0
var collision_shape: CollisionShape3D
var base_visual_mesh: Mesh
var base_visual_material: Material
var base_collision_shape: Shape3D
var soul_orb_core: MeshInstance3D
var soul_orb_halo: MeshInstance3D
var soul_trait_ring: MeshInstance3D
var soul_trait_shell: MeshInstance3D
var soul_trait_rune_ring: MeshInstance3D
var soul_trait_life_ring: MeshInstance3D
var soul_growth_rings: Array[MeshInstance3D] = []
var soul_growth_shell: MeshInstance3D
var soul_fusion_ring: MeshInstance3D
var soul_growth_stage := 1
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
	visual.mesh = null
	player_humanoid = VisualModelLibrary.instantiate_model(
		"player_humanoid",
		func() -> Node3D: return UnderworldVisualFactory.create_player_humanoid()
	)
	player_humanoid.position.y = -0.9
	visual.add_child(player_humanoid)

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
	camera_pivot.position = camera_pivot_base_position
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


func _is_text_input_focused() -> bool:
	var world := get_parent()
	if world != null and world.has_method("is_gameplay_input_blocked"):
		if bool(world.call("is_gameplay_input_blocked")):
			return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focused_control := viewport.gui_get_focus_owner()
	return focused_control is LineEdit or focused_control is TextEdit

func _is_move_key_down(physical_key: int, logical_key: int) -> bool:
	# Text inputs (including Chinese IME composition) own the keyboard.
	# Never poll WASD while a LineEdit/TextEdit has focus: IME key events may
	# be consumed by the control while global key-state polling still sees them.
	if _is_text_input_focused():
		return false
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
	# The chat drawer owns mouse and keyboard interaction while open.
	# Do not rotate the camera or trigger attacks from chat mouse movement/clicks.
	var world := get_parent()
	if world != null and world.has_method("is_gameplay_input_blocked"):
		if bool(world.call("is_gameplay_input_blocked")):
			return
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
	if _is_text_input_focused():
		# Clear queued jump as well; no gameplay movement should leak through
		# while the player is composing or typing in chat/another text field.
		jump_pending = false
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


func set_soul_form(enabled: bool, stage: int = 1, visual_scale: float = 0.35, affinities: Dictionary = {}, growth_stage: int = 1, fusion_names: Array = []) -> void:
	if not is_instance_valid(visual) or not is_instance_valid(collision_shape):
		return
	soul_form_enabled = enabled
	soul_form_scale = clampf(visual_scale / 0.35, 0.85, 3.8)
	if not enabled:
		visual.mesh = null
		if is_instance_valid(player_humanoid):
			player_humanoid.visible = true
		visual.material_override = base_visual_material
		visual.position = Vector3(0.0, 0.9, 0.0)
		visual.scale = Vector3.ONE
		collision_shape.shape = base_collision_shape
		collision_shape.position = Vector3(0.0, 0.9, 0.0)
		camera_pivot.position.y = 1.45
		move_speed = 5.5
		if is_instance_valid(soul_orb_halo):
			soul_orb_halo.visible = false
		for trait_node in [soul_trait_ring, soul_trait_shell, soul_trait_rune_ring, soul_trait_life_ring, soul_growth_shell, soul_fusion_ring]:
			if is_instance_valid(trait_node):
				trait_node.visible = false
		for growth_ring in soul_growth_rings:
			if is_instance_valid(growth_ring):
				growth_ring.visible = false
		return

	if is_instance_valid(player_humanoid):
		player_humanoid.visible = false
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
	_apply_soul_affinity_visuals(affinities)
	_apply_soul_growth_visuals(growth_stage)
	_apply_soul_fusion_visuals(fusion_names)


func _apply_soul_growth_visuals(growth_stage: int) -> void:
	soul_growth_stage = clampi(growth_stage, 1, 5)
	while soul_growth_rings.size() < 3:
		var ring_index := soul_growth_rings.size()
		var ring := MeshInstance3D.new()
		ring.name = "SoulGrowthRing" + str(ring_index + 1)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82 + float(ring_index) * 0.18
		torus.outer_radius = torus.inner_radius + 0.045
		torus.rings = 32
		torus.ring_segments = 6
		ring.mesh = torus
		ring.position.y = 0.42
		ring.rotation.x = [0.0, 0.68, -0.68][ring_index]
		ring.material_override = _make_trait_material(Color(0.42, 0.82, 1.0), 0.42)
		add_child(ring)
		soul_growth_rings.append(ring)
	for i in range(soul_growth_rings.size()):
		var ring := soul_growth_rings[i]
		ring.visible = soul_growth_stage >= i + 2
		ring.scale = Vector3.ONE * soul_form_scale * (1.0 + float(i) * 0.08)
	if not is_instance_valid(soul_growth_shell):
		soul_growth_shell = MeshInstance3D.new()
		soul_growth_shell.name = "SoulMatureShell"
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = 0.53
		shell_mesh.height = 1.06
		shell_mesh.radial_segments = 24
		shell_mesh.rings = 12
		soul_growth_shell.mesh = shell_mesh
		soul_growth_shell.position.y = 0.42
		soul_growth_shell.material_override = _make_trait_material(Color(0.42, 0.82, 1.0), 0.10)
		add_child(soul_growth_shell)
	soul_growth_shell.visible = soul_growth_stage >= 5
	soul_growth_shell.scale = Vector3.ONE * soul_form_scale * 1.12

func _apply_soul_fusion_visuals(fusion_names: Array) -> void:
	if not is_instance_valid(soul_fusion_ring):
		soul_fusion_ring = MeshInstance3D.new()
		soul_fusion_ring.name = "SoulFusionSealRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.94
		ring_mesh.outer_radius = 1.015
		ring_mesh.rings = 40
		ring_mesh.ring_segments = 8
		soul_fusion_ring.mesh = ring_mesh
		soul_fusion_ring.position.y = 0.42
		soul_fusion_ring.rotation.x = 0.34
		add_child(soul_fusion_ring)
	var fusion_color := Color(0.92, 0.78, 0.42)
	if fusion_names.has("战躯魂印"):
		fusion_color = Color(1.0, 0.34, 0.18)
	if fusion_names.has("风灵魂印"):
		fusion_color = Color(0.28, 0.82, 1.0)
	if fusion_names.has("不灭魂种"):
		fusion_color = Color(0.30, 1.0, 0.48)
	if fusion_names.has("五行混元魂"):
		fusion_color = Color(1.0, 0.82, 0.34)
	soul_fusion_ring.material_override = _make_trait_material(fusion_color, 0.82)
	soul_fusion_ring.visible = fusion_names.size() > 0
	soul_fusion_ring.scale = Vector3.ONE * soul_form_scale * 1.28

func _make_trait_material(color: Color, alpha: float = 0.58) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.35
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _apply_soul_affinity_visuals(affinities: Dictionary) -> void:
	var beast := int(affinities.get("beast", 0))
	var battle := int(affinities.get("battle", 0))
	var gale := int(affinities.get("gale", 0))
	var spirit := int(affinities.get("spirit", 0)) + int(affinities.get("selected_spirit", 0))
	var life := int(affinities.get("life", 0)) + int(affinities.get("selected_vitality", 0))
	var strength := int(affinities.get("selected_strength", 0))
	var constitution := int(affinities.get("selected_constitution", 0))
	var agility := int(affinities.get("selected_agility", 0))
	var primary := Color(0.12, 0.62, 1.0)
	var highest := 0
	var traits := [
		{"count": beast, "color": Color(1.0, 0.68, 0.22)},
		{"count": battle, "color": Color(1.0, 0.20, 0.16)},
		{"count": gale, "color": Color(0.22, 0.92, 0.72)},
		{"count": spirit, "color": Color(0.72, 0.42, 1.0)},
		{"count": life, "color": Color(0.28, 1.0, 0.48)},
		{"count": strength, "color": Color(1.0, 0.38, 0.22)},
		{"count": constitution, "color": Color(0.86, 0.72, 0.38)},
		{"count": agility, "color": Color(0.24, 0.88, 0.86)}
	]
	for trait_data in traits:
		if int(trait_data["count"]) > highest:
			highest = int(trait_data["count"])
			primary = trait_data["color"]
	var core_material := _make_trait_material(primary, 0.72)
	core_material.emission_energy_multiplier = 2.4
	visual.material_override = core_material
	if not is_instance_valid(soul_trait_ring):
		soul_trait_ring = MeshInstance3D.new()
		soul_trait_ring.name = "SoulAffinityRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.55
		ring_mesh.outer_radius = 0.59
		ring_mesh.rings = 36
		ring_mesh.ring_segments = 8
		soul_trait_ring.mesh = ring_mesh
		soul_trait_ring.position.y = 0.42
		add_child(soul_trait_ring)
	soul_trait_ring.material_override = _make_trait_material(primary, 0.72)
	soul_trait_ring.visible = highest > 0
	soul_trait_ring.scale = Vector3.ONE * soul_form_scale
	if not is_instance_valid(soul_trait_shell):
		soul_trait_shell = MeshInstance3D.new()
		soul_trait_shell.name = "SoulBeastAura"
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = 0.43
		shell_mesh.height = 0.86
		shell_mesh.radial_segments = 20
		shell_mesh.rings = 10
		soul_trait_shell.mesh = shell_mesh
		soul_trait_shell.position.y = 0.42
		add_child(soul_trait_shell)
	soul_trait_shell.material_override = _make_trait_material(Color(1.0, 0.64, 0.20), 0.16)
	soul_trait_shell.visible = beast > 0
	soul_trait_shell.scale = Vector3.ONE * soul_form_scale * 1.16
	if not is_instance_valid(soul_trait_rune_ring):
		soul_trait_rune_ring = MeshInstance3D.new()
		soul_trait_rune_ring.name = "SoulSpiritRunes"
		var rune_mesh := TorusMesh.new()
		rune_mesh.inner_radius = 0.68
		rune_mesh.outer_radius = 0.71
		rune_mesh.rings = 32
		rune_mesh.ring_segments = 6
		soul_trait_rune_ring.mesh = rune_mesh
		soul_trait_rune_ring.position.y = 0.42
		soul_trait_rune_ring.rotation.x = 0.72
		add_child(soul_trait_rune_ring)
	soul_trait_rune_ring.material_override = _make_trait_material(Color(0.72, 0.38, 1.0), 0.72)
	soul_trait_rune_ring.visible = spirit > 0
	soul_trait_rune_ring.scale = Vector3.ONE * soul_form_scale
	if not is_instance_valid(soul_trait_life_ring):
		soul_trait_life_ring = MeshInstance3D.new()
		soul_trait_life_ring.name = "SoulLifeHalo"
		var life_mesh := TorusMesh.new()
		life_mesh.inner_radius = 0.76
		life_mesh.outer_radius = 0.79
		life_mesh.rings = 32
		life_mesh.ring_segments = 6
		soul_trait_life_ring.mesh = life_mesh
		soul_trait_life_ring.position.y = 0.42
		soul_trait_life_ring.rotation.x = -0.72
		add_child(soul_trait_life_ring)
	soul_trait_life_ring.material_override = _make_trait_material(Color(0.28, 1.0, 0.48), 0.68)
	soul_trait_life_ring.visible = life > 0
	soul_trait_life_ring.scale = Vector3.ONE * soul_form_scale


func play_hit_reaction(damage: int, attack_style: String = "") -> void:
	hit_reaction_time = maxf(hit_reaction_time, 0.32)
	var style_strength := 0.115 if attack_style == "heavy_slam" else 0.055
	var damage_strength := clampf(float(maxi(damage, 0)) / 240.0, 0.0, 0.045)
	hit_reaction_strength = maxf(hit_reaction_strength, style_strength + damage_strength)

func play_attack_animation() -> void:
	if soul_form_enabled or not is_instance_valid(player_humanoid):
		return
	attack_animation_time = 0.34


func _process(delta: float) -> void:
	hit_reaction_time = maxf(hit_reaction_time - delta, 0.0)
	if is_instance_valid(camera_pivot):
		var shake_weight := hit_reaction_time / 0.32
		var shake_time := 0.32 - hit_reaction_time
		var shake := sin(shake_time * 58.0) * hit_reaction_strength * shake_weight
		var vertical := absf(cos(shake_time * 34.0)) * hit_reaction_strength * 0.28 * shake_weight
		camera_pivot.position = camera_pivot_base_position + Vector3(shake, vertical, 0.0)
	if hit_reaction_time <= 0.0:
		hit_reaction_strength = 0.0
	if not soul_form_enabled and is_instance_valid(player_humanoid):
		humanoid_animation_time += delta
		var moving := current_move_input.length() > 0.08
		var stride := sin(humanoid_animation_time * (9.0 if moving else 1.8))
		var swing := stride * 0.42 if moving else 0.0
		attack_animation_time = maxf(attack_animation_time - delta, 0.0)
		var attack_weight := 0.0
		if attack_animation_time > 0.0:
			attack_weight = sin((1.0 - attack_animation_time / 0.34) * PI)
		var left_arm := player_humanoid.get_node_or_null("ArmPivotLeft") as Node3D
		var right_arm := player_humanoid.get_node_or_null("ArmPivotRight") as Node3D
		var left_leg := player_humanoid.get_node_or_null("LegPivotLeft") as Node3D
		var right_leg := player_humanoid.get_node_or_null("LegPivotRight") as Node3D
		if is_instance_valid(left_arm):
			left_arm.rotation.x = (swing if moving else sin(humanoid_animation_time * 1.1) * 0.018) - attack_weight * 0.20
		if is_instance_valid(right_arm):
			right_arm.rotation.x = (-swing if moving else sin(humanoid_animation_time * 1.1 + 0.5) * 0.018) - attack_weight * 1.18
			right_arm.rotation.z = -attack_weight * 0.28
		if is_instance_valid(left_leg):
			left_leg.rotation.x = -swing * 0.82
		if is_instance_valid(right_leg):
			right_leg.rotation.x = swing * 0.82 + attack_weight * 0.035
		player_humanoid.position.y = -0.9 + (absf(stride) * 0.045 if moving else sin(humanoid_animation_time * 1.8) * 0.012)
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
	if is_instance_valid(soul_trait_ring) and soul_trait_ring.visible:
		soul_trait_ring.position.y = 0.42 + bob
		soul_trait_ring.rotation.y -= delta * 0.45
	if is_instance_valid(soul_trait_shell) and soul_trait_shell.visible:
		soul_trait_shell.position.y = 0.42 + bob
	if is_instance_valid(soul_trait_rune_ring) and soul_trait_rune_ring.visible:
		soul_trait_rune_ring.position.y = 0.42 + bob
		soul_trait_rune_ring.rotation.y += delta * 0.9
	if is_instance_valid(soul_trait_life_ring) and soul_trait_life_ring.visible:
		soul_trait_life_ring.position.y = 0.42 + bob
		soul_trait_life_ring.rotation.y -= delta * 0.35
	for i in range(soul_growth_rings.size()):
		var growth_ring := soul_growth_rings[i]
		if is_instance_valid(growth_ring) and growth_ring.visible:
			growth_ring.position.y = 0.42 + bob
			growth_ring.rotation.y += delta * (0.22 + float(i) * 0.12)
	if is_instance_valid(soul_growth_shell) and soul_growth_shell.visible:
		soul_growth_shell.position.y = 0.42 + bob
		var mature_pulse := 1.0 + sin(soul_form_time * 1.35) * 0.018
		soul_growth_shell.scale = Vector3.ONE * soul_form_scale * 1.12 * mature_pulse
	if is_instance_valid(soul_fusion_ring) and soul_fusion_ring.visible:
		soul_fusion_ring.position.y = 0.42 + bob
		soul_fusion_ring.rotation.y += delta * 0.32
		var seal_pulse := 1.0 + sin(soul_form_time * 1.8) * 0.025
		soul_fusion_ring.scale = Vector3.ONE * soul_form_scale * 1.28 * seal_pulse
