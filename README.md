# 洪荒：诸天轮回

一款以洪荒神话、诸天世界与灵魂轮回为核心的 3D 开放世界 MMORPG。项目采用 Godot 4.x 客户端、Go 业务后端、C++ 实时世界服务器，面向 Windows PC 首发。

## 当前阶段

**P0：工程基础与多人联网垂直切片。** 当前优先验证账号登录、灵魂档案、世界入口、多人连接、玩家位置同步与断线恢复。美术资源先使用占位资产，联网闭环稳定后再投入高品质场景与角色资产。

## 技术栈

- Client: Godot 4.x, GDScript; performance-critical extensions via C++/GDExtension when needed
- Backend: Go modular monolith, HTTPS/JSON
- Realtime: standalone C++20 world server, ENet over UDP
- Database: PostgreSQL
- Cache: Redis
- Messaging: NATS
- Admin: Vue 3 + TypeScript
- Deployment: Linux + Docker Compose
- Protocol: versioned, language-neutral message schemas shared by client and server

## Repository layout

```text
Client/HongHuangClient/   Godot client
Backend/                  Go account and world business APIs
GameServer/WorldServer/   C++ authoritative realtime server
Protocol/                 Shared network/API protocol definitions
Database/                 PostgreSQL migrations and seed data
Admin/WebDashboard/       Operations dashboard
Deployment/               Docker, configs and local scripts
Tests/                    Integration and acceptance tests
Docs/                     Architecture and development documents
```

## Development principles

1. The server is authoritative for movement validation, combat, attributes, inventory, drops and reincarnation outcomes.
2. The client sends input/intent, never trusted final state.
3. Account, soul and each lifetime's body/character are separate domain entities. Reincarnation creates a new character record; it does not overwrite previous lives.
4. World design data is separate from physical server nodes. A world may span multiple nodes; a node may host multiple instances.
5. Start with a modular Go backend; split services only when scale and operational needs justify it.
6. Do not assume Godot MultiplayerAPI RPC packets are wire-compatible with the standalone C++ server. Define and test an explicit shared protocol.
7. Keep dependencies and toolchain versions pinned. Avoid unreviewed automatic upgrades.

## P0 acceptance

- [ ] Go backend, C++ world server and Godot client build independently.
- [ ] PostgreSQL, Redis and NATS start and are reachable.
- [ ] Register, login and logout work.
- [ ] A soul can be created and loaded after restart.
- [ ] A soul can create its first-life character.
- [ ] Center service returns a world-server endpoint and short-lived one-time ticket.
- [ ] At least two clients enter the same test world and see each other's movement.
- [ ] Disconnect/reconnect restores the latest valid character snapshot.
- [ ] Server rejects client-submitted final positions, item counts and combat outcomes.
- [ ] Local start/stop scripts and readable logs are provided.

## Project status

This repository is being initialized. See `Docs/Development/ROADMAP.md` for staged delivery and `Docs/Architecture/OVERVIEW.md` for the initial architecture.

## 树莓派 ARM64 部署

- 一键部署脚本：Deployment/deploy-raspberry-pi.sh
- 详细部署说明：[Docs/Deployment/RASPBERRY_PI.md](Docs/Deployment/RASPBERRY_PI.md)
- 当前支持 64 位 Raspberry Pi OS / Debian（aarch64），用于 P0 局域网联网测试。

## 客户端美术预览

Godot 客户端提供独立美术预览场景：`Client/HongHuangClient/scenes/ArtPreviewStage.tscn`。可在 Godot 编辑器中打开运行，检查玩家/怪物占位模型、酆都鬼门关以及模块化街区组合。

- `1–5`：选择玩家、荒原狼、铁骨兽魂、炽战残魂、游祟。
- `I / W / R`：待机、行走、奔跑（循环预览）。
- `A / H / D`：攻击、受击、死亡（单次动作）。
- `Esc`：返回待机。
- 酆都街区预览包含城墙直段、城防角楼、阴司衙门、鬼市摊位、铺地和引魂灯。

注意：当前街区与角色仍包含程序化原型；尚未代表已导入第三方 GLB 模型。正式地图仍需按区域拆分和流式加载，街区预览不直接等同于完整酆都世界。

另有独立酆都内城总览场景：`Client/HongHuangClient/scenes/FengduCityLayoutPreview.tscn`，用于检查城墙、南门、轮回大道、中央广场、阴司官署区、六道轮回区、鬼市坊区与居民坊区的空间关系。它仍是美术/关卡灰盒，不是正式联机地图。

冥界宏观区域关系预览：`Client/HongHuangClient/scenes/UnderworldRegionOverview.tscn`。该场景将酆都、忘川、远处血海（冥河老祖道场）和独立十八层地狱入口放在同一张规划总览中，仅供地理关系与路线评审，不是正式联机地图或服务器分区配置。
