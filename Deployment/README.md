# 本地部署

## 基础设施

1. 安装 Docker Desktop（Windows）或 Docker Engine + Compose（Linux）。
2. 在本目录复制 `.env.example` 为 `.env`，将两个示例密码替换为随机长密码。
3. Windows 执行 `start-infra.bat`；Linux/macOS 执行 `docker compose --env-file .env up -d`。
4. 使用 `docker compose --env-file .env ps` 查看健康状态。
5. 停止服务执行 `stop-infra.bat` 或 `docker compose --env-file .env stop`。停止不会删除持久化数据卷。

## 服务端口

- Game API：8787（HTTP_ADDR）
- ChatServer：8788（CHAT_HTTP_ADDR，独立进程）
- Admin API：8790（ADMIN_HTTP_ADDR，独立管理进程）
- PostgreSQL：5432
- Redis：6379（启用密码）
- NATS：4222；监控端口 8222 仅供本地开发检查

## 数据库迁移

迁移脚本按文件名前缀顺序执行。首次开发可在基础设施健康后执行迁移脚本；脚本会按编号应用尚未执行的迁移：

```powershell
.\Deployment\migrate-database.ps1
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


## Windows 本地联机测试启动顺序

所有脚本都从仓库根目录调用，且默认使用同一份 `Deployment/.env`：

1. 安装 Docker Desktop、Go 1.24、CMake 3.24+、Visual Studio 2022 C++ 桌面开发工具、Godot 4.3。
2. 安装 vcpkg，并设置用户环境变量 `VCPKG_ROOT` 指向 vcpkg 根目录。WorldServer 的 `vcpkg.json` 会声明 ENet、libcurl 和 nlohmann-json 依赖。
3. 复制 `Deployment/.env.example` 为 `Deployment/.env`，修改 PostgreSQL/Redis 密码；确保 `DATABASE_URL` 中的 PostgreSQL 密码与 `POSTGRES_PASSWORD` 一致，并将 `WORLD_SERVER_API_KEY` 改为足够长的随机密钥。
4. 启动基础设施：`.\Deployment\start-infra.bat`。
5. 首次初始化数据库时执行 `.\Deployment\migrate-database.ps1`；脚本会创建迁移账本并按顺序执行尚未应用的迁移（当前迁移版本为 000044，包含游戏基础、轮回成长、聊天、后台管理及世界服务器节点管控）；已记录的版本会自动跳过。若数据库已有 `accounts` 表但没有迁移账本，脚本会停止，避免猜测现有数据库版本。
6. 在独立 PowerShell 窗口启动中心服：`.\Deployment\start-backend.ps1`。确认 `http://127.0.0.1:8787/ready` 返回 HTTP 200。
7. 配置后台首次初始化账号：在 Deployment/.env 中设置 ADMIN_BOOTSTRAP_USERNAME、ADMIN_BOOTSTRAP_EMAIL 和唯一的 ADMIN_BOOTSTRAP_PASSWORD（至少 12 位，不要使用示例密码）。首次启动管理 API 时会创建超级管理员；后续重启检测到已有超级管理员后不会重置密码。启动命令：Windows `./Deployment/start-admin-server.ps1`；Linux/macOS `bash Deployment/start-admin-server.sh`。后台 API 默认仅监听本机 127.0.0.1:8790；需要远程访问时应通过 HTTPS 反向代理或 VPN，不要直接暴露管理端口，检查 `http://127.0.0.1:8790/ready`。
8. 在另一个独立 PowerShell 窗口启动聊天服：`.\Deployment\start-chat-server.ps1`。确认 `http://127.0.0.1:8788/ready` 返回 HTTP 200。聊天服必须配置 `CHAT_DATABASE_URL`；开发阶段可与 `DATABASE_URL` 指向同一个数据库，但进程、监听端口和连接池彼此独立。Linux/macOS 在仓库根目录运行 `bash Deployment/start-chat-server.sh`。
9. 在仓库根目录构建 C++ 世界服务器：`.\Deployment\build-world-server.ps1`。首次运行会通过 vcpkg 安装依赖。
10. 在另一个 PowerShell 窗口启动世界服务器：`.\Deployment\start-world-server.ps1`。日志出现 `WorldServer heartbeat accepted` 后，中心服才会把青云人界实例视为可用。
11. 构建 Godot 原生 ENet 扩展：`powershell -ExecutionPolicy Bypass -File .\Client\NativeNet\build_windows.ps1`；然后用 Godot 4.3 打开 `Client/HongHuangClient/project.godot` 并运行项目。

本机测试时 `WORLD_SERVER_ADVERTISE_HOST=127.0.0.1`；跨设备联机时改为运行 WorldServer 的局域网 IP，并在 Windows 防火墙放行 `WORLD_SERVER_UDP_PORT` 对应的 UDP 入站端口。中心服 API 地址和游戏服务器广告地址是两回事：前者是 HTTP，后者是 ENet UDP。

如果客户端显示“没有可用世界服务器”，先检查 WorldServer 窗口是否持续打印心跳成功、`WORLD_SERVER_API_KEY` 是否与中心服一致、`WORLD_ID` 是否为 `qingyun_human`，以及 PostgreSQL 中节点心跳是否在最近 30 秒内。


## 冥界·酆都世界服（与青云人界并行）

复活会把当前肉身的世界归属切换为 `underworld_fengdu`。如果只运行默认的青云人界节点（`WORLD_ID=qingyun_human`），复活后会因没有冥界实例而得到 HTTP 503。需要在同一台 WorldServer 主机上再启动一个独立进程；不要停止青云人界节点。

先确保 `Deployment/.env` 中的 `BACKEND_URL`、`WORLD_SERVER_API_KEY` 和 `WORLD_SERVER_ADVERTISE_HOST` 正确。广告地址必须是客户端可访问的主机 IP。两个节点必须使用不同的节点标识、实例标识、UDP 端口和 Outbox 数据库文件。

Linux（在仓库根目录，单独终端运行）：

```bash
bash Deployment/start-underworld-server.sh
```

Windows（在仓库根目录，单独 PowerShell 窗口运行）：

```powershell
.\\Deployment\\start-underworld-server.ps1
```

冥界节点使用 UDP 7778，青云节点继续使用 UDP 7777。请在 WorldServer 主机防火墙/云安全组放行 UDP 7778。启动日志应出现心跳成功（`WorldServer heartbeat accepted`）；中心服收到心跳后才会把酆都实例标记为 ready。Linux 构建产物路径为 `build/world-server/world_server`，Windows 构建产物路径为 `build\\world-server\\Release\\world_server.exe`。



### 游戏运营配置管理

- `GET /api/v1/admin/game-config/npcs?world_id={world_id}`：需要 `game_config.read`，查询世界 NPC 定义、交互类型、位置、交互半径、对白 JSON 和启用状态。
- `GET /api/v1/admin/game-config/exploration-points?world_id={world_id}`：查询探索点区域、位置、危险等级、功德/业力奖励和启用状态。
- `GET /api/v1/admin/game-config/exploration-events?world_id={world_id}`：查询探索奇遇、关联探索点、资格限制和奖励配置。
- `PATCH /api/v1/admin/game-config/{resource}/{id}/state`：需要 `game_config.manage`，请求体为 `{"enabled":true|false}`；resource 仅允许 `npcs`、`exploration-points`、`exploration-events`。
- 配置数据只由 Game 服务读写；Admin 通过独立的 Game 内部 API 调用，所有状态变更写入 Admin 审计日志。当前阶段先提供查询和启停，奖励数值、对白及坐标编辑后续增加带校验的版本化发布流程。

### 世界与世界实例管理

- `GET /api/v1/admin/worlds`：需要 `worlds.read`，返回世界类型、等级、启用状态、实例数量、可用实例数量和在线会话数。
- `GET /api/v1/admin/worlds/{world_id}/instances`：需要 `worlds.read`，查看该世界的实例、节点地址、心跳、有效状态和会话数量。
- `PATCH /api/v1/admin/worlds/{world_id}/state`：需要 `worlds.manage`，请求体为 `{"enabled":true|false}`。
- 停用世界会在同一 Game 数据库事务中关闭世界入口、将实例置为 draining、把活动会话标记为 saving，并作废未兑换的入口票据；WorldServer 通过既有快照/HTTP 409 链路优雅断开。
- 重新启用只恢复世界定义，不会伪造实例在线状态；实例必须等待 WorldServer 下一次有效心跳才会恢复 ready。

### WorldServer 节点管理

- `GET /api/v1/admin/servers/nodes`：需要 `servers.read` 权限，返回节点地址、UDP 端口、区域、世界实例、容量、心跳、在线会话数、连接中/保存中的会话数和有效状态。
- `PATCH /api/v1/admin/servers/nodes/{node_key}/state`：需要 `servers.manage` 权限，JSON 请求体为 `{"admin_state":"normal|draining|disabled"}`。
- `normal`：恢复正常接入；若心跳已过期，节点和实例仍显示离线，待下一次有效心跳恢复。
- `draining`：停止给该节点签发/兑换新世界入口票据，但不强制断开现有玩家，适用于计划维护。
- `disabled`：节点停止接入新玩家，并将现有 active 会话标记为 `saving`，由 WorldServer 快照链路优雅下线。
- WorldServer 后续心跳不会覆盖管理员设置的 `draining` / `disabled` 状态；解除维护必须由有权限的管理员显式设置为 `normal`。

### 管理后台在线玩家监控

- `GET /api/v1/admin/players/online`：需要管理员 `players.read` 权限。
- Admin 服务通过 `GAME_API_BASE` 和 `GAME_ADMIN_INTERNAL_API_KEY` 调用 Game 内部接口，不跨库读取游戏数据。
- Game 返回当前 `active` 世界会话、账号 ID、角色名称/等级、世界名称，以及 WorldServer 节点地址、区域、状态、容量、当前负载和最近心跳时间。
- 节点最近心跳超过 30 秒时，接口将 `node_status` 标记为 `offline`，避免仅依赖节点上报的 `ready` 状态。
- 在线列表最多返回 500 条；账号 ID 用于与 Identity 账号资料关联，Identity 用户名/邮箱仍由 Identity 服务单独管理。
## 管理后台玩家详情内部接口

管理后台通过 Identity 和 Game 各自的内部 API 聚合玩家详情，不直接跨库查询：
- Identity：`IDENTITY_API_BASE` + `IDENTITY_INTERNAL_API_KEY`，负责账号资料与账号状态。
- Game：`GAME_API_BASE=http://127.0.0.1:8787` + `GAME_ADMIN_INTERNAL_API_KEY`，负责灵魂、历世角色、当前角色和活动世界会话。
- `GAME_ADMIN_INTERNAL_API_KEY` 必须使用独立随机密钥，不得复用 `WORLD_SERVER_API_KEY` 或 Identity 内部密钥。Game API 启动时会检查该配置。
- 管理后台玩家详情：`GET /api/v1/admin/players/{account_id}`，需要 `players.read` 权限。该接口会分别请求 Identity 与 Game 服务。
- 管理后台强制下线：`POST /api/v1/admin/players/{account_id}/disconnect`，需要 `players.ban` 权限。Game 将活动会话标记为 `saving`；WorldServer 下一次周期快照收到 HTTP 409 后断开 ENet 玩家连接、广播离开事件，并提交最终位置/生命值后关闭会话。
- 封禁账号（`PATCH /api/v1/admin/players/{account_id}/status`，status=`locked`）会同时请求 Game 强制下线；若 Game 服务暂时不可用，账号仍会被锁定，接口响应会明确提示断开请求未送达，可稍后重试。
- 强制下线是异步请求，接口返回 HTTP 202 和 `requested_sessions` 数量；实际断开在 WorldServer 下一次周期快照时完成（通常约 1 秒内，受节点负载影响）。

修改 `Deployment/.env.example` 后，请同步更新本机 `Deployment/.env` 中的配置，再分别重启 Game API 与 Admin API。
