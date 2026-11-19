# 洪荒 · 万界传音（玩家聊天系统）

## 1. 产品规则（已确认）

- 跨界频道：全服所有世界共用一个频道，不按 world_id 或世界实例隔离。
- 私聊权限：陌生人可以先发送私聊申请；接收者可以关闭陌生人申请。好友之间可直接私聊。黑名单优先级最高，双向屏蔽均阻止私聊。
- 聊天记录：普通聊天消息保存 30 天；超过 30 天的消息由服务端清理。私聊记录同样遵守 30 天策略。
- 普通文本上限：200 个 Unicode 字符；客户端不得决定发送者身份、世界归属、境界或宗门信息。
- 账号、灵魂、肉身角色分离。聊天身份以当前存活肉身角色为准；好友关系是否跨轮回保留，按角色好友关系实现，不自动把旧肉身的身份冒充为新角色。

## 2. 频道定义

| 频道 | 可见范围 | 发送与路由规则 |
|---|---|---|
| 附近 | 当前世界实例的附近玩家 | WorldServer 根据服务端权威坐标和 AOI 范围过滤 |
| 世界 | 当前 world_id 下所有玩家 | 同一世界不同实例也应可达；由中心服按 world_id 路由 |
| 跨界 | 全服所有世界 | 所有世界共用一个全局 scope，不附加 world_id 过滤 |
| 队伍 | 当前队伍成员 | 必须属于同一有效队伍 |
| 宗门 | 当前宗门成员 | 必须属于同一宗门，管理权限由服务端验证 |
| 私聊 | 指定角色与对端角色 | 好友直接发送；陌生人先申请并经接收者接受 |
| 系统 | 指定玩家或全服 | 仅服务端可写入 |
| 喇叭 | 全服 | 仅服务端验证消耗传音道具后写入 |

频道分阶段开放。未实现的频道必须返回明确的 unsupported 状态，不得静默丢消息。

## 3. 客户端交互

- 游戏 HUD 左下角提供可收起聊天框，默认仅展示最近数条消息。
- 展开后显示频道标签、滚动历史、输入框和发送状态。
- Enter 聚焦输入框/发送；Esc 关闭输入框或收起窗口；Tab 在可用频道间切换。
- 点击玩家名可打开操作菜单：私聊、申请好友、查看资料、举报、屏蔽。
- 私聊申请、好友请求、系统消息和未读数在独立社交面板显示。
- 消息显示服务端返回的角色名、种族、世界、境界、宗门与称号；缺失字段应优雅隐藏。
- UI 必须避让移动/战斗操作，不得遮挡主要视野；窗口尺寸适配 16:9 与宽屏。

## 4. 私聊与社交规则

1. 发送者提交目标角色 ID 和申请文本，不能直接创建私聊会话。
2. 服务端检查双方当前角色、陌生人申请开关、黑名单、频率限制和待处理申请唯一性。
3. 接收者可接受、拒绝或拉黑；接受后创建/启用私聊会话。
4. 好友可直接发起私聊；好友关系不绕过黑名单。
5. 关闭陌生人申请只拒绝新的陌生人申请，不影响已有好友或已建立会话。
6. 离线消息进入持久化收件箱；上线后按创建时间投递，客户端回执后标记已读/已送达。
7. 好友请求与私聊申请分开管理，避免把“加好友”误当作“允许私聊”。

## 5. 技术架构

- Godot：聊天窗口、输入、历史展示、未读状态；不持有任何服务端密钥。游戏 ENet 与聊天连接独立。
- 独立 Go ChatServer：身份认证、权限判断、持久化、跨世界频道路由、好友/黑名单/申请、限流、保留期清理；默认监听 8788。
- Go Game API：账号、角色和世界等游戏业务；聊天路由仅在迁移期保留兼容，不应成为游戏实时操作的依赖。
- C++ WorldServer：权威游戏模拟和附近频道 AOI 数据源；不得在游戏主循环中同步等待 ChatServer、NATS 或聊天数据库。
- PostgreSQL：消息、会话、好友、申请、黑名单、偏好和回执持久化；当前迁移期与游戏数据共用数据库，但 ChatServer 使用独立进程和连接池。
- Redis：在线状态、角色到节点/会话路由缓存、短期限流计数。
- NATS：跨服务事件总线；不可用不得阻塞游戏 tick，消息分发后续采用消息 ID 幂等消费和失败重试。

消息链路：客户端通过独立聊天连接访问 ChatServer；WorldServer 只提供权威 AOI/在线世界事件，并通过有界异步通道参与附近频道路由。ChatServer 负责权限与限流校验、持久化和路由接收者。跨界频道必须通过中心化路由扇出，不能让每台 WorldServer 各自维护互不相通的“跨界频道”。

## 6. 数据模型

现有迁移 000038 已创建 chat_preferences、chat_friendships、chat_private_requests、chat_blocks、chat_messages。后续按兼容迁移逐步补齐：

- chat_conversations：私聊会话及参与者。
- chat_message_receipts：送达/已读回执。
- chat_friend_requests：独立好友申请状态。
- chat_mutes：角色/账号禁言、到期时间、原因和操作人。
- chat_reports：举报内容、举报人、被举报人、处理状态。
- chat_messages：补充稳定的 scope/conversation 索引、消息类型、服务端来源和必要的审计字段。

消息表的 channel_type 采用 nearby/world/cross_world/party/sect/whisper/system/shout。跨界消息的 scope 固定为全服常量，不使用 world_id；世界频道必须绑定 world_id；附近频道必须绑定 world_instance_id；私聊必须绑定 conversation_id/recipient。所有消息均由服务端生成 created_at 与 sender 身份。

## 7. 安全与反滥用

- 世界频道建议 3 秒 1 条；跨界频道 5 秒 1 条；私聊建议 1 秒 1 条；申请类操作单独限流。
- 30 秒内重复发送相同内容应限频；限制单条内容 200 字、拒绝控制字符和恶意链接。
- 限流按角色和账号双维度执行，不能只依赖客户端计时。
- 屏蔽只影响屏蔽关系双方的私聊/申请，不得让任意玩家通过屏蔽操作压制第三方的公开频道发言。
- 禁言、封禁、敏感词过滤和举报均由服务端执行并留审计记录。
- message_id 与 client_message_id 用于幂等，重试不得重复投递或重复入库；同一 client_message_id 必须对应相同频道和正文，复用 ID 但更改内容返回 409 冲突。
- 30 天保留策略必须有可运维的清理任务；发送/查询请求不应每次都全表清理。

## 8. 分阶段实施与验收

### P0-A：激活现有聊天后端
- 在独立 ChatServer 注册 POST/GET /api/v1/chat/messages 路由（迁移期 Game API 保留兼容路由）。
- 保留 world 与 cross_world 两类持久化消息；跨界历史全服共享。
- 修正屏蔽逻辑：屏蔽不能导致被屏蔽者无法在公开世界频道发言。
- 验收：Bearer Token 认证、200 字校验、3/5 秒限流、幂等写入、历史分页。

### P0-B：实时传输与附近/世界/跨界频道
- P0-B1（已提交，待运行验证）：为 ENet 协议分配聊天消息类型；Godot 网络层支持发送/接收；WorldServer 负责计算当前实例附近频道 AOI，服务端身份由 ChatServer 根据活动会话注入，ChatServer 执行 200 字校验与 1 秒限流。
- P0-B2（进行中）：已增加受 `X-World-Server-Key` 与 `X-World-Server-Node` 保护的 `GET /api/v1/servers/chat/messages` 拉取接口，以及 `POST /api/v1/servers/chat/messages` 发布接口；现已同时挂载到独立 ChatServer，Game API 暂保留兼容入口。发布时必须验证 world_sessions + server_registry + character 三者关系、节点心跳、会话归属与状态；发送者名称/境界/世界由数据库注入，客户端不能伪造。客户端消息 ID 重试返回原消息，限流在幂等检查之后执行。拉取按节点当前 ready 的 world_instances 返回其 world 消息，以及全服统一 cross_world 消息；按 `(created_at,id)` 稳定游标分页。WorldServer 已将附近消息通过独立后台 worker 异步 POST 到 ChatServer；ChatServer 验证节点和会话归属；考虑到 WorldServer 的异步发件箱可能在玩家断线后才投递，允许同节点最近 30 天内处于 saving 或 closed 的会话完成原消息投递。AOI 接收者快照必须属于该实例的活动或最近 30 天内关闭的会话，再持久化并经 JetStream 扇出。世界/跨界消息仍由玩家独立 WebSocket 连接发送；WorldServer 的世界/跨界定时拉取链路暂不承担客户端广播。
- 验收：B1 需两客户端同实例附近可见，超出 AOI 不可见，伪造 sender 字段无效，限流和长度校验生效；B2 需不同实例同世界可见世界频道、不同世界可见同一跨界频道。

### P0-C：Godot 聊天 HUD
- P0-C1（已提交，待运行验证）：增加左下方可折叠聊天窗、附近/世界/跨界频道切换、输入发送和服务端错误提示；附近仍走 ENet，世界/跨界走独立 ChatServer WebSocket。
- P0-C2（进行中）：ChatServer 新增 Bearer Token 认证的 WebSocket `/api/v1/chat/socket`；Godot 新增独立 `HHChatNetwork`，具备独立 20 秒心跳、Pong 超时检测和 4 秒重连。世界/跨界频道通过该连接发送与接收；附近消息由 ENet 发送给 WorldServer，WorldServer 通过最多 256 条的有界内存入口队列，将消息异步写入现有 SQLite WAL/FULL 持久发件箱；收到 ENet accepted 回执前必须先完成本地持久化。独立 Chat Outbox worker 负责 HTTP 投递、指数退避和重启恢复，游戏奖励/掉落 worker 明确排除 nearby_chat 类型，聊天故障不会占用游戏事件投递线程。SQLite 聊天事件配额最多占总容量一半且不超过 2000 条，为奖励/掉落保留空间；客户端在收到持久化回执前使用相同 client_message_id 退避重发。ChatServer 最终再由独立 WebSocket 按 AOI 接收者集合投递。WebSocket 连接成功后自动补拉附近/世界/跨界频道最近 50 条历史，按消息 ID 去重并按 created_at 插入排序；断线重连会再次补拉，过期连接的历史响应会丢弃。已建立 PostgreSQL 事务 Outbox（迁移 `000039_chat_transactional_outbox`）：玩家 HTTP/WS 与 WorldServer 发布入口均在同一数据库事务中写入 `chat_messages` 和 `chat_event_outbox`，事件 payload 保存当时的角色展示快照。后台 publisher 使用 `FOR UPDATE SKIP LOCKED` + 有效期租约领取待发事件，JetStream 返回 PubAck 后才标记 published；失败释放租约并指数退避重试，进程崩溃后租约过期可重新领取。NATS 不可用时 Outbox 保留待发事件，恢复 JetStream 后继续发送。JetStream 消息 ID 使用 chat message UUID，在 2 分钟去重窗口内抑制 PubAck 成功但数据库标记前崩溃造成的重复发布；超过去重窗口仍按至少一次投递处理，客户端继续按消息 ID 去重。每节点 durable pull consumer 仍负责离线 ChatServer 恢复；Outbox 与 JetStream 均保留 30 天。
- 验收：不遮挡基础移动与战斗操作，输入/发送/错误提示正常，重连后自动补拉最近 50 条世界/跨界历史，实时与历史消息按 ID 去重、按时间排序。

### P0-D5：附近聊天发件箱运维
- WorldServer 增加本机 `world_outbox_admin` 管理程序，不开放公网管理 API。支持 `stats` 查看队列状态/最老 pending 与 dead-letter 年龄，`dead-letters` 查询附近聊天死信，`retry <event_id>` 将指定 nearby_chat 死信重新排队。
- 管理程序以非恢复模式打开 SQLite，不会把正在投递的 inflight 事件重置为 pending；人工重试只允许修改 event_type=nearby_chat 的 dead-letter，不能触碰经验、掉落等游戏事件。
- Chat Outbox worker 每 60 秒输出独立指标：pending、inflight、dead_letter、最老 pending 年龄和最老死信年龄；存在死信或最老 pending 超过 60 秒时输出 WARN；永久 HTTP 4xx 仍进入死信并记录原因。
- 本机使用示例：
  ```sh
  ./world_outbox_admin stats
  ./world_outbox_admin dead-letters 50
  ./world_outbox_admin retry nearby-chat:SESSION_UUID:CLIENT_MESSAGE_UUID
  ```
  也可在命令前显式传入 SQLite 文件路径。默认读取 `WORLD_SERVER_OUTBOX_PATH`，未设置时使用 `./data/worldserver-outbox.sqlite3`。
- 验收：检查工具可在 WorldServer 运行期间安全读取状态；重试死信后由原 Chat Outbox worker 自动重新投递；管理工具不能重置 live inflight，也不能重试非 nearby_chat 事件。

### P0-E：附近聊天可靠性验收准备（已提交，待运行验证）
- 抽出可单元测试的 HTTP 错误分类策略：普通永久 4xx（如 401/403/409）进入 dead-letter；408/425/429、连接失败和 5xx 保持退避重试。
- 新增 `chat_delivery_policy_test`，覆盖永久错误与临时错误分类；新增本地 loopback 假 ChatServer `Deployment/scripts/chat-fake-server.py`，可切换 201/401/429/503 并按 client_message_id 返回稳定模拟消息 ID。
- 新增 `Docs/Testing/CHAT-RELIABILITY-TEST-PLAN.md`，覆盖服务不可用、恢复投递、WorldServer 重启恢复、401 死信人工重试、聊天队列配额与游戏事件隔离的本机验收步骤。
- 尚未执行 CMake/CTest、假服务联调或真实 ChatServer 验收；本阶段不触发 GitHub Actions。

### P1：好友、陌生人申请、私聊和离线投递
- 好友申请/接受/拒绝、陌生人私聊申请开关、黑名单、离线消息、未读与回执。
- 验收：陌生人关闭申请后不能建立新会话；好友可私聊；黑名单双方不能私聊；离线消息 30 天内可收取。

### P2：队伍/宗门频道、举报、禁言、完整历史
### P3：传音玉符、全服喇叭、招募/悬赏卡片
### P4：表情、聊天外观和扩展消息类型

## 9. 当前实现状态（2026-11-18）

- 已有：迁移 000038 的基础表；Go chat service 支持 world/cross_world 文本写入和历史查询。
- 本次新增：ENet ChatSendCommand/ChatEvent 协议；WorldServer 当前实例附近频道 AOI 转发、服务端身份注入、200 字校验和 1 秒限流；Godot 网络层发送/接收接口；协议帧测试覆盖聊天消息类型；Godot 初版附近聊天 HUD（可折叠、输入发送、错误提示）。
- 独立服务拆分第一步已提交：新增 Backend/cmd/chat 独立 Go 进程（默认 :8788）、httpapi.NewChatRouter（只注册聊天与健康检查路由）、CHAT_DATABASE_URL/CHAT_HTTP_ADDR 配置，以及 Windows/Linux 启动脚本。Godot 使用 `CHAT_API_BASE` 环境变量覆盖聊天服务地址；未设置时从游戏 API 的 `:8787` 推导 `:8788`。Game API 暂时保留原聊天路由作为迁移兼容入口。详见 Docs/Architecture/SERVICE-ISOLATION.md。
- P0-B2 本次新增：WorldServer 节点认证的中心消息拉取和发布 API。发布接口校验活动会话确属该节点，服务端注入消息身份并做附近 1 秒/世界 3 秒/跨界 5 秒限流与幂等；附近消息还验证 AOI 接收者属于同一活动实例。拉取接口按节点服务世界筛选 world 频道，cross_world 对所有 ready 节点可见，支持 1–100 条分页与 `(created_at,id)` 游标。WorldServer 附近发布已接入；WorldServer 世界/跨界定时拉取仍未接入（客户端直接使用 ChatServer WebSocket）。
- 附近频道已由 WorldServer 计算 AOI 接收者，通过有界异步 worker 提交 ChatServer；ChatServer 校验接收者属于同一活动世界实例后写入 PostgreSQL，并将接收者快照写入消息与事务 Outbox。ChatServer WebSocket 仅向同实例且在 AOI 列表中的角色投递，附近历史查询也按接收者和当前实例过滤。世界/跨界实时消息通过 ChatServer WebSocket 与 NATS JetStream 跨 ChatServer 进程广播；每个 ChatServer 使用独立 durable consumer，短暂离线后可从确认位置重放。
- 仍未实现：WorldServer 世界/跨界轮询接口（目前由玩家 WebSocket 直接收发，无需 WorldServer 中转）、跨世界实例的附近 AOI（当前定义为同一 world instance）、好友/私聊 API、离线私聊投递、队伍/宗门频道。
- 独立 ChatServer 已增加 30 天消息保留清理调度：启动后执行一次，之后每小时执行；清理不再发生在玩家发送/查询请求路径，避免请求触发全表删除。清理失败仅记录日志并等待下一轮重试。
- 聊天用户接口和 WorldServer 内部发布接口均强化幂等：相同 client_message_id + 相同频道/正文返回原消息；相同 ID 被用于不同频道或正文时返回 409，避免客户端错误重试覆盖/混淆消息。
- 当前仍未实现 NATS 故障期间在线客户端历史增量同步、WorldServer 本地 SQLite 与 ChatServer/JetStream 的自动故障注入验收、聊天数据物理数据库拆分。
- 本轮新增附近频道 SQLite 持久发件箱接入：复用 WorldServer 现有 WAL/FULL DurableOutbox，新增独立 nearby_chat claim worker；游戏事件 worker 排除聊天事件，聊天队列设置容量配额；客户端在持久化确认前使用相同 client_message_id 退避重发；服务端从已有 outbox 读取原始 AOI 快照以保证重试幂等；允许同节点最近 30 天处于 saving/closed 的会话完成延迟投递；新增重启恢复、类型隔离和容量配额测试。
- P0-D5 新增本机 outbox 管理程序，可查询队列指标/死信并人工重试 nearby_chat 死信；管理进程不会重置运行中 inflight 事件，且无法重试游戏事件。Chat Outbox worker 每 60 秒输出独立健康指标。新增本机 CLI 与 SQLite 管理逻辑测试。
- P0-E 新增 HTTP 错误分类单元测试、本地假 ChatServer 和端到端可靠性验收计划；尚未运行 C++ 编译/CTest、假服务联调、Go 测试、Godot 解析/运行、数据库迁移或 GitHub Actions。不要把静态代码提交视为运行验收通过。


## 9. 好友与私聊实现进度（2026-11-19）

### 已接入 Chat 独立数据库
- 迁移 `000004_friend_chat`：增加独立好友申请表 `chat_friend_requests`、好友私聊会话表 `chat_conversations`，并为消息增加 `conversation_id`。
- 好友关系仍由 Chat 数据库维护；接受好友申请时双向写入 `chat_friendships`，查询时兼容旧的单向关系。
- Chat API：角色名搜索、好友列表、收到的好友申请、发送申请、接受/拒绝申请、删除好友，以及允许/关闭陌生人好友申请设置。
- 搜索只返回存活角色；屏蔽关系双方不会出现在搜索结果中；好友申请由服务端检查当前角色、目标角色、隐私设置、重复申请和屏蔽关系。
- 好友私聊只允许已建立好友关系且双方未互相屏蔽的角色；会话由服务端按角色 ID 规范化创建，消息持久化在 Chat DB，30 天后清理。
- 私聊事件复用 Chat Outbox + NATS JetStream；WebSocket 只向发送者和接收者的当前角色连接投递，不广播到公开频道。
- Godot 好友面板支持角色名搜索、好友申请同意/拒绝、好友列表/在线状态、删除好友、陌生人好友申请开关和进入私聊；私聊历史通过独立接口补拉，消息走现有独立 Chat WebSocket。
- 好友关系按肉身角色 ID 绑定，不自动转移到轮回后的新角色；账号切换当前角色后，社交列表随当前角色变化。

### 当前验收边界
- 已提交代码与迁移，仍需在树莓派应用 Chat migration 000004，并由两个真实账号/角色完成好友申请、同意、在线状态和双向私聊验证。
- 好友在线状态目前通过 Chat Presence 租约与 Game 会话投影查询；跨 Chat 节点的实时好友状态推送仍是后续工作，不把定时查询误报为实时推送。
