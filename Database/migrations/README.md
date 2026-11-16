# 数据库迁移约定

- 文件名格式：`NNNNNN_description.up.sql` 与 `.down.sql`。
- 迁移必须可审查、可重复部署；不要在应用启动时自动执行迁移。
- 部署流水线需要维护 schema_migrations 版本记录，执行每个版本前先检查是否已应用。
- 生产环境执行前先备份，并在测试环境验证 up/down。
- `000001_initial_schema` 创建账号、会话、灵魂、肉身角色、世界定义、世界实例、节点注册和世界会话表。
- `000002_character_progression` 创建角色属性、种族目录、种族专属修炼体系、境界阶段、跨种族实力参考映射和幂等奖励流水，并为已有角色补齐默认成长记录。旧角色若没有可识别的种族映射，会暂时归入人族仙道作为兼容默认值。

## 当前迁移顺序

本仓库暂未引入迁移 CLI。全新数据库按编号依次执行：

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000001_initial_schema.up.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f Database/migrations/000002_character_progression.up.sql
```

回滚时按相反顺序执行对应的 `.down.sql`。不要在已运行的生产库上重复执行非幂等迁移；后续接入迁移工具后，应由工具记录每个已应用版本，避免人工重复执行。
