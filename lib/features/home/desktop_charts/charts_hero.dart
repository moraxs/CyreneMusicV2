part of 'desktop_charts_home.dart';

/// 首屏一排：随心畅听横幅 + 票根式正在播放。宽屏并排等高，窄屏上下堆叠。
class _ListeningRow extends StatelessWidget {
  const _ListeningRow({required this.hero, required this.ticket});

  final Widget Function(double? height) hero;
  final Widget Function(double? height) ticket;

  static const _ticketWidth = 348.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000 && _textScale(context) <= 1.3;
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [hero(null), const SizedBox(height: 16), ticket(null)],
        );
      }
      final height = math.max(
        _MixHero.heightFor(context),
        _ListeningTicket.heightFor(context),
      );
      return SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: hero(height)),
            const SizedBox(width: 20),
            SizedBox(width: _ticketWidth, child: ticket(height)),
          ],
        ),
      );
    },
  );
}

/// 随心畅听：左侧文案与操作，右侧是各榜榜首封面散开的拼贴，后面探出一张黑胶。
/// 悬停时拼贴微微散开、黑胶转一点角度。
class _MixHero extends StatelessWidget {
  const _MixHero({
    required this.height,
    required this.covers,
    required this.chartCount,
    required this.trackCount,
    required this.onShuffle,
    required this.onBrowse,
    this.leadTrack,
  });

  final double? height;
  final List<String> covers;
  final int chartCount;
  final int trackCount;
  final Track? leadTrack;
  final VoidCallback? onShuffle;
  final VoidCallback onBrowse;

  static double heightFor(BuildContext context) => math.max(
    288.0,
    30 +
        _line(context, 13) +
        12 +
        _line(context, 38, 1.15) +
        10 +
        _line(context, 14) +
        6 +
        _line(context, 13) +
        26 +
        math.max(44.0, _line(context, 14) + 20) +
        // 大字号下两枚按钮可能折成两行。
        (_textScale(context) > 1.1 ? 54 : 0) +
        30,
  );

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final lead = leadTrack;
    return _Hover(
      builder: (context, hovered) => LayoutBuilder(
        builder: (context, constraints) {
          final showFan =
              constraints.maxWidth >= 560 && _textScale(context) <= 1.6;
          final fanWidth = showFan
              ? (constraints.maxWidth * 0.44).clamp(250.0, 440.0)
              : 0.0;
          return Container(
            key: const ValueKey('desktop-charts-hero'),
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.peach, palette.paper, palette.rose],
                stops: const [0, 0.58, 1],
              ),
              shape: MiuixSquircleBorder(
                cornerRadius: 32,
                side: BorderSide(color: palette.outline, width: 0.7),
              ),
            ),
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _GroovePainter(
                          color: palette.accent.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showFan)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: fanWidth,
                    child: _CoverFan(covers: covers, spread: hovered),
                  ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    34,
                    30,
                    fanWidth + 16,
                    30,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.shuffle_rounded,
                            size: 16,
                            color: palette.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '随机模式',
                            style: theme.textStyles.body2.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: palette.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '随心畅听',
                        style: theme.textStyles.title1.copyWith(
                          fontSize: 38,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$chartCount 张榜单 · $trackCount 首热歌，打乱了一起听',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.body2.copyWith(
                          fontSize: 14,
                          height: 1.35,
                          color: palette.muted,
                        ),
                      ),
                      if (lead != null) ...[
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: '此刻最热  '),
                              TextSpan(
                                text: lead.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: palette.ink,
                                ),
                              ),
                              TextSpan(text: ' · ${lead.artists}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.footnote1.copyWith(
                            fontSize: 13,
                            height: 1.35,
                            color: palette.muted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _AccentButton(
                            label: '开始播放',
                            icon: Icons.play_arrow_rounded,
                            semanticLabel: '随机播放全部榜单',
                            onPressed: onShuffle,
                          ),
                          _GhostButton(
                            label: '浏览排行榜',
                            trailingIcon: Icons.south_rounded,
                            onPressed: onBrowse,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 横幅底纹：从左下角荡开的几圈唱片纹路。
class _GroovePainter extends CustomPainter {
  const _GroovePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final center = Offset(size.width * 0.04, size.height * 1.08);
    for (var r = 70.0; r < size.width * 0.62; r += 24) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GroovePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 三张相片式封面 + 一张黑胶 + 一枚「榜首」贴纸。
class _CoverFan extends StatelessWidget {
  const _CoverFan({required this.covers, required this.spread});

  final List<String> covers;
  final bool spread;

  static const _duration = Duration(milliseconds: 420);
  static const _curve = Curves.easeOutBack;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    String cover(int index) =>
        covers.isEmpty ? '' : covers[index % covers.length];
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            final w = constraints.maxWidth;
            final record = h * 0.82;
            final back = h * 0.4;
            final front = h * 0.5;
            final frontLeft = w * 0.16;
            final frontTop = h - h * 0.1 - front - 8;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  right: spread ? -h * 0.14 : -h * 0.24,
                  top: (h - record) / 2,
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    turns: spread ? 0.12 : 0,
                    child: ForYouRecord(coverUrl: cover(3), size: record),
                  ),
                ),
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  left: spread ? w * 0.0 : w * 0.04,
                  top: h * 0.12,
                  child: AnimatedRotation(
                    duration: _duration,
                    curve: _curve,
                    turns: (spread ? -0.3 : -0.2) / (2 * math.pi),
                    child: _Print(url: cover(1), size: back),
                  ),
                ),
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  left: spread ? w * 0.4 : w * 0.34,
                  top: spread ? h * 0.03 : h * 0.07,
                  child: AnimatedRotation(
                    duration: _duration,
                    curve: _curve,
                    turns: (spread ? 0.26 : 0.16) / (2 * math.pi),
                    child: _Print(url: cover(2), size: back),
                  ),
                ),
                Positioned(
                  left: frontLeft,
                  top: frontTop,
                  child: AnimatedRotation(
                    duration: _duration,
                    curve: _curve,
                    turns: (spread ? 0.0 : -0.04) / (2 * math.pi),
                    child: _Print(url: cover(0), size: front),
                  ),
                ),
                Positioned(
                  left: frontLeft + front - 22,
                  top: frontTop - 16,
                  child: AnimatedScale(
                    duration: _duration,
                    curve: _curve,
                    scale: spread ? 1.12 : 1,
                    child: Transform.rotate(
                      angle: -0.26,
                      child: Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.paper, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: palette.shadow,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          '榜首',
                          textScaler: TextScaler.noScaling,
                          style: theme.textStyles.footnote1.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: palette.onAccent,
                          ),
                        ),
                      ),
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

/// 带白边的相片式封面。
class _Print extends StatelessWidget {
  const _Print({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: palette.paper,
        shape: const MiuixSquircleBorder(cornerRadius: 18),
        shadows: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: palette.shadow.a * 1.6),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ForYouArtwork(url: url, size: size, cornerRadius: 14),
    );
  }
}

/// 票根式的「正在播放 / 继续收听」：上半是曲目与播放键，打孔虚线下的存根
/// 叠着最近听过的封面，点进播放记录。
class _ListeningTicket extends StatelessWidget {
  const _ListeningTicket({
    required this.height,
    required this.currentTrack,
    required this.isPlaying,
    required this.recentTracks,
    required this.mix,
    required this.onPlay,
    required this.onToggle,
    required this.onOpenPlayer,
    required this.onOpenHistory,
  });

  final double? height;
  final Track? currentTrack;
  final bool isPlaying;
  final List<Track> recentTracks;
  final List<Track> mix;
  final _PlayTracks onPlay;
  final VoidCallback onToggle;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenHistory;

  static double _stubHeight(BuildContext context) =>
      math.max(68.0, _line(context, 13) + 40);

  static double heightFor(BuildContext context) =>
      22 +
      math.max(32.0, _line(context, 12.5)) +
      18 +
      math.max(84.0, _line(context, 16, 1.3) * 2 + 4 + _line(context, 12.5)) +
      22 +
      _stubHeight(context);

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final track = currentTrack ?? recentTracks.firstOrNull ?? mix.firstOrNull;
    final hasCurrent = currentTrack != null;
    final playing = hasCurrent && isPlaying;
    final title = hasCurrent
        ? (playing ? '正在播放' : '继续收听')
        : recentTracks.isNotEmpty
        ? '最近收听'
        : '试听一首';
    final onListen = track == null
        ? null
        : hasCurrent
        ? onToggle
        : () => onPlay(track, recentTracks.isNotEmpty ? recentTracks : mix);
    final stubHeight = _stubHeight(context);

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                if (playing) ...[
                  _EqualizerGlyph(color: palette.accent, height: 13),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote1.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: playing ? palette.accent : palette.muted,
                    ),
                  ),
                ),
                if (hasCurrent)
                  _RoundButton(
                    label: '打开播放器',
                    icon: Icons.open_in_full_rounded,
                    onPressed: onOpenPlayer,
                    size: 32,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  shape: const MiuixSquircleBorder(cornerRadius: 18),
                  shadows: [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ForYouArtwork(
                  url: track?.picUrl ?? '',
                  size: 84,
                  cornerRadius: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.name ?? '暂无歌曲',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body1.copyWith(
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track?.artists ?? '选择一个榜单开始收听',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.footnote1.copyWith(
                        fontSize: 12.5,
                        height: 1.35,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RoundButton(
                label: playing ? '暂停播放' : '继续播放',
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onPressed: onListen,
                size: 50,
                filled: true,
              ),
            ],
          ),
        ],
      ),
    );

    final recent = recentTracks.take(4).toList(growable: false);
    final stub = Container(
      height: stubHeight,
      color: palette.sage.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (recent.isNotEmpty) ...[
            SizedBox(
              width: 30 + (recent.length - 1) * 19,
              height: 30,
              child: Stack(
                children: [
                  for (var i = recent.length - 1; i >= 0; i--)
                    Positioned(
                      left: i * 19,
                      child: Container(
                        width: 30,
                        height: 30,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: palette.paper,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: ForYouArtwork(
                            url: recent[i].picUrl,
                            cornerRadius: 0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              recentTracks.isEmpty
                  ? '还没有播放记录'
                  : '最近听过 ${recentTracks.length} 首',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote1.copyWith(
                fontSize: 13,
                color: palette.sageAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _GhostButton(
            label: '播放记录',
            trailingIcon: Icons.chevron_right_rounded,
            semanticLabel: '查看播放记录',
            onPressed: onOpenHistory,
          ),
        ],
      ),
    );

    return Container(
      key: const ValueKey('desktop-listening-panel'),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: palette.paper,
        shape: _TicketBorder(
          notchFromBottom: stubHeight,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
        shadows: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (height == null) top else Expanded(child: Center(child: top)),
          CustomPaint(
            size: const Size.fromHeight(1),
            painter: _PerforationPainter(
              color: palette.ink.withValues(alpha: 0.16),
              inset: _TicketBorder.notchRadius + 8,
            ),
          ),
          stub,
        ],
      ),
    );
  }
}

/// 票根外形：圆角矩形在左右两侧各咬掉一个半圆缺口，缺口对齐打孔线。
class _TicketBorder extends ShapeBorder {
  const _TicketBorder({
    required this.notchFromBottom,
    this.side = BorderSide.none,
  });

  final double notchFromBottom;
  final BorderSide side;

  static const radius = 28.0;
  static const notchRadius = 11.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(radius)));
    final y = rect.bottom - notchFromBottom;
    final notches = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(rect.left, y), radius: notchRadius),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(rect.right, y), radius: notchRadius),
      );
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      _TicketBorder(notchFromBottom: notchFromBottom * t, side: side.scale(t));
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter({required this.color, required this.inset});

  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 5.0;
    final y = size.height / 2;
    for (var x = inset; x < size.width - inset; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width - inset), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.inset != inset;
}
