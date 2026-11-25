# Godot 原生 ENet 客户端扩展

本目录构建 honghuang_native_net GDExtension，封装 ENet 客户端传输，发送和接收项目自定义 HHW1 帧。它不是 Godot MultiplayerAPI 的 RPC 协议。

## 本地构建

构建产物直接输出到本仓库的 bin/，与 bin/honghuang_native_net.gdextension 对应。

### Windows x64

前置条件：Git、CMake 3.24+、Visual Studio 2022 C++ 桌面开发工具。

在仓库根目录运行：

    powershell -ExecutionPolicy Bypass -File .\NativeNet\build_windows.ps1

成功后应生成 bin/honghuang_native_net.dll。

### Linux x86_64

安装 CMake 3.24+、Git、Python 3 和 C/C++ 编译工具，在仓库根目录运行：

    bash NativeNet/build_linux.sh

成功后应生成 bin/libhonghuang_native_net.so。

## 构建依赖与版本

CMake 固定拉取 godot-cpp 的 godot-4.3-stable 和 ENet v1.3.18。扩展描述文件的最低兼容版本为 Godot 4.3。

project.godot 当前声明的项目特性版本为 4.6。若使用 Godot 4.6 编辑器，请在更新 godot-cpp 构建链并重新编译 DLL/SO 后再做联机测试；不要把旧版本二进制当作已验证兼容。

## GDScript API

扩展注册 EnetClient Node：

- connect_to_host(host: String, port: int) -> Error
- send_frame(frame: PackedByteArray, reliable: bool = true) -> Error
- disconnect_from_host()
- is_connected_to_server() -> bool

信号：

- connected
- connection_failed
- disconnected
- frame_received(frame: PackedByteArray)

可靠消息使用 channel 0；移动输入等高频消息使用不可靠有序 channel 1。
