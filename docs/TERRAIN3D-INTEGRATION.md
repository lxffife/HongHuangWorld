# Terrain3D 接入记录与版本门禁

更新：2026-11-20

## 当前结论

**暂不把 Terrain3D 二进制放入正式客户端。** 先完成版本核对和独立样板场景，再决定正式接入。原因是 Terrain3D 是 C++ GDExtension，必须匹配 Godot 版本、操作系统、CPU 架构和渲染器。

## 仓库版本现状（核对后）

- project.godot 声明项目特性版本为 Godot 4.6。
- NativeNet/CMakeLists.txt 仍固定拉取 godot-cpp 4.3-stable，扩展描述文件最低兼容版本为 4.3。
- 因此项目引擎与原生扩展构建链尚未统一；必须先升级并验证 NativeNet，再决定 Terrain3D 二进制版本。不要只升级 Terrain3D。

## 官方版本兼容矩阵

| Godot 引擎 | Terrain3D 候选 | 决策 |
|---|---|---|
| 4.3 | 1.0.0-stable | 官方 1.0.0 发布说明列出 4.3/4.4；需使用对应 4.3 二进制 |
| 4.4 | 1.0.2-stable 或 1.1.0-stable | 两者官方范围均覆盖 4.4；优先在隔离场景验证 1.1.0 |
| 4.5–4.8 | 1.1.0-stable | 官方声明支持 4.5–4.8 |
| 未确定 | 不安装 | 先统一 Godot 与 NativeNet 构建链 |

官方来源：
- [Terrain3D Releases](https://github.com/TokisanGames/Terrain3D/releases)
- [Terrain3D README](https://github.com/TokisanGames/Terrain3D)
- [Terrain3D 安装说明](https://terrain3d.readthedocs.io/en/stable/docs/installation.html)
- [Terrain3D 平台说明](https://terrain3d.readthedocs.io/en/stable/docs/platforms.html)

## 计划接入时机（当前开发路线）

Terrain3D 不会等到整张大地图全部完成才接入，也不会现在就把正式世界切换到插件。接入安排为“先隔离样板、后主世界替换”：

1. **当前阶段：** 先完成酆都城内安全区、NPC 位置审计、城外怪物生态分区，并明确服务端权威出生点规则。客户端已具备区域诊断，但真正的刷怪点和 NPC 数据修复仍需服务端同步。
2. **插件样板阶段：** 对齐 NativeNet 的 godot-cpp 版本到项目 Godot 4.6 构建链，完成 Windows/Linux 原生扩展编译后，立即建立独立 Terrain3D 样板场景。候选先验证官方 Terrain3D 1.1.0-stable 对应 Godot 4.6 的构建包。
3. **样板验收：** 验证导入、雕刻、heightmap、地形碰撞、高度查询、角色移动和导出运行；样板不替换正式世界。
4. **正式接入：** 样板通过后，先替换一块酆都城外地形，再扩展城外生态区和分块流送；酆都城内建筑、NPC、怪物坐标与网络协议保持原坐标契约。
5. **逐区迁移：** 最后才逐步扩展罗酆山、后土神域、十八层地狱地表入口和远方血海等独立地图。血海必须是远域，不通过把酆都当前 200 m 原型简单拉伸来伪造距离。

因此，Terrain3D 的实际接入时间点是：**NPC/怪物区域规则确定，并且 NativeNet 4.6 原生构建链验证通过后的下一阶段**。目前阻塞点是 NativeNet 仍使用 godot-cpp 4.3，而不是 Terrain3D 本身。

## 正式接入前的门禁

1. 确认开发机 Godot Editor 的精确版本（含补丁号）。
2. 确认 Windows/Linux 目标平台、CPU 架构和渲染器；当前项目使用 Forward+，需要在该渲染器验证。
3. 对齐 NativeNet 的 godot-cpp 版本并成功构建，不能只让 Terrain3D 单独匹配。
4. 下载官方 Release 中对应引擎与平台的 Terrain3D 包；不从第三方网盘取 GDExtension。
5. 在独立测试项目/分支验证编辑器加载、地形雕刻、heightmap、碰撞、高度查询、导出运行。
6. 验证通过后才将 addon、二进制、版本记录和许可证加入主客户端。
7. 在主世界中保留 PlaneMesh fallback，直到地形和角色移动回归验收完成。

## 未来地图数据和渲染器边界

- 世界坐标使用米制 X/Y/Z；X/Z 为地图平面坐标，Y 为地形高度。
- WorldMapProjection 只负责世界坐标与地图像素坐标转换，不依赖 Terrain3D。
- WorldRegionCatalog 只提供现有原型区域的客户端显示标签；这些矩形不是服务端权威边界。
- Region/POI 的正式边界、可进入条件和探索权限最终由服务端地图元数据决定。
- Terrain3D 负责地形网格、材质、编辑、LOD 和地形碰撞；它不负责世界分区、实体 AOI、寻路权限或区域规则。
- 小地图、大地图、导航和世界坐标拾取共用同一投影接口。Terrain3D 替换后不得修改这些坐标契约。

## 本轮地图架构改动

新增 `scripts/world_region_catalog.gd`，把原来写在 `world_scene.gd` 的区域显示名称判断独立出来。现有坐标判断顺序与范围保持一致，区域名仍是客户端展示提示，不作为服务端区域边界。

血海 `fengdu_blood_sea` 仍是规划区域，尚未分配正式世界坐标边界、地形资源或服务端进入规则。完成区域设计和服务端元数据前，不把它显示成已经开放的地图区域。


## 方案对比

完整工具链对比、户外/室内分工、酆都首张样板制作顺序和血海地形组合见 [WORLD-LEVEL-DESIGN-PIPELINE.md](WORLD-LEVEL-DESIGN-PIPELINE.md)。当前最终方向是 Terrain3D + Blender GLB + MultiMesh 的户外组合；GridMap 用于规则地宫；FuncGodot/TrenchBroom 只作为复杂室内/洞窟候选；CSG 只用于灰盒。ProtonScatter 先独立验证版本与导出，不直接加入主项目。
