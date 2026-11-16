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

迁移脚本按文件名前缀顺序执行。首次开发可在基础设施健康后按顺序执行：

```bash
docker compose --env-file .env exec -T postgres psql -U honghuang -d honghuang < ../Database/migrations/000001_initial_schema.up.sql
docker compose --env-file .env exec -T postgres psql -U honghuang -d honghuang < ../Database/migrations/000002_character_progression.up.sql
docker compose --env-file .env exec -T postgres psql -U honghuang -d honghuang < ../Database/migrations/000003_race_bloodline_techniques.up.sql
docker compose --env-file .env exec -T postgres psql -U honghuang -d honghuang < ../Database/migrations/000004_bloodline_awakening_technique_training.up.sql
```

生产环境必须使用专门的迁移执行器记录已应用版本，不要重复执行初始迁移。

## 世界服务器注册与心跳

WorldServer 启动后会立即调用中心服 `POST /api/v1/servers/heartbeat`，随后每 10 秒更新一次节点和世界实例状态；关闭时上报 `draining`。只有心跳成功、世界实例状态为 `ready` 且最近 30 秒内有心跳，中心服才会向客户端签发该节点的世界入口票据。

本机单机测试请保留以下配置：
- `BACKEND_URL=http://127.0.0.1:8787`
- `WORLD_SERVER_ADVERTISE_HOST=127.0.0.1`（客户端实际连接地址，不能填 `0.0.0.0`）
- `WORLD_ID=qingyun_human`
- `WORLD_SERVER_UDP_PORT=7777`
- `WORLD_SERVER_NODE_KEY` 与 `WORLD_SERVER_INSTANCE_KEY` 在同一测试节点保持稳定且唯一
- `WORLD_SERVER_API_KEY` 必须与 Go 后端使用的值完全一致，不能放入客户端配置

如果客户端和世界服务器不在同一台机器，需把 `WORLD_SERVER_ADVERTISE_HOST` 改为客户端可访问的服务器 IP，并开放对应 UDP 端口。
