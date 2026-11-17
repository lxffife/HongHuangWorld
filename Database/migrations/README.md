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
```

回滚时按相反顺序执行对应的 `.down.sql`。不要在已运行的生产库上重复执行非幂等迁移；后续接入迁移工具后，应由工具记录每个已应用版本，避免人工重复执行。
