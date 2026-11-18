# 服务隔离架构（游戏实时面与聊天通信面）

## 目标

游戏实时操作与聊天通信必须是两个独立故障域。聊天服务不可用时，已连接的玩家仍可移动、战斗、探索和执行其他由 WorldServer 权威处理的操作；游戏中心 API 或单个 WorldServer 不可用时，聊天服务仍可提供独立连接、历史消息和不依赖故障世界实例的频道。

这是一项架构约束，不只是代码目录拆分。

## 服务边界

### Game API（现有 Go 中心服）
- 默认监听 :8787（HTTP_ADDR）。
- 负责登录、账号、角色、轮回、世界入口、游戏数据和 WorldServer 管理接口。
- 不得同步调用 ChatServer 来完成移动、战斗或其他游戏操作。
- 已有聊天 HTTP 路由暂时保留为迁移兼容入口；新客户端和 WorldServer 应逐步切换到 ChatServer，完成切换后再移除旧入口。

### WorldServer（C++ / ENet UDP）
- 负责权威游戏模拟、移动、战斗、AOI 和实例内玩家连接。
- 游戏主循环不得等待 ChatServer、NATS 或聊天数据库。
- 附近频道需要 AOI 时，通过有界异步队列与 ChatServer/事件总线交换消息；任何聊天网络故障都不得阻塞游戏 tick。
- 不把聊天业务、聊天持久化和全服频道扇出放进 WorldServer 主循环。

### ChatServer（独立 Go 进程）
- 默认监听 :8788（CHAT_HTTP_ADDR），入口为 Backend/cmd/chat。
- 使用独立 HTTP server、独立生命周期、独立数据库连接池和健康检查。
- 只注册聊天用户 HTTP/WebSocket 接口与受 WorldServer 节点密钥保护的内部聊天接口；不注册登录、世界入口、角色修改、背包或游戏业务路由。
- 使用账号 session token 验证聊天用户；客户端不得持有 WorldServer API key。
- 使用 CHAT_DATABASE_URL，必须显式配置。开发阶段可指向现有 PostgreSQL 数据库，以读取账号 session、角色和世界会话数据；这只是迁移期共享存储，不代表运行时服务耦合。
- ChatServer 不得控制角色位置、生命、背包、战斗或其他游戏状态。

## 通信原则
1. 客户端维护独立游戏连接（ENet）和聊天连接（WebSocket）。聊天断线只重连聊天连接，不重新登录或重建游戏连接。当前 Godot 已接入独立 WebSocket 客户端；附近频道由 ENet 发往权威 WorldServer，WorldServer 异步提交 ChatServer，消息接收与历史走独立 WebSocket。
2. 游戏操作不依赖聊天请求成功；聊天服务超时、拒绝连接或宕机不能影响游戏操作。
3. WorldServer 与 ChatServer 的消息交互必须异步、有界、可丢弃/重试策略明确；不得在 ENet 主循环中执行同步 HTTP。
4. NATS 用于跨服务事件分发，不是游戏 tick 的前置依赖。ChatServer 使用 PostgreSQL 事务 Outbox + NATS JetStream：聊天消息与事件发件箱在同一事务提交，后台发布器通过 SKIP LOCKED 租约领取，收到 JetStream PubAck 后标记完成；失败或进程重启后可重试。每个 ChatServer 使用独立 durable pull consumer，广播后 AckSync。WorldServer 的附近聊天由独立有界后台 worker 异步提交 ChatServer；ENet 主循环只计算 AOI 接收角色并入队，不等待网络。队列最多 256 条、每条最多 5 次 HTTP 尝试；WorldServer 进程崩溃或队列满时可能丢弃未提交消息，后续增加本地 SQLite 持久重试队列。ChatServer 验证节点、会话和同一 world instance 的 AOI 接收者，再持久化并只向该接收集合广播。NATS 不可用时，游戏核心操作继续，ChatServer Outbox 累积已入库待发事件；WorldServer 网络队列会重试有限次数，队列耗尽时仅聊天发送失败，不影响游戏操作。
5. 账号身份可共享验证，但服务令牌和服务端密钥不得下发客户端。
6. 共享 PostgreSQL 只作为迁移期选择。服务使用独立连接池、独立数据库角色/权限；未来按数据所有权拆分 chat 数据库。游戏和聊天不得依赖跨库强事务。

## 故障行为

| 故障 | 游戏实时操作 | 聊天 |
|---|---|---|
| ChatServer 进程退出 | 已连接 WorldServer 继续游戏；附近聊天后台 worker 有限重试，超过重试次数后仅该条聊天发送失败 | 客户端聊天连接自动重连；已提交消息可补拉，未提交消息不会伪称已送达 |
| 聊天数据库不可用 | WorldServer 游戏 tick 继续 | 持久化发送/历史暂不可用 |
| Game API 不可用 | 已连接 WorldServer 尽可能继续；新登录/角色管理受影响 | ChatServer 独立运行；已签发有效 token 可按策略继续验证 |
| 单个 WorldServer 退出 | 该实例游戏暂不可用，其他实例继续 | 全局频道和私聊继续；该实例附近成员状态标记过期 |
| NATS 不可用 | 游戏核心操作继续 | 本机聊天继续；PostgreSQL Outbox 持久累积待发事件，JetStream 恢复后后台发布器继续发送；离线 ChatServer 从 durable consumer 的 ack 位置重放 |

注意：若游戏和聊天仍共用同一物理 PostgreSQL，数据库主机整体故障仍可能同时影响两边的持久化和认证。要获得更强物理故障隔离，需要后续拆分数据库实例或至少独立数据库集群；WorldServer 的实时模拟仍应在短时数据库故障期间继续运行。

## 当前落地状态
- 已新增 Backend/cmd/chat 独立进程，默认监听 :8788。
- 已新增 httpapi.NewChatRouter，只暴露聊天和健康检查路由。
- 已新增 CHAT_DATABASE_URL / CHAT_HTTP_ADDR 配置与 Windows/Linux 启动脚本。客户端可通过 `CHAT_API_BASE` 单独指定 ChatServer 地址；默认将游戏 API `:8787` 推导为聊天服务 `:8788`。
- ChatServer 当前复用现有 chat service、账号 session 验证和节点内部接口；数据库仍是迁移期共享 PostgreSQL。
- 30 天消息保留由 ChatServer 后台调度器负责：启动时执行一次，之后每小时执行；发送和历史查询请求不再触发过期消息删除，清理失败记录日志并在下一周期重试。
- Game API 暂时保留原聊天路由，作为客户端/WorldServer 切换期间的兼容入口。
- Godot 已建立独立 WebSocket 聊天连接：Bearer Token 握手、20 秒心跳、Pong 超时检测和断线自动重连；世界/跨界频道使用独立连接，附近频道由 ENet 上行、WebSocket 下行。每次连接/重连成功后自动拉取附近/世界/跨界最近 50 条历史，按消息 ID 去重并按时间+ID排序；过期连接的历史响应会被丢弃。ChatServer 已通过 JetStream 跨进程广播世界/跨界消息；配置优先使用 `CHAT_NATS_URL`，未设置时回退到 `NATS_URL`。每个聊天节点必须连接同一启用 JetStream 的 NATS 集群，并配置稳定且唯一的 `CHAT_NODE_ID`；本地单机开发可使用 `nats://localhost:4222`。每节点 durable consumer 会在重启后从上次确认位置继续消费；附近消息按实例与 AOI 接收者快照过滤，WebSocket 心跳会刷新当前角色的世界实例绑定。
- PostgreSQL 事务 Outbox 与 JetStream 持久流/每节点 durable consumer 已提交；NATS 故障期间在线客户端历史增量同步、在线状态订阅、聊天数据库物理拆分、完整历史分页/离线投递和故障注入测试尚未实现。
- 本轮增加 JetStream 持久流、每节点独立 durable pull consumer、消费确认/重投递、后台异步发布和消息 ID 去重；没有运行 Go 测试、构建、迁移、Godot 解析/运行或 GitHub Actions；所有新增代码仍待本地验证。