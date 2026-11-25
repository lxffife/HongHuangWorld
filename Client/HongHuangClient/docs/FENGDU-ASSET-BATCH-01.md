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
