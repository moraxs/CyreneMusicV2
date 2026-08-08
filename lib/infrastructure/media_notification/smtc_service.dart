import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../application/playback/playback_controller.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/repeat_mode.dart';

/// Windows 系统媒体传输控件（SMTC）桥接服务。
///
/// 监听 [PlaybackController] 的状态变化，通过 MethodChannel 把曲目元数据、
/// 播放状态、播放进度同步到 Windows 原生端（SystemMediaTransportControls，
/// 即任务栏媒体浮层 / Win + 媒体快捷键 / 键盘多媒体键）；同时接收原生端回传
/// 的按钮事件（播放/暂停/上一首/下一首/seek/循环模式），转发到
/// [PlaybackController]。
///
/// 原生端实现在 windows/runner/smtc_handler.{h,cpp}（C++/WinRT，零新增
/// pub 依赖）。仅在 Windows 平台生效；其他平台调用为空操作。
class SmtcService {
  SmtcService(this._playback, {bool? isWindows})
    : _isWindows = isWindows ?? Platform.isWindows;

  final PlaybackController _playback;
  final bool _isWindows;

  static const _channel = MethodChannel('cyrene.music/smtc');
  static const _events = EventChannel('cyrene.music/smtc/events');

  // 缓存上次同步的状态，避免高频重复同步（与 Android MediaNotificationService
  // 的策略一致）。
  Track? _lastTrack;
  bool? _lastIsPlaying;
  Duration? _lastDuration;
  RepeatMode? _lastRepeatMode;

  // position 定时同步（播放中每秒一次，避免每帧都走 channel）。
  Timer? _positionSyncTimer;
  StreamSubscription<dynamic>? _eventSubscription;

  bool _bound = false;
  bool _available = false;

  // 封面文件缓存：同一 URL 只下载一次，路径稳定后不再重复传给原生端。
  String? _lastArtUrl;
  String? _lastArtPath;

  /// 绑定到原生端并开始监听播放状态。
  void start() {
    if (_bound || !_isWindows) return;
    _bound = true;
    _playback.addListener(_onPlaybackChanged);
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error) {
        debugPrint('[SMTC] 事件流异常: $error');
      },
    );
    _channel
        .invokeMethod<bool>('init')
        .then((supported) {
          _available = supported ?? false;
          if (_available) _onPlaybackChanged();
        })
        .catchError((Object error) {
          // 原生端缺失（异常构建）时静默降级，不影响播放器。
          _available = false;
          debugPrint('[SMTC] 初始化失败: $error');
        });
  }

  /// 解绑，停止同步并清空系统媒体控件。
  void stop() {
    if (!_bound) return;
    _bound = false;
    _positionSyncTimer?.cancel();
    _positionSyncTimer = null;
    _playback.removeListener(_onPlaybackChanged);
    _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_available) {
      _channel.invokeMethod('clear');
    }
    _available = false;
  }

  void dispose() => stop();

  // ==================== 原生 → Flutter（按钮事件） ====================

  Future<void> _onNativeEvent(dynamic event) async {
    final map = Map<String, dynamic>.from(event as Map);
    switch (map['event']) {
      case 'play':
        await _resume();
      case 'pause':
        await _pause();
      case 'playPause':
        await _playback.togglePlay();
      case 'next':
        await _playback.playNext();
      case 'previous':
        await _playback.playPrevious();
      case 'seek':
        final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
        await _playback.seek(Duration(milliseconds: positionMs));
      case 'stop':
        await _playback.clearQueue();
      case 'setRepeatMode':
        final mode = map['mode'] as String?;
        if (mode != null) {
          _playback.setRepeatMode(_parseRepeatMode(mode));
        }
    }
  }

  Future<void> _resume() async {
    if (!_playback.state.isPlaying && _playback.state.currentTrack != null) {
      await _playback.togglePlay();
    }
  }

  Future<void> _pause() async {
    if (_playback.state.isPlaying) {
      await _playback.togglePlay();
    }
  }

  // ==================== Flutter → 原生（状态同步） ====================

  void _onPlaybackChanged() {
    if (!_bound || !_available) return;
    final state = _playback.state;

    final track = state.currentTrack;
    final trackChanged = track?.key != _lastTrack?.key;
    final isPlayingChanged = state.isPlaying != _lastIsPlaying;
    final durationChanged = state.duration != _lastDuration;
    final repeatChanged = state.repeatMode != _lastRepeatMode;

    // 无曲目：清空系统媒体控件
    if (track == null) {
      if (_lastTrack != null) {
        _lastTrack = null;
        _channel.invokeMethod('clear');
      }
      _positionSyncTimer?.cancel();
      _positionSyncTimer = null;
      return;
    }

    if (trackChanged || durationChanged || isPlayingChanged || repeatChanged) {
      _lastTrack = track;
      _lastDuration = state.duration;
      _lastIsPlaying = state.isPlaying;
      _lastRepeatMode = state.repeatMode;
      unawaited(_syncFull(track));
    }

    // position 定时同步（播放中每秒一次，与 Android 通知栏一致）
    if (state.isPlaying && _positionSyncTimer == null) {
      _positionSyncTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _syncPosition(),
      );
    } else if (!state.isPlaying && _positionSyncTimer != null) {
      _positionSyncTimer?.cancel();
      _positionSyncTimer = null;
    }
  }

  Future<void> _syncFull(Track track) async {
    final artPath = await _ensureArtwork(track.picUrl);
    if (!_bound || !_available) return;
    await _channel.invokeMethod('update', {
      'title': track.name,
      'artist': track.artists,
      'album': track.album,
      'artPath': artPath,
      'isPlaying': _playback.state.isPlaying,
      'positionMs': _playback.state.position.inMilliseconds,
      'durationMs': _playback.state.duration.inMilliseconds,
      'repeatMode': _repeatModeName(_playback.state.repeatMode),
    });
  }

  void _syncPosition() {
    if (!_bound || !_available) return;
    _channel.invokeMethod('updatePosition', {
      'positionMs': _playback.state.position.inMilliseconds,
    });
  }

  // ==================== 封面 ====================

  /// 把网络封面下载到临时目录并返回本地路径（同一 URL 只下载一次）。
  ///
  /// 下载失败或 URL 为空时返回 null，原生端会跳过缩略图（其余元数据不受影响）。
  Future<String?> _ensureArtwork(String url) async {
    if (url.isEmpty) {
      _lastArtUrl = null;
      _lastArtPath = null;
      return null;
    }
    if (url == _lastArtUrl) return _lastArtPath;
    try {
      final directory = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}cyrene_smtc_art',
      );
      await directory.create(recursive: true);
      final digest = await Sha256().hash(utf8.encode(url));
      final hash = digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final file = File(
        '${directory.path}${Platform.pathSeparator}$hash${_artExtension(url)}',
      );
      if (!file.existsSync()) {
        // 网易 CDN 对非官方 UA 返回 403，须与界面封面一样带上 imageHeaders。
        final response = await http
            .get(Uri.parse(url), headers: imageHeaders(url))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          // 下载失败不缓存映射，下次播放同一首时重试。
          _lastArtUrl = null;
          return _lastArtPath = null;
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
      }
      _lastArtUrl = url;
      return _lastArtPath = file.path;
    } catch (error) {
      debugPrint('[SMTC] 封面下载失败: $error');
      _lastArtUrl = null;
      return _lastArtPath = null;
    }
  }

  static String _artExtension(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return '.png';
    if (lower.contains('.webp')) return '.webp';
    if (lower.contains('.jpeg')) return '.jpg';
    return '.jpg';
  }

  // ==================== 工具方法 ====================

  static String _repeatModeName(RepeatMode mode) => switch (mode) {
    RepeatMode.off => 'off',
    RepeatMode.all => 'all',
    RepeatMode.one => 'one',
    RepeatMode.shuffle => 'shuffle',
  };

  static RepeatMode _parseRepeatMode(String name) => switch (name) {
    'off' => RepeatMode.off,
    'all' => RepeatMode.all,
    'one' => RepeatMode.one,
    'shuffle' => RepeatMode.shuffle,
    _ => RepeatMode.all,
  };
}
