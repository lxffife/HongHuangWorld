# Godot 客户端

使用 Godot 4.3，GDScript 负责界面与游戏逻辑，GDExtension + ENet 负责与独立 C++ 世界服通信。

## 当前客户端流程

1. 输入中心服 API 地址，默认 `http://127.0.0.1:8787`。
2. 账号登录。
3. 自动读取灵魂档案；不存在时创建灵魂档案。
4. 读取世界列表；首次进入时创建第一世角色。
5. 调用中心服申请 60 秒有效的一次性世界入口票据。
6. 通过原生 ENet 扩展连接世界服，发送 ClientHello。
7. 校验 ServerWelcome / ServerReject；成功后每 10 秒发送一次心跳。

## 构建原生网络扩展

请先构建扩展，具体步骤见 [NativeNet README](../NativeNet/README.md)。

Windows 开发机在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Client\NativeNet\build_windows.ps1
```

然后使用 Godot 4.3 打开本目录中的 `project.godot`。确保 `bin/honghuang_native_net.dll` 已生成。

## 服务端前置条件

- 启动中心服 API。
- 启动已注册、心跳新鲜且状态为 ready 的 WorldServer 节点。
- 确保角色所在世界存在 ready 的 world instance。
- 客户端网络必须能够访问中心服 HTTP 地址和世界服 UDP 地址。

如果没有可用世界服，申请入口时中心服会返回 503；这是服务部署状态，不是客户端登录故障。

## 当前边界

- 已实现：登录、灵魂档案初始化、世界列表、第一世角色创建、入口票据申请。
- 已实现：Godot 原生 ENet 连接、ClientHello、ServerWelcome / ServerReject 解析和心跳。
- 尚未实现：玩家实体场景、服务器权威移动、EntitySnapshot、AOI、断线持久化与重连。
- 当前收到 ServerWelcome 只代表网络身份握手成功，尚未进入可操作的游戏地图。
- 不要使用 Godot 内置 MultiplayerAPI 直接连接当前 C++ 世界服；它的 RPC wire protocol 与项目自定义帧协议不同。
