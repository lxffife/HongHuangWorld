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
4. 客户端使用返回的 host、udp_port 和 ticket 连接指定 WorldServer。
5. WorldServer 验证并兑换票据，成功加入后把入层事件写入 SQLite durable outbox。
6. Outbox 后台线程重试 `POST /api/v1/servers/hell-trials/entries`，中心服再核对当前活动会话、节点身份和实际实例楼层。

普通 `POST /api/v1/worlds/enter` 只选择 `hell_floor IS NULL` 的常规世界实例，不会把玩家随机送入地狱某一层。

## 迁移与运维

- 先执行数据库迁移 `000072_hell_trial_progress`，它为 `world_instances` 添加 `hell_floor`。
- 所有 WorldServer 节点使用相同的 `WORLD_SERVER_API_KEY`，节点身份必须唯一。
- 每个楼层的 `WORLD_SERVER_INSTANCE_KEY` 必须唯一且稳定；改变楼层号时应同步更换实例键，避免把已有实例身份改绑到另一层。
- 先启动中心服，再启动各 WorldServer；检查心跳成功后确认对应实例的 `hell_floor` 正确。
- 本地 SQLite outbox 文件必须持久化保存，不能放在会被容器重建清空的临时目录。

## 当前边界

本阶段已接通楼层实例注册、按层签发票据、普通入口隔离、玩家加入后可靠记录入层。每层的怪物波次/关卡目标、守将配置、击杀确认、完成回调和 Godot 场景仍需后续开发；不要通过客户端参数直接提交通关结果。
