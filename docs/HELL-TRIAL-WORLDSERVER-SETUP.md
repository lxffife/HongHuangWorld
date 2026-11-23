# 十八层地狱专属 WorldServer 配置

十八层地狱采用“每层一个专属 WorldServer 实例”的第一阶段部署方式。普通酆都实例不承担地狱楼层副本，地狱实例通过心跳把楼层号注册到 `world_instances.hell_floor`。

## 环境变量

每个楼层实例均需配置：

```bash
WORLD_ID=underworld_fengdu
WORLD_SERVER_HELL_FLOOR=1
WORLD_SERVER_INSTANCE_KEY=underworld-hell-floor-01
WORLD_SERVER_NODE_KEY=world-hell-floor-01
WORLD_SERVER_UDP_PORT=7781
WORLD_SERVER_ADVERTISE_HOST=你的可访问地址
BACKEND_URL=http://127.0.0.1:8787
WORLD_SERVER_API_KEY=与中心服一致的密钥
```

第二层到第十八层分别将 `WORLD_SERVER_HELL_FLOOR` 设置为 2..18，并使用各自唯一的 `WORLD_SERVER_NODE_KEY`、`WORLD_SERVER_INSTANCE_KEY` 和 UDP 端口。不要在同一节点身份上同时启动多个不同楼层的进程。

普通酆都世界服务器必须设置：

```bash
WORLD_ID=underworld_fengdu
WORLD_SERVER_HELL_FLOOR=0
```

其他世界也使用 0。有效值为 0 或 1..18；非酆都世界不能设置非零地狱层号。

## 玩家进入流程

1. 客户端先请求 `GET /api/v1/characters/current/hell-trials` 获取服务端权威进度。
2. 客户端请求 `POST /api/v1/worlds/hell-trials/{floor}/enter`，携带账号 Bearer 令牌。
3. 中心服校验角色当前肉身、楼层解锁状态、楼层实例在线状态与容量，签发 60 秒有效的一次性票据。
4. 中心服兑换票据时读取 `world_instances.hell_floor`；地狱层出生点强制设为 `(0, 0.15, 18)`，不会沿用酆都城内的旧坐标。
5. 客户端使用返回的 host、udp_port 和 ticket 连接指定 WorldServer；ServerWelcome 返回 `hell_floor`，Godot 根据楼层加载程序化灰盒场景。
6. WorldServer 验证并兑换票据，成功加入后把入层事件写入 SQLite durable outbox。
7. Outbox 后台线程重试 `POST /api/v1/servers/hell-trials/entries`，中心服再核对原始 session ID、节点身份和实际实例楼层。即使回调在角色断线后才送达，也会绑定到原始 `world_sessions` 记录，而不是要求玩家仍在线。

普通 `POST /api/v1/worlds/enter` 只选择 `hell_floor IS NULL` 的常规世界实例，不会把玩家随机送入地狱某一层。

## 迁移与运维

- 先执行数据库迁移 `000072_hell_trial_progress`，它为 `world_instances` 添加 `hell_floor`。
- 所有 WorldServer 节点使用相同的 `WORLD_SERVER_API_KEY`，节点身份必须唯一。
- 每个楼层的 `WORLD_SERVER_INSTANCE_KEY` 必须唯一且稳定；改变楼层号时应同步更换实例键，避免把已有实例身份改绑到另一层。
- 先启动中心服，再启动各 WorldServer；检查心跳成功后确认对应实例的 `hell_floor` 正确。
- 本地 SQLite outbox 文件必须持久化保存，不能放在会被容器重建清空的临时目录。

## 关卡遭遇配置

WorldServer 当前内置 18 份静态遭遇定义，位置在 `GameServer/WorldServer/src/hell_trial_encounter.cpp`。每个专属实例启动时只生成配置楼层的 3 个目标怪物和 1 个守将：

- 3 个目标怪物使用不同且固定的 definition ID；每个稳定 spawn runtime ID 在本轮遭遇中只计数一次。
- 守将使用该层唯一的 guardian definition ID。
- 地狱实例使用独立的服务端移动边界，玩家 X/Z 坐标被限制在 `[-27, 27]`，不会走出 58 米见方的试炼灰盒场地。
- 目标数达到 3 且守将被服务器确认死亡，才产生通关事件；先杀守将或先完成目标都不会提前通关。
- 每层推荐等级、名称、目标怪物 ID、守将 ID 在 C++ 遭遇目录中定义；中心服也维护对应的守将 ID 白名单。
- 入层和通关回调都携带创建事件时的 `session_id`；中心服校验该 session 由当前 WorldServer 节点创建，并允许对 `closed` 会话补交事件，避免网络重试期间玩家断线导致进度永久丢失。
- 怪物配置热刷新会保留专属地狱遭遇点，避免后端常规刷怪配置覆盖本地楼层怪物。

完整目录见 `docs/HELL-TRIAL-ENCOUNTER-CATALOG.md`。

## 当前边界

本阶段已接通楼层实例注册、按层签发票据、普通入口隔离、玩家加入后可靠记录入层，以及“3 个目标怪物 + 本层守将”的服务端权威通关事件。通关事件经 SQLite durable outbox 重试投递，中心服核对目标快照、楼层和守将身份。

Godot 已有十八层入口面板、服务端票据连接、地狱内进度查看/返回酆都，以及每层程序化灰盒场景；危险标记目前仅为视觉占位。当前遭遇计数仍保存在 WorldServer 进程内；服务重启会重置尚未完成的遭遇轮次。多波次刷怪、动态难度、队伍贡献资格、失败/重置流程、独立地图机关、Boss 多阶段技能和各层精细美术场景仍需后续开发。不要通过客户端参数直接提交通关结果。


## 十八层地狱波次检查点

- 每个地狱 WorldServer 的 `WORLD_SERVER_INSTANCE_KEY` 必须在进程重启后保持不变；波次检查点以 instance key 与楼层号作为唯一键。
- 检查点保存在 `WORLD_SERVER_OUTBOX_PATH` 指向的本地 SQLite 数据库中，与现有 durable outbox 使用同一文件；请确保该目录位于持久化磁盘，不要使用容器临时目录。
- 每次完成一个目标波次后，WorldServer 先持久化阶段，再激活下一波。最终守将阶段只有在所有合格玩家的通关事件批量写入 SQLite 成功后才会标记完成。
- 玩家伤害/治疗贡献账本尚未持久化；重启会恢复当前波次与目标击杀数，但未结算的个人贡献需要重新累计。
