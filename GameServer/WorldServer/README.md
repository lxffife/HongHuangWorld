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

## 战斗模拟基础

include/simulation/combat.hpp 提供无随机数、无网络依赖的确定性伤害计算：
- 攻击倍率使用 basis points，10000 表示 1.0 倍。
- 防御穿透使用 basis points，0 表示不穿透，10000 表示完全无视防御。
- 伤害至少为 1，且不会超过目标当前生命值。
- 输入属性与倍率有上限校验，避免负数、异常状态和整数溢出。
- combat_test 覆盖基础伤害、倍率、防御穿透、最低伤害、生命值上限和非法参数。

当前仅完成可独立测试的战斗计算基础，尚未接入 ENet 战斗消息、怪物 AI、冷却/距离校验或中心服奖励结算；不能视为已经具备可玩的战斗系统。

## 怪物仿真基础

`include/simulation/monster.hpp` 提供独立于网络层的怪物定义与确定性 AI 步进：
- 怪物定义包含等级、生命、攻防、移动速度、仇恨半径、离巢半径与出生坐标，并进行数值校验。
- 怪物在仇恨半径内发现存活目标后进入追击状态；目标离开仇恨范围后返回出生点。
- 怪物超出离巢半径会强制返回，避免被玩家无限引离出生区域。
- 生命归零后进入死亡状态；该模块不负责奖励、掉落、刷新计时或网络广播。
- `monster_test` 覆盖定义校验、索敌追击、离巢返回与死亡状态。

当前已接入 WorldServer 服务端实体集合与 20Hz 世界 Tick：世界启动时生成 3 只荒原狼，服务端选择最近玩家作为索敌目标并执行追击/返回；AOI 快照向 80 米范围内客户端发送怪物实体，Godot 客户端显示简易占位模型并平滑同步位置。当前已接入左键攻击、服务端距离与冷却校验、统一伤害结算和 12 秒定时重生；玩家基础攻击暂为配置常量 20。经验/修为奖励、掉落拾取尚未接入；模型仍是联调占位体。

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

正常断线和正常关服仍会执行最终快照并关闭会话。周期快照将意外进程崩溃时的理论位置回退窗口缩短到约 1 秒（还取决于数据库和网络延迟）。中心服每 15 秒扫描一次孤儿会话：节点心跳与会话快照均超过 45 秒未更新时，标记节点离线并关闭其孤儿会话。跨节点旧会话会在下一次周期快照收到 409 后断开；目前尚未实现中心服向旧节点的实时强制踢线推送。


## 多人可见范围（AOI）

P0 使用基于 X/Z 平面距离的简单兴趣范围：每个客户端每 50ms 收到自己的实体以及 80 米范围内的其他玩家。超出范围的玩家会从下一帧快照中消失，重新进入范围后会再次出现。当前实现是逐玩家逐实体距离过滤，适用于当前小规模联调；后续人数增大时应替换为网格/空间哈希分区，并加入地形遮挡和更细粒度实体订阅。


## 多人加入与离开事件

- 新玩家完成一次性票据兑换后，WorldServer 会向当前在线客户端发送可靠的 `PlayerJoined` 事件，包含角色 ID、名称和初始位置。
- 玩家断线或同角色新连接替换旧连接时，WorldServer 会向其他客户端发送可靠的 `PlayerLeft` 事件。
- 加入/离开事件使用可靠 ENet 通道；20Hz `EntitySnapshot` 仍是实体位置与 AOI 可见范围的权威状态来源。客户端收到事件后即时创建/移除远端占位角色，随后由快照持续校正位置。
