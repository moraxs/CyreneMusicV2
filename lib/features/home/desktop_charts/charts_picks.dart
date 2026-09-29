part of 'desktop_charts_home.dart';

/// 「今天就听这些」：两排方形封面，悬停时封面抬起、右下角浮出播放键。
/// 列数随宽度变化，两排放多少就取多少首，不做横向滚动。
class _PickShelf extends StatelessWidget {
  const _PickShelf({
    super.key,
    required this.tracks,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlay,
  });

  final List<Track> tracks;
  final Track? currentTrack;
  final bool isPlaying;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 18.0;
      final target = 172 * math.max(1.0, _textScale(context) * 0.85);
      final columns = ((constraints.maxWidth + gap) / (target + gap))
          .floor()
          .clamp(2, 8);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final shown = tracks.take(columns * 2).toList(growable: false);
      return Wrap(
        key: const ValueKey('desktop-hot-tracks'),
        spacing: gap,
        runSpacing: 24,
        children: [
          for (final track in shown)
            SizedBox(
              width: width,
              child: _PickCard(
                track: track,
                active: track.key == currentTrack?.key,
                isPlaying: isPlaying,
                onPressed: () => onPlay(track),
              ),
            ),
        ],
      );
    },
  );
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.track,
    required this.active,
    required this.isPlaying,
    required this.onPressed,
  });

  final Track track;
  final bool active;
  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final playing = active && isPlaying;
    return _Hover(
      builder: (context, hovered) => MiuixPressable(
        onPressed: onPressed,
        semanticLabel:
            '${playing ? '暂停' : '播放'} ${track.name}，${track.artists}',
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.97,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LiftedArtwork(
              hovered: hovered,
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ForYouArtwork(url: track.picUrl, cornerRadius: 20),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: AnimatedScale(
                        duration: _kHoverDuration,
                        curve: Curves.easeOutBack,
                        scale: hovered || active ? 1 : 0.6,
                        child: AnimatedOpacity(
                          duration: _kHoverDuration,
                          opacity: hovered || active ? 1 : 0,
                          child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: active && !hovered
                                ? _EqualizerGlyph(
                                    color: palette.onAccent,
                                    height: 15,
                                  )
                                : Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 24,
                                    color: palette.onAccent,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
    );
  }
}
