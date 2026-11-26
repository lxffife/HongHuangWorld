# 洪荒世界 AI 后台测试玩家

这是一个独立的无窗口 Godot 客户端进程。它使用正式账号、角色、世界入口票据和 ENet 协议进入游戏，不向服务器伪造玩家状态，也不修改你的主账号。

## 环境要求

- Godot 4.6（建议与主客户端相同的小版本）
- 已编译的 `bin/honghuang_native_net.gdextension` 原生 ENet 扩展及其当前平台动态库
- 身份/API 服务和世界服务器正常运行
- 运行 AI 的电脑能够访问 API HTTP 地址和世界服务器 UDP 地址/端口

## 启动

Windows：
```bat
set HH_API_BASE=http://你的API服务器地址:8787
tools\run-ai-test-player.bat
```

Linux：
```sh
export HH_API_BASE=http://你的API服务器地址:8787
./tools/run-ai-test-player.sh
```

也可以直接运行：
```sh
godot --headless --path  --script res://scripts/ai_test_player.gd
```

## 账号与数据

首次启动会创建独立测试账号、魂魄和人族初始角色。账号名会打印在控制台（默认 `hhbot_随机后缀`），密码自动生成并保存在 Godot 的用户数据目录 `user://ai_test_player.cfg`，不会写入 Git 仓库。后续启动复用该账号。

可选环境变量：

- `HH_API_BASE`：API 服务地址，默认 `http://127.0.0.1:8787`
- `HH_AI_BOT_USERNAME`：指定测试账号名；首次运行时生效
- `HH_AI_BOT_PASSWORD`：指定密码（至少 12 个字符）；首次运行时生效
- `HH_AI_BOT_NAME`：游戏角色名，默认“洪荒测试仙”

## 和真人组队

1. 启动 AI 进程，等待日志显示“世界连接成功”。
2. 你的真人角色进入同一个世界实例。
3. 在游戏中邀请控制台显示的测试账号名。
4. AI 每 2 秒检查邀请并自动接受。
5. 加入队伍后，AI 会跟随队伍中的真人玩家；遇到距离不超过 2.6 米且存活的怪物时自动发起普通攻击。

## 当前阶段限制

- 当前为第一版联机陪测：登录/注册、角色准备、进入世界、自动接受邀请、队伍跟随和近身普通攻击。
- 暂不自动复活、拾取、施法或跨地图追踪。
- 如果 AI 无法连接 ENet，请确认主客户端平台对应的原生扩展已编译，并确认 UDP 端口可从运行 AI 的电脑访问。
- 停止方式：在运行窗口按 Ctrl+C（Linux）或关闭命令窗口（Windows）。
