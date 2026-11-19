# 网络协议约定

协议定义与传输实现分离。当前协议版本为 v1，网络整数使用大端序，禁止直接发送语言结构体内存布局。

## 传输与帧格式

- 业务 API：HTTPS + JSON。
- 实时游戏：UDP + ENet。
- ENet channel 0：可靠有序控制消息；后续将 channel 1 用于可丢弃的高频状态消息。
- 固定帧头共 12 字节：magic(4, ASCII `HHW1`)、version(2)、message_type(2)、payload_length(4)。
- payload 最大 64 KiB。接收端必须校验 magic、版本和长度。
- 所有整数均为网络字节序（big-endian）；ClientHello 字符串使用 uint16 长度前缀，随后是 UTF-8 字节。
- ServerWelcome 和 ServerReject 当前使用 UTF-8 JSON payload，后续协议版本升级时再迁移为紧凑二进制结构。

## 消息类型

| ID | 消息 | 方向 | 用途 |
|---:|---|---|---|
| 1 | ClientHello | C→S | 一次性票据与客户端构建版本 |
| 2 | ServerWelcome | S→C | 后端确认的角色与世界初始快照 |
| 3 | ServerReject | S→C | 握手失败原因 |
| 4 | Heartbeat | 双向 | 连接健康检查 |
| 5 | HeartbeatAck | 双向 | 心跳应答 |
| 10 | InputCommand | C→S | 输入序列号、移动/动作意图 |
| 11 | EntitySnapshot | S→C | 服务器权威实体状态 |
| 12 | PlayerJoined | S→C | AOI 实体进入 |
| 13 | PlayerLeft | S→C | AOI 实体离开 |
| 14 | AttackCommand | C→S | 请求攻击目标实体 |
| 15 | CombatEvent | S→C | 命中、伤害、击败或拒绝原因 |
| 16 | PickupCommand | C→S | 请求拾取指定地面掉落实体 |
| 17 | PickupEvent | S→C | 返回拾取结算状态与物品数量 |

## ClientHello v1 payload

1. ticket：uint16 长度 + UTF-8 字节，长度 1–128。
2. client_build：uint16 长度 + UTF-8 字节，长度 1–64。
3. 不允许尾随字节。

## ServerWelcome JSON payload

由 Go 后端兑换票据返回的快照直接转发，字段包括：
- character_id、world_id、instance_id
- name
- position_x、position_y、position_z、rotation_y

客户端不得自行指定或覆盖这些权威身份与初始位置字段。

## 安全规则

服务端验证票据、协议版本、消息大小、输入序列号、输入频率、移动速度、攻击目标、攻击距离、攻击间隔和状态转换。客户端发来的坐标仅作为输入意图或预测参考，不能直接成为权威状态。世界服务器 API Key 只能用于服务器到后端的 HTTPS 管理调用，绝不能下发给客户端；票据不得写入日志。

## 当前实现边界

- 已实现：C++ ENet UDP host、连接/断开事件、帧编码/解码、协议版本/长度校验、ClientHello 解析、通过 HTTPS 调用后端兑换一次性票据、ServerWelcome / ServerReject、认证后心跳。
- 已实现：服务端权威玩家水平移动与跳跃积分、输入序列号检查、输入频率限制、超时停止移动、20Hz 实体快照、兴趣范围内 AOI 玩家加入/离开与状态广播。
- 已实现：玩家定期位置快照、断线保存并关闭会话、重连时以新票据恢复角色最近保存的位置；服务端后台工作线程负责周期快照重试。
- 客户端移动消息只携带方向/跳跃意图，服务器自行积分位置；客户端不能提交权威坐标。
- 已实现：WorldServer 启动时创建基础怪物实体，20Hz 服务端 Tick 执行最近玩家索敌、追击与离巢返回；怪物随玩家 AOI 进入/离开 EntitySnapshot，Godot 客户端显示简易怪物占位体。
- 已实现：客户端左键攻击最近的可见怪物；服务端校验目标、存活状态、3.5 米攻击距离与 650ms 攻击间隔，使用统一伤害计算结算；怪物死亡后隐藏并在 12 秒后于出生点满血重生。当前玩家基础攻击值为临时配置值 20。
- 已实现：怪物击败后按等级计算经验与修为，WorldServer 通过带节点身份的服务端接口异步提交中心服持久化；每次击杀使用 UUID 事件 ID，并绑定产生击杀的世界会话；中心服按节点+事件 ID 防止重复发放，且允许该会话关闭后 10 分钟内完成异步补交。中心服已建立物品目录、怪物掉落配置、地面掉落记录、角色背包和幂等拾取结算 API。WorldServer 启动时从中心服读取掉落表；怪物被击败后服务端按配置概率抽取物品，异步持久化地面掉落，只有归属角色在 AOI 内可见。PickupCommand 由服务端校验归属、会话、3 米距离和拾取频率，异步调用中心服事务结算，并通过 PickupEvent 返回结果。Godot 客户端显示掉落球体，按 E 请求拾取，并提供背包窗口读取持久化物品。地面掉落持久化在中心服数据库，WorldServer 启动时按节点恢复未过期掉落，允许同一角色在同一节点重新进入后拾取此前会话产生的掉落；等级成长阈值与升级奖励、NPC、任务事件也尚未实现。完成握手和玩家移动不代表这些玩法已可用。

## CombatEvent 权威字段

CombatEvent 使用 JSON payload，事件方向与字段由服务端确定：

- 玩家攻击怪物（返回给发起攻击的玩家）：`accepted`、`attacker_character_id`、`target_entity_id`、`target_name`、`damage`、`remaining_health`、`max_health`、`defeated`，以及击败奖励字段。
- 怪物攻击玩家（返回给受击玩家）：`accepted`、`source`（固定为 `monster`）、`source_entity_id`（怪物运行时实体 ID）、`damage`、`health`、`max_health`、`defeated`。
- 被拒绝的攻击：`accepted=false` 与 `reason`；不应触发命中、攻击或伤害表现。
- 客户端必须使用 `source_entity_id` 关联怪物攻击者，使用 `target_entity_id` 关联玩家攻击的怪物目标。不得使用近似字段名替代，也不得自行推断攻击来源。
- 以上字段均为表现层关联依据；伤害、生命、击败和奖励仍以 WorldServer 的权威结算为准。

## 世界入口票据流程

1. 客户端使用账号 Bearer Token 调用 `POST /api/v1/worlds/enter`。
2. 中心后端签发 60 秒有效的一次性随机票据，数据库只保存 SHA-256 摘要。
3. 客户端连接返回的 UDP 地址，在 ClientHello 携带票据与构建版本。
4. C++ 世界服务器使用自身 node_key 与服务器 API Key 调用 `POST /api/v1/servers/tickets/redeem`。
5. 兑换成功后，世界服务器发送 ServerWelcome。断线后必须重新申请票据，不得复用旧票据。

- 客户端通过 `AttackCommand` 提交目标实体 ID；服务端通过 `CombatEvent` 返回命中、伤害、击败或拒绝原因。攻击冷却/距离等正常拒绝不会关闭连接。
