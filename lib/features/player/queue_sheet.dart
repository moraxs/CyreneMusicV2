import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import 'cyrene_track_tile.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.playback});

  final PlaybackController playback;

  static Future<void> show(BuildContext context, PlaybackController playback) =>
      showCyreneSheet<void>(
        context: context,
        title: '播放队列',
        builder: (_, _) => QueueSheet(playback: playback),
      );

  @override
  Widget build(BuildContext context) {
    final state = playback.state;
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 原 ShadSheet 的 description（歌曲数）与「清空」操作行；标题由抽屉自带。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${state.queue.length} 首歌曲',
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
            MiuixTextButton(
              '清空',
              enabled: state.queue.isNotEmpty,
              onPressed: playback.clearQueue,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: state.queue.isEmpty
              ? SizedBox(
                  height: 220,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MiuixIcon(
                          vector: MiuixIcons.extended.byName('playlist')!,
                          size: 32,
                          tint: theme.colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '队列空空如也',
                          style: theme.textStyles.body2.copyWith(
                            color: theme.colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  height: MediaQuery.sizeOf(context).height * .52,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: state.queue.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = state.queue[index];
                      return CyreneTrackTile(
                        track: track,
                        isActive: track == state.currentTrack,
                        onPlay: () =>
                            playback.playTrack(track, queue: state.queue),
                        trailing: MiuixIconButton(
                          onPressed: () => playback.removeFromQueue(track),
                          child: MiuixIcon(
                            vector: MiuixIcons.extended.byName('close')!,
                            size: 18,
                            tint: theme.colors.onSurfaceContainer,
                          ),
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
