extends RefCounted
## Canonical, presentation-independent Fengdu layout data.
## Coordinates are in meters in the current city-local X/Z plane.
## Keep gameplay identities and placements here; terrain and building art are replaceable adapters.

const CITY_HALF := 96.0
const MOAT_HALF := 108.0
const WALL_HEIGHT := 13.0
const WALL_THICKNESS := 5.0
const GATE_WIDTH := 16.0
const OUTER_LANDSCAPE_EXTENT := 600.0

static func get_city_config() -> Dictionary:
	return {
		"city_half_extent": CITY_HALF,
		"moat_half_extent": MOAT_HALF,
		"wall_height": WALL_HEIGHT,
		"wall_thickness": WALL_THICKNESS,
		"gate_width": GATE_WIDTH,
		"imperial_palace_center": Vector3(0, 0, 72),
		"outer_landscape_extent": OUTER_LANDSCAPE_EXTENT
	}


static func get_gates() -> Array[Dictionary]:
	return [
		{"id": "north_heaven_gate", "name": "北天门", "position": Vector3(0, 0, CITY_HALF), "outward": Vector3(0, 0, 1), "destination": "罗酆山古道"},
		{"id": "south_ghost_gate", "name": "南幽门", "position": Vector3(0, 0, -CITY_HALF), "outward": Vector3(0, 0, -1), "destination": "忘川与轮回渡口"},
		{"id": "east_mystic_gate", "name": "东玄门", "position": Vector3(CITY_HALF, 0, 0), "outward": Vector3(1, 0, 0), "destination": "幽冥荒原远域官道"},
		{"id": "west_dark_gate", "name": "西冥门", "position": Vector3(-CITY_HALF, 0, 0), "outward": Vector3(-1, 0, 0), "destination": "阴司军屯与古战场"}
	]


static func get_districts() -> Array[Dictionary]:
	return [
		{"id": "soul_ward", "name": "万家魂坊", "center": Vector3(-55, 0, -53), "footprint": Vector2(34, 26), "subtitle": "居住 · 工匠 · 社区", "building_count": 5, "accent": "#a9b9c4"},
		{"id": "ghost_market", "name": "万魂鬼市", "center": Vector3(55, 0, -53), "footprint": Vector2(34, 26), "subtitle": "交易 · 拍卖 · 情报", "building_count": 6, "accent": "#d7b47b"},
		{"id": "soul_registry", "name": "鬼籍司", "center": Vector3(-52, 0, 4), "footprint": Vector2(27, 24), "subtitle": "新魂登记 · 身份凭籍", "building_count": 4, "accent": "#9cb8c8"},
		{"id": "merit_bureau", "name": "功过司", "center": Vector3(52, 0, 4), "footprint": Vector2(27, 24), "subtitle": "功德 · 罪业 · 因果", "building_count": 4, "accent": "#c4b28e"},
		{"id": "ten_kings_court", "name": "十王府", "center": Vector3(-51, 0, 48), "footprint": Vector2(30, 23), "subtitle": "十殿审判 · 刑狱协调", "building_count": 5, "accent": "#b9a4a4"},
		{"id": "judge_bureau", "name": "判官司", "center": Vector3(51, 0, 48), "footprint": Vector2(30, 23), "subtitle": "案卷复核 · 司法文书", "building_count": 5, "accent": "#b9a4a4"},
		{"id": "patrol_office", "name": "巡城司", "center": Vector3(0, 0, 12), "footprint": Vector2(23, 20), "subtitle": "治安 · 巡逻 · 夜禁", "building_count": 4, "accent": "#a5b2c0"},
		{"id": "reincarnation_bureau", "name": "轮回司", "center": Vector3(0, 0, -68), "footprint": Vector2(32, 20), "subtitle": "轮回文牒 · 忘川通道", "building_count": 5, "accent": "#b6a5d0"},
		{"id": "barracks", "name": "阴兵大营", "center": Vector3(-77, 0, 0), "footprint": Vector2(18, 27), "subtitle": "城防 · 军需 · 驻军", "building_count": 3, "accent": "#9ba6b2"},
		{"id": "waystation", "name": "引魂驿站", "center": Vector3(77, 0, 0), "footprint": Vector2(18, 27), "subtitle": "接引 · 分流 · 远途驿传", "building_count": 3, "accent": "#a8b7c3"}
	]
