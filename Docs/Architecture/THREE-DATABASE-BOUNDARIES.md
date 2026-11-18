# 三数据库架构与安全迁移计划

## 目标架构

洪荒万界采用三个独立 PostgreSQL 数据库、三个独立数据所有权边界：

| 数据库 | 建议名称 | 唯一数据所有者 | 核心数据 |
|---|---|---|---|
| Identity | honghuang_identity | Identity Service | 玩家账号、用户名/邮箱唯一性、密码哈希、账号状态、登录会话、Token 哈希、设备会话、凭据安全审计 |
| Game | honghuang_game | Game API / 游戏域服务 | 灵魂、角色、世界定义/实例、服务器注册、世界会话、背包、装备、修炼、轮回、游戏进度 |
| Chat | honghuang_chat | ChatServer | 聊天消息、频道、会话、好友、私聊申请、屏蔽、回执、聊天偏好、聊天事务 Outbox |

三个数据库使用不同数据库角色。运行时服务只获得自己数据库的读写权限；不得通过共享超级用户连接跨库读写。初期可以同一个 PostgreSQL 实例承载三个独立 database，之后再按容量和故障隔离需要迁移到不同实例。

## 服务职责和 API

### Identity Service（新增独立进程）
- 负责注册、登录、登出/撤销会话、当前账号资料、Token 验证、账号锁定/禁用。
- 对外提供 HTTPS/内网 API；客户端只持有访问凭据，不接触数据库凭据或服务间密钥。
- 建议 API：POST /api/v1/auth/register、POST /api/v1/auth/login、POST /api/v1/auth/logout、GET /api/v1/auth/introspect、GET /api/v1/account/me。
- 内部服务使用独立服务凭据调用 introspection；必须校验服务身份、超时、响应大小和错误状态。不得把客户端 Bearer Token 当作服务身份。
- 密码只保存强哈希；Token 只保存哈希；登录/注册限流、审计和统一错误响应属于 Identity 的责任。

### Game API
- 使用 DATABASE_URL 连接 Game 数据库。
- 通过 Identity API 验证用户身份；游戏库只保存 Identity 返回的稳定 account_id UUID，不保存密码或登录 Token。
- souls.account_id 等字段在跨数据库后不能再建立指向 Identity 库的 PostgreSQL 外键。使用应用层校验和本地索引/缓存；禁止跨库强事务。
- 角色、世界会话、游戏进度仍由 Game API/WorldServer 负责。

### ChatServer
- 使用 CHAT_DATABASE_URL 连接 Chat 数据库。
- 通过 Identity API 验证用户 Token；不得读取 Identity 数据库的 accounts 或 account_sessions。
- 角色、世界和在线状态不能通过查询 Game 数据库获得；改由 Game API 内部接口或可靠事件投影提供必要的最小数据。
- Chat 故障不能阻塞游戏 tick；Identity 短时不可用时，已验证会话可按明确的短期缓存策略工作，不能无限期接受过期凭据。

## 连接配置（目标）

示意配置如下，尚不代表当前版本已经支持这些变量：

    IDENTITY_DATABASE_URL=postgres://identity_user:<secret>@127.0.0.1:5432/honghuang_identity
    IDENTITY_HTTP_ADDR=127.0.0.1:8789
    IDENTITY_INTERNAL_API_KEY=<独立的服务间密钥>
    DATABASE_URL=postgres://game_user:<secret>@127.0.0.1:5432/honghuang_game
    IDENTITY_API_BASE=http://127.0.0.1:8789
    IDENTITY_SERVICE_TOKEN=<Game API 专用服务凭据>
    CHAT_DATABASE_URL=postgres://chat_user:<secret>@127.0.0.1:5432/honghuang_chat
    CHAT_HTTP_ADDR=:8788
    IDENTITY_API_BASE=http://127.0.0.1:8789
    IDENTITY_SERVICE_TOKEN=<ChatServer 专用服务凭据>

不得把示例密钥用于生产环境。

## 现状与重要依赖

- Backend/internal/auth 在 Game API 中直接查询 accounts、account_sessions。
- Backend/cmd/chat 使用 CHAT_DATABASE_URL，但 NewChatRouter 仍在 Chat 数据库中调用 auth.NewService(db) 验证账号会话。
- Database/migrations/000001_initial_schema.up.sql 同时创建 accounts、account_sessions、souls，并建立 souls.account_id -> accounts.id 外键。
- 聊天路由和聊天业务还会校验角色、世界实例、WorldServer 节点及会话归属；这些数据属于 Game 域，必须先通过内部 API/事件投影替代直接跨域 SQL。
- 因此，不能现在就把两个连接串改成不同库名，也不能把账号表直接从现有数据库删除。直接切换会导致登录、角色查询、聊天认证或附近频道校验失败。

## 迁移阶段与验收门槛

### 阶段 0：盘点和备份
1. 盘点所有 SQL、外键、事务和服务对 accounts、account_sessions、account_id、角色/世界在线表的依赖。
2. 记录当前数据库迁移版本、表数量和数据量；对现有数据库做可恢复的逻辑备份并验证备份可读。
3. 确认当前部署配置来源（树莓派默认 /etc/honghuang-world.env），生成独立配置备份；不在日志或聊天中输出密码。
4. 不删除旧表，不重置玩家账号，不自动执行生产迁移。

### 阶段 1：Identity Service
1. 将账号 schema 和认证逻辑迁移到 Identity 专属 migration 目录与独立进程。
2. 保留现有注册/登录响应契约，新增 introspection/logout；Game API 与 ChatServer 改用受服务认证保护的 Identity 客户端。
3. 对 token 撤销、账号禁用、服务超时、Identity 不可用进行单元/集成测试。
4. 在迁移窗口同步旧账号和 session 数据；双写/只读兼容必须有明确截止点和回滚办法。

### 阶段 2：Game 数据库解耦
1. souls.account_id 等跨域引用改为普通 UUID，不再保留跨库外键。
2. 检查账号级唯一性和授权规则，改为 Identity API 或受控事件投影验证。
3. Game API 启动只依赖 Game DB；认证依赖通过明确的降级策略隔离。

### 阶段 3：Chat 数据库解耦
1. 聊天专属表迁移到 Chat DB，保留消息 ID、时间戳、幂等键和 30 天保留规则。
2. 角色展示资料、世界实例和在线路由通过 Game 内部 API/事件投影获得；Chat DB 不复制游戏权威状态。
3. 移除 ChatServer 对 Game DB 表的直接 SQL 依赖。

### 阶段 4：切换、验证和清理
- 三个数据库分别使用不同 database、不同账号和最小权限。
- 分别停止 Identity、Game、Chat，验证故障域和恢复行为。
- 验证旧玩家可登录、Token 撤销有效、角色/轮回/世界进入正常、聊天认证/历史/跨界/附近投递正常。
- 只有在数据核对、备份恢复演练和回滚演练完成后，才清理旧库中的账号/聊天残留表。

## 不可违反的迁移原则
- 绝不对现有生产数据执行 DROP/重建或覆盖式初始化。
- 绝不把 DATABASE_URL、CHAT_DATABASE_URL、IDENTITY_DATABASE_URL 留成同一个数据库作为“已拆分”。
- 不在 Game/Chat 数据库保存密码哈希或登录 Token。
- 不用跨库外键、跨库事务或共享数据库超级用户绕过服务边界。
- 任何数据搬迁必须可重复、可核对、有备份、有回滚；迁移脚本默认 dry-run 或显式确认。
- 本文档提交不代表运行时拆分已经完成；在每个阶段验收通过前，现有连接方式保持不变。

## 已落地的迁移代码（尚未在生产执行）

- `Backend/internal/auth/http_client.go`：Identity HTTP 客户端，实现注册、登录、Token introspection；服务端调用带独立服务凭据头。
- Game API 与 ChatServer 的认证处理器改为依赖 `auth.Provider` 接口；设置 `IDENTITY_API_BASE` 后走 Identity HTTP API，未设置时仍保留旧数据库认证作为迁移回退。
- `Backend/internal/auth/http_client_test.go`：新增 HTTP 客户端认证、401 与登录响应测试（尚未实际运行）。
- `Deployment/raspberry-pi/07-build.sh`：同时构建 `honghuang-identity`。
- `Deployment/raspberry-pi/08-install-services.sh`：新增 Identity systemd 服务安装、启动和 readiness 检查。
- `Deployment/raspberry-pi/08-copy-identity-data.sh`：要求显式确认，目标账号表必须为空；通过单事务复制账号与会话数据，并核对行数。复制密码哈希与 Token 哈希，不复制明文凭据。
- `Database/migrations/000042_detach_soul_account_identity_fk.up.sql`：在切换 Identity 前，解除 Game souls 对旧本地 accounts 表的外键依赖；旧账号表暂时保留，不删除。
- `Deployment/raspberry-pi/04-configure.sh` 与 `.env.example` 已为全新安装增加 Identity API 客户端变量。现有树莓派环境文件不会自动更新。

### 生产切换顺序（不要跳步）

1. 备份当前 Game 数据库，并确认可恢复。
2. 更新代码和构建；在 Identity 数据库执行 `07-migrate-identity.sh`。
3. 确认 Identity 账号/会话表为空后，执行 `CONFIRM_IDENTITY_DATA_COPY=YES bash Deployment/raspberry-pi/08-copy-identity-data.sh`；检查源/目标行数一致。
4. 在 Game 数据库应用 migration 000042，之后新注册账号才能创建 souls 而不要求旧 accounts 表存在同一账号行。
5. 在现有 `/etc/honghuang-world.env` 中配置 `IDENTITY_API_BASE`、`IDENTITY_SERVICE_TOKEN`，并保证其值与 Identity 服务端 `IDENTITY_INTERNAL_API_KEY` 一致。不要把密钥发到聊天或日志。
6. 启动并检查 Identity readiness，再启动 Game API；验证旧账号登录、Token、创建灵魂、角色与轮回流程。
7. ChatServer 仍需独立迁移聊天 schema 和 Game 域角色/世界状态依赖；在完成前，不要把 `CHAT_DATABASE_URL` 指向空的 Chat DB。
8. 所有验收通过后再做聊天数据搬迁与旧表清理。当前脚本不会自动执行生产迁移，也不会删除旧数据。
