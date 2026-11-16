# Go 业务后端

P0 采用模块化单体，按领域划分 internal 包。HTTP 层只负责协议适配和输入校验；业务规则放在领域服务；数据库访问通过 repository 层封装。

首批 API：

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/account/me`
- `POST /api/v1/souls`
- `GET /api/v1/souls/current`
- `GET /api/v1/worlds`
- `POST /api/v1/worlds/enter`
- `POST /api/v1/servers/heartbeat`
- `GET /health`

配置从环境变量读取。日志输出到 stdout，采用结构化日志。不得在日志中输出密码、访问令牌或完整连接票据。
