import 'package:flutter/foundation.dart';

import '../../domain/models/playlist.dart';
import '../../domain/models/playlist_import.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/playlist_import_service.dart';
import '../../infrastructure/services/playlist_service.dart';

/// 从第三方平台导入歌单的结果分类。
enum ImportExternalResultKind {
  /// 成功：歌单已创建并写入曲目。
  success,
  /// 输入的 URL/ID 无法解析出歌单 ID。
  parseFailed,
  /// 拉取远端歌单详情失败（ID 不存在或后端不可达）。
  fetchFailed,
  /// 创建新歌单失败。
  createFailed,
  /// 创建了歌单但批量写入曲目失败。
  addTracksFailed,
}

/// [importFromExternal] 的返回值，供 UI 据此弹不同 toast。
class ImportExternalResult {
  const ImportExternalResult({
    required this.kind,
    this.playlist,
    this.importedCount = 0,
  });

  final ImportExternalResultKind kind;

  /// 成功时为新创建的歌单；[addTracksFailed] 时为已创建但写曲失败的歌单。
  final Playlist? playlist;

  /// 成功时为写入的曲目数。
  final int importedCount;

  bool get isSuccess => kind == ImportExternalResultKind.success;
}

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

  /// 从第三方平台导入歌单：
  /// 解析 ID → 拉取远端歌单详情 → 创建空壳歌单（绑定 source） →
  /// 批量写入曲目 → 刷新歌单库。
  ///
  /// [nameOverride] 为预览步用户修改的歌单名；为空则用远端原名。
  ///
  /// 注意：本方法会**再次拉取**远端歌单。若调用方已在预览步拉取过
  /// （如导入弹窗），应改用 [importFetchedExternal] 直接复用已有数据，
  /// 避免重复网络往返与「预览成功、导入时二次拉取失败」的竞态。
  Future<ImportExternalResult> importFromExternal(
    String token,
    MusicPlatform platform,
    String input,
    String nameOverride,
  ) async {
    final id = PlaylistImportService.instance.parsePlaylistId(platform, input);
    if (id == null) {
      return const ImportExternalResult(kind: ImportExternalResultKind.parseFailed);
    }

    final external = await PlaylistImportService.instance.fetchExternalPlaylist(
      platform,
      id,
      token: token,
    );
    if (external == null) {
      return const ImportExternalResult(kind: ImportExternalResultKind.fetchFailed);
    }
    return importFetchedExternal(token, platform, id, external, nameOverride);
  }

  /// 用已在预览步拉取到的 [external] 完成导入：创建空壳歌单（绑定 source）→
  /// 批量写入曲目 → 刷新歌单库。不再发起远端请求。
  ///
  /// [id] 为解析出的歌单 ID（用于绑定 `sourcePlaylistId`）。
  Future<ImportExternalResult> importFetchedExternal(
    String token,
    MusicPlatform platform,
    String id,
    ExternalPlaylist external,
    String nameOverride,
  ) async {
    final finalName = nameOverride.trim().isEmpty
        ? external.name
        : nameOverride.trim();
    final created = await _service.createPlaylist(
      token,
      finalName,
      source: platform.wireName,
      sourcePlaylistId: id,
    );
    if (created == null) {
      return const ImportExternalResult(kind: ImportExternalResultKind.createFailed);
    }

    final inputs = <PlaylistTrackInput>[
      for (final t in external.tracks)
        (
          trackId: t.id,
          name: t.name,
          artists: t.artists,
          album: t.album,
          picUrl: t.picUrl,
          source: t.source.wireName,
        ),
    ];
    final ok = await _service.addTracksToPlaylist(token, created.id, inputs);
    if (!ok) {
      return ImportExternalResult(
        kind: ImportExternalResultKind.addTracksFailed,
        playlist: created,
      );
    }

    // 写入成功后刷新歌单库，让列表立刻出现新歌单。
    if (token.isNotEmpty) {
      await load(token);
    }
    return ImportExternalResult(
      kind: ImportExternalResultKind.success,
      playlist: created,
      importedCount: inputs.length,
    );
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
