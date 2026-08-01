import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
// material 自身也导出一个 RepeatMode(RepeatingAnimationBuilder 用),与本项目的
// 播放循环模式撞名,hide 掉即可——本文件不用 material 那个。
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;
import 'package:flutter_svg/flutter_svg.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/playback/repeat_mode.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'mobile/mobile_player_page.dart';
import 'track_artwork.dart';

/// 桌面端专用底部迷你播放器底栏（WinUI 扁平语言，铺满窗口宽度）。
///
/// 与移动端 [MiniPlayer]（液态玻璃悬浮药丸）完全无关：这是一根贴底常驻的命令栏，
/// 三段式布局——
///   - 顶部一条可拖动 seek 的细进度条（hover 变粗，强调色）；
///   - **左**：封面 + 标题/歌手（点击进全屏播放页）· 喜欢；
///   - **中**：随机 · 上一首 · 大圆播放键 · 下一首 · 循环；
///   - **右**：时间 · 歌词 · 音量图标+滑块 · 播放列表。
///
/// **为什么整条不用 fluent_ui、也不用任何 [Slider]**：桌面端曾出现「启动即闪退」，
/// 原生崩溃在 `flutter_windows.dll` 的无障碍桥 `accessibility_bridge.cc`
/// （"Failed to update ui::AXTree"）——fluent/Material `Slider` 等控件的语义节点
/// 会让 Windows 无障碍桥更新 AXTree 失败。这里进度条 / 音量条 / 按钮全部自绘，
/// 顶层再包一层 [ExcludeSemantics] 兜底：底栏对全局语义树零贡献，从根上杜绝该崩溃
/// （桌面迷你条无障碍非关键取舍）。配色改取 [MiuixTheme]，与桌面外壳同源。
///
/// 高频 position 只驱动进度条与时间文字（[PlaybackController.positionListenable]），
/// 其余控件走结构性主通知（外层 [AnimatedBuilder]），避免每 tick 全条重建。
class DesktopMiniPlayer extends StatelessWidget {
  const DesktopMiniPlayer({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;

    void openPlayer() {
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => MobilePlayerPage(
            playback: playback,
            audioSources: audioSources,
            account: account,
          ),
        ),
      );
    }

    // ExcludeSemantics：见类文档——彻底移除本子树的语义节点，杜绝 Windows
    // 无障碍桥更新 AXTree 失败导致的原生闪退。
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          // 与上方内容区的分界线（无独立 divider 配色，用 onSurface 低透明度）。
          border: Border(
            top: BorderSide(
              color: colors.onSurface.withValues(alpha: 0.08),
            ),
          ),
        ),
        child: AnimatedBuilder(
          animation: playback,
          builder: (context, _) {
            final track = playback.state.currentTrack;
            if (track == null) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SeekBar(playback: playback),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 69,
                    child: Row(
                      children: [
                        // 左右两段等 flex，中段传输控件才会真正居中。
                        Expanded(
                          child: _LeftSection(
                            playback: playback,
                            onOpenPlayer: openPlayer,
                          ),
                        ),
                        _CenterControls(playback: playback),
                        Expanded(
                          child: _RightControls(
                            playback: playback,
                            onOpenLyrics: openPlayer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 顶部细进度条：点击 / 拖动 seek，hover 变粗。duration 走主通知，position
/// 走独立高频通知；拖动过程中用本地 [_dragFraction] 预览，松手才真正 seek。
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.playback});

  final PlaybackController playback;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  bool _hover = false;
  double? _dragFraction;

  void _preview(Offset local, double width) {
    setState(() => _dragFraction = (local.dx / width).clamp(0.0, 1.0));
  }

  void _commit() {
    final fraction = _dragFraction;
    if (fraction != null) {
      final duration = widget.playback.state.duration;
      if (duration > Duration.zero) {
        widget.playback.seek(duration * fraction);
      }
    }
    setState(() => _dragFraction = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final accent = colors.primary;
    final trackColor = colors.onSurfaceContainer.withValues(alpha: 0.15);
    final active = _hover || _dragFraction != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _preview(d.localPosition, width),
            onTapUp: (_) => _commit(),
            onTapCancel: () => setState(() => _dragFraction = null),
            onHorizontalDragUpdate: (d) => _preview(d.localPosition, width),
            onHorizontalDragEnd: (_) => _commit(),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: Align(
                child: AnimatedBuilder(
                  animation: widget.playback,
                  builder: (context, _) {
                    final total =
                        widget.playback.state.duration.inMilliseconds;
                    return ValueListenableBuilder<Duration>(
                      valueListenable: widget.playback.positionListenable,
                      builder: (context, position, _) {
                        final played = total > 0
                            ? position.inMilliseconds / total
                            : 0.0;
                        final fraction = (_dragFraction ?? played)
                            .clamp(0.0, 1.0);
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: active ? 5 : 3,
                          width: double.infinity,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: trackColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: fraction,
                            alignment: Alignment.centerLeft,
                            child: ColoredBox(color: accent),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 左段：封面 + 标题/歌手（点击进全屏播放页）+ 喜欢按钮。
class _LeftSection extends StatelessWidget {
  const _LeftSection({required this.playback, required this.onOpenPlayer});

  final PlaybackController playback;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final textStyles = MiuixTheme.of(context).textStyles;
    final track = playback.state.currentTrack!;

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 封面 + 文字整体点击进全屏；喜欢按钮独立命中，不被这层拦走。
          Flexible(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpenPlayer,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrackArtwork(track: track, size: 48, borderRadius: 6),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.body2.copyWith(
                              color: colors.onSurfaceContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.body2.copyWith(
                              color: colors.onSurfaceVariantSummary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _HoverIconButton(
            icon: Icons.favorite_border_rounded,
            tooltip: '喜欢',
            color: colors.onSurfaceContainer,
            onPressed: () => CyreneToast.show('收藏功能即将上线'),
          ),
        ],
      ),
    );
  }
}

/// 中段传输控件：随机 · 上一首 · 大圆播放键 · 下一首 · 循环。
/// isPlaying / isLoading / repeatMode 均为结构性状态，由外层主通知重建。
class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.playback});

  final PlaybackController playback;

  void _cycleRepeat(RepeatMode mode) {
    // 三态轮转：all → one → shuffle → all
    final next = switch (mode) {
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.shuffle,
      RepeatMode.shuffle || RepeatMode.off => RepeatMode.all,
    };
    playback.setRepeatMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final iconColor = colors.onSurfaceContainer;
    final dimColor = colors.onSurfaceVariantSummary;
    final accent = colors.primary;

    final state = playback.state;
    final isActive =
        state.repeatMode == RepeatMode.all ||
        state.repeatMode == RepeatMode.one ||
        state.repeatMode == RepeatMode.shuffle;
    final repeatAsset = switch (state.repeatMode) {
      RepeatMode.one => 'assets/icons/MaterialSymbolsRepeatOneRounded.svg',
      RepeatMode.shuffle => 'assets/icons/BxShuffle.svg',
      _ => 'assets/icons/LucideRepeat.svg',
    };
    final tooltip = switch (state.repeatMode) {
      RepeatMode.one => '单曲循环',
      RepeatMode.shuffle => '随机播放',
      _ => '列表循环',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HoverSvgButton(
          asset: repeatAsset,
          color: isActive ? accent : dimColor,
          tooltip: tooltip,
          onPressed: () => _cycleRepeat(state.repeatMode),
        ),
        const SizedBox(width: 4),
        _HoverIconButton(
          icon: Icons.skip_previous_rounded,
          color: iconColor,
          size: 26,
          tooltip: '上一首',
          onPressed: playback.playPrevious,
        ),
        const SizedBox(width: 8),
        _BigPlayButton(playback: playback, accent: accent),
        const SizedBox(width: 8),
        _HoverIconButton(
          icon: Icons.skip_next_rounded,
          color: iconColor,
          size: 26,
          tooltip: '下一首',
          onPressed: playback.playNext,
        ),
        const SizedBox(width: 4),
        // 右段留白占位，维持中段居中。
      ],
    );
  }
}

/// 大圆播放键：强调色实心圆 + 白色播放/暂停；加载时显示环形进度。
class _BigPlayButton extends StatefulWidget {
  const _BigPlayButton({required this.playback, required this.accent});

  final PlaybackController playback;
  final Color accent;

  @override
  State<_BigPlayButton> createState() => _BigPlayButtonState();
}

class _BigPlayButtonState extends State<_BigPlayButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.playback.state;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: state.isLoading ? null : widget.playback.togglePlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover
                ? Color.lerp(widget.accent, Colors.white, 0.12)
                : widget.accent,
            shape: BoxShape.circle,
          ),
          child: state.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 25,
                ),
        ),
      ),
    );
  }
}

/// 右段：时间 / 歌词 / 音量 / 播放列表。
class _RightControls extends StatelessWidget {
  const _RightControls({required this.playback, required this.onOpenLyrics});

  final PlaybackController playback;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final iconColor = colors.onSurfaceContainer;

    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TimeLabel(playback: playback),
          const SizedBox(width: 10),
          _HoverSvgButton(
            asset: 'assets/icons/icon_lyrics.svg',
            color: iconColor,
            tooltip: '歌词',
            onPressed: onOpenLyrics,
          ),
          const SizedBox(width: 4),
          _VolumeControl(playback: playback),
          const SizedBox(width: 4),
          _HoverIconButton(
            icon: Icons.queue_music_rounded,
            color: iconColor,
            tooltip: '播放列表',
            onPressed: () => CyreneToast.show('播放队列即将上线'),
          ),
        ],
      ),
    );
  }
}

/// 播放时间：`已播 / 总时长`。position 走独立高频通知，duration 走主通知。
class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final duration = playback.state.duration;
    return ValueListenableBuilder<Duration>(
      valueListenable: playback.positionListenable,
      builder: (context, position, _) => Text(
        '${_formatDuration(position)} / ${_formatDuration(duration)}',
        style: theme.textStyles.body2.copyWith(
          color: theme.colors.onSurfaceVariantSummary,
          fontSize: 12,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 音量：图标（点击静音/恢复）+ 自绘水平滑块（拖动实时生效）。
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.playback});

  final PlaybackController playback;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  /// 拖动中的临时值（松手即清空，回落到 state.volume）。
  double? _dragVolume;

  /// 静音前的音量，供再次点击图标时恢复。
  double _lastNonZero = 0.8;

  void _set(double value) {
    final v = value.clamp(0.0, 1.0);
    setState(() => _dragVolume = v);
    widget.playback.setVolume(v);
  }

  void _toggleMute() {
    final current = widget.playback.state.volume;
    if (current > 0) {
      _lastNonZero = current;
      widget.playback.setVolume(0);
    } else {
      widget.playback.setVolume(_lastNonZero <= 0 ? 0.8 : _lastNonZero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final volume = (_dragVolume ?? widget.playback.state.volume).clamp(0.0, 1.0);
    final icon = volume <= 0
        ? Icons.volume_off_rounded
        : volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HoverIconButton(
          icon: icon,
          color: colors.onSurfaceContainer,
          tooltip: volume <= 0 ? '取消静音' : '静音',
          size: 20,
          onPressed: _toggleMute,
        ),
        const SizedBox(width: 2),
        SizedBox(
          width: 92,
          height: 24,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                const thumb = 12.0;
                final thumbLeft = (volume * (width - thumb)).clamp(
                  0.0,
                  width - thumb,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _set(d.localPosition.dx / width),
                  onTapUp: (_) => setState(() => _dragVolume = null),
                  onTapCancel: () => setState(() => _dragVolume = null),
                  onHorizontalDragUpdate: (d) =>
                      _set(d.localPosition.dx / width),
                  onHorizontalDragEnd: (_) =>
                      setState(() => _dragVolume = null),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 轨道 + 已填充。
                      Center(
                        child: Container(
                          height: 4,
                          width: width,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: colors.onSurfaceContainer.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: volume,
                            alignment: Alignment.centerLeft,
                            child: ColoredBox(color: colors.primary),
                          ),
                        ),
                      ),
                      // 圆点 thumb。
                      Positioned(
                        left: thumbLeft,
                        child: Container(
                          width: thumb,
                          height: thumb,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.primary,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 通用 hover 图标按钮：桌面悬停高亮底 + 手型光标 + 文字提示。
///
/// 用 Material [Tooltip]（简单 label 语义，不同于会崩的 Slider 语义节点），且外层
/// [DesktopMiniPlayer] 的 [ExcludeSemantics] 已兜底，启动首帧不产生任何语义节点。
class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover
                  ? colors.onSurfaceContainer.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: widget.size, color: widget.color),
          ),
        ),
      ),
    );
  }
}

/// 通用 hover SVG 图标按钮：桌面悬停高亮底 + 手型光标 + 文字提示。
/// 与 [_HoverIconButton] 共用同一套视觉样式，但用 SvgPicture.asset 渲染图标。
class _HoverSvgButton extends StatefulWidget {
  const _HoverSvgButton({
    required this.asset,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.size = 22,
  });

  final String asset;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_HoverSvgButton> createState() => _HoverSvgButtonState();
}

class _HoverSvgButtonState extends State<_HoverSvgButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover
                  ? colors.onSurfaceContainer.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SvgPicture.asset(
              widget.asset,
              width: widget.size,
              height: widget.size,
              colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return '$mm:$ss';
}
