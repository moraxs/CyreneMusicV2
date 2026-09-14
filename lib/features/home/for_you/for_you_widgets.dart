import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../domain/models/track.dart';
import 'for_you_artwork.dart';
import 'for_you_palette.dart';

/// 仅含推荐页展示所需字段，点击和播放行为仍由首页负责。
@immutable
class ForYouPlaylistData {
  const ForYouPlaylistData({
    required this.id,
    required this.name,
    required this.coverUrl,
    this.heroTag = '',
    this.description = '',
    this.trackCount = 0,
    this.playCount = 0,
  });

  final int id;
  final String name;
  final String coverUrl;
  final String heroTag;
  final String description;
  final int trackCount;
  final int playCount;

  String get caption {
    if (trackCount > 0) return '$trackCount 首歌曲';
    if (description.trim().isNotEmpty) return description.trim();
    return '一份刚刚好的音乐陪伴';
  }
}

/// 固定的暖纸色背景独立重绘，滚动不重新绘制装饰，也不使用全屏模糊。
class ForYouAtmosphere extends StatelessWidget {
  const ForYouAtmosphere({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final surface = MiuixTheme.of(context).colors.surface;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        surface,
                        palette.background,
                        palette.background,
                        surface,
                      ],
                      stops: const [0, 0.18, 0.82, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class ForYouGreeting extends StatelessWidget {
  const ForYouGreeting({
    super.key,
    required this.title,
    required this.subtitle,
    required this.refreshing,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;
    final weekday = const [
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ][now.weekday - 1];
    final night = now.hour >= 18 || now.hour < 6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      night ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                      size: 14,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        '$month 月 $day 日 · $weekday',
                        style: theme.textStyles.footnote1.copyWith(
                          fontSize: 11.5,
                          letterSpacing: 0.6,
                          color: palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  title,
                  style: theme.textStyles.title1.copyWith(
                    fontSize: 29,
                    height: 1.15,
                    letterSpacing: -0.6,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  style: theme.textStyles.body2.copyWith(
                    fontSize: 12.5,
                    height: 1.5,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: '刷新推荐',
            child: MiuixIconButton(
              enabled: !refreshing,
              onPressed: onRefresh,
              backgroundColor: palette.paper,
              cornerRadius: 17,
              minWidth: 44,
              minHeight: 44,
              child: refreshing
                  ? const MiuixInfiniteProgressIndicator(size: 18)
                  : Icon(
                      Icons.refresh_rounded,
                      color: palette.accent,
                      size: 21,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 纸张拼贴主卡：内容区打开推荐详情，独立的主按钮直接播放，不嵌套点击区域。
class ForYouDailyCard extends StatelessWidget {
  const ForYouDailyCard({
    super.key,
    required this.tracks,
    required this.onOpen,
    required this.onPlay,
  });

  final List<Track> tracks;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final now = DateTime.now();
    final covers = tracks
        .map((track) => track.picUrl)
        .where((url) => url.isNotEmpty)
        .take(3)
        .toList(growable: false);
    final count = tracks.length;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: MiuixSquircleBorder(
          cornerRadius: 28,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.peach, palette.paper, palette.rose],
          stops: const [0, 0.7, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Icon(Icons.today_rounded, size: 15, color: palette.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '每日推荐',
                    style: theme.textStyles.body2.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.accent,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.paper.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${now.month} 月 ${now.day} 日',
                    style: theme.textStyles.footnote2.copyWith(
                      fontSize: 11,
                      color: palette.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          MiuixPressable(
            onPressed: onOpen,
            semanticLabel: '查看每日推荐歌单',
            borderRadius: BorderRadius.circular(20),
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final artworkWidth = math.min(
                    148.0,
                    constraints.maxWidth * 0.44,
                  );
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今天，也要\n好好听歌',
                              style: theme.textStyles.title1.copyWith(
                                fontSize: constraints.maxWidth < 270 ? 24 : 28,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                letterSpacing: -0.7,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 11),
                            Text(
                              '把小小的快乐，\n藏进今天的旋律里。',
                              style: theme.textStyles.footnote1.copyWith(
                                fontSize: 12,
                                height: 1.65,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      RepaintBoundary(
                        child: _DailyCoverStack(
                          covers: covers,
                          width: artworkWidth,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 19),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '为你精选 $count 首',
                        style: theme.textStyles.footnote1.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '每天都有新的心动',
                        style: theme.textStyles.footnote2.copyWith(
                          fontSize: 11,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ForYouPlayAction(label: '开始聆听', onPressed: onPlay),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ForYouRadioCard extends StatelessWidget {
  const ForYouRadioCard({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onToggle,
    required this.onSkip,
    required this.onOpen,
  });

  final Track track;
  final bool isPlaying;
  final VoidCallback onToggle;
  final VoidCallback onSkip;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: ShapeDecoration(
        color: palette.sage,
        shape: MiuixSquircleBorder(
          cornerRadius: 25,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.headphones_rounded,
                size: 17,
                color: palette.sageAccent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '私人 FM',
                  style: theme.textStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.sageAccent,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.paper.withValues(
                    alpha: isPlaying ? 0.8 : 0.45,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.sageAccent.withValues(
                          alpha: isPlaying ? 1 : 0.45,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isPlaying ? '正在播放' : '随心收听',
                      style: theme.textStyles.footnote2.copyWith(
                        fontSize: 10,
                        color: palette.sageAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          MiuixPressable(
            onPressed: onOpen,
            semanticLabel: '打开私人 FM 播放器',
            borderRadius: BorderRadius.circular(18),
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    _RadioArtwork(
                      coverUrl: track.picUrl,
                      size: constraints.maxWidth < 290 ? 88 : 102,
                      isPlaying: isPlaying,
                    ),
                    const SizedBox(width: 17),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.headline1.copyWith(
                              fontSize: 18,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.footnote1.copyWith(
                              color: palette.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '进入你的音乐小世界',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textStyles.footnote2.copyWith(
                                    fontSize: 10.5,
                                    color: palette.sageAccent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 12,
                                color: palette.sageAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            height: 0.7,
            color: palette.sageAccent.withValues(alpha: 0.13),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Text(
                  '下一首，也许就是心动',
                  style: theme.textStyles.footnote1.copyWith(
                    fontSize: 11.5,
                    color: palette.muted,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: isPlaying ? '暂停私人 FM' : '播放私人 FM',
                child: MiuixIconButton(
                  onPressed: onToggle,
                  backgroundColor: palette.sageAccent,
                  cornerRadius: 17,
                  minWidth: 48,
                  minHeight: 46,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      key: ValueKey(isPlaying),
                      size: 25,
                      color: palette.onAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Tooltip(
                message: '下一首',
                child: MiuixIconButton(
                  onPressed: onSkip,
                  backgroundColor: palette.paper.withValues(alpha: 0.6),
                  cornerRadius: 16,
                  minWidth: 44,
                  minHeight: 44,
                  child: Icon(
                    Icons.skip_next_rounded,
                    size: 23,
                    color: palette.sageAccent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ForYouSectionHeading extends StatelessWidget {
  const ForYouSectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textStyles.headline1.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.3,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: theme.textStyles.footnote1.copyWith(
                    fontSize: 12,
                    height: 1.5,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// 不套多一层厚重卡片，让封面、细小元信息和留白组成唱片架。
class ForYouPlaylistCard extends StatelessWidget {
  const ForYouPlaylistCard({
    super.key,
    required this.data,
    required this.onTap,
  });

  final ForYouPlaylistData data;
  final ValueChanged<BuildContext> onTap;

  static double heightFor(BuildContext context, double width) {
    final textScaler = MediaQuery.textScalerOf(context);
    return width +
        12 +
        textScaler.scale(14) * 1.35 * 2 +
        5 +
        textScaler.scale(11.5) * 1.35 +
        4;
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final titleHeight = MediaQuery.textScalerOf(context).scale(14) * 1.35 * 2;
    return MiuixPressable(
      onPressed: () => onTap(context),
      semanticLabel: data.name,
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.97,
      shape: const MiuixSquircleBorder(cornerRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ForYouArtwork(url: data.coverUrl, cornerRadius: 21),
                if (data.playCount > 0)
                  Positioned(
                    left: 9,
                    bottom: 9,
                    child: _CoverLabel(
                      text: _formatPlayCount(data.playCount),
                      icon: Icons.headphones_rounded,
                    ),
                  ),
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                      color: palette.paper.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_outward_rounded,
                      size: 14,
                      color: palette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: titleHeight,
            child: Text(
              data.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.body2.copyWith(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            data.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.footnote2.copyWith(
              fontSize: 11.5,
              height: 1.35,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 专属精选与雷达使用宽幅封面，和方形唱片架形成不同的阅读节奏。
class ForYouSpotlightPlaylist extends StatelessWidget {
  const ForYouSpotlightPlaylist({
    super.key,
    required this.data,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final ForYouPlaylistData data;
  final String label;
  final ValueChanged<BuildContext> onTap;
  final bool compact;

  static double heightFor(BuildContext context, {bool compact = false}) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(
      compact ? 176.0 : 218.0,
      104 +
          scaler.scale(compact ? 16 : 21) * 1.3 * 2 +
          scaler.scale(11.5) * 1.35,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return MiuixPressable(
      onPressed: () => onTap(context),
      semanticLabel: data.name,
      shape: const MiuixSquircleBorder(cornerRadius: 24),
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      child: Container(
        height: heightFor(context, compact: compact),
        clipBehavior: Clip.antiAlias,
        decoration: const ShapeDecoration(
          shape: MiuixSquircleBorder(cornerRadius: 24),
        ),
        child: _PlaylistDepthLayers(
          background: RepaintBoundary(
            child: ForYouArtwork(url: data.coverUrl, cornerRadius: 0),
          ),
          overlay: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x20000000),
                  Color(0x30000000),
                  Color(0xD919171C),
                ],
                stops: [0, 0.3, 1],
              ),
            ),
          ),
          foreground: Padding(
            padding: EdgeInsets.all(compact ? 15 : 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverLabel(
                  text: label,
                  icon: compact
                      ? Icons.explore_outlined
                      : Icons.favorite_border_rounded,
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.headline1.copyWith(
                              color: Colors.white,
                              fontSize: compact ? 16 : 21,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            data.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.footnote2.copyWith(
                              fontSize: 11.5,
                              height: 1.35,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 16),
                      Container(
                        width: 39,
                        height: 39,
                        decoration: BoxDecoration(
                          color: palette.paper,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 19,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverLabel extends StatelessWidget {
  const _CoverLabel({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x99000000),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0x30FFFFFF), width: 0.6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          text,
          style: MiuixTheme.of(
            context,
          ).textStyles.footnote2.copyWith(fontSize: 10, color: Colors.white),
        ),
      ],
    ),
  );
}

class ForYouPlayAction extends StatelessWidget {
  const ForYouPlayAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.play_arrow_rounded,
    this.subtle = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final foreground = subtle ? palette.accent : palette.onAccent;
    return MiuixPressable(
      onPressed: onPressed,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: subtle ? 10 : 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: subtle ? palette.paper : palette.accent,
          borderRadius: BorderRadius.circular(18),
          border: subtle
              ? Border.all(color: palette.outline, width: 0.7)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: subtle ? 18 : 20, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: MiuixTheme.of(context).textStyles.button.copyWith(
                fontSize: subtle ? 11.5 : 13,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForYouSongSurface extends StatelessWidget {
  const ForYouSongSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: palette.paper.withValues(alpha: 0.86),
        shape: MiuixSquircleBorder(
          cornerRadius: 20,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      child: child,
    );
  }
}

class ForYouEndNote extends StatelessWidget {
  const ForYouEndNote({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 28, height: 0.7, color: palette.outline),
              const SizedBox(width: 12),
              Icon(
                Icons.favorite_border_rounded,
                size: 15,
                color: palette.accent.withValues(alpha: 0.65),
              ),
              const SizedBox(width: 12),
              Container(width: 28, height: 0.7, color: palette.outline),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '把平凡的日子，听成喜欢的样子。',
            textAlign: TextAlign.center,
            style: MiuixTheme.of(context).textStyles.footnote1.copyWith(
              fontSize: 11.5,
              height: 1.6,
              letterSpacing: 0.5,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPlayCount(int count) {
  if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)} 亿';
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)} 万';
  return count.toString();
}

class _DailyCoverStack extends StatelessWidget {
  const _DailyCoverStack({required this.covers, required this.width});

  final List<String> covers;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox(
          width: width,
          height: width * 1.12,
          child: Stack(
            children: [
              for (var i = 2; i >= 0; i--)
                Positioned(
                  left: width * (0.02 + i * 0.075),
                  top: width * (0.18 - i * 0.065),
                  child: Transform.rotate(
                    angle: (i - 1) * 0.065,
                    child: Container(
                      width: width * 0.8,
                      height: width * 0.8,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: palette.paper,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: palette.outline),
                        boxShadow: [
                          BoxShadow(
                            color: palette.shadow,
                            blurRadius: 14,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: ForYouArtwork(
                        url: covers.isEmpty ? '' : covers[i % covers.length],
                        cornerRadius: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioArtwork extends StatelessWidget {
  const _RadioArtwork({
    required this.coverUrl,
    required this.size,
    required this.isPlaying,
  });

  final String coverUrl;
  final double size;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: palette.paper.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ForYouArtwork(url: coverUrl, cornerRadius: 15),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final height in const <double>[
                    4,
                    8,
                    12,
                    6,
                    14,
                    9,
                    5,
                    11,
                    7,
                  ])
                    Container(
                      width: 3,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: palette.sageAccent.withValues(
                          alpha: isPlaying ? 0.8 : 0.35,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
          ],
        ),
      ),
    );
  }
}

class _PlaylistDepthLayers extends StatelessWidget {
  const _PlaylistDepthLayers({
    required this.background,
    required this.overlay,
    required this.foreground,
  });

  final Widget background;
  final Widget overlay;
  final Widget foreground;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final scrollable = reduceMotion
        ? null
        : Scrollable.maybeOf(context, axis: Axis.vertical);
    return Flow(
      clipBehavior: Clip.none,
      delegate: _PlaylistDepthDelegate(
        scrollable: scrollable,
        cardContext: context,
      ),
      children: [background, overlay, foreground],
    );
  }
}

class _PlaylistDepthDelegate extends FlowDelegate {
  _PlaylistDepthDelegate({required this.scrollable, required this.cardContext})
    : super(repaint: scrollable?.position);

  final ScrollableState? scrollable;
  final BuildContext cardContext;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: constraints.maxWidth,
        height: constraints.maxHeight + (i == 0 ? 72 : 0),
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    var progress = 0.0;
    final viewport = scrollable?.context.findRenderObject();
    final card = cardContext.findRenderObject();
    if (viewport is RenderBox &&
        card is RenderBox &&
        viewport.hasSize &&
        card.hasSize &&
        viewport.size.height > 0) {
      final center = card.localToGlobal(
        card.size.center(Offset.zero),
        ancestor: viewport,
      );
      progress = (center.dy / viewport.size.height * 2 - 1).clamp(-1.0, 1.0);
    }
    context.paintChild(
      0,
      transform: Matrix4.translationValues(0, -36 - progress * 32, 0),
    );
    context.paintChild(1);
    context.paintChild(
      2,
      transform: Matrix4.translationValues(0, progress * 5, 0),
    );
  }

  @override
  bool shouldRepaint(covariant _PlaylistDepthDelegate oldDelegate) =>
      oldDelegate.scrollable != scrollable ||
      oldDelegate.cardContext != cardContext;
}
