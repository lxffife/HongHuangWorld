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

服务端验证票据、协议版本、消息大小、输入序列号、输入频率、移动速度和状态转换。客户端发来的坐标仅作为输入意图或预测参考，不能直接成为权威状态。世界服务器 API Key 只能用于服务器到后端的 HTTPS 管理调用，绝不能下发给客户端；票据不得写入日志。

## 当前实现边界

- 已实现：C++ ENet UDP host、连接/断开事件、帧编码/解码、协议版本/长度校验、ClientHello 解析、通过 HTTPS 调用后端兑换一次性票据、ServerWelcome / ServerReject、认证后心跳。
- 已实现：服务端权威玩家水平移动与跳跃积分、输入序列号检查、输入频率限制、超时停止移动、20Hz 实体快照、兴趣范围内 AOI 玩家加入/离开与状态广播。
- 已实现：玩家定期位置快照、断线保存并关闭会话、重连时以新票据恢复角色最近保存的位置；服务端后台工作线程负责周期快照重试。
- 客户端移动消息只携带方向/跳跃意图，服务器自行积分位置；客户端不能提交权威坐标。
- 尚未实现：怪物/NPC 实体仿真、战斗指令与伤害结算、掉落/拾取、任务事件。完成握手和玩家移动不代表这些玩法已可用。

## 世界入口票据流程

1. 客户端使用账号 Bearer Token 调用 `POST /api/v1/worlds/enter`。
2. 中心后端签发 60 秒有效的一次性随机票据，数据库只保存 SHA-256 摘要。
3. 客户端连接返回的 UDP 地址，在 ClientHello 携带票据与构建版本。
4. C++ 世界服务器使用自身 node_key 与服务器 API Key 调用 `POST /api/v1/servers/tickets/redeem`。
5. 兑换成功后，世界服务器发送 ServerWelcome。断线后必须重新申请票据，不得复用旧票据。
