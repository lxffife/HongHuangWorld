# Terrain3D 接入记录与版本门禁

更新：2026-11-20

## 当前结论

**暂不把 Terrain3D 二进制放入正式客户端。** 先完成版本核对和独立样板场景，再决定正式接入。原因是 Terrain3D 是 C++ GDExtension，必须匹配 Godot 版本、操作系统、CPU 架构和渲染器。

## 仓库版本现状（核对后）

- `Client/HongHuangClient/README.md` 当前仍写 Godot 4.3。
- `Client/NativeNet/README.md` 写明 NativeNet 使用 Godot 4.3 的 godot-cpp；原生扩展也必须与最终客户端引擎版本保持兼容。
- `Client/HongHuangClient/project.godot` 当前没有 `config/features` 引擎版本声明。
- 因此仓库本身尚不能证明正式开发环境已经统一为 4.3 或 4.6。不要只凭项目配置缺失的版本号推断已升级，也不要单独升级 Terrain3D。

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
