# 《洪荒》客户端音频实施与授权规范

## 当前实现：原创程序化音效（第一批）

客户端新增 `HHAudio` Autoload（`scripts/audio_manager.gd`）。第一批音效由项目代码在运行时合成，不依赖第三方录音，也不需要额外下载文件：

- `attack`：近战挥击
- `hit` / `heavy_hit`：普通受击与重击
- `monster_attack`：怪物攻击冲击
- `death`：死亡/消散提示
- `spell`：法术释放
- `pickup`：拾取提示（待接入拾取事件）
- `ui`：UI 轻提示（待接入主要按钮）
- `warning`：危险提示（待接入）
- `footstep`：玩家脚步
- `ambience_underworld`：冥界低频氛围循环（程序合成占位）
- `ambience_qingyun`：青云界轻风氛围循环（程序合成占位）

这些是第一轮占位音效，目的是建立完整反馈链路，不代表最终音效品质或正式配乐。后续可将 WAV/OGG 替换到同一 cue 接口，避免业务代码依赖具体文件。

## 音量与设置

- 自动建立 Music、SFX、UI 音频总线。
- 支持 Master / Music / SFX / UI 独立音量与静音状态。
- 设置保存到 `user://honghuang_audio.cfg`，不会提交账号信息或游戏存档。
- `play_world()` 使用 AudioStreamPlayer3D，按空间距离衰减。
- 已在游戏 HUD 顶部增加「声音设置」入口，可调整总音量、音乐/环境、战斗/环境音效、UI 音效，并可静音和试听。
- 进入冥界或青云界时自动切换对应的程序合成氛围循环，区域切换采用淡入淡出，离开世界时停止；这不是正式配乐，后续替换为授权录音/BGM。

## 代码调用约定

```gdscript
HHAudio.play_ui("ui")
HHAudio.play_combat("attack")
HHAudio.play_combat("spell")
HHAudio.play_world("monster_attack", monster.global_position)
HHAudio.set_volume("SFX", 0.8)
HHAudio.set_muted(false)
```

音频不得决定命中、伤害、拾取或技能成功；只在本地输入反馈或服务端确认事件之后播放。持续脚步、环境循环和怪物待机音需要距离、冷却和同屏数量限制，不能每帧创建播放器。

## 免费商用外部音频候选

外部素材必须逐包检查下载页、随包 LICENSE/README 和具体文件许可。资源站首页的许可说明不能替代具体包的许可记录。

| 来源 | 用途 | 当前状态 | 授权核验规则 |
|---|---|---|---|
| [Kenney Audio](https://kenney.nl/assets?q=audio) | UI、动作、环境基础音效 | candidate | 仅导入具体页面明确标注 CC0 的包，保存随包许可 |
| [Sonniss GameAudioGDC](https://sonniss.com/gameaudiogdc/) | 怪物、武器、环境音效 | candidate | 下载前核对当年度授权条款与包内 EULA，记录版本 |
| [Freesound](https://freesound.org/) | 风、雨、流水、动物和环境音 | candidate | 只选具体文件标注 CC0；排除 CC-BY-NC、未知许可及不可商用素材 |

## 资源验收要求

1. 保存原始下载 URL、下载日期、作者、包名/版本和许可副本。
2. 记录修改（裁剪、降噪、音量归一、格式转换等）。
3. 优先 WAV 源文件，运行时按需要转换 OGG；统一采样率并检查削波、底噪、循环接缝。
4. 逐个在 Godot 实机听音验收，不能只凭导入成功判定可用。
5. 对战斗音效做重复播放节流；环境音做距离衰减；BGM 与 SFX 使用独立总线。
6. 不收录影视、商业游戏、音乐平台抓取音频或来源不明的音效。

## 后续工作

- 建立音量设置 UI（主音量、音乐、音效、界面、静音）。
- 接入拾取、装备、背包、任务、聊天、等级提升、复活等 UI 反馈。
- 为酆都、荒原、血海、十八层地狱分别制作区域环境声与原创/明确授权 BGM。
- 对怪物按 archetype 分配不同叫声、移动声和攻击声。
- 增加本地音效冷却、距离过滤和同时播放上限。
