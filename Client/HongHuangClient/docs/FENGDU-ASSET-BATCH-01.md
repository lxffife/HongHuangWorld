# 酆都正式资产落地批次 01：玩家、NPC、怪物与声音

> 本批次是可执行采购/导入清单，不表示第三方文件已经下载。所有外部资产在具体包的 LICENSE、骨架、动作和画面检查完成前均保持 candidate。

## 本批目标

先建立一套风格统一、性能可控、可被现有 GLB 槽加载的角色资产。不要一次导入大量风格不一致的素材。先完成玩家主角、关键 NPC 和一只四足怪物的纵向切片，再复制流程。

## A. 角色模型采购与导入顺序

| 顺序 | 游戏角色 | 目标文件 | 必须满足 | 资源候选/说明 |
|---|---|---|---|---|
| 1 | 玩家主角 | assets/models/player_humanoid.glb | Humanoid Skeleton、idle/walk；最好有 run/attack/hit/death；武器挂点可配置 | Quaternius Universal Base Characters 或 Ultimate Modular Men；下载后必须核验骨架与现有 HHHumanoidAnimationDriver 的兼容性 |
| 2 | 孟婆 | assets/models/npc_soup_keeper.glb | 独特女性长者轮廓、发髻/玉簪、汤碗；Skeleton、idle | 可用通用人形作骨架基底，但头部、衣饰、汤碗必须有独立造型，不可仅换颜色 |
| 3 | 阴司判官 | assets/models/npc_judge.glb | 官帽、暗紫官袍、判卷/笔道具；Skeleton、idle | 通用人形基底 + 独立头饰/服装配件 |
| 4 | 阴兵守卫 | assets/models/npc_guard.glb | 甲胄、长戟/长枪、站岗轮廓；Skeleton、idle | 可复用 Humanoid 骨架，但装备轮廓需独立 |
| 5 | 试炼使者 | assets/models/npc_trial_master.glb | 暗朱袍、令牌、引导者轮廓；Skeleton、idle | 可复用 Humanoid 骨架，不可与判官仅换材质 |
| 6 | 鬼市铁匠 | assets/models/npc_blacksmith.glb | 厚围裙、护腕、锻造锤；Skeleton、idle | 通用人形基底 + 铁匠专属装备 |
| 7 | 城民/商贩 | assets/models/npc_generic.glb | 至少一套中性基础服装；Skeleton、idle | 后续用头巾、背篓、衣服配件做变体 |
| 8 | 荒原狼 | assets/models/wasteland_wolf.glb | 四足骨架；idle/walk/attack/death；扑咬动作方向正确 | Quaternius Ultimate Monsters / Ultimate Animated Animal Pack，必须实际预览四足动作 |
| 9 | 铁骨兽魂 | assets/models/iron_beast.glb | 大型四足或兽型骨架；idle/walk/attack/death；重击动作 | 优先筛选可重定向四足怪物；不合适则保留程序化模型等待专门制作 |
| 10 | 战魂 | assets/models/warrior_soul.glb | Humanoid 骨架；idle/walk/attack/death；武器动作 | 通用人形骨架 + 东方甲胄和兵器配件 |
| 11 | 四属性游魂 | life_soul.glb / wind_soul.glb / fire_soul.glb / frost_soul.glb | 灵体外观、idle/attack/death；可共用基础骨架但外形/材质/特效需区分 | 可先保留程序化灵体，避免把不匹配的普通怪物硬套为灵魂 |
| 12 | 游祟 | wraith.glb | 漂浮轮廓、idle/attack/death；透明材质排序稳定 | 低面数灵体或程序化原创；不强求 walk/run |

## B. 建筑与道具资产批次

| 顺序 | 资产 | 目标内容 | 交付格式/验收 |
|---|---|---|---|
| 1 | 鬼门关 | 门柱、门楣、门扇、匾额、瓦檐 | 分件 GLB；门洞净宽与现有通行碰撞匹配 |
| 2 | 城墙模块 | 直墙、转角、垛口、墙顶步道、角楼 | 可重复拼接；模块端点对齐；远景低模 |
| 3 | 阴司衙门 | 主体、台阶、廊柱、匾额、案牍 | 建筑与道具分开，避免单一超大网格 |
| 4 | 六道轮回殿 | 主殿、轮回法轮、台基、灯柱 | 远距离地标清晰；法轮可独立动画 |
| 5 | 鬼市 | 摊棚、招牌、货架、器皿、锻造台 | 模块化小件，支持街区重复摆放 |
| 6 | 居民坊 | 民居、院墙、门窗、井台、杂物 | 低层密度建筑，避免全城宫殿化 |
| 7 | 城市道具 | 引魂灯、镇魂碑、石柱、旗幡、灯笼 | 单件可实例化；光源数量受预算控制 |

建筑首批可以从 Quaternius Ultimate Fantasy RTS 选择模块化结构作灰盒替代，但需进行东方屋顶、瓦檐、木构与石材统一处理。不要把西式城堡完整套入酆都。

## C. 音效正式替换清单

全部通过现有 HHAudio 总线与音量设置，不允许绕过总线直接播放。目标统一为 WAV/OGG，建议 44.1kHz 或 48kHz；短音效避免削波，环境音检查循环接缝。

| 类别 | 目标文件建议 | 场景/触发 | 验收 |
|---|---|---|---|
| 酆都环境 | fengdu_ambience_loop.ogg | 城区持续环境 | 30–90 秒可无缝循环，低强度、不盖过 UI |
| 远钟 | fengdu_distant_bell_01.ogg | 低频随机播放 | 远近感自然，不能高频重复 |
| 街巷氛围 | fengdu_market_murmur_loop.ogg | 鬼市区域 | 不出现可辨识或侵权对白 |
| 引魂灯 | soul_lantern_flame_loop.ogg | 灯具附近 | 低音量循环 |
| 鬼门关 | ghost_gate_rumble.ogg | 城门开闭/靠近 | 低频短音，避免持续轰鸣 |
| 孟婆交互 | mengpo_bowl_clink.ogg | 对话/递碗 | 轻柔、短促 |
| 判官交互 | judge_seal_stamp.ogg | 判卷/确认 | 木案、印玺质感 |
| 阴兵 | guard_armor_step.ogg | 巡逻/站岗 | 金属装备轻响，不要每帧触发 |
| 铁匠 | blacksmith_hammer_loop.ogg | 鬼市铁匠铺 | 有节奏的循环，距离衰减 |
| 游魂 | soul_whisper_loop.ogg | 灵体附近 | 低音量、循环无接缝 |
| 怪物 | monster_wolf_growl.ogg / monster_beast_roar.ogg | 怪物待机/攻击 | 与攻击事件绑定，避免客户端自行猜测伤害 |
| 战斗 | combat_swing_*.ogg / combat_hit_*.ogg | 已确认攻击/命中事件 | 挥击、命中、重击分层，命中只由确认事件播放 |
| 技能 | spell_cast_*.ogg | 技能释放 | 按技能类型区分 |
| 机关 | hell_hazard_warning.ogg | 服务端预警阶段 | 必须先于危险生效；与伤害阶段同步 |

音源候选：
- Kenney Audio：只在具体资源包页面及随包许可确认 CC0 后使用。
- Sonniss GameAudioGDC：逐年核对 EULA 与再分发限制，未核验不得导入。
- Freesound：只选单个明确标记 CC0 的文件；不得把平台整体登记为 CC0。

## D. 导入步骤（每个批次都执行）

1. 下载原始压缩包到项目外的临时目录，保留原始文件。
2. 保存具体资源页截图/URL、作者、包名、版本、LICENSE 原文及下载日期。
3. 逐个确认许可：CC0、Quaternius QAL 或其他许可必须分别记录；未确认就不进游戏发行资产。
4. 在 Blender 或 Godot 中检查根节点、比例、朝向、脚底、Skeleton3D、AnimationPlayer、材质、贴图与动画。
5. 复制选定 GLB 到固定映射文件名；原始资源包不要整体塞入发行包。
6. 更新 assets/3d/asset-register.csv 或 assets/audio/asset-register.csv，状态依次为 candidate → imported → verified。
7. 运行模型校验：
   - 普通结构检查：godot --headless --path . --script res://tools/validate_model_assets.gd
   - 要求角色骨架和动画播放器：godot --headless --path . --script res://tools/validate_model_assets.gd -- --strict-rig
   - 要求模型齐全且动作齐全：godot --headless --path . --script res://tools/validate_model_assets.gd -- --require-all --strict-animations --strict-rig
8. 打开 ArtPreviewStage，实际播放动作；随后进入酆都联机镜头检查多人同步、比例、遮挡与帧率。
9. 只有全部通过才标记 verified。静态结构通过不等于美术验收通过。

## E. 本批验收目标

- 玩家：至少一个可用人形骨架、idle/walk 播放正确，原装备/战斗逻辑不受影响。
- NPC：孟婆、判官、阴兵三个关键 NPC 外观可区分，idle 可播放。
- 怪物：至少一只正式四足模型替换荒原狼，扑咬/死亡动画可用。
- 建筑：鬼门关或城墙至少一套模块化模型在预览场景拼装成功。
- 音频：先替换远钟、环境氛围、引魂灯三类音源并完成循环/响度检查。

当前仓库尚未包含上述外部 GLB/WAV 文件。本清单完成后，仍须执行实际下载、导入和 Godot 画面验收，不能把 candidate 标成 verified。

## F. 关键 NPC 轮廓评审补充（程序化占位，不是正式模型）

当前程序化回退已强化五类可远距离识别的轮廓，方便在正式 GLB 到位前做场景构图与交互位置验收：

- **孟婆**：保留发髻、玉簪、忘忧汤碗与轻雾。
- **阴司判官**：新增高冠与横向冠翼、手持判卷/笏板及朱色印记；避免只靠紫色官袍区分。
- **阴兵守卫**：新增盔顶、盔缨、护面与长枪；注意正式模型到位后应由骨骼挂点承载武器。
- **试炼使者**：使用披肩与发光令牌，避免与判官共享同一头饰/手持物。
- **鬼市铁匠**：加厚围裙、工具环、护腕与大锤轮廓。
- **普通城民**：使用头巾、围巾和肩背货篓，区别于阴司官员。

这些部件目前由 Godot 原始几何体拼装，**不具备正式角色骨骼、表情、布料或高质量动画**。它们只用于占位阶段的轮廓辨识与镜头评审；不能把资产登记状态改为 imported/verified。正式交付仍需独立 GLB、骨架/动画检查和实际画面验收。

## G. 已核对的免费资产候选（2026-11-25）

> 这里只登记官方资源页当前明确标注的许可，不代表已经下载、导入或通过游戏内验收。下载时必须保留压缩包内 LICENSE，并记录下载日期与文件哈希。

| 用途 | 官方资源包 | 页面明确内容 | 对本项目的用途判断 |
|---|---|---|---|
| 玩家/人形 NPC 基础 | [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) | 页面标注 CC0；6 个 Humanoid rig 基础角色；glTF/FBX 等格式 | 第一优先。玩家先选 Regular 比例基底；孟婆、判官、阴兵再用配件/服装差异化，不要直接把同一裸模型复制成六个 NPC |
| 玩家动作 | [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) | 页面标注 CC0；120+ 通用 Humanoid 动作；含 GLB；页面说明适配 Godot/Unity/Unreal | 与基础人形配套，先测试 idle/walk/run/attack/hit/death 的 retarget 和现有玩家动画驱动冲突 |
| 荒原狼 | [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html) | 页面标注 CC0；12 种动物；每种 12+ 动画；含 glTF | 四足怪物优先候选。下载后先确认具体 wolf 模型、骨架朝向、扑咬/死亡动作，再映射为 wasteland_wolf.glb |
| 怪物备选 | [Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) | 需以下载时官方包页和 LICENSE 为准 | 先筛出适合洪荒的轮廓；不要只因包名含 Monsters 就默认有合适四足狼 |
| 建筑/场景 | [Ultimate Fantasy RTS](https://quaternius.com/packs/ultimatefantasyrts.html) | 页面标注 CC0；128 个建筑与自然模型；含 glTF | 先拿墙段、塔楼、市场/建筑体块做模块评估；东方屋顶与酆都石木色调仍需二次统一 |
| 建筑备选 | [Ultimate Buildings Pack](https://quaternius.com/packs/ultimatetexturedbuildings.html) | 页面标注 CC0；76 个模块化建筑 | 仅作民居体块与材质调色参考，不直接替代鬼门关/六道轮回殿的东方主地标设计 |

### 许可边界必须区分

- Quaternius 官方 FAQ 明确：每个资源包可能采用 CC0 或 QAL，具体看该包详情页及下载包内 LICENSE；不能把整个站点统一写成 CC0。
- [Quaternius Asset License（QAL）](https://quaternius.com/license.html) v1.0（页面标注 2026-08-28 更新）允许个人、教育和商业项目使用、修改并随完成产品发布；但禁止把资产本身作为独立素材包/模板重新分发或转售。
- 对当前列为 CC0 的旧包，仍须保存对应资源页与随包 LICENSE；如果下载时许可已变化，以实际下载包的许可文件和官方条款为准。
- 本项目允许把资产集成进游戏成品，不会把第三方原始模型作为独立素材库向外分发。资产状态在完成导入和检查前一律保持 candidate。

### 建议导入顺序（不擅自替用户下载/引入第三方二进制）

1. Universal Base Characters：只选一个 Regular 人形做玩家基底，先检查骨骼命名、朝向、比例和脚底位置。
2. Universal Animation Library：先独立验证 retarget；确认不会与 HHHumanoidAnimationDriver 双重驱动，再接入玩家。
3. Ultimate Animated Animal Pack：单独挑狼模型，检查四足骨架与攻击/死亡动画。
4. Ultimate Fantasy RTS：挑 3–5 个墙/塔/建筑部件做酆都风格适配试拼，不要整包导入发行资源。
5. 通过 ArtPreviewStage 和严格模型校验后，再逐个替换 NPC、怪物与城区建筑。


### H. 玩家人形 GLB 接入验收门槛（代码侧）

- `VisualModelLibrary` 在实例化 `player_humanoid` 时记录 MeshInstance3D、Skeleton3D、AnimationPlayer、总骨骼数和动画片段；少于 15 根骨骼、缺少骨架或没有动画片段时标记为需要人工复核。严格校验器同步检查 15 骨骼门槛，并要求玩家至少有 idle/walk/attack/hit 四类动作。
- 美术预览台在选中玩家模型时显示骨架验收与动画片段状态，不能仅凭“GLB 已加载”认定为正式角色。
- `HHHumanoidAnimationDriver` 会在多个 AnimationPlayer 中选择包含当前动作片段的播放器；待机/行走强制循环，攻击/受击按单次动作播放，避免误选第一个播放器或循环攻击动画。
- 玩家动画仍由现有 `HHHumanoidAnimationDriver` 统一驱动，不再给玩家模型挂第二套自动移动动画控制器；NPC/怪物仍使用各自的 `ModelAnimationController`。
- 骨架数量阈值只是快速筛查，不等于骨骼命名、蒙皮权重、动作重定向和脚底贴地验收。正式入库前仍须在 Godot 中实际检查骨骼树、动作覆盖、朝向、比例、脚底位置和装备挂点。
- 当前仓库尚无正式玩家 GLB，因此这些验收信息在实际模型导入前不会显示为通过。


### I. 装备挂点与多动画播放器验收

- 装备挂点解析支持常见 Mixamo 命名（含 `mixamorig:` / `mixamorig1:` 前缀）、下划线变体和中英文手部/躯干别名；匹配时会先尝试精确骨骼名，再进行规范化名称匹配。
- 武器、副手和背部挂点优先使用骨骼 `BoneAttachment3D`；程序化角色的手部挂点继续使用随手臂 pivot 运动的节点。找不到骨骼时保留 root offset 兼容回退，但会在诊断中明确标为未跟随骨骼。
- 玩家预览台显示武器手、副手和背部挂点是否跟随动画骨骼。严格模型校验器也会把这三个挂点的绑定情况写入 JSON 报告；`--strict-rig` 下若没有真实姿态跟随则失败。
- 怪物/NPC 动画控制器现在可在多个 AnimationPlayer 间按动作挑选可用片段，避免 GLB 把待机、移动和攻击拆到不同播放器时只读取第一个播放器。
- 荒原狼正式模型至少需要 idle、walk、run、attack、death 五类动画；实际资源若缺少其中一类，严格动画校验会指出缺项。
- 当前没有正式 GLB，故挂点和狼动作仍未完成实物验收；不把 root offset 或程序化模型记作正式通过。


## J. 荒原狼四足骨架与动画验收（v4）

荒原狼不再沿用玩家人形的“骨骼数量够用”判断。模型校验器会额外输出四足结构诊断：骨骼名称列表、骨盆/根骨、脊柱/背部、头部，以及前肢和后肢的命名匹配数量。狼模型的最低骨骼数门槛单独设为 12；严格模式还要求前后肢各至少出现两个可识别骨骼命名线索。

命名识别兼容常见的 front/fore、hind/back/rear、leg/limb/paw/foot 等词根，并忽略大小写、下划线、连字符、空格和命名空间前缀。不同资源包骨架命名差异很大，因此该检查是自动初筛：若资源使用纯数字或完全自定义骨骼名，报告会提示人工复核，不应通过放宽规则来掩盖缺少四足关节的问题。

动画控制器同时改进片段匹配评分：完全匹配优先于前缀匹配，前缀匹配优先于普通包含匹配；多 AnimationPlayer 时按目标动作的片段匹配质量选播放器，降低误把相似命名片段当作目标动作的概率。狼正式资产仍须具备 idle/walk/run/attack/death 五类动作，并实际检查四足步态、脚掌落地、转向和攻击动作是否正确。

当前仍没有导入正式狼 GLB；本节是导入前验收能力，不代表模型或动画已经完成。


## K. 物种专属攻击动作与四足预览诊断（v5）

动画控制器按模型类型选择攻击动作：荒原狼优先 bite/pounce/lunge/maul，再退回通用 attack；铁骨兽魂优先 smash/charge/stomp/crush。四足移动动作识别补充 trot、gallop、canter，待机补充 rest，避免资源包使用动物学动作命名时被误判为缺失。

ArtPreviewStage 选中狼或铁骨兽魂时，会读取 Skeleton3D 骨骼名称，展示前肢/后肢命名匹配数量和骨骼名数量。该信息只用于快速定位资源包骨架命名差异，不等于动作播放、蒙皮或脚掌贴地已经通过。最终仍须在 Godot 内逐个播放步态与攻击片段，观察四肢是否正确驱动、脚掌是否穿地/滑步、根运动是否造成额外位移。

## L. 民居与鬼市沿街建筑模块（2026-11-25）

本批次在既有城墙、阴司衙门、六道轮回殿和临时摊位之外，补充可重复摆放的城区建筑单元：

- `create_fengdu_residential_house()`：窄地块民居，包含石质基座、夯土墙体、木门窗、前廊立柱、双层屋面、门匾和近似阻挡碰撞体。
- `create_ghost_market_shop()`：两层鬼市店铺门面，包含上下层窗格、店招、外挑布檐、双层屋面和阻挡碰撞体。
- `create_fengdu_residential_lane()`：将两栋民居、一间店铺、铺地和魂灯组合成独立评审街巷，便于检查建筑比例与行人通道。 场景入口为 `scenes/FengduResidentialLanePreview.tscn`，可在Godot编辑器单独打开评审。

注意：以上仍是项目内原创程序化灰盒/风格块，不是最终高模建筑，也没有替代正式酆都地图。当前碰撞体按建筑主体近似包围，门窗开口与檐廊细节尚未拆成可通行碰撞；接入正式城区前需要在Godot中检查尺度、朝向、导航可达性和碰撞穿行，并逐步替换为外部正式模型或原创高质量模型。

## M. 酆都居民区街道网格与街区级组合（2026-11-25）

本批次将民居从单条街巷扩展为可重复拼接的街区：

- `create_fengdu_street_tile()`：8m × 8m 模块化铺地，含路面、四边矮路缘、排水槽视觉线和地面碰撞体。可通过平移/旋转拼接。
- `create_fengdu_residential_district()`：5 × 5 街道网格，外围布置民居、鬼市店铺、魂灯和街区告示碑，用于评审城区密度、街道尺度与地标节奏。
- 独立场景入口：`scenes/FengduResidentialDistrictPreview.tscn`。场景使用俯视斜角镜头和环境补光，便于整体观察。

该组合仍是街区尺度的视觉评审样板，不是正式世界地图分块；道路导航网格、房屋室内、门洞精确碰撞、NPC路径和动态加载尚未接入。道路碰撞目前只覆盖铺地平面，路缘是视觉构件；正式接入时应把可行走区域纳入 NavigationRegion3D，并避免建筑包围碰撞侵入道路。
