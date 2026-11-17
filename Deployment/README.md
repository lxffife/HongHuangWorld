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
5. 首次初始化数据库时执行 `.\Deployment\migrate-database.ps1`；脚本会创建迁移账本并按顺序执行尚未应用的迁移（当前共十三个版本，包含灵魂历世档案与前世记忆）；已记录的版本会自动跳过。若数据库已有 `accounts` 表但没有迁移账本，脚本会停止，避免猜测现有数据库版本。
6. 在独立 PowerShell 窗口启动中心服：`.\Deployment\start-backend.ps1`。确认 `http://127.0.0.1:8787/ready` 返回 HTTP 200。
7. 在仓库根目录构建 C++ 世界服务器：`.\Deployment\build-world-server.ps1`。首次运行会通过 vcpkg 安装依赖。
8. 在另一个 PowerShell 窗口启动世界服务器：`.\Deployment\start-world-server.ps1`。日志出现 `WorldServer heartbeat accepted` 后，中心服才会把青云人界实例视为可用。
9. 构建 Godot 原生 ENet 扩展：`powershell -ExecutionPolicy Bypass -File .\Client\NativeNet\build_windows.ps1`；然后用 Godot 4.3 打开 `Client/HongHuangClient/project.godot` 并运行项目。

本机测试时 `WORLD_SERVER_ADVERTISE_HOST=127.0.0.1`；跨设备联机时改为运行 WorldServer 的局域网 IP，并在 Windows 防火墙放行 `WORLD_SERVER_UDP_PORT` 对应的 UDP 入站端口。中心服 API 地址和游戏服务器广告地址是两回事：前者是 HTTP，后者是 ENet UDP。

如果客户端显示“没有可用世界服务器”，先检查 WorldServer 窗口是否持续打印心跳成功、`WORLD_SERVER_API_KEY` 是否与中心服一致、`WORLD_ID` 是否为 `qingyun_human`，以及 PostgreSQL 中节点心跳是否在最近 30 秒内。
