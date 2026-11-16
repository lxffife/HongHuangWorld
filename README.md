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
- 已实现：青云人界第三人称测试场景、服务器权威水平移动、基础跳跃/重力、20Hz EntitySnapshot 和远端玩家占位实体。
- 尚未实现：服务端地形碰撞/寻路、AOI、断线持久化与重连。
- 当前收到 ServerWelcome 后进入可操作的程序化测试地图；这不是最终游戏地图或角色美术。
- 不要使用 Godot 内置 MultiplayerAPI 直接连接当前 C++ 世界服；它的 RPC wire protocol 与项目自定义帧协议不同。


## 青云人界客户端原型

通过中心服认证并收到世界服务器的 `ServerWelcome` 后，客户端会切换到 `scenes/World.tscn`。网络节点和角色快照保存在 `HHSession` Autoload 中，不会因登录场景释放而断开连接。

操作：
- WASD：移动
- 空格：跳跃
- 鼠标：旋转第三人称视角
- ESC：释放鼠标；点击窗口重新捕获

当前角色是用于验证镜头、场景和输入的程序化占位模型，不代表最终角色美术。移动和跳跃由客户端发送意图，WorldServer 计算权威位置并广播实体快照。


## 青云人界联机移动原型

- 认证成功后进入程序化第三人称测试场景。
- 客户端每 50ms 发送一次移动/跳跃意图（不直接提交位置）；空格触发跳跃请求。
- 移动输入通过 ENet 不可靠有序通道发送，避免旧输入在网络拥塞时堆积。
- WorldServer 对输入做有限值检查、方向归一化、速度限制和地图边界限制；跳跃、重力和地面高度由服务器计算，并以 20Hz 广播权威实体快照。
- 客户端根据快照插值本地角色和其他在线角色。

当前仍是验证网络与移动闭环的原型：尚未实现服务端地形碰撞/寻路、技能战斗、AOI 分区、掉线重连和角色位置持久化。不要将其视为最终战斗或物理系统。
