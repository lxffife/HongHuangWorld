# 核心领域模型

## 主要实体

- Account：登录身份、账号状态和安全信息。
- Soul：跨轮回的灵魂身份、灵魂本源、记忆与因果摘要。
- Character：某一世的肉身角色，关联 soul_id 和 world_id；每一世独立保存。
- ReincarnationRecord：一次轮回的来源角色、轮回道、目标世界、结果和时间。
- WorldDefinition：世界静态规则与内容配置。
- WorldInstance：某个世界当前运行的实例。
- ServerNode：实际运行的世界服务器节点及其地址、容量和健康状态。
- WorldSession：角色在世界服务器上的在线会话。

## 数据约束

1. accounts.id 是账号主键；souls.account_id 关联账号。
2. characters.soul_id 关联灵魂；角色记录不可因轮回而覆盖。
3. 每个角色记录有明确的 life_index、world_id、状态和创建时间。
4. 物品实例必须有唯一实例 ID；涉及交易/掉落时写入可审计流水。
5. 世界定义与运行实例分开，实例可迁移或重建，静态配置可版本化。

## P0 最小表

accounts、account_sessions、souls、characters、world_definitions、world_instances、server_registry、world_sessions。后续再增加 soul_memories、reincarnation_records、character_inventory、character_attributes 等扩展表。
