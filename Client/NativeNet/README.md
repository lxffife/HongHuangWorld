# Godot 原生 ENet 客户端扩展

本目录构建一个 Godot 4.3 GDExtension，封装 ENet 客户端传输，使 Godot 可以发送/接收项目自定义的 HHW1 帧。它不是 Godot MultiplayerAPI 的 RPC 协议。

## 推荐方式：GitHub Actions 自动编译

日常开发和测试不需要在 Windows 电脑安装 Visual Studio、CMake 或 C++ 编译工具。

仓库工作流：`.github/workflows/native-net-build.yml`

工作流会自动构建三个平台：

| 平台 | 产物 | 用途 |
| --- | --- | --- |
| Windows x64 | `honghuang_native_net.dll` | Windows Godot 客户端 |
| Linux x86_64 | `libhonghuang_native_net.so` | x86_64 Linux |
| Linux ARM64 | `libhonghuang_native_net.so` | 64 位树莓派 / ARM Linux |

### 下载测试构建

1. 打开 GitHub 仓库的 **Actions**。
2. 选择 **Godot NativeNet Builds** 工作流。
3. 打开成功完成的运行记录。
4. 在页面底部 **Artifacts** 区域下载对应平台的压缩包。
5. 解压后，将 DLL 或 SO 放入 `Client/HongHuangClient/bin/`，不要改文件名。

PR 指向 `develop` 时会自动构建；也可以在 Actions 页面点击 **Run workflow** 手动构建。构建附件默认保留 30 天。

### 发布正式版本

推送形如 `native-net-v1.0.0` 的标签后，工作流会构建三个平台，并自动创建 GitHub Release，附上三个平台的 ZIP 包。

例如：

```bash
git tag native-net-v1.0.0
git push origin native-net-v1.0.0
```

ARM64 产物在 Ubuntu 22.04 ARM64 容器中编译，以降低对较新 glibc 的依赖，更适合 Raspberry Pi OS Bookworm 一类系统。仍需在目标树莓派上实际验证 Godot 版本、系统架构和动态库依赖。

## 本地手动编译（可选）

只有在开发原生 C++ 代码且希望本地调试时，才需要安装编译环境。

### Windows

前置条件：Git、CMake 3.24+、Visual Studio 2022 C++ 桌面开发工具。

```powershell
powershell -ExecutionPolicy Bypass -File .\Client\NativeNet\build_windows.ps1
```

### Linux

安装 CMake 3.24+、Git、Python 3 和 C/C++ 编译工具后运行：

```bash
bash Client/NativeNet/build_linux.sh
```

## 构建依赖

CMake 会自动拉取固定版本 godot-cpp（Godot 4.3）和 ENet 1.3.18。

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

- 扩展支持可靠 channel 0 和不可靠有序 channel 1；服务端每个 ENet packet 对应一个 HHW1 frame。
- 连接成功不代表已通过身份验证；必须收到 ServerWelcome 才算进入世界。
- 心跳定时器和认证后的青云人界场景切换已接入。
- 客户端移动/跳跃意图已发送至 WorldServer，服务器计算位置并广播实体快照；AOI、重连和断线状态持久化尚未实现。
