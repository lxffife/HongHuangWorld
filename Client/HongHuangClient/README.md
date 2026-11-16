# Godot 客户端

使用 Godot 4.x，优先 GDScript。性能关键或需要复用 C++ 网络库的部分再评估 GDExtension。

建议场景：Startup、Login、CharacterCreate、SoulSelection、WorldEntry、QingyunTestMap、Player、GameHUD。

P0 操作：WASD 移动、鼠标视角、跳跃、第三人称相机、基础角色动画、昵称显示和远端玩家插值表现。先使用占位模型。客户端只提交输入意图，权威位置由世界服务器下发。

注意：不要直接假设 Godot MultiplayerAPI RPC 与独立 C++ ENet 服务端兼容；使用 Protocol/ 中定义的显式消息格式。
