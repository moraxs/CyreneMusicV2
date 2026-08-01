import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/playback/repeat_mode.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import 'lyric_view.dart';
import 'queue_sheet.dart';
import 'track_artwork.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final state = playback.state;
    final track = state.currentTrack;
    if (track == null) {
      return const CyrenePage(
        title: '播放器',
        body: CyreneEmptyState(
          icon: Icons.music_note,
          title: '还没有选择歌曲',
          description: '从发现或搜索页面选择一首歌曲开始播放。',
        ),
      );
    }

    final duration = state.duration;
    final progress = duration == Duration.zero
        ? 0.0
        : (state.position.inMilliseconds / duration.inMilliseconds)
              .clamp(0, 1)
              .toDouble();

    return CyrenePage(
      title: '正在播放',
      actions: [
        MiuixIconButton(
          onPressed: () => QueueSheet.show(context, playback),
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('playlist')!,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final theme = MiuixTheme.of(context);
          final artworkSize = math.min(
            MediaQuery.sizeOf(context).width - 72,
            constraints.maxHeight * .36,
          );
          return Column(
            children: [
              const SizedBox(height: 18),
              MiuixCard(
                insideMargin: const EdgeInsets.all(8),
                child: TrackArtwork(
                  track: track,
                  size: artworkSize,
                  borderRadius: 10,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      track.name,
                      style: theme.textStyles.title3.copyWith(
                        color: theme.colors.onBackground,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body2.copyWith(
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    MiuixSlider(
                      value: progress * 100,
                      max: 100,
                      onValueChanged: (value) => playback.seek(
                        Duration(
                          milliseconds: (duration.inMilliseconds * value / 100)
                              .round(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _format(state.position),
                          style: theme.textStyles.body2.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                        Text(
                          _format(duration),
                          style: theme.textStyles.body2.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _PlaybackControls(
                      repeatMode: state.repeatMode,
                      isLoading: state.isLoading,
                      isPlaying: state.isPlaying,
                      onRepeat: () =>
                          playback.setRepeatMode(_nextMode(state.repeatMode)),
                      onPrevious: playback.playPrevious,
                      onToggle: playback.togglePlay,
                      onNext: playback.playNext,
                      onQueue: () => QueueSheet.show(context, playback),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LyricView(track: track, position: state.position),
              ),
            ],
          );
        },
      ),
    );
  }

  RepeatMode _nextMode(RepeatMode mode) => switch (mode) {
    RepeatMode.all => RepeatMode.one,
    RepeatMode.one => RepeatMode.shuffle,
    RepeatMode.shuffle => RepeatMode.off,
    RepeatMode.off => RepeatMode.all,
  };

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.repeatMode,
    required this.isLoading,
    required this.isPlaying,
    required this.onRepeat,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onQueue,
  });

  final RepeatMode repeatMode;
  final bool isLoading;
  final bool isPlaying;
  final VoidCallback onRepeat;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        MiuixIconButton(
          onPressed: onRepeat,
          child: SvgPicture.asset(
            _repeatAsset(repeatMode),
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(
              MiuixTheme.of(context).colors.onSurfaceContainer,
              BlendMode.srcIn,
            ),
          ),
        ),
        MiuixIconButton(
          onPressed: onPrevious,
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('chevronBackward')!,
            size: 22,
          ),
        ),
        MiuixIconButton(
          enabled: !isLoading,
          onPressed: onToggle,
          backgroundColor: colors.primary,
          child: isLoading
              ? MiuixCircularProgressIndicator(
                  size: 22,
                  strokeWidth: 2,
                  colors: MiuixProgressIndicatorColors(
                    foregroundColor: colors.onPrimary,
                    disabledForegroundColor: colors.onPrimary,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : MiuixIcon(
                  vector: MiuixIcons.extended.byName(
                    isPlaying ? 'pause' : 'play',
                  )!,
                  size: 25,
                  tint: colors.onPrimary,
                ),
        ),
        MiuixIconButton(
          onPressed: onNext,
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('chevronForward')!,
            size: 22,
          ),
        ),
        MiuixIconButton(
          onPressed: onQueue,
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('playlist')!,
            size: 20,
          ),
        ),
      ],
    );
  }

  String _repeatAsset(RepeatMode mode) => switch (mode) {
    RepeatMode.one => 'assets/icons/MaterialSymbolsRepeatOneRounded.svg',
    RepeatMode.shuffle => 'assets/icons/BxShuffle.svg',
    RepeatMode.all => 'assets/icons/LucideRepeat.svg',
    RepeatMode.off => 'assets/icons/LucideRepeat.svg',
  };
}
