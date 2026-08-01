import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'home_song_row.dart';

/// 每日推荐详情页（对应原版 DailyRecommendDetailPage 的移动端形态）：
/// 日期卡 + 播放全部 + 可浏览的推荐曲目列表。
class DailyRecommendPage extends StatelessWidget {
  const DailyRecommendPage({
    super.key,
    required this.tracks,
    required this.playback,
  });

  final List<Track> tracks;
  final PlaybackController playback;

  void _playAll() {
    if (tracks.isEmpty) return;
    playback.playTrack(tracks.first, queue: tracks);
    CyreneToast.show('开始播放每日推荐');
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final now = DateTime.now();
    return CyrenePage(
      title: '每日推荐',
      bodyBuilder: (context, topPadding) => ListView(
        padding: topPadding + const EdgeInsets.fromLTRB(12, 0, 12, 32),
        children: [
          MiuixCard(
            cornerRadius: 20,
            insideMargin: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: ShapeDecoration(
                    color: colors.secondaryContainer,
                    shape: const MiuixSquircleBorder(cornerRadius: 18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${now.day}',
                        style: theme.textStyles.title3.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '${now.month}月',
                        style: theme.textStyles.footnote2.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '为您精选 ${tracks.length} 首',
                        style: theme.textStyles.headline1.copyWith(
                          color: colors.onSurfaceContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '每日凌晨更新，遇见你的心头好',
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MiuixIconButton(
                  onPressed: tracks.isEmpty ? null : _playAll,
                  backgroundColor: colors.primary,
                  cornerRadius: 16,
                  minWidth: 48,
                  minHeight: 48,
                  child: MiuixIcon(
                    icon: Icons.play_arrow_rounded,
                    size: 26,
                    tint: colors.onPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: CyreneEmptyState(
                icon: Icons.music_note,
                title: '暂无推荐歌曲',
                description: '每日凌晨更新，稍后再来看看。',
              ),
            )
          else
            CyreneMenuGroup(
              children: [
                for (final track in tracks)
                  HomeSongRow(
                    track: track,
                    playback: playback,
                    onPlay: () => playback.playTrack(track, queue: tracks),
                    onAddToQueue: () => playback.addToQueue(track),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
