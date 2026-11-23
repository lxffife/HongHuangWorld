extends RefCounted
## Data-driven client map metadata.
## Region bounds are display hints only; gameplay boundaries remain server-authoritative.
## Coordinates use world X/Z meters. Bounds are [min_x, max_x, min_z, max_z].

const FENGDU_REGIONS := [
	{"id": "imperial_palace", "name": "酆都皇城", "priority": 5, "bounds": [[-10.0, 10.0, -84.0, -74.0]]},
	{"id": "ten_kings_manors", "name": "十王府", "priority": 6, "bounds": [[-35.0, -12.0, -77.0, -66.0]]},
	{"id": "judge_court", "name": "判官司", "priority": 7, "bounds": [[12.0, 35.0, -77.0, -66.0]]},
	{"id": "ghost_registry", "name": "鬼籍司", "priority": 8, "bounds": [[-35.0, -12.0, -64.0, -54.0]]},
	{"id": "merit_bureau", "name": "功过司", "priority": 9, "bounds": [[12.0, 35.0, -64.0, -54.0]]},
	{"id": "patrol_office", "name": "巡城司", "priority": 10, "bounds": [[-8.0, 8.0, -66.0, -56.0]]},
	{"id": "reincarnation_bureau", "name": "轮回司", "priority": 11, "bounds": [[-10.0, 10.0, -48.0, -38.0]]},
	{"id": "ghost_market", "name": "万魂鬼市", "priority": 12, "bounds": [[12.0, 35.0, -45.0, -35.0]]},
	{"id": "residential_quarter", "name": "万家魂坊", "priority": 13, "bounds": [[-35.0, -12.0, -45.0, -35.0]]},
	{"id": "yin_army_camp", "name": "阴兵大营", "priority": 14, "bounds": [[-44.0, -34.0, -68.0, -58.0]]},
	{"id": "soul_waystation", "name": "引魂驿站", "priority": 15, "bounds": [[34.0, 44.0, -68.0, -58.0]]},
	{"id": "south_gate", "name": "南幽门", "priority": 16, "bounds": [[-7.0, 7.0, -32.0, -22.0]]},
	{"id": "north_gate", "name": "北天门", "priority": 17, "bounds": [[-7.0, 7.0, -98.0, -88.0]]},
	{"id": "naihe_bridge", "name": "奈何桥", "priority": 10, "bounds": [[15.0, 29.0, -0.5, 5.5]]},
	{"id": "reincarnation_forecourt", "name": "轮回殿前", "priority": 20, "bounds": [[-35.0, -8.0, -69.0, -42.0]]},
	{"id": "fengdu_ghost_gate", "name": "酆都鬼门关", "priority": 30, "bounds": [[-12.0, 12.0, -28.0, -9.0]]},
	{"id": "forgotten_riverbank", "name": "忘川河畔", "priority": 40, "bounds": [[17.0, 27.0, -68.0, 82.0]]},
	{"id": "soul_guiding_road", "name": "引魂石道", "priority": 50, "bounds": [[-32.0, 32.0, -40.0, -26.0]]},
	{"id": "ancient_battlefield", "name": "古战场遗址", "priority": 60, "bounds": [[-1000000000.0, -36.0, 10.0, 46.0]]}
]

const QINGYUN_REGIONS := [
	{"id": "qingyun_gate", "name": "青云山门", "priority": 10, "bounds": [[-9.0, 9.0, -28.0, -16.0]]},
	{"id": "qingyun_path", "name": "青云石径", "priority": 20, "bounds": [[-7.0, 7.0, -42.0, -3.0]]},
	{"id": "qingyun_pine_forest", "name": "青云松林", "priority": 30, "bounds": [[-30.0, -8.0, -48.0, 8.0], [8.0, 30.0, -48.0, 8.0]]}
]


## Schematic atlas coordinates are deliberately separate from gameplay X/Z meters.
## They communicate relative geography only; they are never navigation coordinates.
const UNDERWORLD_ATLAS := {
	"coordinate_space": "schematic",
	"title": "冥界总览",
	"subtitle": "后土掌幽冥轮回 · 酆都治阴司 · 冥河统血海",
	"nodes": [
		{
			"id": "fengdu_capital", "name": "酆都天城", "kind": "capital",
			"position": [-72.0, 4.0], "size": [76.0, 48.0],
			"authority": "酆都大帝 · 阴司",
			"sovereignty": "后土娘娘幽冥法统之下",
			"distance": "冥界中枢", "danger_level": 2,
			"recommended_realm": "初入冥界至高阶修士",
			"access": "主城区域",
			"description": "冥界最大城池，设皇城、十王府、判官司、鬼籍司、鬼市与阴兵营。"
		},
		{
			"id": "wangchuan_basin", "name": "忘川流域", "kind": "river",
			"position": [-8.0, -45.0], "size": [66.0, 30.0],
			"authority": "阴司渡魂体系",
			"sovereignty": "阴司辖理",
			"distance": "酆都近域", "danger_level": 4,
			"recommended_realm": "筑基至化神（建议）",
			"access": "经黄泉道抵达",
			"description": "忘川河、奈何桥、孟婆亭、望乡台与渡魂驿站所在的亡魂通行区域。"
		},
		{
			"id": "luofeng_mountains", "name": "罗酆古神山", "kind": "sacred",
			"position": [-12.0, -112.0], "size": [62.0, 34.0],
			"authority": "古幽冥神系",
			"sovereignty": "古神禁域",
			"distance": "冥界北境", "danger_level": 8,
			"recommended_realm": "合体至大乘（建议）",
			"access": "神谕、古遗迹与高阶探索",
			"description": "罗酆山与六天宫传说的游戏化遗址，保留古老幽冥神权的历史。"
		},
		{
			"id": "hou_tu_domain", "name": "后土神域", "kind": "divine",
			"position": [-8.0, -172.0], "size": [58.0, 30.0],
			"authority": "后土娘娘",
			"sovereignty": "幽冥本源",
			"distance": "神域", "danger_level": 10,
			"recommended_realm": "非普通境界可抵达",
			"access": "神谕与主线剧情",
			"description": "后土娘娘显化神域的原创设定，象征幽冥本源与六道轮回法则，不代表可自由进入的普通地图。"
		},
		{
			"id": "eighteen_hells", "name": "十八层地狱", "kind": "hell",
			"position": [-72.0, 94.0], "size": [68.0, 40.0],
			"authority": "十殿阎罗 · 地狱守将",
			"sovereignty": "阴司刑狱体系",
			"distance": "酆都地下辖域", "danger_level": 9,
			"recommended_realm": "依层数递增",
			"access": "审判、任务与封印入口",
			"description": "独立的多层地下空间，兼具罪魂刑罚、危险存在镇压与远古封印剧情。层级名称参考民间传说并作游戏化整理，不同地方志与民俗版本可能有异；阿鼻无间为本作最深层核心禁区。",
			"layers": [
				{"floor": 1, "id": "hell_1", "name": "拔舌地狱", "theme": "妄语、诽谤与恶意造谣", "guardian": "拔舌判官", "danger_level": 2},
				{"floor": 2, "id": "hell_2", "name": "剪刀地狱", "theme": "挑拨离间、破坏盟约与姻缘", "guardian": "剪缘鬼将", "danger_level": 2},
				{"floor": 3, "id": "hell_3", "name": "铁树地狱", "theme": "背信弃义、构陷无辜", "guardian": "铁树守狱使", "danger_level": 3},
				{"floor": 4, "id": "hell_4", "name": "孽镜地狱", "theme": "照见隐罪、核验因果真相", "guardian": "孽镜司主", "danger_level": 3},
				{"floor": 5, "id": "hell_5", "name": "蒸笼地狱", "theme": "散布谣言、伪证害人", "guardian": "蒸笼狱卒长", "danger_level": 4},
				{"floor": 6, "id": "hell_6", "name": "铜柱地狱", "theme": "纵火、酷刑与暴虐", "guardian": "铜柱刑官", "danger_level": 4},
				{"floor": 7, "id": "hell_7", "name": "刀山地狱", "theme": "杀伐残害、兵灾血债", "guardian": "刀山巡狱将", "danger_level": 5},
				{"floor": 8, "id": "hell_8", "name": "冰山地狱", "theme": "忘恩负义、冷酷背弃", "guardian": "冰山女狱吏", "danger_level": 5},
				{"floor": 9, "id": "hell_9", "name": "油锅地狱", "theme": "贪婪强夺、以权谋私", "guardian": "油锅狱主", "danger_level": 6},
				{"floor": 10, "id": "hell_10", "name": "牛坑地狱", "theme": "虐待生灵、残害牲畜", "guardian": "牛坑监狱官", "danger_level": 6},
				{"floor": 11, "id": "hell_11", "name": "石压地狱", "theme": "欺压弱小、恃强凌弱", "guardian": "石压力士", "danger_level": 7},
				{"floor": 12, "id": "hell_12", "name": "舂臼地狱", "theme": "侵夺粮道、断人生计", "guardian": "舂臼刑使", "danger_level": 7},
				{"floor": 13, "id": "hell_13", "name": "血池地狱", "theme": "屠戮无辜、累积血债", "guardian": "血池夜叉统领", "danger_level": 8},
				{"floor": 14, "id": "hell_14", "name": "枉死地狱", "theme": "含冤亡魂复核、怨念平息与错案追查", "guardian": "枉死城主", "danger_level": 6},
				{"floor": 15, "id": "hell_15", "name": "磔刑地狱", "theme": "背盟叛义、残害同袍", "guardian": "磔刑鬼将", "danger_level": 8},
				{"floor": 16, "id": "hell_16", "name": "火山地狱", "theme": "焚城灭门、重大恶业", "guardian": "火山狱君", "danger_level": 9},
				{"floor": 17, "id": "hell_17", "name": "石磨地狱", "theme": "盘剥众生、吞并与榨取", "guardian": "石磨鬼王", "danger_level": 9},
				{"floor": 18, "id": "hell_18", "name": "阿鼻无间地狱", "theme": "极重罪业与上古邪物封镇", "guardian": "无间狱主", "danger_level": 10}
			]
		},
		{
			"id": "ghost_wilderness", "name": "幽冥荒原", "kind": "wilderness",
			"position": [32.0, 76.0], "size": [58.0, 36.0],
			"authority": "无统一常设统治",
			"sovereignty": "边境争夺地带",
			"distance": "酆都外域", "danger_level": 6,
			"recommended_realm": "金丹至渡劫（建议）",
			"access": "陆路探索",
			"description": "连接阴司核心与远方险域的广阔荒野，分布废弃驿站、古战场、鬼寨与失序亡魂。"
		},
		{
			"id": "blood_sea", "name": "幽冥血海", "kind": "blood_sea",
			"position": [126.0, -6.0], "size": [86.0, 58.0],
			"authority": "冥河老祖 · 阿修罗诸王",
			"sovereignty": "血海自治疆域",
			"distance": "极遥远的冥界远域",
			"danger_level": 10,
			"recommended_realm": "大乘及以上（外围建议）",
			"access": "跨越荒原山脉、古战场与封锁关隘",
			"description": "远离酆都的独立血海大陆级险域，设血海荒原、海岸、浅海、深海、沉船禁区、漩涡与修罗魔宫。"
		}
	],
	"links": [
		{"from": "fengdu_capital", "to": "wangchuan_basin", "label": "黄泉古道"},
		{"from": "fengdu_capital", "to": "eighteen_hells", "label": "阴司地脉入口"},
		{"from": "fengdu_capital", "to": "luofeng_mountains", "label": "古道 / 神山道"},
		{"from": "fengdu_capital", "to": "ghost_wilderness", "label": "幽冥官道"},
		{"from": "ghost_wilderness", "to": "blood_sea", "label": "远征路线 · 多重险境"},
		{"from": "luofeng_mountains", "to": "hou_tu_domain", "label": "神域朝圣之路"}
	]
}


## Fengdu city plan uses a separate schematic coordinate space (not world meters).
const FENGDU_CITY_PLAN := {
	"coordinate_space": "schematic_city",
	"title": "酆都天城",
	"subtitle": "皇城居中 · 十王分治 · 四门通幽",
	"wall_size": [760.0, 590.0],
	"moat_size": [820.0, 650.0],
	"nodes": [
		{"id": "imperial_palace", "name": "酆都皇城", "kind": "palace", "position": [0.0, 178.0], "size": [154.0, 88.0], "authority": "酆都大帝", "danger_level": 2, "access": "主线剧情与高阶政务", "description": "冥界最高行政中枢，设帝阙、议政殿与幽冥法印中枢。"},
		{"id": "ten_kings_manors", "name": "十王府", "kind": "court", "position": [-190.0, 94.0], "size": [132.0, 76.0], "authority": "十殿阎罗", "danger_level": 3, "access": "审判委托与功过任务", "description": "十殿阎罗在酆都的府署群，负责分殿审判与刑狱协调。"},
		{"id": "judge_court", "name": "判官司", "kind": "court", "position": [190.0, 94.0], "size": [132.0, 76.0], "authority": "判官首座", "danger_level": 2, "access": "鬼籍查询与审判任务", "description": "汇总生死簿案卷、复核功过、签发审判文书。"},
		{"id": "ghost_registry", "name": "鬼籍司", "kind": "admin", "position": [-190.0, -8.0], "size": [132.0, 70.0], "authority": "鬼籍主簿", "danger_level": 1, "access": "新魂登记与身份服务", "description": "亡魂登记、身份核验、来历追溯与居留凭籍。"},
		{"id": "merit_bureau", "name": "功过司", "kind": "admin", "position": [190.0, -8.0], "size": [132.0, 70.0], "authority": "功过判官", "danger_level": 2, "access": "功德记录与因果委托", "description": "记录善恶功过、因果债契与轮回资格建议。"},
		{"id": "patrol_office", "name": "巡城司", "kind": "admin", "position": [0.0, 12.0], "size": [118.0, 62.0], "authority": "巡城统领", "danger_level": 2, "access": "治安巡查、失魂寻人和城市事件", "description": "负责城内治安、街区巡逻、夜禁、失魂案件与突发鬼患处置。"},
		{"id": "reincarnation_bureau", "name": "轮回司", "kind": "sacred", "position": [0.0, -142.0], "size": [150.0, 78.0], "authority": "轮回司主", "danger_level": 5, "access": "完成审判与轮回资格流程", "description": "管理轮回流程、转生文牒与通往忘川流域的官方通道；六道根本法则仍归后土。"},
		{"id": "ghost_market", "name": "万魂鬼市", "kind": "market", "position": [190.0, -166.0], "size": [142.0, 76.0], "authority": "鬼市行会", "danger_level": 4, "access": "交易、拍卖与玩家社交", "description": "冥界最大交易区，经营灵材、法器、情报、委托与跨阵营贸易。"},
		{"id": "residential_quarter", "name": "万家魂坊", "kind": "residential", "position": [-190.0, -166.0], "size": [142.0, 76.0], "authority": "坊正与巡城司", "danger_level": 1, "access": "居住、生活技能与社区活动", "description": "亡魂居民、商户、工匠与玩家居所聚集的生活城区。"},
		{"id": "yin_army_camp", "name": "阴兵大营", "kind": "military", "position": [-305.0, 20.0], "size": [88.0, 70.0], "authority": "阴兵统领", "danger_level": 3, "access": "巡城、军需与阵营任务", "description": "阴兵驻防、装备整备、城防演练与出征集结之地。"},
		{"id": "soul_waystation", "name": "引魂驿站", "kind": "transport", "position": [305.0, 20.0], "size": [88.0, 70.0], "authority": "引魂使", "danger_level": 2, "access": "新魂接引与远途交通", "description": "接引新魂、分流旅客、管理黄泉古道与远域驿传。"},
		{"id": "north_gate", "name": "北天门", "kind": "gate", "position": [0.0, 278.0], "size": [84.0, 34.0], "authority": "北门守将", "danger_level": 3, "access": "通往罗酆山古道", "description": "连接北境古道与罗酆山方向的主城门。"},
		{"id": "south_gate", "name": "南幽门", "kind": "gate", "position": [0.0, -278.0], "size": [84.0, 34.0], "authority": "南门守将", "danger_level": 3, "access": "通往忘川与轮回渡口", "description": "亡魂进入忘川流域与轮回渡口的主要门户。"},
		{"id": "east_gate", "name": "东玄门", "kind": "gate", "position": [370.0, 0.0], "size": [34.0, 84.0], "authority": "东门守将", "danger_level": 4, "access": "通往幽冥荒原与远域官道", "description": "通往幽冥荒原、边境关隘和远方血海方向的出城门户。"},
		{"id": "west_gate", "name": "西冥门", "kind": "gate", "position": [-370.0, 0.0], "size": [34.0, 84.0], "authority": "西门守将", "danger_level": 3, "access": "通往阴司军屯与古战场方向", "description": "连接军屯、古战场巡防线与西部边境的城门。"}
	],
	"roads": [
		{"from": "imperial_palace", "to": "ten_kings_manors"},
		{"from": "imperial_palace", "to": "patrol_office"},
		{"from": "imperial_palace", "to": "judge_court"},
		{"from": "ten_kings_manors", "to": "ghost_registry"},
		{"from": "judge_court", "to": "merit_bureau"},
		{"from": "ghost_registry", "to": "residential_quarter"},
		{"from": "merit_bureau", "to": "ghost_market"},
		{"from": "reincarnation_bureau", "to": "south_gate"},
		{"from": "yin_army_camp", "to": "west_gate"},
		{"from": "soul_waystation", "to": "east_gate"},
		{"from": "imperial_palace", "to": "north_gate"}
	]
}

const FENGDU_PROTOTYPE := {
	"world_id": "underworld_fengdu",
	"bounds": [-100.0, 100.0, -100.0, 100.0],
	"world_size": 200.0,
	"heightfield_cells": 128,
	"tile_count": 5,
	"water_bodies": [
		{"id": "forgotten_river", "name": "忘川河", "kind": "river_visual", "size": [8.0, 150.0], "center": [22.0, 8.0], "height": -0.62, "color": "#344b69", "alpha": 0.76, "map_visible": false},
		{"id": "blood_sea", "name": "血海", "kind": "sea_visual", "size": [56.0, 236.0], "center": [100.0, 0.0], "height": -1.25, "color": "#681d32", "alpha": 0.84, "map_visible": false}
	],
	"landmarks": [
		{"id": "naihe_bridge_valley", "name": "奈何桥 / 忘川河谷", "position": [22.0, 2.0, 2.0], "color": "#9ebce8", "kind": "visual", "map_visible": true},
		{"id": "reincarnation_terrace", "name": "轮回殿台地", "position": [-34.0, 8.0, -55.0], "color": "#c7b6dc", "kind": "visual", "map_visible": true},
		{"id": "blood_sea_coast", "name": "血海岸线（样板）", "position": [78.0, -6.0, 18.0], "color": "#e58b9e", "kind": "visual", "map_visible": false},
		{"id": "fengdu_outer_ridge", "name": "酆都北部山脊", "position": [-42.0, 12.0, -112.0], "color": "#b6a8a0", "kind": "visual", "map_visible": false}
	]
}



static func get_fengdu_city_plan() -> Dictionary:
	return FENGDU_CITY_PLAN.duplicate(true)


static func get_underworld_atlas() -> Dictionary:
	return UNDERWORLD_ATLAS.duplicate(true)


static func get_underworld_atlas_node(node_id: String) -> Dictionary:
	for node_variant in UNDERWORLD_ATLAS["nodes"]:
		if str(node_variant.get("id", "")) == node_id:
			return node_variant.duplicate(true)
	return {}


static func get_eighteen_hell_layers() -> Array:
	var hell_region := get_underworld_atlas_node("eighteen_hells")
	var layers: Array = hell_region.get("layers", [])
	return layers.duplicate(true)


static func get_world_bounds(world_id: String) -> Vector4:
	# Must match WorldServer's integrate_horizontal default clamp.
	return Vector4(-100.0, 100.0, -100.0, 100.0)


static func get_regions(world_id: String) -> Array:
	match world_id:
		"underworld_fengdu":
			return FENGDU_REGIONS.duplicate(true)
		"qingyun_human":
			return QINGYUN_REGIONS.duplicate(true)
		_:
			return []


static func get_landmarks(world_id: String) -> Array:
	if world_id != "underworld_fengdu":
		return []
	return FENGDU_PROTOTYPE["landmarks"].duplicate(true)


static func get_minimap_landmarks(world_id: String) -> Array:
	var result: Array = []
	for landmark in get_world_map_landmarks(world_id):
		var position_data: Array = landmark.get("position", [])
		if position_data.size() < 3:
			continue
		result.append({
			"id": str(landmark.get("id", "")),
			"name": str(landmark.get("name", "地标")),
			"position_x": float(position_data[0]),
			"position_z": float(position_data[2]),
			"kind": str(landmark.get("kind", "visual"))
		})
	return result


static func get_world_map_landmarks(world_id: String) -> Array:
	var result: Array = []
	for landmark in get_landmarks(world_id):
		if bool(landmark.get("map_visible", true)):
			result.append(landmark)
	return result


static func get_world_map_water_bodies(world_id: String) -> Array:
	var result: Array = []
	for water_body in get_water_bodies(world_id):
		if bool(water_body.get("map_visible", true)):
			result.append(water_body)
	return result


static func get_water_bodies(world_id: String) -> Array:
	if world_id != "underworld_fengdu":
		return []
	return FENGDU_PROTOTYPE["water_bodies"].duplicate(true)


static func get_prototype_definition(world_id: String) -> Dictionary:
	if world_id != "underworld_fengdu":
		return {}
	return FENGDU_PROTOTYPE.duplicate(true)


static func resolve_region_name(world_id: String, position: Vector3) -> String:
	var regions := get_regions(world_id)
	for region in regions:
		for bounds in region["bounds"]:
			if _inside_bounds(position, bounds):
				return str(region["name"])
	if world_id == "underworld_fengdu":
		return "酆都荒原"
	if world_id == "qingyun_human":
		return "青云郊野"
	return "未知区域"


static func _inside_bounds(position: Vector3, bounds: Array) -> bool:
	return (
		position.x >= float(bounds[0])
		and position.x <= float(bounds[1])
		and position.z >= float(bounds[2])
		and position.z <= float(bounds[3])
	)
