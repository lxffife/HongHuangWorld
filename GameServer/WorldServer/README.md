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
