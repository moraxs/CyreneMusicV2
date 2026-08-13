import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/playlist_service.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'fullscreen/add_to_playlist_sheet.dart';

/// 桌面端共享收藏按钮：把当前曲目加入 / 移出后端歌单。
///
/// 与 [DesktopMiniPlayer] 里的 [_LikeButton] 同源同逻辑，但渲染改走胶囊栏
/// 的 Miuix 风格（空心 / 实心 + 颜色高亮），以便在 [DesktopFullscreenPlayer]
/// 的 `_MainCapsule` 里复用，替代原先的「收藏功能即将上线」占位。
///
/// 点击交互沿用应用既有范式（迷你条 _LikeButton / 全屏 FullscreenPlayer）：
/// - 未登录 → 提示「请先登录后再收藏」；
/// - 未在任何歌单 → 只有一个歌单则直接添加，多个则弹 [AddToPlaylistSheet]；
/// - 已在一个歌单 → 直接移除（不弹层）；
/// - 已在多个歌单 → 弹 [AddToPlaylistSheet]（仅显示已加入，勾选移除）。
///
/// 切歌时自动刷新收藏态；进度 tick 走独立通知，不会触发网络查询。
class DesktopFavoriteButton extends StatefulWidget {
  const DesktopFavoriteButton({
    super.key,
    required this.playback,
    required this.account,
    this.iconSize = 23,
  });

  final PlaybackController playback;
  final AccountSessionController account;
  final double iconSize;

  @override
  State<DesktopFavoriteButton> createState() => _DesktopFavoriteButtonState();
}

class _DesktopFavoriteButtonState extends State<DesktopFavoriteButton> {
  final _service = PlaylistService.instance;

  List<int> _playlistIds = const [];
  List<String> _playlistNames = const [];
  int _favoriteRequest = 0;
  String? _lastTrackKey;

  @override
  void initState() {
    super.initState();
    _lastTrackKey = widget.playback.state.currentTrack?.key;
    widget.playback.addListener(_onPlaybackChanged);
    _refreshLike();
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  /// 仅在当前曲目变化时刷新收藏态；进度 tick / 播放暂停等结构变更不换曲，
  /// 都不会触发网络查询。
  void _onPlaybackChanged() {
    final key = widget.playback.state.currentTrack?.key;
    if (key == _lastTrackKey) return;
    _lastTrackKey = key;
    _refreshLike();
  }

  Future<void> _refreshLike() async {
    final request = ++_favoriteRequest;
    final track = widget.playback.state.currentTrack;
    final token = widget.account.token;
    if (track == null || token == null) {
      if (mounted && _playlistIds.isNotEmpty) {
        setState(() {
          _playlistIds = const [];
          _playlistNames = const [];
        });
      }
      return;
    }
    final result = await _service.checkTrackInPlaylists(
      token,
      track.id,
      track.source.wireName,
    );
    if (!mounted || request != _favoriteRequest) return;
    setState(() {
      _playlistIds = result.playlistIds;
      _playlistNames = result.playlistNames;
    });
  }

  bool get _favorited => _playlistIds.isNotEmpty;

  Future<void> _onTap() async {
    final track = widget.playback.state.currentTrack;
    if (track == null) return;
    final token = widget.account.token;
    if (token == null) {
      CyreneToast.show('请先登录后再收藏');
      return;
    }
    // 以最新歌单归属为准（图标可能因切歌略滞后）。
    await _refreshLike();
    if (!mounted) return;

    // 已在歌单中 → 移除。
    if (_playlistIds.isNotEmpty) {
      if (_playlistIds.length == 1) {
        final ok = await _service.removeTrackFromPlaylist(
          token,
          _playlistIds.first,
          track.id,
          track.source.wireName,
        );
        CyreneToast.show(ok ? '已从歌单中移除' : '从歌单移除失败');
        if (ok) await _refreshLike();
        return;
      }
      final changed = await AddToPlaylistSheet.show(
        context,
        token: token,
        track: track,
        showOnlyJoinedInitially: true,
      );
      if (changed == true) await _refreshLike();
      return;
    }

    // 未在任何歌单中 → 添加。
    final playlists = await _service.getPlaylists(token);
    if (!mounted) return;
    if (playlists.isEmpty) {
      CyreneToast.show('还没有歌单，请先在歌单页创建');
      return;
    }
    if (playlists.length == 1) {
      final playlist = playlists.first;
      final ok = await _service.addTrackToPlaylist(
        token,
        playlist.id,
        track.id,
        track.name,
        track.artists,
        track.album,
        track.picUrl,
        track.source.wireName,
      );
      CyreneToast.show(ok ? '已收藏到「${playlist.name}」' : '收藏失败');
      if (ok) await _refreshLike();
      return;
    }
    final changed = await AddToPlaylistSheet.show(
      context,
      token: token,
      track: track,
      showOnlyJoinedInitially: false,
    );
    if (changed == true) await _refreshLike();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final favorited = _favorited;
    final tooltip = favorited
        ? '已收藏到: ${_playlistNames.join(", ")}'
        : '添加到歌单';
    final tint = favorited
        ? const Color(0xFFEF4444)
        : theme.colors.onSurfaceContainer;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: _onTap,
        icon: Icon(
          favorited ? Icons.favorite : Icons.favorite_border,
          size: widget.iconSize,
          color: tint,
        ),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          hoverColor: theme.colors.onSurfaceContainer.withValues(alpha: 0.08),
          highlightColor:
              theme.colors.onSurfaceContainer.withValues(alpha: 0.13),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
