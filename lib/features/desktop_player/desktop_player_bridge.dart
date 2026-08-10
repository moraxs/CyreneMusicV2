import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/playback/repeat_mode.dart';
import '../../infrastructure/services/playlist_service.dart';

/// 主窗口 ↔ 桌面歌词子窗口之间的通道常量。
///
/// 不再依赖 desktop_multi_window 插件：runner 在子引擎 messenger 上注册了
/// 三个标准 MethodChannel，主引擎侧再通过原始字节中继把它们接通到子引擎：
/// - [toSubChannel]：主→子，主窗口推送播放状态。
/// - [toMainChannel]：子→主，子窗口索要状态 / 回传播放控制命令。
/// - [directChannel]：子→原生（cyrene/desktop_lyrics），setHitRects 直达，
///   不经主窗口中转——这是修复「设置按钮点不动」的结构性保证。
class DesktopPlayerBridge {
  DesktopPlayerBridge._();

  /// 主→子：主窗口推送播放状态。
  static const toSubChannel = 'cyrene/desktop_lyrics/to_sub';

  /// 子→主：子窗口索要状态 / 回传命令。
  static const toMainChannel = 'cyrene/desktop_lyrics/to_main';

  /// 子→原生：setHitRects 直达（命中区域）。
  static const directChannel = 'cyrene/desktop_lyrics';

  static const methodSyncState = 'syncState';
  static const methodSyncPosition = 'syncPosition';
  static const methodSyncQueue = 'syncQueue';
  static const methodRequestState = 'requestState';
  static const methodCommand = 'command';
  static const methodSetHitRects = 'setHitRects';
  static const methodSetWallpaperAcrylic = 'setWallpaperAcrylic';

  /// 把播放状态编码为可跨窗口传输的 JSON 字符串。
  ///
  /// Track 直接走它自带的 toJson/fromJson（含 lyric/yrc/tlyric/ytlrc 四种
  /// 歌词字段），不手写字段映射——否则漏一个歌词字段歌词就不显示。
  ///
  /// 队列**不**放在这里：它体量大且变化频率远低于播放状态，单独走
  /// [methodSyncQueue]，只在队列签名变化时推送（见 DesktopPlayerStateSender）。
  static String encodeState(
    PlaybackController playback, {
    required bool favorite,
    required bool favoriteAvailable,
  }) {
    final state = playback.state;
    final track = state.currentTrack;
    return jsonEncode({
      'isPlaying': state.isPlaying,
      'durationMs': state.duration.inMilliseconds,
      'volume': state.volume,
      'repeatMode': state.repeatMode.name,
      'favorite': favorite,
      'favoriteAvailable': favoriteAvailable,
      'track': track?.toJson(),
    });
  }

  /// 队列的**去歌词**编码：展览馆要真正的 [Track] 对象（封面/专辑/时长都要用），
  /// 因此走 Track.toJson，但把四份歌词剔掉。
  ///
  /// 绝不能直接整包 `track.toJson()`——那会把每首歌的 lyric/yrc/tlyric/ytlrc
  /// 一起塞进去，几百首的队列一次推送就是几 MB，跨引擎通道会直接卡住主线程。
  /// 当前曲目的歌词另经 [methodSyncState] 单独推送。
  static String encodeQueue(PlaybackController playback) => jsonEncode({
    'tracks': [
      for (final track in playback.state.queue)
        track.toJson()
          ..remove('lyric')
          ..remove('yrc')
          ..remove('tlyric')
          ..remove('ytlrc'),
    ],
  });
}

/// 主窗口侧：监听 PlaybackController，把状态推送给桌面歌词子窗口。
///
/// 生命周期与桌面播放器窗口绑定——窗口关闭时必须 dispose，否则会持续向
/// 一个已销毁的引擎发消息（invoke 会抛 PlatformException，被 catchError 吞掉）。
///
/// 不再依赖 WindowController：主窗口可以先注册 [toMainChannel] 的命令 handler，
/// 再创建窗口——这样子窗口启动后索要状态（requestState）时主窗口一定已就绪，
/// 消灭了原插件方案下「sender 早于 handler 注册导致第一帧丢失」的竞态。
///
/// 收藏状态也在这一侧解算：子窗口是独立引擎，重新搭一套鉴权 + 网络栈既冗余
/// 又要复制登录态，不如由持有 [account] 的主窗口查好了随状态一起推过去。
class DesktopPlayerStateSender {
  DesktopPlayerStateSender({required this.playback, this.account}) {
    playback.addListener(_onStateChanged);
    playback.positionListenable.addListener(_onPositionChanged);
    account?.addListener(_onAccountChanged);
    _inbound.setMethodCallHandler((call) async {
      switch (call.method) {
        case DesktopPlayerBridge.methodRequestState:
          _onStateChanged();
          _onPositionChanged();
          _pushQueue();
        case DesktopPlayerBridge.methodCommand:
          await _runCommand(call.arguments);
      }
      return null;
    });
    // 主动推一次：子窗口若已就绪就能立刻显示，不必等它来问。
    _onStateChanged();
  }

  final PlaybackController playback;

  /// 登录态来源。为空（未注入或未登录）时收藏按钮在面板上显示为不可用。
  final AccountSessionController? account;

  late final MethodChannel _inbound = const MethodChannel(
    DesktopPlayerBridge.toMainChannel,
  );

  bool _disposed = false;

  String? _lastTrackKey;
  String? _lastQueueSignature;

  bool _favorite = false;
  int _favoriteRequest = 0;

  /// 「收藏」落到哪个歌单：用户的默认歌单（无默认则取第一个）。解析一次后
  /// 缓存，切换账号时由 [_onAccountChanged] 失效。
  int? _defaultPlaylistId;

  void _onStateChanged() {
    if (_disposed) return;
    final trackKey = playback.state.currentTrack?.key;
    if (trackKey != _lastTrackKey) {
      _lastTrackKey = trackKey;
      // 切歌后旧的收藏态已无意义，先清再异步查，避免面板短暂显示上一首的爱心。
      _favorite = false;
      unawaited(_refreshFavorite());
    }
    _pushState();
    _pushQueue();
  }

  void _pushState() {
    if (_disposed) return;
    _send(
      DesktopPlayerBridge.methodSyncState,
      DesktopPlayerBridge.encodeState(
        playback,
        favorite: _favorite,
        favoriteAvailable: account?.token != null,
      ),
    );
  }

  /// 队列只在内容真正变化时推送：状态变更（播放/暂停/切歌）每次都带上队列的话，
  /// 几百首的列表会被反复序列化。
  void _pushQueue() {
    if (_disposed) return;
    final signature = playback.state.queue.map((track) => track.key).join('|');
    if (signature == _lastQueueSignature) return;
    _lastQueueSignature = signature;
    _send(
      DesktopPlayerBridge.methodSyncQueue,
      DesktopPlayerBridge.encodeQueue(playback),
    );
  }

  void _onPositionChanged() {
    if (_disposed) return;
    _send(
      DesktopPlayerBridge.methodSyncPosition,
      playback.positionListenable.value.inMilliseconds,
    );
  }

  void _onAccountChanged() {
    if (_disposed) return;
    // 换账号后默认歌单不同，缓存必须作废，否则会把歌收进上一个账号的歌单 id。
    _defaultPlaylistId = null;
    unawaited(_refreshFavorite());
  }

  /// 执行子窗口回传的播放控制命令（在主窗口的真实 PlaybackController 上）。
  ///
  /// [arguments] 为 `{'action': String, 'value': Object?}`。
  Future<void> _runCommand(Object? arguments) async {
    if (arguments is! Map) {
      debugPrint('[桌面播放器] 命令格式错误: $arguments');
      return;
    }
    final action = arguments['action']?.toString();
    final value = arguments['value'];
    switch (action) {
      case 'togglePlay':
        await playback.togglePlay();
      case 'next':
        await playback.playNext();
      case 'previous':
        await playback.playPrevious();
      case 'seek':
        if (value is num) {
          await playback.seek(Duration(milliseconds: value.toInt()));
        }
      case 'setVolume':
        if (value is num) await playback.setVolume(value.toDouble());
      case 'setRepeatMode':
        playback.setRepeatMode(
          RepeatMode.values.firstWhere(
            (mode) => mode.name == value,
            orElse: () => RepeatMode.all,
          ),
        );
      case 'toggleFavorite':
        await _toggleFavorite();
      case 'playTrack':
        final track = playback.state.queue
            .where((item) => item.key == value)
            .firstOrNull;
        if (track != null) {
          await playback.playTrack(track, queue: playback.state.queue);
        }
      case 'removeFromQueue':
        final track = playback.state.queue
            .where((item) => item.key == value)
            .firstOrNull;
        if (track != null) playback.removeFromQueue(track);
      case 'clearQueue':
        await playback.clearQueue();
      default:
        debugPrint('[桌面播放器] 未知命令: $action');
    }
  }

  /// 查当前曲目是否在默认歌单里，并把结果推给子窗口。
  Future<void> _refreshFavorite() async {
    final request = ++_favoriteRequest;
    final token = account?.token;
    final track = playback.state.currentTrack;
    if (token == null || track == null) {
      _favorite = false;
      _pushState();
      return;
    }
    final playlistId = await _ensureDefaultPlaylist(token);
    if (_disposed || request != _favoriteRequest) return;
    if (playlistId == null) {
      _favorite = false;
      _pushState();
      return;
    }
    final result = await PlaylistService.instance.checkTrackInPlaylists(
      token,
      track.id,
      track.source.wireName,
    );
    if (_disposed || request != _favoriteRequest) return;
    _favorite = result.playlistIds.contains(playlistId);
    _pushState();
  }

  /// 收藏 = 加入/移出默认歌单。
  ///
  /// 覆盖层被钉在 z-order 底层，弹「选择歌单」这类模态会被任何窗口盖住，
  /// 且要临时把整屏变成命中区域，因此这里固定走默认歌单，不弹选择面板。
  Future<void> _toggleFavorite() async {
    final token = account?.token;
    final track = playback.state.currentTrack;
    if (token == null || track == null) return;
    final playlistId = await _ensureDefaultPlaylist(token);
    if (_disposed) return;
    if (playlistId == null) {
      debugPrint('[桌面播放器] 收藏失败：账号下没有任何歌单');
      return;
    }
    final service = PlaylistService.instance;
    final ok = _favorite
        ? await service.removeTrackFromPlaylist(
            token,
            playlistId,
            track.id,
            track.source.wireName,
          )
        : await service.addTrackToPlaylist(
            token,
            playlistId,
            track.id,
            track.name,
            track.artists,
            track.album,
            track.picUrl,
            track.source.wireName,
          );
    if (_disposed) return;
    if (ok) _favorite = !_favorite;
    _pushState();
  }

  Future<int?> _ensureDefaultPlaylist(String token) async {
    final cached = _defaultPlaylistId;
    if (cached != null) return cached;
    final playlists = await PlaylistService.instance.getPlaylists(token);
    if (playlists.isEmpty) return null;
    final target = playlists
        .where((playlist) => playlist.isDefault)
        .firstOrNull;
    return _defaultPlaylistId = (target ?? playlists.first).id;
  }

  void _send(String method, Object? arguments) {
    _outbound.invokeMethod<void>(method, arguments).catchError((Object e) {
      // 进度每 200ms 一次，失败时不刷屏；状态推送失败才值得记录
      // （子窗口可能尚未就绪，或已被销毁）。
      if (method != DesktopPlayerBridge.methodSyncPosition) {
        debugPrint('[桌面播放器] 状态推送失败($method): $e');
      }
      return null;
    });
  }

  late final MethodChannel _outbound = const MethodChannel(
    DesktopPlayerBridge.toSubChannel,
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    playback.removeListener(_onStateChanged);
    playback.positionListenable.removeListener(_onPositionChanged);
    account?.removeListener(_onAccountChanged);
    _inbound.setMethodCallHandler(null);
  }
}

/// 子窗口侧：向主窗口回传播放控制命令。
///
/// 子窗口的 PlaybackController 只是显示层（gateway 不接音频），直接调它的
/// play/pause 不会发声，因此面板上的操作必须经此转交主窗口执行。
class DesktopPlayerCommands {
  DesktopPlayerCommands._();

  static const MethodChannel _toMain = MethodChannel(
    DesktopPlayerBridge.toMainChannel,
  );

  /// [action] 取 togglePlay / next / previous / seek / setVolume /
  /// setRepeatMode / toggleFavorite / playTrack；[value] 为对应参数。
  static Future<void> send(String action, [Object? value]) async {
    try {
      await _toMain.invokeMethod<void>(DesktopPlayerBridge.methodCommand, {
        'action': action,
        'value': value,
      });
    } catch (e) {
      debugPrint('[桌面播放器][子窗口] 命令发送失败($action): $e');
    }
  }

  /// 上报可交互矩形（窗口客户区物理像素，[l,t,r,b] 扁平列表）。
  ///
  /// 直达原生 `cyrene/desktop_lyrics` 通道——子引擎上该方法在 C++ 侧于引擎
  /// 启动时同步注册，早于子引擎 Dart 运行，不可能再丢。
  static Future<void> setHitRects(List<int> rects) async {
    try {
      await const MethodChannel(
        DesktopPlayerBridge.directChannel,
      ).invokeMethod<void>(DesktopPlayerBridge.methodSetHitRects, rects);
      debugPrint('[桌面播放器][子窗口] 交互区域已上报: $rects');
    } catch (e) {
      debugPrint('[桌面播放器][子窗口] 交互区域上报失败: $e');
    }
  }

  /// 开关覆盖层窗口的「壁纸亚克力」（DWM 实时模糊桌面壁纸）。
  ///
  /// Flutter 的 BackdropFilter 只能模糊本层已绘制的内容；覆盖层背后的真实壁纸
  /// （含 Wallpaper Engine 动态壁纸）不在 Flutter 合成树里，纯 Dart 模糊不到，
  /// 只能交给 DWM（见 desktop_lyrics_window.cpp 的 SetWallpaperAcrylic）。
  ///
  /// [argb] 是叠在模糊之上的着色层，A 在高字节。返回是否生效——Win10 1809
  /// 之前没有该 API，调用方据此回退到不模糊的暗色蒙版。
  static Future<bool> setWallpaperAcrylic({
    required bool enabled,
    int argb = 0x99101014,
  }) async {
    try {
      final ok = await const MethodChannel(
        DesktopPlayerBridge.directChannel,
      ).invokeMethod<bool>(DesktopPlayerBridge.methodSetWallpaperAcrylic, {
        'enabled': enabled,
        'argb': argb,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[桌面播放器][子窗口] 壁纸亚克力设置失败: $e');
      return false;
    }
  }
}
