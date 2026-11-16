# Godot 原生 ENet 客户端扩展

本目录构建一个 Godot 4.3 GDExtension，封装 ENet 客户端传输，使 Godot 可以发送/接收项目自定义的 HHW1 帧。它不是 Godot MultiplayerAPI 的 RPC 协议。

## Windows 开发机

前置条件：Git、CMake 3.24+、Visual Studio 2022 C++ 桌面开发工具。

在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Client\NativeNet\build_windows.ps1
```

脚本会自动拉取固定版本 godot-cpp（Godot 4.3）和 ENet 1.3.18，并将 DLL 输出到：

`Client/HongHuangClient/bin/honghuang_native_net.dll`

## Linux

安装 CMake、Git、Python 3 和 C/C++ 编译工具后运行：

```bash
bash Client/NativeNet/build_linux.sh
```

动态库输出到客户端 bin 目录。

## GDScript API

扩展注册 `EnetClient` Node：

- `connect_to_host(host: String, port: int) -> Error`
- `send_frame(frame: PackedByteArray, reliable: bool = true) -> Error`（可靠消息使用 channel 0；移动输入等高频消息使用不可靠有序 channel 1）
- `disconnect_from_host()`
- `is_connected_to_server() -> bool`

信号：

- `connected`
- `connection_failed`
- `disconnected`
- `frame_received(frame: PackedByteArray)`

`HHWorldNetwork` 封装连接后发送 ClientHello，并解析 ServerWelcome / ServerReject。

## 重要说明

- 当前扩展只处理可靠 channel 0 的单帧消息；服务端每个 ENet packet 对应一个 HHW1 frame。
- 连接成功不代表已通过身份验证；必须收到 ServerWelcome 才算进入世界。
- 心跳定时器和认证后的青云人界场景切换已接入。
- 当前移动仍是客户端本地原型；服务器权威移动输入、实体快照、AOI、重连和断线状态持久化尚未实现。
- 首次配置时 CMake 需要联网拉取 godot-cpp 与 ENet 源码。


CI 会缓存 Godot C++ binding 的 CMake 构建目录，避免每次提交都从头编译完整的 Godot 4.3 绑定。功能分支只通过 PR 工作流运行检查，避免 push 与 pull_request 同时重复启动同一套原生编译。
