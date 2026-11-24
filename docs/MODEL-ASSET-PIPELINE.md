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
