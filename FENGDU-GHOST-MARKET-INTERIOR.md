# 酆都鬼市店铺室内灰盒（第一版）

## 场景入口
- 预览场景：`Client/HongHuangClient/scenes/FengduGhostMarketShopInteriorPreview.tscn`
- 工厂函数：`UnderworldVisualFactory.create_ghost_market_shop_interior()`
- 目标空间：12m 宽、14m 深、3.6m 高。

## 已实现
- 独立可行走地面与四周墙体碰撞。
- 正面保留约 2.4m 的入口，墙体碰撞分段，不封死门洞。
- 后侧商贩柜台，左右实体货架，中央两处商品陈列台。
- 中央主通道保持约 3m 净宽，顾客可由入口进入柜台区域。
- 货架、柜台、陈列台有碰撞体，防止角色穿模。
- 鬼灯提供基础室内光源。
- 商贩站位、交易点和浏览点以 Marker3D 标记，并写入 interaction_kind 元数据。

## 交互边界
这些 Marker3D 只是场景布局锚点，不代表已经接入 NPC 实体、寻路、对话或交易。商品模型是视觉陈列，不是背包库存。实际交易、货币扣除、库存变化和防重复提交必须由服务端权威处理。

## 尚未完成
- 正式 GLB 商贩角色、货品模型和模块化建筑材质。
- NavigationRegion3D / NavigationLink3D 与 NPC 寻路。
- NPC 生成、营业状态、商品库存、价格和交易 RPC。
- Godot 编辑器解析、运行时碰撞及实际角色通行验证。

## 验证说明
本次通过 GitHub 内容接口写入代码和预览场景；当前执行环境没有可用的 Godot 项目运行时，因此没有声称通过 Godot parser 或游戏内测试。
