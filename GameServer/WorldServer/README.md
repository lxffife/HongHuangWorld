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