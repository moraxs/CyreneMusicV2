import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../domain/models/track.dart';
import 'track_artwork.dart';

class CyreneTrackTile extends StatelessWidget {
  const CyreneTrackTile({
    super.key,
    required this.track,
    required this.onPlay,
    this.onAddToQueue,
    this.onShowMenu,
    this.trailing,
    this.isActive = false,
    this.isGlass = false,
  });

  final Track track;
  final VoidCallback onPlay;
  final VoidCallback? onAddToQueue;

  /// 三个点入口：null 时回落为直接加入队列（[onAddToQueue]）或前进箭头。
  /// 搜索结果页、歌单详情页用它在卡片上弹出歌曲操作菜单。
  final VoidCallback? onShowMenu;
  final Widget? trailing;
  final bool isActive;
  final bool isGlass;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isActive ? colors.primary : colors.onSurfaceContainer;

    final content = Semantics(
      button: true,
      selected: isActive,
      label: '${track.name}，${track.artists}',
      child: Row(
        children: [
          TrackArtwork(track: track, size: 52, borderRadius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.artists} · ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote1.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onShowMenu != null)
            MiuixIconButton(
              key: ValueKey('menu-${track.id}'),
              onPressed: onShowMenu,
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName('more')!,
                size: 20,
                tint: colors.onSurfaceContainer,
              ),
            )
          else if (onAddToQueue != null)
            MiuixIconButton(
              key: ValueKey('add-${track.id}'),
              onPressed: onAddToQueue,
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName('more')!,
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
      ),
    );

    if (isGlass) {
      final glassBg = isDark
          ? const Color(0x33000000)
          : const Color(0x73FFFFFF);
      final borderColor = isDark
          ? const Color(0x1FFFFFFF)
          : const Color(0x33FFFFFF);

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: 0.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPlay,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MiuixCard(
      insideMargin: const EdgeInsets.all(12),
      onPressed: onPlay,
      feedbackType: MiuixPressFeedbackType.sink,
      child: content,
    );
  }
}
