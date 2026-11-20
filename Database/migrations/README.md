# 数据库迁移约定

- 文件名格式：`NNNNNN_description.up.sql` 与 `.down.sql`。
- 迁移必须可审查、可重复部署；不要在应用启动时自动执行迁移。
- 部署流水线需要维护 schema_migrations 版本记录，执行每个版本前先检查是否已应用。
- 生产环境执行前先备份，并在测试环境验证 up/down。
- `000001_initial_schema` 创建账号、会话、灵魂、肉身角色、世界定义、世界实例、节点注册和世界会话表。
- `000002_character_progression` 创建角色属性、种族目录、种族专属修炼体系、境界阶段、跨种族实力参考映射和幂等奖励流水，并为已有角色补齐默认成长记录。
- `000003_race_bloodline_techniques` 创建种族属性成长权重、血脉定义/修正/角色继承记录、功法目录/跨族适配矩阵/角色熟练度记录，并为已有角色补齐默认血脉。
- `000004_bloodline_awakening_technique_training` 创建数据驱动的血脉觉醒门槛、种族入门功法映射，并为已有角色补齐一项种族入门功法。
- `000005_items_inventory_drops` 创建物品目录、怪物掉落配置、地面掉落实体、角色背包和幂等拾取流水；初始配置荒原狼掉落荒狼獠牙与荒狼皮。
- `000006_character_equipment` 增加物品类型/装备部位/基础属性/使用效果元数据，以及角色装备槽；兼容同步现有 category 与 item_type。
- `000007_item_use_and_starter_catalog` 增加消耗品幂等流水、初始装备/丹药目录，并为已有角色发放一次性新手物品。
- `000048_backfill_current_character_projection` 为已有角色补发当前角色投影事件，修复聊天侧当前角色状态缺失。
- `000049_weapon_type_metadata` 为武器目录增加显式 `weapon_type`（sword/spear/bow/staff/dagger/axe/hammer/focus），现有武器按目录标识初始化；非武器禁止填写该字段。
- `000052_unified_economy_foundation` 建立跨世界统一货币目录、账号钱包、不可变账本、世界/势力财政、托管、发行额度、修炼适配和兑换基础。
- `000053_faction_authority` 建立宗门/势力身份、成员角色、入宗申请与组织财政账户。
- `000054_faction_bounty_tasks` 建立宗门悬赏、预算托管、成员捐献流水与多人接取；扩展财政流水类型。
- `000055_bounty_task_settlement` 增加财政冻结余额流水字段、结算幂等凭证，并支持悬赏预算原子支付和未使用额度退回。
- `000008_character_death_and_respawn` 增加角色死亡事件与复活记录。
- `000009_reincarnation_history` 增加肉身轮回历史。
- `000010_soul_progression` 增加跨世保留的灵魂境界、灵魂经验与幂等奖励事件。
- `000011_soul_trials` 增加数据驱动的冥界灵魂试炼定义与每个灵魂的任务进度。
- `000012_world_npcs` 增加世界NPC目录、交互配置与酆都五名引导NPC。
- `000013_soul_memories` 增加跨世前世记忆档案；轮回时自动保存上一世摘要，魂将境（灵魂境界序号 5）后才向玩家开放具体内容。
- `000014_soul_fate_ledger` 增加灵魂因果账簿，以不可变事件记录功德/业力变化；酆都游祟讨伐每次增加 1 点功德。
- `000015_npc_fate_choices` 增加每个灵魂对每名 NPC 只能作出一次的因果抉择记录，并为冥府判官配置善恶分支；选项效果由中心服规则计算。
- `000016_reincarnation_fate_imprint` 在轮回事件中保存轮回当刻的功德、业力与命格快照，供后续出生路线和世界反应使用。
- `000017_character_fate_traits` 为新肉身写入不可变命格特性，供 NPC 态度、隐藏遭遇与出生路线规则读取。
- `000018_npc_fate_reactions` 为冥府判官与孟婆配置四种命格专属对白，由中心服读取当前肉身命格并返回反应文本。
- `000019_hidden_fate_encounters` 增加灵魂级一次性命格奇遇领取记录，并为孟婆配置四种命格对应的隐藏奇遇。奖励在同一事务中写入因果簿。
- `000020_reincarnation_birth_routes` 增加数据驱动的轮回出生路线；路线限定种族/命格、目标世界与服务端出生坐标，并将路线描述和出生快照写入不可变轮回档案。
- `000021_birth_route_region_metadata` 为出生路线补充区域说明、危险等级、资源标签、探索点与种族适应性资料，供轮回选择界面展示；不向客户端暴露出生坐标或初始奖励配置。
- `000022_world_exploration_points` 创建服务端权威的世界探索点与灵魂级发现记录；中心服依据角色服务端保存的位置校验距离，并在同一事务中写入幂等发现记录和功德/业力因果账簿。
- `000023_world_exploration_events` 创建数据驱动的区域奇遇与灵魂级一次性领取记录；奇遇必须先发现关联探索点，并可按种族或肉身命格特性限制资格；触发时由中心服验证活跃会话、服务端位置和领取幂等性，并在同一事务中结算功德/业力。
- `000024_underworld_exploration` 为冥界酆都增加鬼门关、忘川河、奈何桥、轮回殿四处服务端权威探索点及对应奇遇，发现记录与奖励仍按灵魂幂等保存。
- `000025_exploration_event_choices` 为区域奇遇增加服务端配置的分支选项；客户端只提交选项 ID，中心服按可信 effect_key 计算功德/业力，并将所选 choice_id 与灵魂级领取记录一同保存，继续使用唯一约束防止重复选择。
- `000026_exploration_causal_followups` 为区域奇遇增加灵魂级前置事件/分支条件；以已领取事件的 choice_id 解锁后续探索点与奇遇，首条链路为收取引魂灯火后发现魂灯旧影。
- `000027_soul_essence_foundation` 建立跨轮回保留的灵魂核心属性、吞噬容量与能量统计、普通游魂/兽魂/战魂类别目录，以及按灵魂幂等的吞噬审计流水；为已有灵魂补齐初始魂体属性。后续结算逻辑在此基础上逐步扩展，属性吞噬成长进度由迁移 000032 管理。
- `000028_soul_inheritance_essences` 建立灵魂级力量/体质/敏捷/灵力/气血五项来世资质；扩展魂质类别的稀有度与固定属性映射，并为无相灵魄记录玩家选择的属性和分配时间。
- `000029_reincarnation_inheritance_snapshots` 为每一世新肉身保存不可变的灵魂资质、吞噬成长阶段、种族成长权重与最终出生属性加成快照。
- `000030_soul_mutation_records` 为每次成功吞噬保存唯一魂质异变记录，包含异变类型、稀有度、来世属性和加成值。
- `000031_soul_fusion_records` 保存每个灵魂唯一的魂质融合结果；原始异变记录永久保留，融合奖励由服务端固定配方写入五维来世资质。
- `000032_soul_absorption_attribute_progress` 建立五项资质各自的吞噬成长进度；同属性魂质累计吞噬门槛为 3、9、21、45、93、189、381、765、1533、3069 次，每达到一个门槛获得 1 点，普通吞噬最多贡献 10 点；随机异变每项属性最多贡献 2 点；所有来源的单项来世资质统一封顶 20 点，并为已有吞噬记录回填历史进度。
- `000033_soul_absorption_quality_tiers` 为魂质目录增加服务端配置的品质阶层与成长进度倍率（普通/精英/远古/上古分别为 ×1/×2/×4/×8）；首批为炽战残魂配置精英、远古、上古变体，倍率写入吞噬流水并在同一事务中推进多个成长档位。
- `000034_wangchuan_echo_soul` 增加忘川回音灵识相关魂体与灵魂奇遇配置。
- `000035_ancient_battlefield_god_soul` 增加古战场上古战神残魂配置与吞噬资格。
- `000036_equipment_sets` 增加装备套装定义及装备与套装的关联字段。
- `000037_qingyun_starter_equipment_set` 配置青云初修六件套。
- `000038_chat_foundation` 创建聊天偏好、好友关系、私聊申请、屏蔽关系和消息持久化基础表；消息保留策略为 30 天。
- `000039_chat_transactional_outbox` 创建聊天事件事务发件箱；每条公开聊天消息与待发布事件在同一 PostgreSQL 事务内提交，后台发布器通过 `FOR UPDATE SKIP LOCKED` 租约领取并在 JetStream PubAck 后标记完成。
- `000040_chat_nearby_instance_scope` 为附近频道增加强制世界实例范围、AOI 接收者快照 JSONB 与实例历史索引；WorldServer 计算 AOI，ChatServer 校验接收者均属于同一活动实例。
- `000041_admin_console_foundation` 建立独立后台用户、角色、权限、会话和操作审计表；种子化超级管理员/运营角色及细粒度权限目录，不创建默认管理员密码。
- `000042_detach_soul_account_identity_fk` 移除 Game 灵魂账号 ID 对 Identity 账号表的数据库外键依赖，保持账号身份服务与游戏数据库独立。\n- `000043_game_domain_event_outbox` 建立 Game 领域事件事务发件箱及世界实例、节点心跳、世界会话事件投影触发器。\n- `000044_server_node_admin_control` 为 WorldServer 节点增加管理员运行状态（normal/draining/disabled），并增加 `servers.manage` 权限；draining 停止新玩家接入，disabled 触发在线会话优雅下线。 节点状态由 Game 服务统一执行，WorldServer 心跳不会覆盖管理员维护状态；恢复 normal 时仍要求节点心跳有效。

## 当前迁移顺序

本仓库暂未引入迁移 CLI。全新数据库按编号依次执行：

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000001_initial_schema.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000002_character_progression.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000003_race_bloodline_techniques.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000004_bloodline_awakening_technique_training.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000005_items_inventory_drops.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000006_character_equipment.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000007_item_use_and_starter_catalog.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000008_character_death_and_respawn.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000009_reincarnation_history.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000010_soul_progression.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000011_soul_trials.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000012_world_npcs.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000013_soul_memories.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000014_soul_fate_ledger.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000015_npc_fate_choices.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000016_reincarnation_fate_imprint.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000017_character_fate_traits.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000018_npc_fate_reactions.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000019_hidden_fate_encounters.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000020_reincarnation_birth_routes.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000021_birth_route_region_metadata.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000022_world_exploration_points.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000023_world_exploration_events.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000024_underworld_exploration.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000025_exploration_event_choices.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000026_exploration_causal_followups.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000027_soul_essence_foundation.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000028_soul_inheritance_essences.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000029_reincarnation_inheritance_snapshots.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000030_soul_mutation_records.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000031_soul_fusion_records.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000032_soul_absorption_attribute_progress.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000033_soul_absorption_quality_tiers.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000034_wangchuan_echo_soul.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000035_ancient_battlefield_god_soul.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000036_equipment_sets.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000037_qingyun_starter_equipment_set.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000038_chat_foundation.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000039_chat_transactional_outbox.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000040_chat_nearby_instance_scope.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000041_admin_console_foundation.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000042_detach_soul_account_identity_fk.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000043_game_domain_event_outbox.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000044_server_node_admin_control.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000045_monster_definitions_and_spawn_points.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000046_game_config_revisions.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000047_game_config_revision_reason.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000048_backfill_current_character_projection.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000049_weapon_type_metadata.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000050_admin_operations_query_indexes.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000051_admin_analytics_indexes.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000052_unified_economy_foundation.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000053_faction_authority.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000054_faction_bounty_tasks.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000055_bounty_task_settlement.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000056_bounty_task_refunds.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000057_bounty_character_eligibility.up.sql
```

回滚时按相反顺序执行对应的 `.down.sql`。不要在已运行的生产库上重复执行非幂等迁移；后续接入迁移工具后，应由工具记录每个已应用版本，避免人工重复执行。

- `000052_unified_economy_foundation` 建立跨世界统一货币目录、Identity UUID 账号级钱包、可用/冻结余额、不可变玩家账本、各世界财政账户/财政流水、悬赏托管、货币发行来源与额度策略、修炼适配与消耗配置、官方汇率/市场报价/兑换储备/兑换事件，以及账号逐步解锁跨界经济的记录。凡俗货币不可直接修炼；修炼石可交易并可作为修炼/制造资源。


- `000056_bounty_task_refunds` 增加悬赏取消/到期退款凭证、参与者 cancelled 状态和到期扫描索引。宗主/长老可主动取消并全额退回托管预算；可信 WorldServer 调度器通过 `POST /api/v1/servers/bounties/expire` 批量处理到期任务（`X-World-Server-Key`，limit 1–100，默认 50）。调度器需要由部署环境定期调用；本迁移和 API 不会自行创建定时任务。


- `000057_bounty_character_eligibility` 为悬赏增加最低角色等级要求。接取时后端读取账号当前角色、存活状态、所在世界、角色等级和真实修炼境界；不接受客户端自报角色或境界。新增 `POST /api/v1/bounties/{taskID}/leave`，参与者可在任务结束/到期前主动退出并释放名额；已退出成员可在任务仍开放时重新接取。
