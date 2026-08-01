import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../player/track_artwork.dart';

/// 分组卡片（CyreneMenuGroup）内的歌曲行：可选排名 + 封面 + 曲名/歌手。
///
/// 自行监听 [playback] 的**当前曲目变化**，当前播放曲目高亮为主题色，
/// 父级无需因播放状态重建。
///
/// 性能要点：[PlaybackController] 在播放进度（position）变化时也会
/// `notifyListeners`（高频，每秒数十次）。若用 [ListenableBuilder] 监听
/// 整个 playback，榜单页数十个本组件会每秒重建数十次，滑动严重卡顿。
/// 因此改为 [StatefulWidget] 手动监听，仅在 `isActive` 真正变化时
/// `setState`，position 变化只做一次轻量 key 比较，不触发重建。
class HomeSongRow extends StatefulWidget {
  const HomeSongRow({
    super.key,
    required this.track,
    required this.playback,
    required this.onPlay,
    this.rank,
    this.onAddToQueue,
  });

  final Track track;
  final PlaybackController playback;
  final VoidCallback onPlay;
  final int? rank;
  final VoidCallback? onAddToQueue;

  @override
  State<HomeSongRow> createState() => _HomeSongRowState();
}

class _HomeSongRowState extends State<HomeSongRow> {
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.playback.state.currentTrack?.key == widget.track.key;
    widget.playback.addListener(_onPlaybackChanged);
  }

  @override
  void didUpdateWidget(HomeSongRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.playback, oldWidget.playback)) {
      oldWidget.playback.removeListener(_onPlaybackChanged);
      widget.playback.addListener(_onPlaybackChanged);
    }
    if (widget.track.key != oldWidget.track.key) {
      _isActive = widget.playback.state.currentTrack?.key == widget.track.key;
    }
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  /// playback 通知回调：position 变化也会触发，但这里只做一次 key 比较，
  /// 仅在当前曲目与本行曲目的高亮状态翻转时才 setState。
  void _onPlaybackChanged() {
    final active =
        widget.playback.state.currentTrack?.key == widget.track.key;
    if (active != _isActive) {
      setState(() => _isActive = active);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixBasicComponent(
      title: widget.track.name,
      titleColor: _isActive
          ? MiuixBasicComponentColors(
              color: colors.primary,
              disabledColor: colors.disabledOnSurface,
            )
          : null,
      summary: widget.track.artists,
      insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      startAction: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.rank != null) ...[
              SizedBox(
                width: 22,
                child: Text(
                  '${widget.rank}',
                  textAlign: TextAlign.center,
                  style: theme.textStyles.body1.copyWith(
                    color: widget.rank! <= 3
                        ? colors.primary
                        : colors.onSurfaceVariantSummary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            TrackArtwork(track: widget.track, size: 44, borderRadius: 10),
          ],
        ),
      ),
      endActions: [
        if (widget.onAddToQueue != null)
          MiuixIconButton(
            onPressed: widget.onAddToQueue,
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('playlist')!,
              size: 20,
              tint: colors.onSurfaceContainer,
            ),
          )
        else
          MiuixIcon(
            vector: MiuixIcons.extended.byName('chevronForward')!,
            size: 16,
            tint: colors.onSurfaceVariantActions,
          ),
      ],
      onClick: widget.onPlay,
      role: MiuixBasicComponentRole.button,
    );
  }
}
