extends RefCounted
class_name HHEquipmentVisualFactory

# Shared presentation-only attachment resolver for local and remote humanoids.
# Existing authored sockets always win; GLB skeleton bones are the second choice.
const SOCKET_NAMES := {
	"weapon": "EquipmentWeaponSocket",
	"offhand": "EquipmentOffhandSocket",
	"head": "EquipmentHeadSocket",
	"chest": "EquipmentChestSocket",
	"legs": "EquipmentLegsSocket",
	"boots": "EquipmentBootsSocket",
	"back": "EquipmentBackSocket",
	"accessory": "EquipmentAccessorySocket"
}

const BONE_ALIASES := {
	"weapon": ["RightHand", "Hand_R", "hand_r", "mixamorig:RightHand", "mixamorig_RightHand", "右手"],
	"offhand": ["LeftHand", "Hand_L", "hand_l", "mixamorig:LeftHand", "mixamorig_LeftHand", "左手"],
	"head": ["Head", "head", "mixamorig:Head", "头"],
	"chest": ["Spine2", "Spine1", "Chest", "chest", "mixamorig:Spine2", "mixamorig:Spine1", "脊柱"],
	"legs": ["Hips", "Pelvis", "mixamorig:Hips", "髋"],
	"boots": ["RightFoot", "Foot_R", "foot_r", "mixamorig:RightFoot", "右脚"],
	"back": ["Spine2", "Chest", "chest", "mixamorig:Spine2", "脊柱"],
	"accessory": ["Spine2", "Chest", "chest", "mixamorig:Spine2", "脊柱"]
}

const FALLBACK_POSITIONS := {
	"weapon": Vector3(0.43, 1.12, -0.20),
	"offhand": Vector3(-0.43, 1.12, -0.20),
	"head": Vector3(0.0, 2.08, 0.0),
	"chest": Vector3(0.0, 1.20, -0.24),
	"legs": Vector3(0.0, 0.58, -0.22),
	"boots": Vector3(0.0, 0.18, -0.06),
	"back": Vector3(0.0, 1.28, 0.24),
	"accessory": Vector3(0.20, 0.82, -0.30)
}

static func get_or_create_socket(humanoid: Node3D, slot: String) -> Node3D:
	if not is_instance_valid(humanoid) or not SOCKET_NAMES.has(slot):
		return null
	var socket_name: String = SOCKET_NAMES[slot]
	var existing := _find_named_node(humanoid, socket_name) as Node3D
	if is_instance_valid(existing):
		return existing

	# Prefer animated procedural pivots when the model exposes them.
	var pivot_name := ""
	if slot == "weapon":
		pivot_name = "ArmPivotRight"
	elif slot == "offhand":
		pivot_name = "ArmPivotLeft"
	if not pivot_name.is_empty():
		var pivot := _find_named_node(humanoid, pivot_name) as Node3D
		if is_instance_valid(pivot):
			return _create_socket(pivot, socket_name, _hand_offset(slot), false)

	# Imported GLB models commonly expose Skeleton3D bones instead of named pivots.
	var skeleton := _find_skeleton(humanoid)
	if is_instance_valid(skeleton):
		for alias in BONE_ALIASES.get(slot, []):
			var bone_index := skeleton.find_bone(str(alias))
			if bone_index < 0:
				continue
			var attachment := BoneAttachment3D.new()
			attachment.name = socket_name
			attachment.bone_name = str(alias)
			attachment.position = _bone_offset(slot)
			skeleton.add_child(attachment)
			attachment.set_meta("equipment_socket", true)
			attachment.set_meta("equipment_attachment_type", "bone")
			return attachment

	# Last resort keeps older assets and the procedural fallback compatible.
	return _create_socket(humanoid, socket_name, FALLBACK_POSITIONS.get(slot, Vector3.ZERO), false)

static func _create_socket(parent: Node3D, socket_name: String, offset: Vector3, bone_attachment: bool) -> Node3D:
	var socket := Node3D.new()
	socket.name = socket_name
	socket.position = offset
	socket.set_meta("equipment_socket", true)
	if bone_attachment:
		socket.set_meta("equipment_attachment_type", "bone")
	parent.add_child(socket)
	return socket

static func _find_named_node(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_named_node(child, target_name)
		if found != null:
			return found
	return null

static func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if is_instance_valid(found):
			return found
	return null

static func _hand_offset(slot: String) -> Vector3:
	return Vector3(0.03, -0.58, -0.06) if slot == "weapon" else Vector3(-0.03, -0.58, -0.06)

static func _bone_offset(slot: String) -> Vector3:
	match slot:
		"weapon": return Vector3(0.0, -0.04, -0.08)
		"offhand": return Vector3(0.0, -0.04, -0.08)
		"head": return Vector3(0.0, 0.12, 0.0)
		"chest": return Vector3(0.0, 0.0, -0.12)
		"legs": return Vector3(0.0, -0.10, -0.08)
		"boots": return Vector3(0.0, -0.08, -0.02)
		"back": return Vector3(0.0, 0.0, 0.16)
		"accessory": return Vector3(0.12, 0.0, -0.12)
	return Vector3.ZERO

# Shared slot mesh generation keeps local and remote player equipment identical.
static func create_equipment_visual(slot: String, quality: int, item_id: String = "") -> Node3D:
	if not SOCKET_NAMES.has(slot):
		return null
	var root := Node3D.new()
	root.name = "EquipmentVisual"
	root.set_meta("item_id", item_id)
	var accent := Color("#c5a66d")
	if quality >= 5:
		accent = Color("#e9a7ff")
	elif quality == 4:
		accent = Color("#8fc8ff")
	elif quality == 3:
		accent = Color("#8ee0b0")
	var material := StandardMaterial3D.new()
	material.albedo_color = accent
	material.metallic = 0.42
	material.roughness = 0.34
	match slot:
		"weapon", "offhand":
			var blade_mesh := BoxMesh.new()
			blade_mesh.size = Vector3(0.075, 0.78, 0.035)
			var blade := _add_mesh(root, "EquipmentBlade", blade_mesh, material)
			blade.position = Vector3(0.0, 0.42, -0.06)
			blade.rotation.z = -0.12 if slot == "weapon" else 0.12
			var grip_mesh := BoxMesh.new()
			grip_mesh.size = Vector3(0.11, 0.20, 0.09)
			var grip := _add_mesh(root, "EquipmentGrip", grip_mesh, _dark_material())
			grip.position.y = -0.02
		"head":
			var mesh := SphereMesh.new()
			mesh.radius = 0.27
			mesh.height = 0.30
			_add_mesh(root, "EquipmentHelmet", mesh, material)
		"chest":
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.58, 0.64, 0.16)
			_add_mesh(root, "EquipmentChestArmor", mesh, material)
		"legs":
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.58, 0.30, 0.13)
			var armor := _add_mesh(root, "EquipmentLegArmor", mesh, material)
			armor.position.y = -0.12
		"boots":
			for side in [-1.0, 1.0]:
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.20, 0.16, 0.34)
				var boot := _add_mesh(root, "EquipmentBoot" + str(side), mesh, material)
				boot.position = Vector3(side * 0.17, -0.10, -0.04)
		"accessory":
			var mesh := TorusMesh.new()
			mesh.inner_radius = 0.07
			mesh.outer_radius = 0.11
			_add_mesh(root, "EquipmentOrnament", mesh, material)
		"back":
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.58, 0.76, 0.10)
			_add_mesh(root, "EquipmentBackMantle", mesh, material)
	return root

static func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance

static func _dark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#493b32")
	material.roughness = 0.72
	return material
