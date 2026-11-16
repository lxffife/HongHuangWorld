# Go 业务后端

P0 采用模块化单体，按领域划分 internal 包。HTTP 层负责协议适配和输入校验；业务规则放在领域服务；数据库访问通过 repository 层封装。

## 当前已实现

- `GET /health`：进程存活检查，不依赖数据库。
- `GET /ready`：检查 PostgreSQL 连接，数据库不可用时返回 503。
- `POST /api/v1/auth/register`：创建账号并签发 30 天 Bearer 会话令牌。
- `POST /api/v1/auth/login`：验证账号密码并创建会话。
- `GET /api/v1/account/me`：通过 Bearer 令牌读取当前账号。
- `POST /api/v1/souls`：为当前账号创建唯一灵魂档案。
- `GET /api/v1/souls/current`：读取当前账号的灵魂档案。
- `GET /api/v1/worlds`：读取已启用的世界目录。
- `POST /api/v1/characters/first-life`：为当前灵魂创建第一世肉身角色。
- `GET /api/v1/characters/current`：读取当前肉身角色。
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

密码使用 bcrypt 哈希后保存，不保存明文；会话令牌使用高熵随机值，数据库只保存 SHA-256 摘要。当前注册密码长度要求 12–72 字节，用户名为 3–32 位字母/数字/下划线。日志不得输出密码、访问令牌或完整连接票据。每个账号当前只允许创建一个主灵魂档案；第一世角色创建使用数据库事务并锁定灵魂行，避免重复创建；轮回时会为同一灵魂创建新的肉身角色，而不是覆盖灵魂。登录限流、邮箱验证、密码重置和主动注销将在后续安全迭代补齐。
