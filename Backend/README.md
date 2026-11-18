# Go 业务后端

P0 采用模块化单体，按领域划分 internal 包。HTTP 层负责协议适配和输入校验；业务规则放在领域服务；数据库访问通过领域服务封装。

## 当前已实现

- `GET /health`：进程存活检查，不依赖数据库。
- `GET /ready`：检查 PostgreSQL 连接，数据库不可用时返回 503。
- `POST /api/v1/auth/register`：创建账号并签发 30 天 Bearer 会话令牌。
- `POST /api/v1/auth/login`：验证账号密码并创建会话。
- `GET /api/v1/account/me`：通过 Bearer 令牌读取当前账号。
- `POST /api/v1/souls`：为当前账号创建唯一灵魂档案。
- `GET /api/v1/souls/current`：读取当前账号的灵魂档案。
- `GET /api/v1/souls/current/progression`：读取跨世保留的灵魂经验与灵魂境界。
- `GET /api/v1/souls/current/essence`：读取跨轮回灵魂本体、当前魂体阶段、各类魂质统计、力量/体质/敏捷/灵力/气血五项来世资质，以及待分配的无相灵魄。
- `POST /api/v1/souls/current/breakthrough`：达到下一灵魂境界经验门槛后主动突破；灵魂经验奖励不会自动提升境界。
- `GET /api/v1/souls/current/trials`：读取当前灵魂可见的冥界试炼目标、进度和奖励状态。
- `GET /api/v1/souls/current/reincarnation-eligibility`：查询当前灵魂是否满足首次投胎门槛（聚灵境、完成酆都首个试炼），并返回未满足条件。
- `POST /api/v1/servers/souls/rewards`：可信世界节点提交灵魂经验奖励；校验节点密钥、节点标识、角色世界会话和事件幂等性。单次奖励限制为 1–100000 灵魂经验。
- `POST /api/v1/servers/souls/absorptions`：可信世界节点提交吞噬事件；中心服校验节点密钥、节点标识、角色会话、存活肉身与冥界世界归属，按服务端怪物类别目录结算魂力、容量和对应来世资质，以 `(soul_id,event_id)` 幂等。
- `POST /api/v1/souls/current/essence/allocate`：玩家为一枚待分配无相灵魄选择 `strength`、`constitution`、`agility`、`spirit` 或 `vitality`；服务端确认记录属于当前灵魂且未分配，在同一事务中只增加一项来世资质，不能重复使用。
- `GET /api/v1/worlds`：读取已启用的世界目录。
- `GET /api/v1/worlds/current/npcs`：按当前角色活跃世界会话读取该世界启用的 NPC 目录和交互配置。
- `POST /api/v1/worlds/current/npcs/interact`：与当前世界 NPC 交互；中心服根据当前活跃会话和已保存角色坐标校验世界归属及交互半径，不接受客户端自报坐标。
- `POST /api/v1/worlds/current/npcs/choose`：提交 NPC 因果分支 ID；中心服重新校验会话、世界和交互距离，从 NPC 数据配置读取选项，并由可信规则计算功德/业力。每个灵魂对同一 NPC 只能作出一次选择，幂等与数值更新在同一事务完成。
- `GET /api/v1/worlds/current/exploration-points`：读取当前世界探索点及当前灵魂的已发现状态；返回区域、危险等级、位置和交互半径。
- `GET /api/v1/worlds/current/exploration-progress`：按区域汇总当前世界探索点发现数、适用奇遇总数和已领取数；发现与领取进度按灵魂跨轮回保留。
- `GET /api/v1/worlds/current/exploration-events`：读取当前世界全部启用的区域奇遇，并返回 `status`（`locked`/`available`/`completed`）、`discovered`、`unlocked`、`completed`、剧情选项 `choices`；选项只暴露 ID、文字和说明，服务端效果键不下发。解锁与领取状态按灵魂及当前肉身种族/命格计算。
- 区域奇遇支持服务端因果前置条件：后续事件只有在同一灵魂领取指定前置事件、且 `choice_id` 与要求分支一致时才解锁；当前示例为收取引魂灯火后解锁“魂灯旧影”。
- `POST /api/v1/worlds/current/exploration-events/trigger`：请求体 `{ "event_id": "...", "choice_id": "..." }`；中心服校验活跃会话、服务端角色位置、探索点发现状态和选项 ID，按可信 effect_key 计算功德/业力，并在同一事务中写入所选 choice_id、灵魂级一次性领取、因果账簿及奖励。客户端不能提交奖励数值或效果键。
- `POST /api/v1/worlds/current/exploration-points/discover`：请求体仅包含 `point_id`；中心服按活跃会话和数据库中的角色位置验证距离，再以灵魂为单位幂等记录发现，并在同一事务中结算功德/业力因果事件。发现跨越轮回保留。
- `GET /api/v1/cultivation/systems`：读取种族、默认修炼体系、各自境界和跨种族实力参考层级。
- `GET /api/v1/cultivation/race-growth`：读取种族五维成长权重（基点总和 10000），用于后续服务端属性成长计算。
- `GET /api/v1/cultivation/bloodlines`：读取种族血脉、品阶、基础纯度和属性修正；角色可持有多条血脉，最多一条主血脉。
- `GET /api/v1/cultivation/techniques`：读取功法目录及各族适配度；跨族修炼必须有明确兼容记录，不从境界映射推断。
- `POST /api/v1/characters/first-life`：为当前灵魂创建第一世肉身并固定在冥界·酆都苏醒；根据 race_id 选择种族默认修炼体系，并在同一事务中初始化属性、修炼进度和新手背包（基础装备与丹药）。未传种族时默认人族。
- `GET /api/v1/characters/current/reincarnation-preview?race_id=human`：只读预览当前灵魂投胎到指定种族时的五维继承结果。服务端读取灵魂级 `soul_inheritance_attributes`、吞噬次数成长阶段和目标种族成长权重，计算每项出生属性加成；客户端不得提交或覆盖这些数值。
- `character_birth_inheritance`（迁移 `000029`）按肉身保存不可变继承快照：前世灵魂五维资质、吞噬次数/成长阶段、目标种族成长权重、最终加到新肉身的五维属性。旧肉身不变，灵魂资质不因投胎而清零。
- 出生属性公式：每项灵魂资质每满 3 点提供 +1，单项基础上限 +3；若目标种族该项成长权重不低于 2600 且资质至少 6，再获得 +1（仍受 +3 上限约束）。灵魂成长阶段达到聚魄成形后，将 +1 出生共鸣加到最强继承项；魂魄圆融阶段加 +2，仍受单项 +3 上限约束。五维属性同步影响攻击、防御、生命、灵力上限和移动速度。此公式是首版可调平衡参数，不把魂体视觉尺寸直接当作战斗力。
- `GET /api/v1/characters/current/reincarnation-routes`：读取已启用的轮回出生路线，返回目标世界、适配种族/命格和路线说明；出生坐标及路线奖励配置仅保留在服务端，不下发客户端。本阶段暂不发放路线专属资源。
- `POST /api/v1/characters/current/reincarnate`：请求体包含 `name`、`race_id`、`route_id`；服务端在同一事务中重新校验灵魂境界、酆都试炼、世界会话、路线启用状态、种族/命格适配，按路线写入出生世界与坐标，并归档路线快照。
- `GET /api/v1/characters/current`：读取当前肉身角色。
- `GET /api/v1/souls/current/lives`：读取当前灵魂全部肉身历世档案，按世次倒序返回角色名、种族、出生世界、境界、等级、状态、创建时间及对应轮回事件；不会把前世肉身数据覆盖为当前肉身数据。
- `GET /api/v1/souls/current/memories`：读取当前灵魂的前世记忆印记；达到记忆要求的灵魂境界才返回摘要和详情，未达到时仅返回印记标题与解封门槛。
- `GET /api/v1/souls/current/fate`：读取灵魂累计功德、业力和最近 20 条因果事件；当前第一条可信规则为在冥界·酆都完成一次游祟讨伐，增加 1 点功德。
- `GET /api/v1/characters/current/inventory`：读取当前角色背包，包含物品分类、品质、堆叠上限、装备部位和基础属性。
- `GET /api/v1/characters/current/equipment`：读取当前角色六个装备部位的已穿戴物品。
- `POST /api/v1/characters/current/equipment/equip` 与 `/unequip`：事务化穿戴/卸下装备；校验物品归属、装备部位和背包堆叠空间。角色仍处于活跃世界会话时拒绝变更，离开并重新进入世界后同步新战斗属性。
- `POST /api/v1/characters/current/inventory/use`：通过 request_id 幂等使用消耗品，事务扣减物品并按物品效果恢复生命/灵力。
- `POST /api/v1/servers/sessions/combat-stats`：仅可信节点可调用；校验当前活跃会话并返回角色基础攻防与已装备物品加成。
- `GET /api/v1/characters/current/status`：读取当前角色属性、经验、修为、种族修炼体系、境界阶段、下一阶段/境界修为门槛、跨种族实力参考层级和角色血脉（品阶、纯度、觉醒阶段、主血脉标记）。
- `POST /api/v1/characters/current/bloodlines/awaken`：请求当前角色已拥有的一条血脉觉醒；服务端按数据表校验下一阶段的境界和修为消耗，原子提升觉醒阶段/纯度并扣除修为。
- `POST /api/v1/characters/current/techniques/train`：修炼角色已拥有的功法；按功法品阶和训练点数消耗修为、增加熟练度，服务端校验持有关系、境界和余额。
- `POST /api/v1/characters/current/breakthrough`：服务端根据累计修为推进一个小境界；达到当前境界圆满并满足下一境界门槛后，进入该修炼体系的下一境界。事务锁定当前角色和成长记录，客户端不能直接提交境界或阶段数值。
- `POST /api/v1/characters/current/attributes/allocate`：将已获得的属性点分配到力量、体质、敏捷、灵力或根骨；在事务中锁定当前角色和成长记录、校验点数余额并更新衍生属性。
- `POST /api/v1/servers/characters/rewards`：可信世界节点使用服务端密钥和节点标识提交经验、修为及属性点奖励；要求角色当前有该节点上的活跃会话，并使用事件 ID 防止重试重复发奖。
- `POST /api/v1/servers/heartbeat`：可信世界服务器通过 `X-World-Server-Key` 注册/更新节点和世界实例状态。
- `POST /api/v1/worlds/enter`：当前角色申请世界入口，返回服务器地址和 60 秒一次性票据。
- `POST /api/v1/servers/tickets/redeem`：世界服务器校验并兑换一次性票据，获取角色初始快照和会话 ID，并创建世界会话。
- `POST /api/v1/servers/sessions/snapshot`：可信世界节点每秒提交在线角色的权威位置/朝向/生命值快照；只允许当前 active 会话写入，不结束会话。旧节点省略 health 时仍兼容位置快照。
- `POST /api/v1/servers/sessions/close`：可信世界节点提交最终位置/朝向/生命值快照并关闭会话；服务端校验节点、会话、角色归属及位置/生命值边界，事务内保存角色位置和生命值并关闭会话，重复关闭请求幂等。
- 后台孤儿会话回收：每 15 秒扫描一次；节点心跳超过 45 秒未更新时标记节点离线，并且仅关闭其最后一次角色快照也超过 45 秒的连接会话。这样不会因节点心跳短暂故障而误清理仍持续提交位置快照的玩家。
- PostgreSQL 连接池通过 `DATABASE_URL` 配置，启动时执行 Ping；连接失败则拒绝启动。
- JSON 结构化日志和优雅关闭。

## 种族成长、血脉与功法

`000003_race_bloodline_techniques` 新增种族五维成长权重、独立血脉定义/属性修正、角色多血脉记录，以及功法目录、跨族适配矩阵和角色功法熟练度记录。每个种族有一条默认初始血脉；既有角色在迁移时获得对应默认血脉。功法的跨族适配必须通过 `technique_race_compatibility` 显式声明，初始跨族适配仅为保守示例值，尚不代表最终平衡数值。

## 种族修炼体系与实力映射

`000002_character_progression` 建立独立的种族、修炼体系、境界、境界阶段和实力参考层级：

- 人族：人族仙道（炼气期、筑基期、金丹期、元婴期、化神期、炼虚期、合体期、大乘期、渡劫期）。
- 妖族：妖族妖修（开灵境、化形境、妖丹境、妖魂境、妖神境、妖域境、通天境、妖圣境、渡劫境）。
- 巫族：巫族炼体（淬体境、铜身境、银身境、金身境、大巫境、祖巫境、领域境、巫圣境、返祖归源境）。
- 龙族：龙族血脉（初血境、蛟血境、真龙境、龙珠境、龙王境、龙君境、龙皇境、祖龙境、化祖境）。

`power_tiers` 与 `realm_power_mappings` 只提供跨种族比较、匹配和难度设计的参考，不代表不同种族境界完全等价。实际战斗结果仍需综合血脉、肉身、功法、神通、装备、技能和环境。每个角色的 `character_progression.system_id` 与 `realm_id` 由数据库复合外键保证一致，境界阶段也受阶段目录约束。

角色种族与修炼体系目前通过默认映射初始化，但数据库支持一个种族关联多个修炼体系；后续可通过传承、血脉融合或特殊机缘开放跨族修炼。当前状态接口只读；属性点分配必须通过认证接口提交分配意图，服务端检查余额并计算衍生属性。境界阶段门槛由相邻境界的累计修为门槛按阶段比例推导，最后一个阶段之后再执行大境界突破；具体突破仪式、失败概率、种族专属条件和战斗属性成长仍待实现。奖励只能由可信世界节点通过服务端接口发放，并以 `(server_id, event_id)` 幂等去重。主动更换修炼体系尚未开放。

## 尚待完成

- 属性点获取节奏、经验/修为曲线和各体系独立突破规则。
- 种族成长权重、血脉与功法目录及 API 已建立；实际属性升级结算、血脉融合、额外功法传承/学习、功法装备和战斗效果仍待实现。角色创建时会自动获得本种族的一项入门功法；更多功法必须由后续可信任务/掉落系统授予。
- 各种族独立的突破仪式、突破失败/成功效果、瓶颈条件和境界压制规则。
- 怪物/NPC复杂行为、战斗技能与完整战斗状态同步；消耗品目前更新中心服生命/灵力，尚未向在线 WorldServer 实时推送角色生命/灵力变化。角色位置与生命值通过 WorldServer 每秒周期快照保存，正常断线/正常关服另存最终状态；约 1 秒快照周期加网络延迟仍构成异常断电时的回退窗口。
- 服务器心跳过期后的后台监控告警与运维面板。
- 跨节点强制踢线通知与完整重连恢复（目前通过旧节点下一次快照收到 409 后断开，尚非实时推送）。
- 登录限流、邮箱验证、密码重置和主动注销。
- Redis/NATS 实际业务接入与服务端 API Key 轮换。

## 本地运行

1. 按 `Deployment/README.md` 启动 PostgreSQL。
2. 按编号执行 `Database/migrations/` 中全部 `.up.sql` 迁移；当前需依次执行 `000001` 至 `000029`（每个编号只执行 `.up.sql` 一次；已部署数据库只执行尚未应用的迁移）。
3. 在 `Deployment/.env` 配置 `DATABASE_URL` 和 `HTTP_ADDR`。
4. Windows PowerShell 执行 `../Deployment/start-backend.ps1`；或在本目录执行 `go test ./...`、`go run ./cmd/api`（需先设置环境变量）。

密码使用 bcrypt 哈希后保存，不保存明文；会话令牌使用高熵随机值，数据库只保存 SHA-256 摘要。当前注册密码长度要求 12–72 字节，用户名为 3–32 位字母/数字/下划线。日志不得输出密码、访问令牌或完整连接票据。每个账号当前只允许创建一个主灵魂档案；第一世角色创建使用数据库事务并锁定灵魂行，避免重复创建；轮回时会为同一灵魂创建新的肉身角色，而不是覆盖灵魂。登录限流、邮箱验证、密码重置和主动注销将在后续安全迭代补齐。世界服务器心跳密钥通过 `WORLD_SERVER_API_KEY` 配置；生产环境必须使用随机长密钥，并通过安全配置渠道分发给节点。当前心跳统计按节点上报，P0 暂按每个节点一个活动实例管理。


### 死亡与复活

- WorldServer 在周期/最终快照提交生命值为 0 时，中心服在同一事务中记录角色死亡事件（按 session + character 幂等）。
- `POST /api/v1/characters/current/respawn`：登录玩家只能复活自己当前肉身的待处理死亡记录；事务关闭死亡会话、将角色世界切换到 `underworld_fengdu`、重置出生坐标为 `(0,0,0)`，恢复生命/灵力，并标记死亡记录已复活。灵魂、修为、背包和装备不被重置。
- 复活后客户端需返回主界面重新申请世界入场票据；冥界实例必须处于 ready 状态才能进入。

## 灵魂主动轮回（第一阶段）

- API：`POST /api/v1/characters/current/reincarnate`，Bearer 登录凭证。
- 请求体：`{"name":"新肉身名称","race_id":"human"}`。
- 仅允许当前肉身存活且没有 `connecting/active/saving` 世界会话时轮回；必须先退出当前世界。
- 新肉身出生世界固定为 `underworld_fengdu`，使用所选种族的默认修炼体系、初始境界、基础属性、默认血脉、种族入门功法和新手背包。
- 旧肉身状态改为 `retired` 并保留原有属性、修为、背包、装备和历史；不会覆盖旧肉身。
- `souls` 记录不重建，灵魂 ID、功德、业力等灵魂级数据保留；只切换 `current_character_id`。
- `reincarnation_events` 保存每次轮回的前后肉身、世界、种族和世次，便于后续轮回殿展示。
- 首次投胎必须达到聚灵境（灵魂境界序号 3）并完成“引魂试炼·初除游祟”；查询接口仅用于展示资格，创建肉身的事务会再次检查门槛。当前尚未扣除功德/业力，也未实现轮回冷却、记忆继承效果或因果/轮回印记加成。
- 新肉身创建后仍需通过正常世界进入流程取得目标 WorldServer 的一次性 ticket；冥界实例未 ready 时不能进入场景。



## 灵魂境界与投胎规则（基础数据阶段）

灵魂拥有独立于肉身修炼体系的永久成长记录，使用 `soul_progression` 保存经验和当前境界，肉身重生或主动轮回不会重置该数据。当前初始境界为游魂境，境界目录为：

| 境界 | 累计灵魂经验门槛 | 设计定位 |
|---|---:|---|
| 游魂境 | 0 | 初入冥界 |
| 凝魂境 | 100 | 完成基础引魂试炼 |
| 聚灵境 | 500 | 首次投胎的基础资格 |
| 灵体境 | 2,500 | 解锁更多种族/出生路线 |
| 魂将境 | 10,000 | 稳固保存部分前世记忆 |
| 魂王境 | 50,000 | 高阶世界轮回门槛 |
| 魂尊境 | 250,000 | 高阶因果与轮回印记 |
| 魂圣境 | 1,000,000 | 特殊轮回路线 |

普通死亡复活与主动投胎必须区分：普通死亡回冥界后复活原肉身，不要求灵魂升级；主动投胎才检查灵魂境界、功德、业力和目标种族/世界条件。当前已接入灵魂经验奖励、主动境界突破、酆都首个试炼，以及首次投胎的聚灵境与试炼完成门槛。高阶世界条件、功德/业力审判和不同种族出生路线仍待扩展。灵魂经验只能由可信世界节点/任务服务端发放，客户端不得自行提交经验数值。


## 灵魂经验奖励与境界突破

世界节点使用 `X-World-Server-Key` 和 `X-World-Server-Node` 调用 `POST /api/v1/servers/souls/rewards`。请求字段为 `event_id`、`session_id`、`character_id`、`experience`、`source`。中心服确认该角色属于节点对应的在线/近期关闭会话后，才会写入灵魂经验；同一灵魂的 event_id 唯一，网络重试不会重复发奖。奖励来源使用小写字母、数字、下划线、短横线或冒号。

经验增加后只更新经验值，不自动突破境界。玩家达到下一境界累计经验门槛后，通过 `POST /api/v1/souls/current/breakthrough` 完成境界晋升。境界突破、NPC交互和投胎资格查询均由中心服提供；投胎创建事务会再次校验聚灵境和首个冥界试炼完成状态。功德/业力审判暂未作为首阶段硬门槛。


冥界首个数据驱动试炼为“引魂试炼·初除游祟”：在酆都击败 20 只怪物，获得一次性 100 点灵魂经验奖励。酆都 WorldServer 每次击败怪物会通过 Durable Outbox 发送 5 点基础灵魂经验；中心服在同一奖励事务中推进试炼计数，第 20 次完成时额外发放 100 点奖励。重复事件不会重复增加经验或任务进度。试炼奖励只增加经验，境界仍需玩家主动突破。


## 冥界 NPC 与轮回殿入口（第一阶段）

迁移 `000012_world_npcs` 建立数据驱动的 `world_npc_definitions`，酆都预置五名 NPC：引魂使、镇祟校尉、冥府判官、孟婆、轮回殿守卫。NPC 的世界归属、位置、朝向、交互半径、交互类型和对白配置均由数据库提供，不在客户端硬编码。

- 客户端进入世界并建立活跃会话后调用 `GET /api/v1/worlds/current/npcs` 加载当前世界 NPC。
- 与 NPC 交互调用 `POST /api/v1/worlds/current/npcs/interact`，请求体为 `{"npc_id":"fengdu_reincarnation_guard"}`。
- 服务端只根据中心服保存的角色位置、当前活跃会话和实例世界归属判定交互距离；未进入世界、NPC 不属于当前世界或距离过远均拒绝。
- 轮回殿守卫交互配置告知首次投胎要求；客户端随后读取 `GET /api/v1/souls/current/reincarnation-eligibility` 展示灵魂境界和试炼条件。
- `POST /api/v1/characters/current/reincarnate` 在创建新肉身的同一事务中再次校验：灵魂境界至少为聚灵境（realm_order >= 3），且 `fengdu_first_exorcism` 已完成。普通死亡复活不受此门槛影响。
- 当前 NPC 交互返回数据驱动对白/功能类型；正式对话树、NPC 动画、任务接取按钮和客户端 UI 尚待接入。


## 灵魂本体、魂质与来世资质（000027–000028）

`soul_essence_attributes` 以 `soul_id` 为主键，保存魂力、灵性、魂韧、神识、吞噬容量和累计吸收能量/次数；`soul_inheritance_attributes` 保存力量、体质、敏捷、灵力、气血五项来世资质，均属于灵魂而非某一世肉身。魂质目录包含普通游魂、炽战残魂、铁骨兽魂、疾风游魂、灵识游魂、生机古魂和无相灵魄。属性魂每次吸收增加对应来世资质 1 点；无相灵魄先进入待分配状态，由玩家自行选择五项属性之一。吞噬记录带 `(soul_id,event_id)` 唯一约束，并保存无相灵魄的选择与分配时间。

当前开放读取 `GET /api/v1/souls/current/essence`，并接入第一条可信吞噬结算链。该档案同时返回 `affinity_counts`：中心服按当前灵魂的吞噬流水统计兽、战、风、灵、生五类魂质亲和，并统计无相灵魄已分配到五项资质的次数。客户端据此改变冥界魂光的主色、兽形外壳、灵识符环与生机光环；境界阶段和视觉尺寸仍由灵魂档案决定。亲和数据不由客户端提交，其他玩家的魂光外观在本阶段仍使用通用样式。 此外返回 `growth_stage` 与 `growth_name`，按当前灵魂累计吞噬次数分为五个纯视觉成长阶段：0–2 次初生魂团、3–7 次魂光凝实、8–19 次聚魄成形、20–39 次灵体初成、40 次及以上魂魄圆融。该阶段只驱动魂光外环层数与成熟灵壳，不替代修炼境界，也不直接增加战斗属性。冥界 WorldServer 只在权威战斗结算确认 `wandering_wraith` 被击败后，才将 `soul_absorption` 事件写入本地 SQLite Durable Outbox；事件携带服务端生成的 UUID、当前世界会话/角色和怪物运行时 ID/服务端定义类别。Outbox 负责断线重试与重启恢复。中心服 `POST /api/v1/servers/souls/absorptions` 仅接受 `X-World-Server-Key` + `X-World-Server-Node`，再次验证节点、角色、会话、存活肉身和 `underworld_fengdu` 世界归属；`wandering_wraith` 由服务端映射为 `ordinary_wraith`，基础能量和特质键从 `soul_absorption_kinds` 读取。中心服事务锁定灵魂本体，按剩余吞噬容量截断本次能量，写入唯一 `(soul_id,event_id)` 流水并增加 `absorbed_energy`、`absorbed_count` 和魂力。客户端不提供能量、类别奖励、特质键或灵魂 ID；同一事件重试不会重复入账。酆都 WorldServer 已加入各属性魂类怪物，并由中心服白名单映射到类别目录。普通游魂只增加基础魂力；属性魂增加对应来世资质；无相灵魄增加固定魂力并留下待分配选择。容量已满时返回 409，WorldServer 将该事件移入死信，不会自动丢弃已有魂力或突破容量。客户端击杀冥界游祟后延迟刷新魂体档案与 HUD。
