# 第三方模型资产与许可记录

本批模型仅用于《洪荒》游戏项目，并保留各作者的原始许可文件。模型被整合进游戏项目，不代表项目作者拥有第三方模型版权。

| 项目文件 | 原始资产 | 作者/来源 | 许可 | 原始来源 |
|---|---|---|---|---|
| player_humanoid.glb | Knight | Kay Lousberg / KayKit Adventurers 1.0 | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 |
| iron_beast.glb | Orc | Quaternius / Ultimate Monsters | CC0 1.0（官方包页） | https://quaternius.com/packs/ultimatemonsters.html |
| fengdu_wall.glb | Wall | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 |
| fengdu_watchtower.glb | Tower | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_hall.glb | Hall | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_house.glb | House | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_tree.glb | Tree | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_rock.glb | Rock | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |

## 许可核验说明

- KayKit 两个包的仓库 README 与随包 LICENSE 明确标注 CC0 1.0，允许个人及商业项目使用，无需署名。
- Quaternius 官方 Ultimate Monsters 包页面标注 CC0，并说明包含 50 个带动画怪物。项目内保存了可获得的随包许可文本；该文本标题与包名不完全一致，因此以官方包页面标注为主要依据，后续若取得原始下载包，应再归档该包自带 LICENSE。
- 二进制模型来自公开 GitHub 镜像仓库 https://github.com/kikoncuo/jevfire；镜像的 web/ASSETS.md 明确记录模型对应的原作者、资源包和许可。镜像仅作为文件获取来源，不作为模型作者。
- 本批文件未做网格重拓扑或骨骼重定向；程序只在运行时调整视觉模型尺寸。城墙和建筑的游戏碰撞仍由《洪荒》代码独立生成。

## 验收状态

所有本批模型状态均为 imported_unverified。在用户本机 Godot 4.6 导入后，还需检查脚底、朝向、材质、动作、缩放和性能。未完成镜头验收前，不标记为 accepted。