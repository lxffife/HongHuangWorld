# 核心领域模型

## 主要实体

- Account：登录身份、账号状态和安全信息。
- Soul：跨轮回的灵魂身份、灵魂本源、记忆与因果摘要。
- Character：某一世的肉身角色，关联 soul_id、race_id 和 world_id；每一世独立保存。
- RaceDefinition：种族目录。
- CultivationSystem：独立修炼体系；体系不与全局境界名称绑定。
- RaceCultivationSystem：种族与可用修炼体系的映射，并标记默认体系；未来允许同一种族拥有多条修炼道路。
- CultivationRealm：某个修炼体系内部的专属境界、顺序、阶段数和修为门槛。
- CultivationStage：境界内部的阶段名称。
- PowerTier：跨种族综合实力参考层级，只用于比较/匹配/难度设计，不表示境界等价。
- RealmPowerMapping：将种族境界映射到一个参考实力层级，并记录比较说明。
- CharacterAttributes：某一世肉身的基础属性、战斗属性和生存资源。
- CharacterProgression：某一世肉身的经验、修为、具体修炼体系、境界阶段和可分配属性点。
- CharacterRewardEvent：由可信世界节点提交的奖励事件，按节点和事件 ID 幂等去重，避免网络重试造成重复发奖。
- ReincarnationRecord：一次轮回的来源角色、轮回道、目标世界、结果和时间。
- WorldDefinition：世界静态规则与内容配置。
- WorldInstance：某个世界当前运行的实例。
- ServerNode：实际运行的世界服务器节点及其地址、容量和健康状态。
- WorldSession：角色在世界服务器上的在线会话。

## 修炼体系设计原则

1. 种族有默认修炼体系，但种族与体系不是永久的一对一绑定；后续可通过功法传承、血脉融合、机缘等方式开放其他体系。
2. 不同种族拥有不同的境界名称、突破条件、成长资源和能力特征。
3. PowerTier 只提供粗粒度参考映射；相同层级不代表相同战斗力，也不保证境界之间严格等价。
4. 战斗能力由境界、属性、血脉、肉身、功法、神通、装备、技能、经验和环境共同决定。
5. 境界、阶段和映射全部数据驱动；客户端只展示，服务端决定成长与突破结果。

## 数据约束

1. accounts.id 是账号主键；souls.account_id 关联账号。
2. characters.soul_id 关联灵魂；角色记录不可因轮回而覆盖。
3. 每个角色记录有明确的 life_index、race_id、world_id、状态和创建时间。
4. 角色属性和成长记录以 character_id 为主键，与肉身一一对应；轮回创建新肉身时初始化新的属性/进度记录，不覆盖前世数据。
5. character_progression 的 system_id 与 realm_id 由复合外键保证属于同一修炼体系；realm_stage 必须存在于该境界阶段目录。
6. 经验、修为和属性点只能由可信世界节点对当前活跃会话提交奖励；奖励事件必须幂等，客户端不得直接发放。
7. 物品实例必须有唯一实例 ID；涉及交易/掉落时写入可审计流水。
8. 世界定义与运行实例分开，实例可迁移或重建，静态配置可版本化。

## 当前主要表

accounts、account_sessions、souls、characters、race_definitions、cultivation_systems、race_cultivation_systems、cultivation_realms、cultivation_stages、power_tiers、realm_power_mappings、character_attributes、character_progression、character_reward_events、world_definitions、world_instances、server_registry、world_entry_tickets、world_sessions。
