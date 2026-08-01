import 'package:flutter/foundation.dart';

import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/playlist_service.dart';

class PlaylistLibraryState {
  const PlaylistLibraryState({
    this.playlists = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<Playlist> playlists;
  final bool isLoading;
  final String? errorMessage;
}

class PlaylistLibraryController extends ChangeNotifier {
  PlaylistLibraryController({PlaylistService? service})
    : _service = service ?? PlaylistService.instance;

  final PlaylistService _service;
  PlaylistLibraryState _state = const PlaylistLibraryState();
  int _requestId = 0;
  bool _disposed = false;

  PlaylistLibraryState get state => _state;

  /// 拉取歌单库。
  ///
  /// **发布状态前先让出一个微任务**：`load()` 通常在页面 `initState` 里调用，
  /// 而桌面外壳首帧会在 fluent `NavigationView` 的布局回调里用 IndexedStack
  /// 一次性挂载全部页面——此刻同步 `notifyListeners()` 会把已挂载的兄弟页
  /// （如同样监听本控制器的桌面首页）在构建期标脏，直接触发
  /// "setState() called during build" 断言并引发异常雪崩。让出一帧后再发布，
  /// 调用方就无需关心自己是否处于构建期。
  ///
  /// 让出期间若有更新的请求进来，旧请求由 [_isStale] 判定过期后丢弃，
  /// 因此重复调用只会有最后一次生效。
  Future<void> load(String? token) async {
    final request = ++_requestId;
    await Future<void>.microtask(() {});
    if (_isStale(request)) return;
    if (token == null || token.isEmpty) {
      _publish(const PlaylistLibraryState());
      return;
    }
    _publish(
      PlaylistLibraryState(playlists: _state.playlists, isLoading: true),
    );
    final playlists = await _service.getPlaylists(token);
    if (_isStale(request)) return;
    _publish(PlaylistLibraryState(playlists: playlists));
  }

  Future<Playlist?> create(String token, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;
    final playlist = await _service.createPlaylist(token, name);
    if (playlist != null && !_disposed) {
      _publish(
        PlaylistLibraryState(playlists: [..._state.playlists, playlist]),
      );
    }
    return playlist;
  }

  Future<bool> delete(String token, Playlist playlist) async {
    final deleted = await _service.deletePlaylist(token, playlist.id);
    if (deleted && !_disposed) {
      _publish(
        PlaylistLibraryState(
          playlists: _state.playlists
              .where((item) => item.id != playlist.id)
              .toList(growable: false),
        ),
      );
    }
    return deleted;
  }

  Future<List<PlaylistTrack>> tracks(String token, int playlistId) =>
      _service.getPlaylistTracks(token, playlistId);

  Future<CheckTrackResult> membership(String token, Track track) =>
      _service.checkTrackInPlaylists(token, track.id, track.source.wireName);

  Future<bool> removeTrack(String token, int playlistId, Track track) =>
      _service.removeTrackFromPlaylist(
        token,
        playlistId,
        track.id,
        track.source.wireName,
      );

  Future<bool> addTrack(String token, int playlistId, Track track) =>
      _service.addTrackToPlaylist(
        token,
        playlistId,
        track.id,
        track.name,
        track.artists,
        track.album,
        track.picUrl,
        track.source.wireName,
      );

  bool _isStale(int request) => _disposed || request != _requestId;

  void _publish(PlaylistLibraryState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
