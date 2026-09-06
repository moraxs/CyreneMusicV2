import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../application/together/together_controller.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
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
    final together = TogetherController.instance;
    // 队列会被房主的那份实时覆盖，所以这里必须跟着重建；一起听的权限变化
    // （放开/收回点歌）同样要即时反映到按钮上。
    return ListenableBuilder(
      listenable: Listenable.merge([playback, together]),
      builder: (context, _) {
        final state = playback.state;
        final theme = MiuixTheme.of(context);
        // 听众的队列是房主那份的镜像，本地增删只会让两边对不上，直接禁掉。
        final isGuest = together.isActive && !together.isHost;
        final canPick = !isGuest || together.roomAllowGuestControl;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 原 ShadSheet 的 description（歌曲数）与「清空」操作行；标题由抽屉自带。
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isGuest
                      ? '${state.queue.length} 首歌曲 · 跟随房主'
                      : '${state.queue.length} 首歌曲',
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
                if (!isGuest)
                  MiuixTextButton(
                    '清空',
                    enabled: state.queue.isNotEmpty,
                    onPressed: playback.clearQueue,
                  ),
              ],
            ),
            if (isGuest)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    canPick ? '房主开放了点歌，点一首大家一起听' : '房主没有开放点歌',
                    style: theme.textStyles.footnote1.copyWith(
                      color: canPick
                          ? theme.colors.primary
                          : theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                ),
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
                            onPlay: () {
                              if (!isGuest) {
                                playback.playTrack(track, queue: state.queue);
                                return;
                              }
                              // 听众点歌不动本机播放：等服务端把 sync 广播回来，
                              // 房主和所有人一起换。
                              if (!together.requestPlay(track)) {
                                CyreneToast.show('房主没有开放点歌');
                              }
                            },
                            trailing: isGuest
                                ? const SizedBox.shrink()
                                : MiuixIconButton(
                                    onPressed: () =>
                                        playback.removeFromQueue(track),
                                    child: MiuixIcon(
                                      vector: MiuixIcons.extended.byName(
                                        'close',
                                      )!,
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
      },
    );
  }
}
