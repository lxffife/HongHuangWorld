# 核心领域模型

## 主要实体

- Account：登录身份、账号状态和安全信息。
- Soul：跨轮回的灵魂身份、灵魂本源、记忆与因果摘要。
- Character：某一世的肉身角色，关联 soul_id 和 world_id；每一世独立保存。
- CharacterAttributes：某一世肉身的基础属性、战斗属性和生存资源。
- CharacterProgression：某一世肉身的经验、修为、境界阶段和可分配属性点。
- CharacterRewardEvent：由可信世界节点提交的奖励事件，按节点和事件 ID 幂等去重，避免网络重试造成重复发奖。
- RealmDefinition：数据驱动的修炼境界目录与突破门槛。
- ReincarnationRecord：一次轮回的来源角色、轮回道、目标世界、结果和时间。
- WorldDefinition：世界静态规则与内容配置。
- WorldInstance：某个世界当前运行的实例。
- ServerNode：实际运行的世界服务器节点及其地址、容量和健康状态。
- WorldSession：角色在世界服务器上的在线会话。

## 数据约束

1. accounts.id 是账号主键；souls.account_id 关联账号。
2. characters.soul_id 关联灵魂；角色记录不可因轮回而覆盖。
3. 每个角色记录有明确的 life_index、world_id、状态和创建时间。
4. 角色属性和成长记录以 character_id 为主键，与肉身一一对应；轮回创建新肉身时初始化新的属性/进度记录，不覆盖前世数据。
5. 境界规则放在 RealmDefinition，客户端只读取展示，不决定突破结果。
6. 经验、修为和属性点只能由可信世界节点对当前活跃会话提交奖励；奖励事件必须幂等，客户端不得直接发放。
6. 物品实例必须有唯一实例 ID；涉及交易/掉落时写入可审计流水。
7. 世界定义与运行实例分开，实例可迁移或重建，静态配置可版本化。

## 当前主要表

accounts、account_sessions、souls、characters、character_attributes、character_progression、realm_definitions、world_definitions、world_instances、server_registry、world_entry_tickets、world_sessions。
