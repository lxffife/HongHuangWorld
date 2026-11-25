# 第三方模型资产与许可记录

本清单记录《洪荒》客户端使用的第三方模型、原作者、资源包、许可证和导入状态。模型整合进游戏项目不代表项目作者拥有第三方模型版权。

## 角色与怪物

| 项目文件 | 原始资产 | 作者 / 资源包 | 许可 | 原始来源 |
|---|---|---|---|---|
| player_humanoid.glb | Knight | Kay Lousberg / KayKit Adventurers 1.0 | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 |
| npc_guard.glb | KnightCharacter | Quaternius / Animated Knight Pack | CC0 1.0 | https://quaternius.com/packs/knightcharacter.html |
| wasteland_wolf.glb | Wolf | Quaternius / Ultimate Animated Animal Pack | CC0 1.0 | https://quaternius.com/packs/ultimateanimatedanimals.html |
| life_soul.glb | Deer | Quaternius / Ultimate Animated Animal Pack | CC0 1.0 | 同上 |
| frost_soul.glb | Stag | Quaternius / Ultimate Animated Animal Pack | CC0 1.0 | 同上 |
| warrior_soul.glb | Skeleton | Quaternius / Animated Monster Pack | CC0 1.0 | https://quaternius.com/packs/animatedmonster.html |
| wind_soul.glb | Bat | Quaternius / Animated Monster Pack | CC0 1.0 | 同上 |
| wraith.glb | Ghost | Quaternius / Ultimate Monsters | CC0 1.0 | https://quaternius.com/packs/ultimatemonsters.html |
| fire_soul.glb | Demon | Quaternius / Ultimate Monsters | CC0 1.0 | 同上 |
| iron_beast.glb | Orc | Quaternius / Ultimate Monsters | CC0 1.0 | 同上 |

## 酆都建筑与环境

| 项目文件 | 原始资产 | 作者 / 资源包 | 许可 | 原始来源 |
|---|---|---|---|---|
| fengdu_wall.glb | Wall | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 |
| fengdu_watchtower.glb | Tower | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_hall.glb | Hall | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_house.glb | House | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_tree.glb | Tree | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_rock.glb | Rock | Kay Lousberg / KayKit Medieval Hexagon 1.0 | CC0 1.0 | 同上 |
| fengdu_lantern.glb | Lamp01 | Polygonal Mind / Lunar Year | CC0 1.0 | https://github.com/ToxSam/cc0-models-Polygonal-Mind/tree/main/projects/lunar-year |
| fengdu_bell.glb | Bell | Polygonal Mind / Lunar Year | CC0 1.0 | 同上 |
| fengdu_east_asian_roof.glb | RoomRoof | Polygonal Mind / Lunar Year | CC0 1.0 | 同上 |
| fengdu_east_asian_wall.glb | RoomWall01 | Polygonal Mind / Lunar Year | CC0 1.0 | 同上 |
| fengdu_column_base.glb | ColumnBase | Polygonal Mind / Lunar Year | CC0 1.0 | 同上 |

## 许可证与来源核验

- KayKit Adventurers 与 Medieval Hexagon 包的仓库 README 和随包 LICENSE 标注 CC0 1.0。
- Quaternius 每个资源包的官方页面分别标注 CC0；具体模型与资源包的映射同时记录在 `licenses/PROVENANCE-Quaternius-Animals.md` 和 `licenses/PROVENANCE-Quaternius-Monsters.md`。公开镜像只作为 GLB 文件获取来源，不是模型作者；镜像仓库 MIT 许可不用于替代模型本身的 CC0 许可。
- Polygonal Mind 的 Lunar Year 资源集合在公开资产登记中标注 CC0；本仓库保存其 CC0 1.0 法律文本副本 `licenses/LICENSE-PolygonalMind-CC0.txt`。
- KayKit 随包许可副本保存在 `licenses/` 目录。
- 本批模型均未进行网格重拓扑、骨骼重定向或动画编辑；游戏只在运行时归一化尺寸和摆放位置。所有碰撞体仍由《洪荒》游戏代码独立生成。

## 验收状态

以上模型均为 `imported_unverified`。在用户本机 Godot 4.6 导入后，还需检查脚底、朝向、比例、材质、骨骼、动画片段、阴影和性能。未完成实际场景镜头验收前，不标记为 `accepted`。
