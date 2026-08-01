# 移植批次 05：设置页剩余三项（均衡器 / 外观 / 关于）

日期：2026-07-27 · 状态：完成（flutter analyze 0 错误，未构建 APK）

## 范围

补齐设置主页 `lib/features/settings/settings_page.dart` 的三个「即将开放」占位：

1. **音效与均衡器** → `EqualizerPage`（参照原版 `pages/settings_page/equalizer_page.dart` 移动端 Material 分支）
2. **外观** → `AppearanceSettingsPage`（参照原版 `pages/settings_page/appearance_settings_page.dart` 的 `_buildMaterialUI`）
3. **关于 Cyrene Music** → `AboutPage`（参照原版 `pages/settings_page/about_settings_page.dart` 的 `_buildMaterialUI`）

`_showComingSoon` 已删除。UI 按约定统一 miuix HyperOS 风格，只移植功能与内容。

## 1. 均衡器

- 原版实现本就是 media_kit/libmpv：把 FFmpeg `equalizer` 滤镜链写入 `af` 属性
  （`equalizer=f=31:width_type=o:width=1:g=1.5,...`），与新版播放管线同源，核心逻辑原样移植。
- 新增 `lib/infrastructure/audio/equalizer_service.dart`（单例 ChangeNotifier）：
  - 频段 `31/63/125/250/500/1k/2k/4k/8k/16k`，±12dB；|gain|≤0.1 跳过；禁用/全平直写空串清除。
  - 持久化键与原版一致：`player_eq_gains`（List\<String\>，1 秒节流）、`player_eq_enabled`（bool，立即写）。
  - `attach(Player)` 由 `AppDependencies.production()` 调用（`MediaKitPlayerGateway` 新增 `player` getter）；
    preview（SilentAudioPlayerGateway）不绑定，设置仍可编辑持久化。
  - 仅当 `player.platform is NativePlayer` 时生效（原版用 `as dynamic`，此处改为类型判断）。
- `lib/features/settings/equalizer_page.dart`：启用开关（MiuixSwitchPreference）、
  「仅支持 mp3」提示条、15 个预设横向 chips（命中判定：每段差 ≤0.1）、
  10 列竖推子（`RotatedBox(quarterTurns:3)` + MiuixSlider）、失真提示。预设表与原版逐值一致。
- 入口：设置主页行（副标题「自定义音频频率响应」，右侧值 已开启/已关闭）+
  播放器设置面板 `EqualizerSection`（原占位 toast 已替换为进入均衡器页）。

## 2. 外观

- 新增 `lib/application/stores/appearance_settings_store.dart`：键名照抄原版
  （`theme_mode`=ThemeMode.index、`follow_system_color`、`seed_color`=ARGB int）。
  **默认值与原版不同（有意为之）**：跟随系统明暗 + 不跟随系统主题色 + 无种子色
  （原版默认亮色 + deepPurple + 跟随开），保持新版 HyperOS 静态配色的既有观感。
  `setSeedColor` 保留原版行为：手动选色自动关闭跟随系统主题色。
- `main.dart`：`MiuixSystemTheme` → `MiuixThemeController`（flutter_miuix 自带），
  由 store 映射 `colorSchemeMode`：开跟随或有种子色 → monet\*（keyColor=null 时读壁纸
  Monet，Android 12+；有种子色按种子生成），否则 system/light/dark 静态配色。
  store 在 `main()` 的 `Future.wait` 中 init，避免首帧主题闪变。
- `lib/features/settings/appearance_settings_page.dart`：
  - 主题：深色模式（跟随系统/亮色/暗色三态 sheet，原版移动端只有开关、桌面才有三态，
    此处取三态以保留新版「跟随系统」默认）、跟随系统主题色开关（文案照抄 Android 分支）、
    主题色（锁定态 + 10 个原版预设色 + 默认 + 自定义 MiuixColorPalette，按钮「取消/应用色彩」）。
  - 播放器：歌词字体（`LyricFontService`，平台预设 + 导入 ttf/otf/ttc + 恢复预设）、
    播放器背景（`PlayerBackgroundService`：自适应/动态/纯色/图片/视频，图片视频赞助专属
    文案与原版一致；自适应且非流体云时展示「封面渐变效果」开关，条件照抄原版）。
  - 不移植：界面风格（Material/Cupertino/Oculus 多框架）、窗口背景、桌面端整节。
    全屏播放器样式已在设置主页，不重复。
- 设置主页「外观」行右侧值随主题模式变化（原硬编码「自动」）。

## 3. 关于

- `lib/features/settings/about_page.dart`：头部 Logo（`assets/icons/new_ico_white.png`
  从原版复制，pubspec 已登记）+ 应用名 + 可点版本号；行：版本信息 / 用户协议 / 开放源代码许可
  （`showLicensePage`）。
- 原版关于页的「检查更新 / 自动更新」与新版设置主页独立入口重复，未移植。
- `lib/features/settings/user_agreement_page.dart`：协议正文逐字照抄原版（八章 + 词语约定 +
  「最新更新时间：2026年2月4日」）。
- 彩蛋：`lib/infrastructure/services/developer_mode_service.dart`——2 秒内连点版本号 5 次
  开启开发者模式，第 2 次起提示剩余次数，键 `developer_mode`；与原版差异：服务返回提示文案
  由页面弹 toast（不反向依赖表现层）。

## 3.1 开发者选项（补充，2026-07-27 第二轮）

原版开发者模式的消费端是主导航里的「开发者」页（developer_page.dart，3500+ 行）；
新版取其移动端核心子集做成 `lib/features/settings/developer_options_page.dart`：

- 入口：设置主页「应用」组，仅 `isDeveloperMode` 时显示（HyperOS 风格 code 图标）。
- 性能叠加层：键照抄 `show_performance_overlay`，由 main.dart 的
  `MaterialApp.showPerformanceOverlay` 消费（外层 ListenableBuilder 合并监听）。
- 运行日志：main() 挂 debugPrint 钩子收集到 1000 条环形缓冲；日志页支持复制/清空；
  用独立 `logRevision` ValueNotifier 通知，避免高频日志重建无关监听方。
- 显示模式信息（新增，非原版）：展示 FlutterDisplayMode active/最高支持刷新率，
  用于核对高刷是否生效。
- 退出开发者模式：确认框 + 连点版本号可重新开启。
- 修复：`ensureLoaded()` 加入 main() 的 Future.wait——此前重启后不恢复开发者状态。
- 原版实验室功能（赞助 gated 的均衡器入口/安卓小部件开关）未移植：均衡器已是正式功能，
  小部件功能新版尚无对应实现。

## 验证

`flutter analyze`：0 错误；30 条既有 warning/info 全部位于批次 01 拷贝的播放器旧文件，
本批次新增/修改文件无任何告警。未构建 APK（按要求）。

## 涉及文件

新增：`infrastructure/audio/equalizer_service.dart`、`infrastructure/services/developer_mode_service.dart`、
`application/stores/appearance_settings_store.dart`、`features/settings/{equalizer_page,appearance_settings_page,about_page,user_agreement_page}.dart`、
`assets/icons/new_ico_white.png`。
修改：`main.dart`、`app/app_dependencies.dart`、`infrastructure/audio/media_kit_player_gateway.dart`、
`features/settings/settings_page.dart`、`features/player/mobile/components/settings_sections/equalizer_section.dart`、`pubspec.yaml`。
