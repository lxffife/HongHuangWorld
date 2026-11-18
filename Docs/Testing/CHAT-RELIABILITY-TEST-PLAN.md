# 聊天可靠性本机验收计划（P0-E）

本文用于在开发机验证附近聊天与游戏事件投递隔离。测试使用本机假 ChatServer，不访问生产服务，不要求 GitHub Actions。

## 1. 自动化单元测试

在 WorldServer 构建目录执行：

```sh
cmake -S GameServer/WorldServer -B build/worldserver -DBUILD_TESTING=ON
cmake --build build/worldserver --target chat_delivery_policy_test durable_outbox_test
ctest --test-dir build/worldserver --output-on-failure
```

新增 `chat_delivery_policy_test` 覆盖 HTTP 状态分类：
- 400/401/403/404/409/422：永久 4xx，进入 dead-letter，等待人工处理。
- 408/425/429：临时错误，继续退避重试。
- 0（连接失败/超时）、3xx、5xx：继续重试。

`durable_outbox_test` 覆盖 SQLite 重启恢复、相同事件 ID 幂等、附近聊天与游戏事件独立 claim、聊天容量配额、死信和人工重试权限。单元测试通过不等于完整网络链路已验收。

### 1.1 假服务 HTTP 故障注入自动化测试

在 Python 3 环境运行（仅标准库）：

```sh
python3 Deployment/scripts/test-chat-fake-server.py
```

该测试会启动独立 loopback 假服务并自动验证。配置 CMake 时若检测到 Python 3，WorldServer 的 CTest 会自动注册 `chat_fake_server_test`；也可单独运行：

```sh
ctest --test-dir build/worldserver -R chat_fake_server_test --output-on-failure
```

该测试覆盖：
- 同一个 `client_message_id` 重复 POST 返回相同模拟消息 ID。
- 401、429、503 能被客户端观察为对应 HTTP 错误。
- 服务端延迟响应可触发客户端超时。
- 服务端主动关闭连接可模拟无 HTTP 响应的网络中断。
- 不支持的管理状态码会被拒绝。

测试结束会关闭它启动的子进程。它不启动 WorldServer，也不修改任何游戏数据库。

## 2. 启动本地假 ChatServer

需要 Python 3，无第三方依赖：

```sh
python3 Deployment/scripts/chat-fake-server.py
```

仅监听 loopback 的 `127.0.0.1:8788`。健康检查：

```sh
curl http://127.0.0.1:8788/health
```

切换模拟响应码（另开终端）。也可以注入延迟或断开连接：

```sh
curl "http://127.0.0.1:8788/__admin/status?code=503"
curl "http://127.0.0.1:8788/__admin/status?code=201"
curl "http://127.0.0.1:8788/__admin/status?code=401"
curl "http://127.0.0.1:8788/__admin/status?code=503&delay_ms=1500"
curl "http://127.0.0.1:8788/__admin/status?code=201&drop=1"
curl http://127.0.0.1:8788/__admin/stats
```

假服务只记录 client_message_id 对应的模拟消息 ID，不保存正文。它不模拟真实鉴权、数据库、AOI 或 WebSocket；只用于测试 WorldServer HTTP 投递与本地 SQLite 发件箱行为。

## 3. WorldServer 端到端步骤

使用独立测试环境和独立 SQLite 文件，确保不会覆盖正在使用的游戏数据：

```sh
export CHAT_SERVER_URL=http://127.0.0.1:8788
export WORLD_SERVER_OUTBOX_PATH=./data/chat-reliability-test.sqlite3
```

Windows PowerShell：

```powershell
$env:CHAT_SERVER_URL = "http://127.0.0.1:8788"
$env:WORLD_SERVER_OUTBOX_PATH = ".\\data\\chat-reliability-test.sqlite3"
```

WorldServer 仍需配置有效的游戏 API、节点密钥和世界实例，并通过真实客户端进入测试世界。确认两个测试角色处于同一实例 AOI。

### 场景 A：ChatServer 暂时不可用

1. 将假服务状态设为 503。
2. 游戏内发送一条附近消息。
3. 使用 `world_outbox_admin <测试数据库路径> stats` 查看队列。
4. 预期：消息进入 SQLite，pending/inflight 按后台重试变化；不会因 503 进入死信。
5. 同时触发一个游戏事件（例如怪物掉落/拾取），确认游戏事件 worker 仍能独立 claim 和处理。

### 场景 B：恢复后最终投递

1. 将假服务状态改为 201。
2. 等待退避时间结束。
3. 预期：附近聊天队列转为 delivered；假服务 `/__admin/stats` 的 unique_messages 增加。
4. 同一条消息不得因网络重试创建多个模拟消息 ID。

### 场景 C：WorldServer 崩溃恢复

1. 先设为 503，发送附近消息，等待其进入 inflight。
2. 正常停止或强制终止测试 WorldServer。
3. 重启同一测试实例，继续使用同一 SQLite 路径。
4. 预期：启动恢复 inflight 为 pending，后台继续投递；恢复为 201 后最终 delivered。
5. 不得丢失已成功写入 SQLite 的消息。

### 场景 D：永久鉴权错误与人工恢复

1. 将假服务状态设为 401，发送附近消息。
2. 预期：该消息进入 dead-letter，错误信息显示 HTTP 401。
3. 将状态恢复为 201。
4. 使用 `world_outbox_admin <测试数据库路径> dead-letters 50` 查看。
5. 使用 `world_outbox_admin <测试数据库路径> retry <event_id>` 人工重试。
6. 预期：原 worker 自动投递，最终 delivered；消息 ID 不变。

### 场景 E：聊天队列满与游戏事件隔离

1. 在独立测试数据库中通过自动化测试构造聊天队列达到配额。
2. 继续 enqueue 游戏奖励/掉落事件。
3. 预期：聊天达到配额不会耗尽为游戏事件预留的容量；游戏 worker 使用 `claim_due_excluding(..., "nearby_chat")` 不会领取聊天事件。
4. ChatServer/NATS 不可用不得阻塞 WorldServer 的移动、战斗主循环。

## 4. 结果记录

每次验收记录：
- Git commit、操作系统、编译器、CMake 版本。
- CTest 通过/失败用例。
- SQLite 队列 stats 前后快照。
- 503 恢复、401 人工重试、进程重启的结果。
- 游戏移动/战斗是否持续响应。
- 假服务 unique_messages 数量与客户端消息 ID 对照。

## 5. 当前边界

- 假服务的 Python 自动化测试只验证模拟 HTTP 端点的响应、幂等键和故障注入能力；仍需连接 WorldServer + 独立测试 SQLite 才能验收真实发件箱重试。
- 本地假服务只验证 WorldServer -> HTTP -> 持久发件箱重试，不代表 ChatServer 的 PostgreSQL/Outbox/JetStream/WebSocket 已端到端验收。
- 真实 ChatServer 的节点鉴权、AOI 快照校验、消息持久化、NATS 故障恢复仍需在隔离测试环境验收。
- 本计划不触发或依赖 GitHub Actions。当前新增测试与脚本尚未在本轮实际运行。
