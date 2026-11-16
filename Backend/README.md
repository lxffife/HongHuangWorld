# Go 业务后端

P0 采用模块化单体，按领域划分 internal 包。HTTP 层负责协议适配和输入校验；业务规则放在领域服务；数据库访问通过领域服务封装。

## 当前已实现

- `GET /health`：进程存活检查，不依赖数据库。
- `GET /ready`：检查 PostgreSQL 连接，数据库不可用时返回 503。
- `POST /api/v1/auth/register`：创建账号并签发 30 天 Bearer 会话令牌。
- `POST /api/v1/auth/login`：验证账号密码并创建会话。
- `GET /api/v1/account/me`：通过 Bearer 令牌读取当前账号。
- `POST /api/v1/souls`：为当前账号创建唯一灵魂档案。
- `GET /api/v1/souls/current`：读取当前账号的灵魂档案。
- `GET /api/v1/worlds`：读取已启用的世界目录。
- `POST /api/v1/characters/first-life`：为当前灵魂创建第一世肉身角色，并在同一事务中初始化基础属性和修炼进度。
- `GET /api/v1/characters/current`：读取当前肉身角色。
- `GET /api/v1/characters/current/status`：读取当前角色属性、经验、修为和境界信息。
- `POST /api/v1/servers/heartbeat`：可信世界服务器通过 `X-World-Server-Key` 注册/更新节点和世界实例状态。
- `POST /api/v1/worlds/enter`：当前角色申请世界入口，返回服务器地址和 60 秒一次性票据。
- `POST /api/v1/servers/tickets/redeem`：世界服务器校验并兑换一次性票据，获取角色初始快照并创建世界会话。
- PostgreSQL 连接池通过 `DATABASE_URL` 配置，启动时执行 Ping；连接失败则拒绝启动。
- JSON 结构化日志和优雅关闭。

## 角色成长数据

`000002_character_progression` 迁移建立角色属性、修炼进度和境界配置表。初始属性由服务端数据库默认值创建；境界目录采用数据驱动配置，当前包含炼气、筑基、金丹、元婴、化神、炼虚、合体、大乘、渡劫九个境界。角色状态接口当前只读，客户端不能直接修改属性、经验或修为。

## 尚待完成

- 服务端权威属性计算、属性点分配和升级规则。
- 修炼/经验来源、境界突破条件、突破失败与奖励规则。
- 服务器心跳过期后的自动摘除与后台监控。
- 服务器票据兑换后的断线清理、快照保存与重连恢复。
- 登录限流、邮箱验证、密码重置和主动注销。
- Redis/NATS 实际业务接入与服务端 API Key 轮换。

## 本地运行

1. 按 `Deployment/README.md` 启动 PostgreSQL。
2. 按编号执行 `Database/migrations/` 中全部 `.up.sql` 迁移；当前需要依次执行 `000001` 和 `000002`。
3. 在 `Deployment/.env` 配置 `DATABASE_URL` 和 `HTTP_ADDR`。
4. Windows PowerShell 执行 `../Deployment/start-backend.ps1`；或在本目录执行 `go test ./...`、`go run ./cmd/api`（需先设置环境变量）。

密码使用 bcrypt 哈希后保存，不保存明文；会话令牌使用高熵随机值，数据库只保存 SHA-256 摘要。当前注册密码长度要求 12–72 字节，用户名为 3–32 位字母/数字/下划线。日志不得输出密码、访问令牌或完整连接票据。每个账号当前只允许创建一个主灵魂档案；第一世角色创建使用数据库事务并锁定灵魂行，避免重复创建；轮回时会为同一灵魂创建新的肉身角色，而不是覆盖灵魂。登录限流、邮箱验证、密码重置和主动注销将在后续安全迭代补齐。世界服务器心跳密钥通过 `WORLD_SERVER_API_KEY` 配置；生产环境必须使用随机长密钥，并通过安全配置渠道分发给节点。当前心跳统计按节点上报，P0 暂按每个节点一个活动实例管理。
