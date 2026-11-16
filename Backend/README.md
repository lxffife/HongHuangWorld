# Go 业务后端

P0 采用模块化单体，按领域划分 internal 包。HTTP 层负责协议适配和输入校验；业务规则放在领域服务；数据库访问通过 repository 层封装。

## 当前已实现

- `GET /health`：进程存活检查，不依赖数据库。
- `GET /ready`：检查 PostgreSQL 连接，数据库不可用时返回 503。
- PostgreSQL 连接池通过 `DATABASE_URL` 配置，启动时执行 Ping；连接失败则拒绝启动。
- JSON 结构化日志和优雅关闭。

## 计划中的首批 API

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/account/me`
- `POST /api/v1/souls`
- `GET /api/v1/souls/current`
- `GET /api/v1/worlds`
- `POST /api/v1/worlds/enter`
- `POST /api/v1/servers/heartbeat`

## 本地运行

1. 按 `Deployment/README.md` 启动 PostgreSQL。
2. 执行 `Database/migrations/000001_initial_schema.up.sql`。
3. 在 `Deployment/.env` 配置 `DATABASE_URL` 和 `HTTP_ADDR`。
4. Windows PowerShell 执行 `../Deployment/start-backend.ps1`；或在本目录执行 `go test ./...`、`go run ./cmd/api`（需先设置环境变量）。

密码只保存安全哈希，不保存明文。日志不得输出密码、访问令牌或完整连接票据。
