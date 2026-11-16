# 本地部署

## 基础设施

1. 安装 Docker Desktop（Windows）或 Docker Engine + Compose（Linux）。
2. 在本目录复制 `.env.example` 为 `.env`，将两个示例密码替换为随机长密码。
3. Windows 执行 `start-infra.bat`；Linux/macOS 执行 `docker compose --env-file .env up -d`。
4. 使用 `docker compose --env-file .env ps` 查看健康状态。
5. 停止服务执行 `stop-infra.bat` 或 `docker compose --env-file .env stop`。停止不会删除持久化数据卷。

## 服务端口

- PostgreSQL：5432
- Redis：6379（启用密码）
- NATS：4222；监控端口 8222 仅供本地开发检查

## 数据库迁移

迁移脚本按文件名前缀顺序执行。P0 初始结构位于 `../Database/migrations/000001_initial_schema.up.sql`。首次开发可在基础设施健康后手动执行：

```bash
docker compose --env-file .env exec -T postgres psql -U honghuang -d honghuang < ../Database/migrations/000001_initial_schema.up.sql
```

生产环境必须使用专门的迁移执行器记录已应用版本，不要重复执行初始迁移。
