import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../app/desktop/window_taskbar_player.dart';
import '../../application/playback/playback_controller.dart';
import '../../application/stores/fullscreen_settings_store.dart';
import '../../features/desktop_player/desktop_player_controller.dart';
import '../../features/taskbar_player/taskbar_player_controller.dart';
import '../../presentation/cyrene/breakpoints.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'player_style_preview.dart';

/// 首启引导第四步「样式设置」的正文（无页面骨架与步骤标题，标题由引导头承担）。
///
/// 播放器样式用两个并排的**真实缩略预览**示意：卡片里跑的是全屏播放器用的同
/// 一批组件（黑胶唱台 / 流体云歌词 / SuperCyrene 逐行逐字画布），画面定格在示例
/// 曲目的某一句中间。用户在这里做的是一个「以后每天都要看」的选择，看真图比看
/// 插画诚实——也不会随播放器改版而失真。预览的隔离手法与红线见
/// [PreviewPlayback] 的文档。
///
/// 经典卡按平台分派：桌面是黑胶 + 右侧歌词，移动端是竖屏大封面，两者是**完全
/// 不同的界面**（见 desktop/mobile_fullscreen_player_host 的分流），画同一张图会
/// 骗人。
///
/// 桌面播放器 / 任务栏播放器开关仅 Windows 生效（其它平台整组隐藏），逻辑与
/// 外观设置页保持一致：先置设置态让开关立即响应，再异步创建/销毁原生窗口，
/// 失败时回滚开关。
class PlayerStyleSettingsBody extends StatefulWidget {
  const PlayerStyleSettingsBody({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
  });

  final EdgeInsets padding;

  @override
  State<PlayerStyleSettingsBody> createState() =>
      _PlayerStyleSettingsBodyState();
}

class _PlayerStyleSettingsBodyState extends State<PlayerStyleSettingsBody> {
  /// 两张卡共用一个假播放源：同一首示例曲目、同一个定格进度，一次装载、一次释放。
  final _preview = PreviewPlayback();

  static const _iconTeal = Color(0xFF00A3A3);
  static const _iconGreen = Color(0xFF3CC756);

  @override
  void initState() {
    super.initState();
    // seed() 内部 await 了一次 store.read()，完成前 currentTrack 为 null；
    // 下面用 AnimatedBuilder 监听 controller，这一两帧只画底色不闪空白。
    _preview.seed();
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: FullscreenSettingsStore.instance,
    builder: (context, _) {
      final store = FullscreenSettingsStore.instance;
      final desktop = isDesktopLayout(context);
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: widget.padding,
        children: [
          // 两个并排的播放器样式预览卡片（经典 / SuperCyrene）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PlayerStyleCard(
                  selected: !store.superCyrenePlayerEnabled,
                  onTap: () => store.setSuperCyrenePlayerEnabled(false),
                  title: '经典',
                  subtitle: desktop ? '黑胶 + 音臂 · 右侧歌词' : '大封面 · 沉浸控制台',
                  // 竖屏预览比 4:3 卡槽窄得多，letterbox 后自然成一个手机取景框。
                  aspectRatio: desktop ? 4 / 3 : 3 / 4,
                  preview: desktop
                      ? _withTrack(
                          (playback) =>
                              DesktopClassicPreview(playback: playback),
                        )
                      : const MobileClassicPreview(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PlayerStyleCard(
                  selected: store.superCyrenePlayerEnabled,
                  onTap: () => store.setSuperCyrenePlayerEnabled(true),
                  title: 'SuperCyrene',
                  subtitle: superCyreneSubtitle(store),
                  aspectRatio: desktop ? 4 / 3 : 3 / 4,
                  preview: _withTrack(
                    (playback) => SuperCyrenePreview(
                      playback: playback,
                      lyricsTheme: store.superCyreneLyricsTheme,
                      backgroundStyle: store.superCyreneBackgroundStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 桌面/任务栏播放器：仅 Windows 生效。
          if (Platform.isWindows) ...[
            const SizedBox(height: 12),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('layers')!,
                  iconBackground: _iconTeal,
                  title: '桌面播放器',
                  subtitle: store.wallpaperPlayerEnabled
                      ? '歌词已渲染到桌面壁纸层'
                      : '将歌词显示在桌面壁纸之上、图标之下',
                  trailing: MiuixSwitch(
                    value: store.wallpaperPlayerEnabled,
                    onChanged: (_) => _toggleWallpaperPlayer(context),
                  ),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('play')!,
                  iconBackground: _iconGreen,
                  title: '任务栏播放器',
                  subtitle: switch ((
                    store.taskbarPlayerEnabled,
                    store.taskbarPlayerMode,
                  )) {
                    (false, _) => '在任务栏的空白区域显示迷你播放控制条',
                    (true, TaskbarPlayerMode.floating) => '已拖出为悬浮窗，拖回任务栏可重新吸附',
                    (true, _) => '已固定在任务栏空白处，拖动标题可移出',
                  },
                  trailing: MiuixSwitch(
                    value: store.taskbarPlayerEnabled,
                    onChanged: (_) => _toggleTaskbarPlayer(context),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
    },
  );

  /// 等示例曲目装载完成后再交给 [build] 画预览。
  ///
  /// 歌词组件都 `required Track`，而 `restore()` 是异步的——首帧 currentTrack 仍
  /// 为 null。这一两帧先画一块底色，避免卡片闪一下空白或抛异常。
  Widget _withTrack(Widget Function(PlaybackController playback) build) =>
      AnimatedBuilder(
        animation: _preview.controller,
        builder: (context, _) =>
            _preview.controller.state.currentTrack == null
            ? const ColoredBox(color: Color(0xFF17151D))
            : build(_preview.controller),
      );

  /// 切换桌面播放器（壁纸层歌词）开关。
  ///
  /// 与外观设置页同构：先置设置态让开关立即响应，再异步创建/销毁原生窗口，
  /// 失败回滚。不在当前帧 await，避免创建子引擎时阻塞 UI 线程。
  void _toggleWallpaperPlayer(BuildContext context) {
    final store = FullscreenSettingsStore.instance;
    final newValue = !store.wallpaperPlayerEnabled;
    store.setWallpaperPlayerEnabled(newValue);

    final controller = DesktopPlayerController.instance;
    final task = newValue ? controller.enable() : controller.disable();

    task.then((error) {
      if (error == null) return;
      store.setWallpaperPlayerEnabled(!newValue);
      if (context.mounted) CyreneToast.show(error);
    }).catchError((Object e) {
      debugPrint('[桌面播放器] 操作异常: $e');
      store.setWallpaperPlayerEnabled(!newValue);
      if (context.mounted) CyreneToast.show('桌面播放器操作失败: $e');
    });

    CyreneToast.show(newValue ? '正在开启桌面播放器...' : '正在关闭桌面播放器...');
  }

  /// 切换任务栏播放器开关。
  ///
  /// 与桌面播放器同样的处理：不在当前帧 await，原生侧创建失败（如任务栏被
  /// 第三方工具替换）时回滚开关，避免设置显示「已开启」但实际没有窗口。
  void _toggleTaskbarPlayer(BuildContext context) {
    final store = FullscreenSettingsStore.instance;
    final newValue = !store.taskbarPlayerEnabled;
    store.setTaskbarPlayerEnabled(newValue);

    final controller = TaskbarPlayerController.instance;
    final task = newValue
        ? controller.enable(
            store.taskbarPlayerAlignment,
            mode: store.taskbarPlayerMode,
            x: store.taskbarPlayerFloatingX,
            y: store.taskbarPlayerFloatingY,
          )
        : controller.disable();

    task
        .then((error) {
          if (error == null) return;
          store.setTaskbarPlayerEnabled(!newValue);
          if (context.mounted) CyreneToast.show(error);
        })
        .catchError((Object e) {
          debugPrint('[任务栏播放器] 操作异常: $e');
          store.setTaskbarPlayerEnabled(!newValue);
          if (context.mounted) CyreneToast.show('任务栏播放器操作失败: $e');
        });
  }
}

/// 播放器样式图形卡片：上方预览区域 + 下方标题/副标题与选中标记。
class _PlayerStyleCard extends StatelessWidget {
  const _PlayerStyleCard({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.aspectRatio,
    required this.preview,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String subtitle;

  /// 预览区的比例：桌面预览是 4:3 的横向取景框，移动预览是 3:4 的竖向手机框。
  final double aspectRatio;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: colors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? colors.primary : colors.dividerLine,
              width: selected ? 2 : 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: aspectRatio, child: preview),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.body2.copyWith(
                            color: colors.onBackground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (selected)
                        MiuixIcon(
                          vector: MiuixIcons.basic.check,
                          size: 18,
                          tint: colors.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote2.copyWith(
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
