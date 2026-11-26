extends RefCounted
## Visual-only entrance markers for Fengdu's outer hunting territories.
## No collision, navigation, spawn, or server-authority behavior is added.

const ENTRANCES := [
	{"id": "SouthernWraithMarsh", "title": "南郊游魂泽", "subtitle": "游魂出没 · 初阶试炼", "position": Vector3(0.0, 0.0, -13.0), "color": Color("#75a9d5")},
	{"id": "WesternBoneWaste", "title": "西郊白骨荒原", "subtitle": "白骨游荡 · 荒原险地", "position": Vector3(-55.0, 0.0, -60.0), "color": Color("#c4b58c")},
	{"id": "EasternForgottenBank", "title": "东郊忘川古渡", "subtitle": "忘川渡口 · 水域凶险", "position": Vector3(55.0, 0.0, -60.0), "color": Color("#6bbdc2")},
	{"id": "AncientBattlefield", "title": "西南古战场", "subtitle": "残兵战魂 · 勿越界深入", "position": Vector3(-55.0, 0.0, 12.0), "color": Color("#bd7774")}
]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "FengduRegionEntrances"
	for entry_variant in ENTRANCES:
		var entry: Dictionary = entry_variant
		var marker := Node3D.new()
		marker.name = "Entrance_" + str(entry["id"])
		marker.position = entry["position"]
		marker.set_meta("region_id", _region_id(str(entry["id"])))
		var color: Color = entry["color"]
		for side in [-1.0, 1.0]:
			var pillar := MeshInstance3D.new()
			pillar.name = "GatePillar_" + str(side)
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.65, 3.4, 0.65)
			pillar.mesh = mesh
			pillar.position = Vector3(side * 2.1, 1.7, 0.0)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("#393641")
			material.roughness = 0.92
			pillar.material_override = material
			marker.add_child(pillar)
			var cap := MeshInstance3D.new()
			cap.name = "BoundaryCrystal_" + str(side)
			var crystal := SphereMesh.new()
			crystal.radius = 0.34
			crystal.height = 0.72
			cap.mesh = crystal
			cap.position = Vector3(side * 2.1, 3.65, 0.0)
			var crystal_material := StandardMaterial3D.new()
			crystal_material.albedo_color = color
			crystal_material.emission_enabled = true
			crystal_material.emission = color
			crystal_material.emission_energy_multiplier = 1.4
			cap.material_override = crystal_material
			marker.add_child(cap)
		var lintel := MeshInstance3D.new()
		lintel.name = "BoundaryLintel"
		var lintel_mesh := BoxMesh.new()
		lintel_mesh.size = Vector3(4.8, 0.42, 0.7)
		lintel.mesh = lintel_mesh
		lintel.position.y = 3.05
		var lintel_material := StandardMaterial3D.new()
		lintel_material.albedo_color = Color("#4b4652")
		lintel.material_override = lintel_material
		marker.add_child(lintel)
		var title := Label3D.new()
		title.name = "EntranceTitle"
		title.text = str(entry["title"])
		title.position = Vector3(0.0, 4.45, 0.0)
		title.font_size = 36
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.modulate = color
		marker.add_child(title)
		var subtitle := Label3D.new()
		subtitle.name = "EntranceSubtitle"
		subtitle.text = str(entry["subtitle"])
		subtitle.position = Vector3(0.0, 3.95, 0.0)
		subtitle.font_size = 22
		subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		subtitle.modulate = Color("#d6d0dc")
		marker.add_child(subtitle)
		root.add_child(marker)
	return root


static func get_entrances() -> Array:
	return ENTRANCES.duplicate(true)


static func _region_id(marker_id: String) -> String:
	match marker_id:
		"SouthernWraithMarsh": return "southern_wraith_marsh"
		"WesternBoneWaste": return "western_bone_waste"
		"EasternForgottenBank": return "eastern_forgotten_bank"
		"AncientBattlefield": return "ancient_battlefield"
	return ""
