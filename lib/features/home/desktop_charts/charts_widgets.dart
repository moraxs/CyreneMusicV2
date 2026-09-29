part of 'desktop_charts_home.dart';

/// 按系统字号换算一行文字的实际高度，用于给固定高度的版块预留空间。
double _line(BuildContext context, double fontSize, [double height = 1.35]) =>
    MediaQuery.textScalerOf(context).scale(fontSize) * height;

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;

/// 四种纸色轮换，相邻两张榜单不同色；鼠尾草底配深绿，其余用陶土色。
(Color tint, Color accent) _tone(ForYouPalette palette, int index) =>
    switch (index % 4) {
      0 => (palette.peach, palette.accent),
      1 => (palette.sage, palette.sageAccent),
      2 => (palette.rose, palette.accent),
      _ => (Color.lerp(palette.peach, palette.sage, 0.5)!, palette.accent),
    };

const _kHoverDuration = Duration(milliseconds: 180);

/// 只把悬停状态交给 [builder]。点击光标与悬停高亮已由 MiuixPressable 提供，
/// 这里补的是「抬起 / 露出播放键 / 黑胶滑出」这类需要知道悬停的装饰。
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  var _hovered = false;

  void _set(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _set(true),
    onExit: (_) => _set(false),
    child: widget.builder(context, _hovered),
  );
}

/// 悬停时轻轻抬起并加深投影的封面。
class _LiftedArtwork extends StatelessWidget {
  const _LiftedArtwork({
    required this.hovered,
    required this.child,
    this.radius = 20,
  });

  final bool hovered;
  final Widget child;
  final double radius;

  static const lift = 5.0;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return AnimatedContainer(
      duration: _kHoverDuration,
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, hovered ? -lift : 0, 0),
      decoration: ShapeDecoration(
        shape: MiuixSquircleBorder(cornerRadius: radius),
        shadows: [
          BoxShadow(
            color: palette.shadow.withValues(
              alpha: palette.shadow.a * (hovered ? 2.4 : 1),
            ),
            blurRadius: hovered ? 26 : 14,
            offset: Offset(0, hovered ? 12 : 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final enabled = onPressed != null;
    return MiuixPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.96,
      overlayColor: palette.onAccent,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: enabled ? 1 : 0.35),
          borderRadius: BorderRadius.circular(22),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: palette.onAccent),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textStyles.button.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final color = palette.accent.withValues(alpha: onPressed == null ? 0.4 : 1);
    return MiuixPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.96,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.outline, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: theme.textStyles.button.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 3),
              Icon(trailingIcon, size: 17, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.size = 36,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final enabled = onPressed != null;
    final background = filled ? palette.accent : palette.paper;
    final foreground = filled ? palette.onAccent : palette.ink;
    return MiuixPressable(
      onPressed: onPressed,
      semanticLabel: label,
      shape: const CircleBorder(),
      feedbackType: MiuixPressFeedbackType.sink,
      overlayColor: foreground,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background.withValues(alpha: enabled ? 1 : 0.4),
          border: filled
              ? null
              : Border.all(color: palette.outline, width: 0.8),
          boxShadow: filled && enabled
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: size * 0.52,
          color: foreground.withValues(alpha: enabled ? 1 : 0.5),
        ),
      ),
    );
  }
}

/// 分区标题：大号标题 + 一行说明，右侧放操作。窄屏或大字号时操作换到下一行。
class _Heading extends StatelessWidget {
  const _Heading({
    super.key,
    required this.title,
    this.subtitle = '',
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textStyles.title3.copyWith(
            fontSize: 22,
            height: 1.3,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: palette.ink,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.footnote1.copyWith(
              fontSize: 12.5,
              height: 1.45,
              color: palette.muted,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 40, 4, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trailing = this.trailing;
          if (trailing == null) return heading;
          if (constraints.maxWidth < 460 || _textScale(context) > 1.4) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 10), trailing],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              trailing,
            ],
          );
        },
      ),
    );
  }
}

/// 纸张底卡：半透明暖白 + 细描边，承载列表类内容。
class _PaperSurface extends StatelessWidget {
  const _PaperSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  static const radius = 28.0;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: palette.paper.withValues(alpha: 0.86),
        shape: MiuixSquircleBorder(
          cornerRadius: radius,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      child: child,
    );
  }
}

/// 静态的均衡器图形，表示「正在播放」。刻意不做常驻动画，免得整页每帧重绘。
class _EqualizerGlyph extends StatelessWidget {
  const _EqualizerGlyph({required this.color, this.height = 16});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final factor in const [0.45, 1.0, 0.7, 0.85])
            Container(
              width: 3,
              height: height * factor,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 封面角标：歌单 / 专辑 / 电台……
class _KindTag extends StatelessWidget {
  const _KindTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x66000000),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x30FFFFFF), width: 0.6),
    ),
    child: Text(
      label,
      style: MiuixTheme.of(
        context,
      ).textStyles.footnote2.copyWith(fontSize: 10.5, color: Colors.white),
    ),
  );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 一行歌曲。带 [rank] 时是排行榜样式：前三名陶土色大号斜体，悬停时名次
/// 换成播放键；当前曲目整行着色并显示均衡器。
class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.track,
    required this.active,
    required this.isPlaying,
    required this.onPressed,
    this.rank,
    this.rankColor,
    this.showDuration = false,
  });

  final Track track;
  final bool active;
  final bool isPlaying;
  final VoidCallback onPressed;
  final int? rank;
  final Color? rankColor;
  final bool showDuration;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final playing = active && isPlaying;
    final duration = track.duration;
    return _Hover(
      builder: (context, hovered) => MiuixPressable(
        onPressed: onPressed,
        semanticLabel:
            '${playing ? '暂停' : '播放'} ${track.name}，${track.artists}',
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: _kHoverDuration,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? palette.accent.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              if (rank != null) ...[
                SizedBox(
                  width: 34,
                  child: Center(
                    child: hovered
                        ? Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                            color: palette.accent,
                          )
                        : _RankNumber(
                            rank: rank!,
                            color: rankColor ?? palette.accent,
                          ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              ForYouArtwork(url: track.picUrl, size: 46, cornerRadius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body2.copyWith(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: active ? palette.accent : palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.footnote2.copyWith(
                        fontSize: 12,
                        height: 1.35,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (showDuration && duration != null) ...[
                const SizedBox(width: 10),
                Text(
                  _formatDuration(duration),
                  style: theme.textStyles.footnote2.copyWith(
                    fontSize: 12,
                    color: palette.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                child: active
                    ? _EqualizerGlyph(color: palette.accent, height: 14)
                    : rank == null && hovered
                    ? Icon(
                        Icons.play_arrow_rounded,
                        size: 20,
                        color: palette.accent,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankNumber extends StatelessWidget {
  const _RankNumber({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final podium = rank <= 3;
    return Text(
      '$rank',
      style: theme.textStyles.body1.copyWith(
        fontSize: podium ? 21 : 16,
        height: 1.1,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
        color: podium ? color : palette.muted.withValues(alpha: 0.75),
      ),
    );
  }
}

class _ChartsUnavailable extends StatelessWidget {
  const _ChartsUnavailable({
    required this.loading,
    required this.onRetry,
    this.message,
  });

  final bool loading;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    if (loading) {
      return Semantics(
        label: '正在加载榜单',
        liveRegion: true,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 280,
                padding: const EdgeInsets.all(34),
                decoration: ShapeDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.peach, palette.paper, palette.rose],
                    stops: const [0, 0.62, 1],
                  ),
                  shape: MiuixSquircleBorder(
                    cornerRadius: 32,
                    side: BorderSide(color: palette.outline, width: 0.7),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SkeletonBlock(width: 90, height: 12),
                    SizedBox(height: 16),
                    _SkeletonBlock(width: 220, height: 34),
                    SizedBox(height: 14),
                    _SkeletonBlock(width: 180, height: 14),
                    SizedBox(height: 28),
                    _SkeletonBlock(width: 130, height: 44),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                '正在加载榜单…',
                style: theme.textStyles.body2.copyWith(color: palette.muted),
              ),
              const SizedBox(height: 16),
              const _SkeletonBlock(width: double.infinity, height: 420),
            ],
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 52),
      decoration: ShapeDecoration(
        color: palette.paper.withValues(alpha: 0.86),
        shape: MiuixSquircleBorder(
          cornerRadius: 32,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.rose, palette.peach],
              ),
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              size: 32,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '暂无榜单',
            textAlign: TextAlign.center,
            style: theme.textStyles.title4.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message ?? '暂时没有可用的榜单，请稍后重试。',
              textAlign: TextAlign.center,
              style: theme.textStyles.body2.copyWith(
                color: palette.muted,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _AccentButton(
            label: '重新加载',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: ForYouPalette.of(context).ink.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(math.min(height / 3, 22)),
    ),
  );
}
