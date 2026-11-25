# 《洪荒》3D 模型资源接入规范

## 目标与原则

本规范用于逐步把程序化占位模型替换为可商用的外部 GLB 资源。**不改变服务器实体、碰撞判定、伤害、寻路或网络同步**：外部模型只负责客户端视觉表现；战斗碰撞体仍由游戏逻辑创建和维护。

推荐优先级：
1. 角色与怪物：优先选择带骨骼、带基础动作的 glTF/GLB；逐个检查具体资源包许可。
2. 建筑与道具：优先模块化 GLB，便于拼装酆都城墙、鬼门关、灯柱、碑石。
3. 材质与环境：优先使用可降采样的 PBR 贴图，控制移动端/低显存设备开销。

## 资源目录与当前替换键

把经过许可核验和人工检查的模型放到 Client/HongHuangClient/assets/models/，文件名必须与 scripts/visual_model_library.gd 中的映射一致：

| 模型键 | 目标文件 | 用途 |
|---|---|---|
| player_humanoid | player_humanoid.glb | 玩家角色 |
| wolf | wasteland_wolf.glb | 荒原狼 |
| iron_beast | iron_beast.glb | 铁骨兽魂 |
| warrior | warrior_soul.glb | 炽战残魂/战魂 |
| life_soul | life_soul.glb | 生机古魂 |
| wind_soul | wind_soul.glb | 疾风游魂 |
| fire_soul | fire_soul.glb | 火属性游魂 |
| frost_soul | frost_soul.glb | 冰属性游魂 |
| wraith | wraith.glb | 游祟/灵识游魂 |

没有对应文件时继续使用程序化模型，不会因为空目录而阻断进入世界。模型覆盖文件必须以 Node3D 为根，并至少包含一个带 Mesh 的 MeshInstance3D；空场景会被识别并回退到占位模型。

## 独立美术预览台

`scenes/ArtPreviewStage.tscn` 不只是静态陈列：运行后可以用键盘直接检查导入模型的动作，不必进入联机世界或触发真实战斗。

| 按键 | 功能 |
|---|---|
| 1–5 | 选择玩家、荒原狼、铁骨兽魂、炽战残魂、游祟 |
| I / W / R | 待机 / 行走 / 奔跑 |
| A / H / D | 攻击 / 受击 / 死亡 |
| Esc | 尝试回到待机 |

预览优先调用模型上的 `ModelAnimationController`；玩家使用原生 AnimationPlayer 直接匹配动作名称，避免和正式玩家动画驱动产生竞争。待机、行走、奔跑通过预览专用接口循环播放；攻击、受击、死亡仍为一次性动作。找不到动画时会在预览面板中明确显示，不会伪装成动作播放成功。当前模型没有 AnimationPlayer 时会提示仍为静态占位模型。

建议导入每批 GLB 后依次检查：站立姿态、脚底是否贴地、行走脚滑、攻击方向、受击幅度、死亡姿态，以及模型面朝方向。自动验收只能检查结构和动画名称，不能替代这些视觉检查。

### 酆都模块化街区预览（本轮新增）

`underworld_visual_factory.gd` 提供可独立替换的建筑部件，并由 `create_fengdu_city_block()` 组合成一处小型街区，当前只用于美术预览，不会自动生成到正式联机地图：

| 组件 | 工厂方法 | 用途 |
|---|---|---|
| 城墙直段 | `create_fengdu_wall_segment()` | 连续围墙、垛口与基础阻挡 |
| 城防角楼 | `create_fengdu_watchtower()` | 城墙转角瞭望与防御节点 |
| 阴司衙门 | `create_yinsi_office_facade()` | 衙门正立面、门洞、立柱和匾额 |
| 鬼市摊位 | `create_ghost_market_stall()` | 街巷商业设施与摊位道具 |
| 街区组合 | `create_fengdu_city_block()` | 铺地、四面城墙、四角角楼、阴司衙门、鬼市摊位和引魂灯 |
| 内城街门 | `create_fengdu_inner_gate()` | 在城墙开出可通行的中央门洞，门柱与门楣分别设置碰撞 |
| 六道轮回殿 | `create_reincarnation_hall()` | 城内核心仪式建筑，以轮回法轮作为正立面标识 |

街区预览以“城防边界—内城街门—内部街巷—阴司衙门—六道轮回殿—鬼市摊位”为基本空间层次。南侧城墙预留门洞，由内城街门承担通行边界；阴司衙门与轮回殿分列街区后侧，避免把行政与轮回职能混成一座建筑。后续正式地图应把城墙和街区拆成可流式加载的场景块，不能把这份预览组合器直接当成整个酆都地图；酆都仍需保留大尺度城市布局，血海应位于城外远距离区域，十八层地狱作为独立区域设计。

当前这些建筑仍是原创程序化原型，便于验证尺度和组合关系；并不代表已经接入高品质外部 GLB。后续可逐件替换网格，但要保留模块接口、碰撞边界和资源登记记录。

## 冥界宏观地理总览（新增）

新增独立场景 `scenes/UnderworldRegionOverview.tscn`，脚本 `scripts/underworld_region_overview.gd`。这是区域关系与路线规划用的宏观灰盒，不是正式世界地图、导航网格或服务器分区配置。

当前规划坐标（仅用于预览）：
- 酆都内城中心约为 (-112, 0, 8)，并在外侧标记城防环。
- 忘川沿酆都外缘绕行，作为独立河流概念，不与血海混称。
- 血海中心约为 (132, 0, 10)，与酆都相隔约 244 米的预览距离；血海中心岛/岸侧设置冥河老祖道场。
- 十八层地狱入口位于另一处独立区域（约 (8, -1, -142)），以深渊环、入口关隘表达，不塞进酆都城内。
- 两条荒原古道分别连接酆都与血海、酆都与地狱入口；路线长度与方位是空间关系草案，不是最终游戏世界比例。

场景复用酆都内城总览作为城市地标，并关闭嵌套预览场景自己的相机/环境，确保宏观场景只有一套主相机与环境。打开该场景可检查三大区域是否足够分离、道路是否可读、地标是否容易识别。

下一阶段正式化之前必须完成：真实地形与高差、河流/海岸轮廓、道路可通行性、区域边界与服务器 world_id/zone_id 对应、分区加载距离、玩家出生点、导航网格与战斗刷怪点。当前灰盒不能直接用于生产出生或服务器寻路。

## 酆都内城总览场景（新增）

新增独立场景 `scenes/FengduCityLayoutPreview.tscn`，脚本为 `scripts/fengdu_city_layout_preview.gd`。它用于评审酆都从“单个街区”扩展到“多功能城区”的空间关系，不会自动写入正式联机地图，也不改变服务器出生点或导航数据。

总览场景采用约 72 × 72 米的城内展示尺度，包含：
- 四面城墙与四角城防角楼；南侧中央墙段留空，由内城街门构成可识别的入口。
- 南北向轮回大道、东西向横街和中央广场，明确主路径与交叉节点。
- 西北阴司官署区：主衙门与次级官署，表达行政/审判功能。
- 东北六道轮回区：轮回殿及镇魂碑，作为独立仪式空间。
- 西南鬼市坊区：两排摊位相向布置，保留中间步行通道。
- 东南居民坊区：低层院落原型，避免所有城区都由大型殿宇构成。
- 引魂灯用于标记广场、街口和南门接近路线。

打开 Godot 后可直接运行该独立场景检查整体布局。当前仍是程序化灰盒，碰撞只用于建筑展示阻挡；正式落地前还需检查城门通行净宽、街道寻路、建筑间距、视线遮挡、场景分块和客户端性能。血海不属于这张城内总览图，应放在酆都城外的远距离世界区域；十八层地狱也应单独制作入口与关卡地图。

## 模型尺寸自动校准（新增）

外部 GLB 接入后，`visual_model_library.gd` 会遍历模型层级内的 MeshInstance3D，计算网格包围盒，并按模型用途将整体视觉高度校准到目标值：

| 模型 | 目标高度 |
|---|---:|
| 玩家人形 | 1.80 m |
| 荒原狼 | 1.15 m |
| 铁骨兽魂 | 2.80 m |
| 战魂 | 1.90 m |
| 四类属性游魂 | 1.65 m |
| 游祟 | 1.85 m |

校准只缩放客户端视觉根节点，不修改服务器实体坐标、攻击距离或碰撞判定。缩放倍率限制在 0.25–4.0；如果源模型尺寸差异过大，会保留原始尺寸并写入 `model_scale_review_required` 元数据，避免把单位错误静默放大。原始高度、目标高度和缩放倍率也会写入模型元数据，方便预览与排查。

这一步只统一高度，不自动旋转模型或移动脚底枢轴。面朝方向、脚底位置、武器挂点仍需在预览场景中人工确认。

## 动画接入（本轮新增）

外部 GLB 若包含 AnimationPlayer，会自动附加 `model_animation_controller.gd`：
- 根据模型根节点的实际位移，在 idle / walk / run 动画间切换。
- idle / walk / run 强制循环播放；attack / hit / death 按一次性动作播放，避免攻击或死亡动作无限循环。
- 忽略异常大的位置跳变，避免网络快照纠正被误判为奔跑。
- 暴露 `play_action("attack" | "hit" | "death")`，由已确认的怪物攻击、受击和死亡事件触发。
- 找不到对应动画时不强行播放，原有程序化受击/死亡视觉仍然保留。
- 玩家人形模型继续使用现有 `HHHumanoidAnimationDriver`，避免两个动画控制器争抢同一个 AnimationPlayer。

首选动作资源：[Quaternius Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html)。官方页面说明它包含 120+ 个通用 Humanoid 动作，支持 Godot、Unity、Unreal 重定向，覆盖多方向移动、战斗、表情动作和死亡动画；页面标注 CC0。建议先下载免费 glTF/GLB 导出，检查动作命名与骨架后再做导入映射。官方页面还说明免费版本为整包的 60–70%，Source 工程包属于额外档位；本项目不依赖付费版本。

## 模型交付检查表

每个角色/怪物模型在进入主分支前应逐项验收：

- [ ] GLB 能在 Godot 4.x 导入，场景根节点为 Node3D。
- [ ] 面朝方向统一：角色正面朝 Godot 的 -Z；脚底落在局部 Y=0 附近。
- [ ] 尺寸统一：人形约 1.7–2.0m；狼类约 0.8–1.4m 高；大型兽类约 2.5–4m 高。最终按场景镜头校准。
- [ ] 网格有法线、UV 与材质；检查透明材质排序和贴图缺失。
- [ ] 骨骼权重正常，无明显拉伸、翻面或穿插。
- [ ] 有动作时检查 idle、walk/run、attack、hit、death；缺失动作不得伪装成已支持。
- [ ] 视觉模型不携带会覆盖服务器战斗判定的碰撞体；碰撞由客户端实体逻辑单独管理。
- [ ] 远景有 LOD 或使用低面数版本；贴图优先 1K/2K，避免默认加载超大纹理。
- [ ] 在实际游戏镜头下检查身高、脚底、朝向、武器挂点和遮挡。
- [ ] 资产登记表记录原始 URL、作者、包名/版本、许可副本、文件路径、修改内容和核验日期。

## 免费商用来源初筛（不是已导入资源）

| 来源 | 合适用途 | 许可结论 | 重要限制 |
|---|---|---|---|
| [Quaternius](https://quaternius.com/) | 人形、怪物、模块化建筑、道具 | 官方 FAQ 表示资源包按包使用 CC0 或 QAL；QAL 允许个人/教育/商业项目使用 | 逐包保存下载页与 LICENSE；QAL 禁止把资源本身作为素材包单独转售/再分发 |
| [Quaternius 许可条款](https://quaternius.com/license.html) | 核对 QAL 许可 | 当前条款允许将资源整合进商业游戏，无需署名 | 不可单独售卖、打包分发原始/修改后的素材本身 |
| [Poly Haven](https://polyhaven.com/models) | 写实石材、树木、环境道具、PBR 材质与 HDRI | 官方资源页声明模型/贴图/HDRI 为 CC0，可商用且无需署名 | 每个资源仍保存来源记录；风格偏写实，需评估是否匹配洪荒美术方向 |
| [Kenney](https://kenney.nl/assets) | 简洁道具、UI、基础环境模块 | 官方支持页说明其资源页上的游戏素材采用 CC0 | 仍需核对具体资源页和下载包内 LICENSE；部分素材风格偏卡通 |

首批优先下载/评估的具体包（这些包页面明确列出 CC0；仍需保存下载包内 LICENSE）：

| 资源包 | 页面明确内容 | 洪荒用途 | 评估顺序 |
|---|---|---|---|
| [Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) | 50 个带动画怪物，含 glTF，页面标注 CC0 | 怪物骨架与动画参考；筛选兽类和大型怪物 | 1 |
| [Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html) | 12 种动物，每种 12+ 动画，含 glTF，页面标注 CC0 | 荒原狼、四足怪物的动作基础 | 2 |
| [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html) | 6 个可重定向 Humanoid 基础角色，含 glTF，页面标注 CC0 | 玩家人形骨架与动画兼容基底 | 3 |
| [Ultimate Fantasy RTS](https://quaternius.com/packs/ultimatefantasyrts.html) | 128 个建筑/自然资产，含 glTF，页面标注 CC0 | 酆都城墙、塔楼、建筑模块的素材参考 | 4 |

官方依据：
- Quaternius FAQ: https://quaternius.com/faq.html
- Quaternius QAL: https://quaternius.com/license.html
- Poly Haven License: https://polyhaven.com/license
- Kenney Support: https://kenney.nl/support

## 导入流程

1. 下载具体资源包，保留原始压缩包和许可文件。
2. 先解压到临时目录，检查包内 LICENSE、README、作者和资源格式。
3. 只把实际使用的 GLB 与必要贴图复制到 assets/models/；不把整个第三方资源包直接塞进发行包。
4. 在 Godot 导入后打开场景，检查比例、朝向、骨骼和材质。
5. 复制/重命名为映射表中的固定文件名；不要覆盖服务器或客户端实体脚本。
6. 更新 assets/3d/asset-register.csv，状态从 candidate 改为 imported/verified，并记录许可文件路径。
7. 在游戏中检查移动、攻击、受击、死亡和多人同步；缺少动画时先保留原有动作占位，不改动战斗权威逻辑。

## 当前代码保护

scripts/visual_model_library.gd 负责可选 GLB 覆盖。它会：
- 按稳定模型键加载 GLB；
- 要求根节点为 Node3D 且存在可渲染 MeshInstance3D；
- 记录模型来源和模型键元数据；
- 缺失、格式不符或空模型时回退到程序化模型。

这只是资源接入保护，不代表已下载、导入或验收任何第三方模型。当前模型替换仍处于候选资源筛选阶段。



### 动画验收规则（第二版）

验收器不再要求所有怪物都必须具备完全相同的六类动画，而是按模型用途检查最低动作集：

| 模型 | 必需动作 |
|---|---|
| 玩家 | idle、walk |
| 荒原狼 / 铁骨兽 / 战魂 | idle、walk、attack、death |
| 生机 / 疾风 / 火 / 冰游魂、游祟 | idle、attack、death |

这避免把漂浮灵体没有四足奔跑动作误判为资源缺陷。报告现在还会列出每段动画的名称、时长、循环模式和轨道数量，并把 run 与 walk 分开识别，避免仅有 walk 时被误报为具备 run。

普通验收仍允许缺少候选模型或动作，只报告警告；需要检查动画完整度时执行：

```bash
godot --headless --path . --script res://tools/validate_model_assets.gd -- --strict-animations
```

需要九个模型全部存在且动画齐备时，同时使用 `--require-all --strict-animations`。注意：动画名称匹配是自动初筛，最终仍需在预览场景中确认动作方向、骨架重定向和实际观感。

## 自动化模型验收工具（新增）

新增 `tools/validate_model_assets.gd`，用于在模型资源放入映射目录后进行无界面检查。它会遍历上面的九个固定模型键，并输出每个模型的：
- 文件是否存在、是否能加载为 PackedScene、根节点是否为 Node3D；
- 可渲染 MeshInstance3D 数量、材质表面数；
- Skeleton3D 与 AnimationPlayer 数量，以及发现的动画名称；
- 最大网格尺寸参考值，便于发现明显的尺寸异常；
- 缺少骨骼/动画等警告，以及无可渲染网格等阻断错误。

首次导入 GLB 时，先用 Godot 编辑器打开项目并等待导入完成，然后在客户端目录执行：

```bash
godot --headless --path . --script res://tools/validate_model_assets.gd
```

缺失文件属于当前阶段的正常情况，默认只列为 missing，不会让干净仓库验收失败。准备发布或要求九个模型全部齐备时，增加严格参数：

```bash
godot --headless --path . --script res://tools/validate_model_assets.gd -- --require-all
```

报告同时打印到控制台，并保存到 Godot 用户目录的 `user://model_asset_validation.json`。该脚本只检查资源，不会下载、改写、移动模型，也不会改动服务器战斗数据。注意：通过结构检查不等于美术验收；比例、朝向、骨骼变形、材质和实际动作仍需在 ArtPreviewStage 与游戏镜头中人工检查。


## NPC 模型正式替换槽（本轮新增）

NPC 不再只有一套不可替换的程序化人形：`create_npc()` 现按 NPC 职能选择独立 GLB 槽位，并保留原有程序化模型作为缺失资源时的安全回退。资源文件放入 `assets/models/` 后即可由同一入口加载：

| 文件 | NPC | 目标高度 | 最低动画 |
|---|---|---:|---|
| `npc_judge.glb` | 阴司判官 | 1.85m | idle |
| `npc_trial_master.glb` | 试炼使者 | 1.85m | idle |
| `npc_guard.glb` | 阴兵守卫 | 1.90m | idle |
| `npc_soup_keeper.glb` | 孟婆 | 1.70m | idle |
| `npc_blacksmith.glb` | 鬼市铁匠 | 1.85m | idle |
| `npc_generic.glb` | 通用城民/商贩 | 1.80m | idle |

导入模型仍必须人工检查面向、脚底、骨架和材质。NPC 模型不应携带游戏逻辑碰撞体；交互范围和服务端 NPC 身份仍由原有系统决定。当前只是把六个资源槽接入工厂，**这些 GLB 文件尚未随本次提交导入**。

## 资产落地优先级与验收门槛（本轮新增）

1. 玩家主角：先定一套东方修行者基础人形，确保 idle/walk、武器挂点和装备插槽兼容，再制作男女/体型变体。
2. 酆都关键 NPC：孟婆、判官、阴兵、试炼使者、铁匠优先；每个重要 NPC 要有独立轮廓、服饰、头饰/道具，不允许只换材质颜色充数。
3. 怪物：荒原狼、铁骨兽魂、战魂、游祟及四属性游魂；四足怪物优先使用带骨骼的动物模型，灵体可以采用低面数漂浮模型。
4. 酆都建筑：鬼门关/城门、城墙和角楼、阴司衙门、六道轮回殿、鬼市摊位、居民院落。建筑按模块拆分，支持复用和远景 LOD。
5. 音频：主城环境底噪、风声、远钟、灯火/魂火、脚步、城门、NPC 交互、怪物叫声、攻击命中、技能、受击、死亡和 UI。环境音需可循环且无明显接缝；战斗提示音必须与危险阶段一致。

每批资产的完成定义：来源与许可已核验、原始文件及 LICENSE 留档、GLB/WAV 已导入、资源登记状态更新、Godot 实际打开检查、游戏镜头检查通过。只有代码槽位或候选网址，不算模型/音效完成。


### 玩家角色 GLB 槽位（本轮新增）

`create_player_humanoid()` 已接入 `player_humanoid.glb` 可选覆盖。导入角色若包含 AnimationPlayer，现有 `HHHumanoidAnimationDriver` 会优先匹配 idle/walk/attack/hit 动作；若没有兼容动作或文件缺失，则继续使用原来的程序化角色与关节摆动。玩家正式模型必须保留约 1.8m 视觉高度，面向 -Z，脚底接近 Y=0，并提供清晰的武器/装备挂点方案。**本次只接通资源槽，不代表玩家 GLB 已经导入或通过动作验收。**
