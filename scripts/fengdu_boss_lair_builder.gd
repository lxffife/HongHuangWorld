extends RefCounted
## Client-only visual landmarks for future elite/boss encounters.
## This builder never spawns entities, collision, damage volumes or gameplay triggers.

const SITES := [
	{
		"id": "southern_marsh_boss_lair",
		"name": "沉魂泽主巢",
		"region_id": "southern_wraith_marsh",
		"position": Vector3(34.0, 0.0, 88.0),
		"color": Color("#75a9d5"),
		"subtitle": "首领区域建议 · 游魂泽深处"
	},
	{
		"id": "western_bone_boss_lair",
		"name": "白骨将军冢",
		"region_id": "western_bone_waste",
		"position": Vector3(-68.0, 0.0, -88.0),
		"color": Color("#c5b99e"),
		"subtitle": "首领区域建议 · 白骨荒原"
	},
	{
		"id": "eastern_ferry_boss_lair",
		"name": "忘川水府祭坛",
		"region_id": "eastern_forgotten_bank",
		"position": Vector3(88.0, 0.0, -88.0),
		"color": Color("#6bbdc2"),
		"subtitle": "首领区域建议 · 古渡深处"
	},
	{
		"id": "battlefield_boss_lair",
		"name": "古战魂将台",
		"region_id": "ancient_battlefield",
		"position": Vector3(-43.0, 0.0, 38.0),
		"color": Color("#bd7774"),
		"subtitle": "首领区域建议 · 古战场"
	}
]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "FengduBossLairLandmarks"
	for site_variant in SITES:
		var site: Dictionary = site_variant
		root.add_child(_build_site(site))
	return root


static func get_sites() -> Array:
	return SITES.duplicate(true)


static func _build_site(site: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "BossLair_" + str(site["id"])
	root.position = site["position"]
	root.set_meta("region_id", str(site["region_id"]))
	root.set_meta("boss_lair_id", str(site["id"]))
	root.set_meta("visual_only", true)
	var accent: Color = site["color"]
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#39343b")
	stone.roughness = 0.94
	var accent_material := StandardMaterial3D.new()
	accent_material.albedo_color = accent
	accent_material.emission_enabled = true
	accent_material.emission = accent
	accent_material.emission_energy_multiplier = 1.15
	accent_material.roughness = 0.38

	var dais := MeshInstance3D.new()
	dais.name = "BossDais"
	var dais_mesh := CylinderMesh.new()
	dais_mesh.top_radius = 4.6
	dais_mesh.bottom_radius = 5.2
	dais_mesh.height = 0.48
	dais.mesh = dais_mesh
	dais.position.y = 0.24
	dais.material_override = stone
	root.add_child(dais)

	var seal := MeshInstance3D.new()
	seal.name = "BossSealRing"
	var seal_mesh := TorusMesh.new()
	seal_mesh.inner_radius = 3.5
	seal_mesh.outer_radius = 3.78
	seal.mesh = seal_mesh
	seal.position.y = 0.56
	seal.material_override = accent_material
	root.add_child(seal)

	for index in range(4):
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var pillar := MeshInstance3D.new()
		pillar.name = "LairPillar_%d" % index
		var pillar_mesh := BoxMesh.new()
		pillar_mesh.size = Vector3(0.62, 2.8, 0.62)
		pillar.mesh = pillar_mesh
		pillar.position = Vector3(cos(angle) * 5.8, 1.4, sin(angle) * 5.8)
		pillar.material_override = stone
		root.add_child(pillar)

		var crystal := MeshInstance3D.new()
		crystal.name = "LairCrystal_%d" % index
		var crystal_mesh := SphereMesh.new()
		crystal_mesh.radius = 0.38
		crystal_mesh.height = 0.82
		crystal.mesh = crystal_mesh
		crystal.position = pillar.position + Vector3(0.0, 1.75, 0.0)
		crystal.material_override = accent_material
		root.add_child(crystal)

	var title := Label3D.new()
	title.name = "BossLairTitle"
	title.text = str(site["name"])
	title.position.y = 5.0
	title.font_size = 34
	title.outline_size = 7
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = accent
	root.add_child(title)

	var subtitle := Label3D.new()
	subtitle.name = "BossLairSubtitle"
	subtitle.text = str(site["subtitle"])
	subtitle.position.y = 4.2
	subtitle.font_size = 19
	subtitle.outline_size = 5
	subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	subtitle.modulate = Color("#e6dfe8")
	root.add_child(subtitle)
	return root
