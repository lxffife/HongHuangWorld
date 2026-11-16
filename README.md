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