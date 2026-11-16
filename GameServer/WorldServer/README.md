# C++ WorldServer

独立运行的 C++20 实时世界服务器，使用 CMake 构建、ENet 处理 UDP 会话。

建议模块：

- Core：Application、Config、Logger、Clock。
- Network：ENetServer、Session、PacketDispatcher、ProtocolCodec。
- World：WorldManager、WorldInstance、AOI。
- Entity：Entity、PlayerEntity、EntityManager。
- Gameplay：MovementValidator、Combat（后续）、Inventory（后续）。
- Persistence：CharacterSnapshot、SaveQueue。

服务器必须权威计算玩家位置并广播快照。P0 先实现单进程单测试世界，后续再扩展多实例与分区。

## 中心服节点注册

WorldServer 使用 `WORLD_SERVER_API_KEY` 调用中心服心跳接口。启动后立即上报，之后每 10 秒上报一次；网络故障时每 5 秒重试。退出时上报 `draining`，避免中心服继续给该节点分配新玩家。

必需配置：
- `BACKEND_URL`：中心服 HTTP 地址
- `WORLD_SERVER_NODE_KEY`：稳定的节点标识
- `WORLD_SERVER_API_KEY`：与中心服共享的服务端密钥
- `WORLD_SERVER_ADVERTISE_HOST`：客户端可连接的主机名/IP；不能填写监听用的 `0.0.0.0`
- `WORLD_ID`：承载的世界 ID，例如 `qingyun_human`
- `WORLD_SERVER_INSTANCE_KEY`：节点内稳定且唯一的实例标识
- `WORLD_SERVER_CAPACITY`：最大在线人数
- `WORLD_SERVER_BIND` / `WORLD_SERVER_UDP_PORT`：ENet 监听地址和 UDP 端口

节点心跳成功后，中心服才会将世界实例标记为 `ready` 并允许签发一次性进入票据。

## 玩家断线与位置保存

兑换世界票据后，中心服会把新建的 `world_sessions.id` 一并返回。WorldServer 在 ENet 客户端断开时，将服务端权威计算的位置和朝向提交到 `POST /api/v1/servers/sessions/close`，由中心服校验节点/会话/角色关系并在同一事务中保存角色坐标、关闭会话。WorldServer 正常关闭时先把节点标记为 `draining`，再保存当前在线角色，避免关闭期间继续分配新玩家。

WorldServer 现在还会每 1 秒将在线玩家的最新权威坐标放入异步保存队列，由后台工作线程调用 `POST /api/v1/servers/sessions/snapshot` 写入角色数据，不阻塞 20Hz 游戏模拟循环。中心服只接受当前仍为 active 的节点会话；如果票据在其他连接上重新兑换，旧会话的周期快照会被拒绝，旧节点随后主动断开该过期玩家。

正常断线和正常关服仍会执行最终快照并关闭会话。周期快照将意外进程崩溃时的理论位置回退窗口缩短到约 1 秒（还取决于数据库和网络延迟），但它不是完整的崩溃恢复系统：尚未实现进程重启后的孤儿会话清理、跨节点强制踢线通知和完整的重连状态恢复。


## 多人可见范围（AOI）

P0 使用基于 X/Z 平面距离的简单兴趣范围：每个客户端每 50ms 收到自己的实体以及 80 米范围内的其他玩家。超出范围的玩家会从下一帧快照中消失，重新进入范围后会再次出现。当前实现是逐玩家逐实体距离过滤，适用于当前小规模联调；后续人数增大时应替换为网格/空间哈希分区，并加入地形遮挡和更细粒度实体订阅。
