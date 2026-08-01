# 移植批次 01：全屏播放器（经典 + 流体云）

日期：2026-07-26 · 状态：完成（flutter analyze 0 错误）

## 范围

把原版项目 `D:\work\cyrene_music` 的移动端全屏播放器完整移植到新版
`lib/features/player/mobile/`，包含两种可切换样式：

- **流体云**（默认）：Apple Music 风格动态背景、弹性逐字歌词面板
  （`MobilePlayerFluidCloudLayout` + `MobilePlayerFluidCloudLyricsPanel`）、
  封面/歌词双模态切换、歌曲百科面板、自动收起控制条、下滑关闭。
- **经典**：大专辑封面 + 卡拉OK 三行歌词（`MobilePlayerClassicLayout` +
  `MobilePlayerKaraokeLyric`）、波浪分段进度条（含副歌高亮）。

入口：迷你播放器与首页的 `_openPlayer` 均改为打开 `MobilePlayerPage`。

## 移植方式：兼容适配层

原版 UI 组件**逐文件原样拷贝**（`components/`、`widgets/`、页面本体），仅改
import；`compat/` 目录按原版单例服务的 API 一比一复刻 20+ 个服务，内部桥接到
新架构：

| 原版单例 | 桥接目标 |
| --- | --- |
| `PlayerService` | `PlaybackController`（bind 注入；positionNotifier 高频/结构性通知拆分还原） |
| `PlaybackModeService` | `RepeatMode`（sequential↔all、repeatOne↔one、shuffle↔shuffle） |
| `PlaylistService` | 新 `PlaylistService.instance` + 登录 token |
| `PlayHistoryService` | `HistoryService.instance` |
| `NeteaseArtistDetailService` | `ArtistService.instance`（Map 形状转换） |
| `NeteaseDiscoverService` / 模型 | 原版服务**原样移植**（直连后端，经 `UrlService` 垫片） |
| `AudioQualityService` | `AudioSourcePreferencesController`（文案与原版一致） |
| `LyricStyleService` / `LyricFontService` / `PlayerBackgroundService` / `SleepTimerService` / `AutoCollapseService` / `ColorExtractionService` | 原样移植（SharedPreferences 自持久化） |

歌词链路：原版 `LyricParser`（LRC/YRC/QRC 逐字）原样移植，输入取自
`Track.lyric/yrc/tlyric/ytlrc`（QQ 的 QRC 存于 yrc 字段，`SongDetail.fromTrack`
按 source 回填）。移植播放器内部**不使用**新架构的 4s lyricIntroDelay 体系。

服务初始化：`main()` 中与原版一致地初始化
`LyricStyleService`（默认流体云）/`PlayerBackgroundService`/`LyricFontService`。

## 设置入口

- 播放器内：右上角 ⋮ → 设置面板 → 「播放器样式」（流体云/沉浸/经典，原版组件）。
- 应用设置页新增「播放器样式」行（音乐分组），弹层选择 流体云/经典。

## 占位与降级（样式保留、功能提示未开放）

- 下载（`DownloadService` stub）、均衡器入口、视频背景/动态封面
  （`VideoBackgroundPlayer` stub）。
- 沉浸样式选中后按流体云渲染（原版为横屏桌面布局，桌面端不在移植范围）。
- 平板专用布局恒用手机布局；专辑名点击改为提示；歌手点击跳新版歌手详情页。

## 新增依赖

`image`（背景取色）、`flutter_colorpicker`（背景设置取色器）。

## 遗留

- 约 30 条 analyze warning 为原版代码自带的未用字段/变量，为保持逐行一致未清理。
- 旧 `fullscreen/` 播放器保留未删（不再是入口）。
- `.port_archive/discover_original_material/` 存有一份原版 Material 风格发现页
  拷贝（方向修正后弃用，仅作参照）。
