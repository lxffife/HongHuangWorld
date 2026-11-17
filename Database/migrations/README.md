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
```

回滚时按相反顺序执行对应的 `.down.sql`。不要在已运行的生产库上重复执行非幂等迁移；后续接入迁移工具后，应由工具记录每个已应用版本，避免人工重复执行。
