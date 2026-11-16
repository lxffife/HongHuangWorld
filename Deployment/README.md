# 本地部署

本地开发目标是 Windows PC，基础服务通过 Docker Compose 启动。建议提供：

- `start-infra.bat`：启动 PostgreSQL、Redis、NATS。
- `start-backend.bat`：启动 Go API。
- `start-world.bat`：启动 C++ WorldServer。
- `start-client.bat`：启动 Godot 客户端。
- `stop-all.bat`：停止本地服务。

同时提供 Linux shell 脚本。所有脚本需检查依赖、输出明确日志和错误码；不得静默吞掉启动失败。配置模板提交 `.env.example`，真实 `.env` 加入 gitignore。
