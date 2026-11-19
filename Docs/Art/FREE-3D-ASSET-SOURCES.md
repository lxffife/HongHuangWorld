# 免费商用 3D 资产来源初筛

更新：2026-11-19

本清单是**来源级初筛**，不是已经下载或导入项目的资产清单。正式采用某个模型前，仍要保存具体资产页面、原始文件内 LICENSE/NOTICE、作者、下载版本和修改记录。

## 优先来源

| 来源 | 已核对许可 | 适合用途 | 采用注意事项 |
|---|---|---|---|
| Poly Haven | 全站资产 CC0 | PBR 材质、石木金属、HDRI、自然物件 | 适合环境材质；写实扫描材质要统一调色，避免与风格化角色割裂 |
| Quaternius | 官方 FAQ 声明模型 CC0 | 低多边形角色、怪物、动物、道具、动画包 | 下载具体 pack 时仍保留该 pack 的 LICENSE；检查骨架/动画是否一致 |
| Kenney | 官方支持页声明资产页均为 CC0 | 原型道具、自然物、模块化场景和 UI | 风格偏简洁低多边形，可作原型/辅助道具，不直接混搭不同画风 |
| ambientCG | 全站资产 CC0 1.0 | 地面、石墙、木材、屋瓦、岩石 PBR 材质、HDRI | 主要用于材质贴图；优先 1K/2K，移动端控制显存和贴图数量 |

## 官方许可链接

- Poly Haven License: https://polyhaven.com/license
- Quaternius FAQ: https://quaternius.com/faq.html
- Kenney Support: https://kenney.nl/support
- ambientCG License: https://docs.ambientcg.com/license/

## 导入规则

1. 仅下载明确标注 CC0/许可兼容商业用途的具体资产；不把“免费”视为“可商用”。
2. Sketchfab、OpenGameArt 等聚合站逐模型核对许可，不按站点整体推断。
3. 不采用 Editorial Use Only、NC（非商业）、ND（禁止演绎）或来源不明模型。
4. 模型优先 GLB/glTF；贴图优先 1K/2K；保留原始下载包和 LICENSE/NOTICE。
5. 记录在 `ASSET-REGISTER.csv`；检查角色/怪物是否包含可用骨架、动画、合理比例和可替换材质。
6. 对商标、现实人物肖像、受保护角色/道具造型另行做权利审查；CC0 文件不代表其中第三方商标/肖像权也自动清除。

## 初步选择建议

- **玩家与怪物**：优先 Quaternius 同一角色系列/同一骨架体系，先做统一比例和动画适配测试。
- **树木、岩石、地表**：优先 Kenney Nature 与 Poly Haven/ambientCG 材质，统一色彩后再批量导入。
- **宗门建筑**：现阶段使用仓库内原创程序化模型；后续优先找模块化建筑部件，或继续原创制作，避免直接拿西式城堡套用国风宗门。
- **环境材质**：ambientCG/Poly Haven 的 CC0 贴图可用作石材、木材、泥土等 PBR 底材，再进行统一色调处理。

## 核对来源

- Poly Haven 明确表示其资产均为 CC0，可用于商业项目且不要求署名。
- Quaternius FAQ 明确表示模型为 CC0，可免费用于商业项目。
- Kenney 支持页明确表示其资产页游戏资产为 CC0，可用于商业项目。
- ambientCG 官方许可页明确 CC0 1.0 允许商业使用，也允许将原始文件包含在游戏项目中。
