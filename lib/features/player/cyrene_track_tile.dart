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
    this.trailing,
    this.isActive = false,
  });

  final Track track;
  final VoidCallback onPlay;
  final VoidCallback? onAddToQueue;
  final Widget? trailing;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final titleColor = isActive ? colors.primary : colors.onSurfaceContainer;
    return MiuixCard(
      insideMargin: const EdgeInsets.all(12),
      onPressed: onPlay,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Semantics(
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
      ),
    );
  }
}
