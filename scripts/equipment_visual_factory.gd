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
