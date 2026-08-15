import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'fullscreen/add_to_playlist_sheet.dart';

/// 歌曲操作菜单（卡片三个点）：下一首播放 / 收藏到歌单。
///
/// 命令式入口：从搜索、歌单等歌曲卡片的三个点触发，弹 Miuix 底部抽屉。
/// 「收藏到歌单」需要登录态，[token] 由调用方从 `AccountSessionController`
/// 传入（与迷你播放器/经典播放器的收藏按钮同一取法）；null 表示未登录，
/// 点击时提示先登录。
Future<void> showTrackActionMenu(
  BuildContext context, {
  required Track track,
  required PlaybackController playback,
  required String? token,
}) async {
  final action = await showCyreneSheet<_TrackAction>(
    context: context,
    title: track.name,
    builder: (_, dismiss) => _TrackActionMenu(
      track: track,
      playback: playback,
      dismiss: dismiss,
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _TrackAction.playNext:
      playback.playNextTrack(track);
      CyreneToast.show('已设为下一首播放');
    case _TrackAction.favorite:
      await _favoriteToPlaylist(context, track, token);
  }
}

/// 「收藏到歌单」动作：登录校验后弹歌单选择抽屉（勾选加入 / 取消勾选移除，
/// 可新建），复用 AddToPlaylistSheet。
Future<void> _favoriteToPlaylist(
  BuildContext context,
  Track track,
  String? token,
) async {
  if (token == null || token.isEmpty) {
    CyreneToast.show('请先登录后再收藏');
    return;
  }
  await AddToPlaylistSheet.show(
    context,
    token: token,
    track: track,
  );
}

enum _TrackAction { playNext, favorite }

class _TrackActionMenu extends StatelessWidget {
  const _TrackActionMenu({
    required this.track,
    required this.playback,
    required this.dismiss,
  });

  final Track track;
  final PlaybackController playback;
  final void Function([_TrackAction? action]) dismiss;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final secondaryText = theme.textStyles.body2.copyWith(
      color: colors.onSurfaceVariantSummary,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${track.artists} · ${track.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondaryText,
              ),
              const SizedBox(height: 6),
              _ActionRow(
                icon: MiuixIcons.extended.byName('forward')!,
                title: '下一首播放',
                onTap: () => dismiss(_TrackAction.playNext),
              ),
              _ActionRow(
                icon: MiuixIcons.extended.byName('favorites')!,
                title: '收藏到歌单',
                onTap: () => dismiss(_TrackAction.favorite),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final MiuixVectorIcon icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixBasicComponent(
      title: title,
      insideMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      startAction: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: MiuixIcon(
          vector: icon,
          size: 20,
          tint: colors.onBackground,
        ),
      ),
      onClick: onTap,
      role: MiuixBasicComponentRole.button,
    );
  }
}
