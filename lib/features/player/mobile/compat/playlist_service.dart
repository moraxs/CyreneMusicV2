import 'package:flutter/foundation.dart';

import '../../../../domain/models/playlist.dart';
import '../../../../domain/models/track.dart';
import '../../../../infrastructure/services/playlist_service.dart' as app;
import 'player_service.dart';

export '../../../../domain/models/playlist.dart' show Playlist;

/// 与原版同名的查询结果模型。
class TrackInPlaylistResult {
  const TrackInPlaylistResult({
    required this.inPlaylist,
    required this.playlistIds,
    required this.playlistNames,
  });

  final bool inPlaylist;
  final List<int> playlistIds;
  final List<String> playlistNames;
}

/// 原版 `PlaylistService` 兼容层：token 取自登录会话，接口转发到
/// 新架构的 PlaylistService。
class PlaylistService extends ChangeNotifier {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal();

  List<Playlist> _playlists = const [];

  List<Playlist> get playlists => _playlists;

  String? get _token => PlayerService().account?.token;

  Future<void> loadPlaylists() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      _playlists = await app.PlaylistService.instance.getPlaylists(token);
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistService compat] 加载歌单失败: $e');
    }
  }

  Future<bool> addTrackToPlaylist(int playlistId, Track track) async {
    final token = _token;
    if (token == null || token.isEmpty) return false;
    return app.PlaylistService.instance.addTrackToPlaylist(
      token,
      playlistId,
      track.id,
      track.name,
      track.artists,
      track.album,
      track.picUrl,
      track.source.wireName,
    );
  }

  Future<bool> removeTrackFromPlaylist(
    int playlistId,
    String trackId,
    String source,
  ) async {
    final token = _token;
    if (token == null || token.isEmpty) return false;
    return app.PlaylistService.instance.removeTrackFromPlaylist(
      token,
      playlistId,
      trackId,
      source,
    );
  }

  Future<TrackInPlaylistResult> isTrackInAnyPlaylist(Track track) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return const TrackInPlaylistResult(
        inPlaylist: false,
        playlistIds: [],
        playlistNames: [],
      );
    }
    final result = await app.PlaylistService.instance.checkTrackInPlaylists(
      token,
      track.id,
      track.source.wireName,
    );
    return TrackInPlaylistResult(
      inPlaylist: result.inPlaylist,
      playlistIds: result.playlistIds,
      playlistNames: result.playlistNames,
    );
  }
}
