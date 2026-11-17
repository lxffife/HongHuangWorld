# C++ WorldServer

独立运行的 C++20 实时世界服务器，使用 CMake 构建、ENet 处理 UDP 会话。

建议模块：

- Core：Application、Config、Logger、Clock。
- Network：ENetServer、Session、PacketDispatcher、ProtocolCodec。
- World：WorldManager、WorldInstance、AOI。
- Entity：Entity、PlayerEntity、EntityManager。
- Gameplay：MovementValidator、Combat、Inventory/Drop（已接入基础 ENet 实时流程）。
- Persistence：CharacterSnapshot、SaveQueue。

服务器必须权威计算玩家位置并广播快照。P0 先实现单进程单测试世界，后续再扩展多实例与分区。

## 战斗模拟基础

include/simulation/combat.hpp 提供无随机数、无网络依赖的确定性伤害计算：
- 攻击倍率使用 basis points，10000 表示 1.0 倍。
- 防御穿透使用 basis points，0 表示不穿透，10000 表示完全无视防御。
- 伤害至少为 1，且不会超过目标当前生命值。
- 输入属性与倍率有上限校验，避免负数、异常状态和整数溢出。
- combat_test 覆盖基础伤害、倍率、防御穿透、最低伤害、生命值上限和非法参数。

当前已接入 ENet 攻击指令与 CombatEvent：客户端左键请求攻击附近怪物，服务端执行目标、距离和冷却校验，并调用该伤害计算模块。奖励结算已接入中心服。中心服提供物品目录、怪物掉落配置查询、地面掉落持久化、角色背包和幂等拾取 API。WorldServer 启动时读取掉落表，击杀时按服务端概率生成掉落并异步持久化，AOI 仅向归属角色广播；拾取请求由服务端校验归属、会话、距离与频率，异步调用中心服事务结算。Godot 客户端显示掉落球体，按 E 拾取，并提供背包 UI。

## 怪物仿真基础

`include/simulation/monster.hpp` 提供独立于网络层的怪物定义与确定性 AI 步进：
- 怪物定义包含等级、生命、攻防、移动速度、仇恨半径、离巢半径与出生坐标，并进行数值校验。
- 怪物在仇恨半径内发现存活目标后进入追击状态；目标离开仇恨范围后返回出生点。
- 怪物超出离巢半径会强制返回，避免被玩家无限引离出生区域。
- 生命归零后进入死亡状态；该模块不负责奖励、掉落、刷新计时或网络广播。
- `monster_test` 覆盖定义校验、索敌追击、离巢返回与死亡状态。

当前已接入 WorldServer 服务端实体集合与 20Hz 世界 Tick：世界启动时生成 3 只荒原狼，服务端选择最近玩家作为索敌目标并执行追击/返回；AOI 快照向 80 米范围内客户端发送怪物实体，Godot 客户端显示简易占位模型并平滑同步位置。当前已接入左键攻击、服务端距离与冷却校验、统一伤害结算和 12 秒定时重生；玩家基础攻击暂为配置常量 20。击杀奖励通过后台队列调用中心服 `/api/v1/servers/characters/rewards`，按怪物等级发放经验与修为，携带原始世界会话 ID，并使用 UUID 事件 ID 幂等去重；奖励队列允许会话关闭后 10 分钟内完成补交；掉落与背包基础链路已接入：荒原狼预置荒狼獠牙（65%）与荒狼皮（30%）掉落配置，地面掉落 15 分钟过期，拾取在单个数据库事务中消费掉落并增加背包堆叠，事件 ID 防重复。WorldServer 读取配置、生成和广播归属掉落，服务端验证拾取距离并异步结算；客户端按 E 拾取并可打开背包查看材料。地面掉落记录由中心服数据库持久化；WorldServer 启动时按节点恢复未过期掉落，角色重新进入同一节点后仍可拾取自己此前会话产生的掉落。拾取时使用当前活动会话验证角色身份，不要求掉落必须属于当前登录会话。模型仍是联调占位体。

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

## 持久化事件 Outbox

怪物击杀奖励（经验/修为）和地面掉落创建已先写入节点本地 SQLite Outbox，再由后台线程异步投递中心服。事件使用稳定 ID；相同 ID 与相同 payload 重复入队幂等，ID 对应不同 payload 会被拒绝。进程重启时会把遗留的 inflight 事件恢复为 pending，网络错误和 HTTP 5xx 使用持久化指数退避重试，HTTP 4xx 进入 dead-letter。中心服仍需按事件 ID/掉落 ID 保持幂等。

新增配置：
- `WORLD_SERVER_OUTBOX_PATH`：SQLite 文件路径，默认 `./data/worldserver-outbox.sqlite3`。父目录会自动创建。
- 数据文件必须放在持久化磁盘；不要放在临时目录或临时容器层。不要让多个 WorldServer 进程共享同一数据库文件。

当前 Outbox 容量为 10,000 条 pending/inflight 事件；已投递和死信记录保留用于排查，不计入活动容量。拾取结算仍使用原内存队列，尚未纳入 Outbox。详见 [OUTBOX.md](OUTBOX.md)。
