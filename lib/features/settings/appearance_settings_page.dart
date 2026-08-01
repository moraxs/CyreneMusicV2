import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/stores/appearance_settings_store.dart';
import '../../features/player/mobile/compat/lyric_font_service.dart';
import '../../features/player/mobile/compat/lyric_style_service.dart';
import '../../features/player/mobile/compat/player_background_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 外观设置页（对应原版 appearance_settings_page.dart 的移动端子集）。
///
/// 保留：主题（明暗模式 / 跟随系统主题色 / 主题色）与播放器（播放器样式 /
/// 歌词字体 / 播放器背景）。原版的界面风格切换（Material/Cupertino/Oculus）、
/// 窗口背景、桌面端一节均为多框架 / 桌面产物，不移植。
/// 全屏播放器样式由设置主页下沉至此处「播放器」分组，与其他播放器外观项聚拢。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key, required this.account});

  final AccountSessionController account;

  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconPurple = Color(0xFF8A64FF);
  static const _iconOrange = Color(0xFFFF9F0A);

  /// 预设主题色（名称 / 色值，照抄原版 ThemeColors.presets）。
  /// 原版元组第三位的 IconData 在此页从未渲染（色卡只画圆形色块），已去掉。
  static const List<(String, Color)> _presetColors = [
    ('深紫色', Colors.deepPurple),
    ('蓝色', Colors.blue),
    ('青色', Colors.cyan),
    ('绿色', Colors.green),
    ('橙色', Colors.orange),
    ('粉色', Colors.pink),
    ('红色', Colors.red),
    ('靛蓝色', Colors.indigo),
    ('青柠色', Colors.lime),
    ('琥珀色', Colors.amber),
  ];

  static String _themeModeName(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '亮色',
    ThemeMode.dark => '暗色',
  };

  static String _themeColorName(AppearanceSettingsStore store) {
    if (store.followSystemColor) return '跟随系统';
    final seed = store.seedColor;
    if (seed == null) return '默认';
    for (final (name, color) in _presetColors) {
      if (color.toARGB32() == seed.toARGB32()) return name;
    }
    return '自定义';
  }

  // 播放器样式入口已隐藏，下列选择器/名称映射暂留注释以备恢复多样式时取消注释。
  /*
  static String _playerStyleName(LyricStyle style) => switch (style) {
    LyricStyle.fluidCloud => '流体云',
    LyricStyle.immersive => '沉浸',
    LyricStyle.defaultStyle => '经典',
    LyricStyle.amll => 'Apple Music',
  };

  Future<void> _choosePlayerStyle(BuildContext context) async {
    await showCyreneSheet<void>(
      context: context,
      title: '播放器样式',
      builder: (context, dismiss) => ListenableBuilder(
        listenable: LyricStyleService(),
        builder: (context, _) {
          final current = LyricStyleService().currentStyle;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (style, iconName, name, desc) in const [
                  (
                    LyricStyle.fluidCloud,
                    'cloudFill',
                    '流体云',
                    '动态封面背景 + 弹性逐字歌词面板',
                  ),
                  (
                    LyricStyle.amll,
                    'notes',
                    'Apple Music',
                    '弹簧物理滚动 + 逐字渐变，还原 Apple Music',
                  ),
                  (
                    LyricStyle.defaultStyle,
                    'album',
                    '经典',
                    '大专辑封面 + 卡拉OK 三行歌词',
                  ),
                ])
                  CyreneMenuRow(
                    vector: MiuixIcons.extended.byName(iconName)!,
                    title: name,
                    subtitle: desc,
                    trailing: current == style
                        ? MiuixIcon(
                            vector: MiuixIcons.basic.check,
                            size: 20,
                            tint: MiuixTheme.of(context).colors.primary,
                          )
                        : const SizedBox(width: 20),
                    onTap: () {
                      LyricStyleService().setStyle(style);
                      dismiss();
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
  */

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '外观',
    bodyBuilder: (context, topPadding) => ListView(
      physics: const BouncingScrollPhysics(),
      padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
      children: [
        const MiuixSmallTitle(
          '主题',
          insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        ListenableBuilder(
          listenable: AppearanceSettingsStore.instance,
          builder: (context, _) {
            final store = AppearanceSettingsStore.instance;
            return CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('background')!,
                  iconBackground: _iconPurple,
                  title: '深色模式',
                  subtitle: '页面明暗外观',
                  value: _themeModeName(store.themeMode),
                  onTap: () => _chooseThemeMode(context),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('theme')!,
                  iconBackground: _iconBlue,
                  title: '跟随系统主题色',
                  subtitle: store.followSystemColor
                      ? '自动获取 Material You 动态颜色 (Android 12+)'
                      : '手动选择主题色',
                  trailing: MiuixSwitch(
                    value: store.followSystemColor,
                    onChanged: store.setFollowSystemColor,
                  ),
                  onTap: () =>
                      store.setFollowSystemColor(!store.followSystemColor),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('image')!,
                  iconBackground: _iconOrange,
                  title: '主题色',
                  value: _themeColorName(store),
                  trailing: store.followSystemColor
                      ? MiuixIcon(
                          vector: MiuixIcons.extended.byName('lock')!,
                          size: 18,
                          tint: MiuixTheme.of(
                            context,
                          ).colors.onSurfaceVariantActions,
                        )
                      : null,
                  onTap: () => store.followSystemColor
                      ? CyreneToast.show('已跟随系统主题色，如需手动选择请先关闭上方开关')
                      : _chooseThemeColor(context),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const MiuixSmallTitle(
          '播放器',
          insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        CyreneMenuGroup(
          children: [
            // 播放器样式入口已隐藏：目前仅保留「流体云」一种样式，
            // 单一选项无意义，整段注释以备未来恢复多样式时取消注释。
            // ListenableBuilder(
            //   listenable: LyricStyleService(),
            //   builder: (context, _) => CyreneMenuRow(
            //     vector: MiuixIcons.extended.byName('play')!,
            //     iconBackground: _iconPurple,
            //     title: '播放器样式',
            //     subtitle: '全屏播放器的整体布局',
            //     value: _playerStyleName(LyricStyleService().currentStyle),
            //     onTap: () => _choosePlayerStyle(context),
            //   ),
            // ),
            ListenableBuilder(
              listenable: LyricFontService(),
              builder: (context, _) => CyreneMenuRow(
                vector: MiuixIcons.extended.byName('notes')!,
                iconBackground: _iconGreen,
                title: '歌词字体',
                value: LyricFontService().currentFontName,
                onTap: () => _chooseLyricFont(context),
              ),
            ),
            ListenableBuilder(
              listenable: PlayerBackgroundService(),
              builder: (context, _) => CyreneMenuRow(
                vector: MiuixIcons.extended.byName('background')!,
                iconBackground: _iconBlue,
                title: '播放器背景',
                subtitle: PlayerBackgroundService()
                    .getBackgroundTypeDescription(),
                value: PlayerBackgroundService().getBackgroundTypeName(),
                onTap: () => _chooseBackground(context),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // ==================== 深色模式 ====================

  Future<void> _chooseThemeMode(BuildContext context) async {
    await showCyreneSheet<void>(
      context: context,
      title: '深色模式',
      builder: (context, dismiss) => ListenableBuilder(
        listenable: AppearanceSettingsStore.instance,
        builder: (context, _) {
          final store = AppearanceSettingsStore.instance;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (mode, iconName, name, desc) in const [
                  (ThemeMode.system, 'theme', '跟随系统', '与系统深色模式保持一致'),
                  (ThemeMode.light, 'show', '亮色', '始终使用浅色外观'),
                  (ThemeMode.dark, 'hide', '暗色', '始终使用深色外观'),
                ])
                  CyreneMenuRow(
                    vector: MiuixIcons.extended.byName(iconName)!,
                    title: name,
                    subtitle: desc,
                    trailing: store.themeMode == mode
                        ? MiuixIcon(
                            vector: MiuixIcons.basic.check,
                            size: 20,
                            tint: MiuixTheme.of(context).colors.primary,
                          )
                        : const SizedBox(width: 20),
                    onTap: () {
                      store.setThemeMode(mode);
                      dismiss();
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==================== 主题色 ====================

  Future<void> _chooseThemeColor(BuildContext context) async {
    await showCyreneSheet<void>(
      context: context,
      title: '主题色',
      builder: (context, dismiss) => ListenableBuilder(
        listenable: AppearanceSettingsStore.instance,
        builder: (context, _) {
          final store = AppearanceSettingsStore.instance;
          final seed = store.seedColor;
          // 「默认」色块用 HyperOS 静态配色的主色示意。
          final defaultColor = lightColorScheme().primary;
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                _ColorOption(
                  name: '默认',
                  color: defaultColor,
                  selected: seed == null,
                  onTap: () => store.setSeedColor(null),
                ),
                for (final (name, color) in _presetColors)
                  _ColorOption(
                    name: name,
                    color: color,
                    selected: seed?.toARGB32() == color.toARGB32(),
                    onTap: () => store.setSeedColor(color),
                  ),
                _ColorOption.custom(
                  selected:
                      seed != null &&
                      !_presetColors.any(
                        (preset) => preset.$2.toARGB32() == seed.toARGB32(),
                      ),
                  onTap: () => _pickCustomThemeColor(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickCustomThemeColor(BuildContext context) async {
    final store = AppearanceSettingsStore.instance;
    final picked = await showCyreneDialog<Color>(
      context: context,
      title: '自定义颜色',
      builder: (_, dismiss) => _CustomColorDialog(
        initial: store.seedColor ?? _presetColors.first.$2,
        dismiss: dismiss,
      ),
    );
    if (picked != null) store.setSeedColor(picked);
  }

  // ==================== 歌词字体 ====================

  Future<void> _chooseLyricFont(BuildContext context) async {
    await showCyreneSheet<void>(
      context: context,
      title: '歌词字体',
      builder: (context, dismiss) => ListenableBuilder(
        listenable: LyricFontService(),
        builder: (context, _) {
          final service = LyricFontService();
          final theme = MiuixTheme.of(context);
          final usingCustom =
              service.fontType == 'custom' && service.customFontPath != null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    if (usingCustom)
                      CyreneMenuRow(
                        vector: MiuixIcons.extended.byName('file')!,
                        title: service.currentFontName,
                        subtitle: '本机导入的字体文件',
                        trailing: MiuixIcon(
                          vector: MiuixIcons.basic.check,
                          size: 20,
                          tint: theme.colors.primary,
                        ),
                      ),
                    for (final font in LyricFontService.platformFonts)
                      CyreneMenuRow(
                        vector: MiuixIcons.extended.byName('notes')!,
                        title: font.name,
                        subtitle: font.description,
                        trailing:
                            !usingCustom && service.presetFontId == font.id
                            ? MiuixIcon(
                                vector: MiuixIcons.basic.check,
                                size: 20,
                                tint: theme.colors.primary,
                              )
                            : const SizedBox(width: 20),
                        onTap: () => service.setPresetFont(font.id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: MiuixButton(
                      onPressed: () => _pickCustomFont(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MiuixIcon(
                            vector: MiuixIcons.extended.byName('import')!,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          MiuixText('选择字体文件', style: theme.textStyles.button),
                        ],
                      ),
                    ),
                  ),
                  if (usingCustom) ...[
                    const SizedBox(width: 10),
                    MiuixButton(
                      onPressed: () => service.clearCustomFont(),
                      child: MiuixText('恢复预设', style: theme.textStyles.button),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickCustomFont(BuildContext context) async {
    final success = await LyricFontService().pickAndLoadCustomFont();
    if (success) CyreneToast.show('自定义字体已加载');
  }

  // ==================== 播放器背景 ====================

  Future<void> _chooseBackground(BuildContext context) async {
    await showCyreneSheet<void>(
      context: context,
      title: '播放器背景',
      builder: (context, dismiss) => ListenableBuilder(
        listenable: Listenable.merge([
          PlayerBackgroundService(),
          LyricStyleService(),
          account,
        ]),
        builder: (context, _) {
          final background = PlayerBackgroundService();
          final theme = MiuixTheme.of(context);
          final isSponsor = account.state.user?.isSponsor ?? false;
          final current = background.backgroundType;

          Widget checkFor(PlayerBackgroundType type) => current == type
              ? MiuixIcon(
                  vector: MiuixIcons.basic.check,
                  size: 20,
                  tint: theme.colors.primary,
                )
              : const SizedBox(width: 20);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    CyreneMenuRow(
                      vector: MiuixIcons.extended.byName('theme')!,
                      title: '自适应',
                      subtitle: '基于专辑封面提取颜色',
                      trailing: checkFor(PlayerBackgroundType.adaptive),
                      onTap: () => background.setBackgroundType(
                        PlayerBackgroundType.adaptive,
                      ),
                    ),
                    // 与原版一致：仅自适应背景 + 非流体云样式时提供渐变开关。
                    // AMLL 样式共用流体云背景，同样不提供该开关。
                    if (background.isAdaptive &&
                        LyricStyleService().currentStyle !=
                            LyricStyle.fluidCloud &&
                        LyricStyleService().currentStyle != LyricStyle.amll)
                      CyreneMenuRow(
                        vector: MiuixIcons.extended.byName('layers')!,
                        title: '封面渐变效果',
                        subtitle: '专辑封面位于顶部，向下渐变到主题色',
                        trailing: MiuixSwitch(
                          value: background.enableGradient,
                          onChanged: background.setEnableGradient,
                        ),
                        onTap: () => background.setEnableGradient(
                          !background.enableGradient,
                        ),
                      ),
                    CyreneMenuRow(
                      vector: MiuixIcons.extended.byName('cloudFill')!,
                      title: '动态背景',
                      subtitle: '基于封面的动态渐变效果',
                      trailing: checkFor(PlayerBackgroundType.dynamic),
                      onTap: () => background.setBackgroundType(
                        PlayerBackgroundType.dynamic,
                      ),
                    ),
                    CyreneMenuRow(
                      vector: MiuixIcons.extended.byName('background')!,
                      title: '纯色背景',
                      subtitle: '使用自定义纯色',
                      trailing: checkFor(PlayerBackgroundType.solidColor),
                      onTap: () => background.setBackgroundType(
                        PlayerBackgroundType.solidColor,
                      ),
                    ),
                    if (background.isSolidColor)
                      CyreneMenuRow(
                        vector: MiuixIcons.extended.byName('edit')!,
                        title: '选择颜色',
                        trailing: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: background.solidColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colors.onSurfaceVariantActions,
                            ),
                          ),
                        ),
                        onTap: () => _pickSolidColor(context),
                      ),
                    CyreneMenuRow(
                      vector: MiuixIcons.extended.byName('image')!,
                      title: '图片背景',
                      subtitle:
                          background.mediaPath != null && background.isImage
                          ? '自定义图片'
                          : '未设置图片',
                      value: isSponsor ? null : '赞助专属',
                      trailing: checkFor(PlayerBackgroundType.image),
                      onTap: () => _selectMediaBackground(isVideo: false),
                    ),
                    CyreneMenuRow(
                      vector: MiuixIcons.extended.byName('photos')!,
                      title: '视频背景',
                      subtitle:
                          background.mediaPath != null && background.isVideo
                          ? '自定义视频'
                          : '未设置视频',
                      value: isSponsor ? null : '赞助专属',
                      trailing: checkFor(PlayerBackgroundType.video),
                      onTap: () => _selectMediaBackground(isVideo: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickSolidColor(BuildContext context) async {
    final background = PlayerBackgroundService();
    final picked = await showCyreneDialog<Color>(
      context: context,
      title: '自定义颜色',
      builder: (_, dismiss) =>
          _CustomColorDialog(initial: background.solidColor, dismiss: dismiss),
    );
    if (picked != null) await background.setSolidColor(picked);
  }

  /// 选择图片/视频背景。赞助校验与文案与原版一致；
  /// 已有同类媒体时点击仅切换类型，再次点击可重新选择文件。
  Future<void> _selectMediaBackground({required bool isVideo}) async {
    final isSponsor = account.state.user?.isSponsor ?? false;
    if (!isSponsor) {
      CyreneToast.show('此功能为赞助用户专属，成为赞助用户即可解锁');
      return;
    }
    final background = PlayerBackgroundService();
    final targetType = isVideo
        ? PlayerBackgroundType.video
        : PlayerBackgroundType.image;
    final hasMatchingMedia =
        background.mediaPath != null &&
        (isVideo
            ? background.isVideoFile(background.mediaPath!)
            : background.isImageFile(background.mediaPath!));
    if (hasMatchingMedia && background.backgroundType != targetType) {
      await background.setBackgroundType(targetType);
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: isVideo
          ? const ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v']
          : const ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
      dialogTitle: isVideo ? '选择背景视频' : '选择背景图片',
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await background.setMediaBackground(path);
    CyreneToast.show(isVideo ? '背景视频已设置' : '背景图片已设置');
  }
}

/// 主题色色块（圆形色样 + 名称）。
class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  }) : isCustom = false;

  const _ColorOption.custom({required this.selected, required this.onTap})
    : name = '自定义',
      color = null,
      isCustom = true;

  final String name;
  final Color? color;
  final bool selected;
  final bool isCustom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              gradient: isCustom
                  ? const SweepGradient(
                      colors: [
                        Colors.red,
                        Colors.orange,
                        Colors.yellow,
                        Colors.green,
                        Colors.blue,
                        Colors.purple,
                        Colors.red,
                      ],
                    )
                  : null,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colors.primary, width: 3)
                  : Border.all(
                      color: theme.colors.onSurfaceVariantActions.withAlpha(60),
                    ),
            ),
            child: selected
                ? MiuixIcon(
                    vector: MiuixIcons.basic.check,
                    size: 20,
                    tint: Colors.white,
                  )
                : (isCustom
                      ? MiuixIcon(
                          vector: MiuixIcons.extended.byName('edit')!,
                          size: 18,
                          tint: Colors.white,
                        )
                      : null),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            style: theme.textStyles.footnote2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义取色对话框（HSV 网格调色板，替代原版的 HSV 滑块 + Hex 输入）。
class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial, required this.dismiss});

  final Color initial;

  /// 弹层关闭回调：带颜色应用、不带颜色取消。
  final void Function([Color?]) dismiss;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        MiuixColorPalette(
          color: _color,
          onColorChanged: (color) => setState(() => _color = color),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: () => widget.dismiss()),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: () => widget.dismiss(_color),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('应用色彩', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}
