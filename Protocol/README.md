# 网络协议约定

协议定义与传输实现分离。当前协议版本为 v1，网络整数使用大端序，禁止直接发送语言结构体内存布局。

## 传输与帧格式

- 业务 API：HTTPS + JSON。
- 实时游戏：UDP + ENet。
- ENet channel 0：可靠有序的控制消息；后续将 channel 1 用于可丢弃的高频状态消息。
- 固定帧头共 12 字节：magic(4, ASCII `HHW1`)、version(2)、message_type(2)、payload_length(4)。
- payload 最大 64 KiB。接收端必须校验 magic、版本、长度和消息类型。
- 所有整数均为网络字节序（big-endian）；字符串使用 uint16 长度前缀，随后是 UTF-8 字节。

## 消息类型

| ID | 消息 | 方向 | 用途 |
|---:|---|---|---|
| 1 | ClientHello | C→S | 票据与客户端构建版本 |
| 2 | ServerWelcome | S→C | 角色实体与初始世界快照 |
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

## 安全规则

服务端验证票据、协议版本、消息大小、序列号、输入频率、移动速度和状态转换。客户端发来的坐标仅作为输入意图或预测参考，不能直接成为权威状态。世界服务器 API Key 只能用于服务器到后端的 HTTPS 管理调用，绝不能下发给客户端；票据不得写入日志。

## 当前实现边界

- 已实现：C++ ENet UDP host、连接/断开事件、帧编码解码、协议版本/长度校验、心跳应答。
- 尚未实现：ClientHello 的后端票据兑换、ServerWelcome、玩家实体创建、移动同步。当前服务端会断开非心跳业务消息，不能作为可登录游戏服使用。
- 后续握手：服务端通过受保护的 HTTPS `POST /api/v1/servers/tickets/redeem` 兑换一次性票据，后端原子消费票据并返回可信角色快照，再创建实体并发送 ServerWelcome。

## 世界入口票据流程

1. 客户端使用账号 Bearer Token 调用 `POST /api/v1/worlds/enter`。
2. 中心后端签发 60 秒有效的一次性随机票据，数据库只保存 SHA-256 摘要。
3. 客户端连接返回的 UDP 地址，在 ClientHello 携带票据与构建版本。
4. C++ 世界服务器使用自身 node_key 与服务器 API Key 调用兑换接口。
5. 兑换成功后，世界服务器恢复角色实体并发送 ServerWelcome。断线后必须重新申请票据，不得复用旧票据。
