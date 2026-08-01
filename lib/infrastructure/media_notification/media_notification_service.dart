import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/repeat_mode.dart';

/// 安卓系统通知栏媒体控制器桥接服务。
///
/// 监听 [PlaybackController] 的状态变化，通过 MethodChannel 把曲目元数据、
/// 播放状态同步到原生端（MediaSession + 媒体通知）；同时接收原生端回传的
/// 通知按钮事件（播放/暂停/上一首/下一首/seek），转发到 [PlaybackController]。
///
/// 仅在 Android 平台生效；其他平台调用为空操作。
class MediaNotificationService {
  MediaNotificationService(this._playback);

  final PlaybackController _playback;

  static const _channel = MethodChannel('com.cyrene.media/notification');

  // 缓存上次同步的状态，避免高频重复同步
  Track? _lastTrack;
  bool? _lastIsPlaying;
  Duration? _lastDuration;
  RepeatMode? _lastRepeatMode;

  // position 定时同步（播放中每秒一次，避免每帧都走 channel）
  Timer? _positionSyncTimer;

  bool _initialized = false;
  bool _bound = false;

  /// 绑定到原生端并开始监听播放状态。
  void start() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler(_onMethodCall);
    _playback.addListener(_onPlaybackChanged);
    _ensureInitialized();
  }

  /// 解绑，停止同步并隐藏通知。
  void stop() {
    if (!_bound) return;
    _bound = false;
    _positionSyncTimer?.cancel();
    _positionSyncTimer = null;
    _playback.removeListener(_onPlaybackChanged);
    _channel.setMethodCallHandler(null);
    if (Platform.isAndroid) {
      _channel.invokeMethod('hide');
    }
  }

  void dispose() => stop();

  // ==================== 原生 → Flutter（按钮事件） ====================

  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
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
        final posMs = (call.arguments as num?)?.toInt() ?? 0;
        await _playback.seek(Duration(milliseconds: posMs));
      case 'stop':
        await _playback.clearQueue();
      case 'setRepeatMode':
        final mode = call.arguments as String?;
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

  Future<void> _ensureInitialized() async {
    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;
    // 通知原生端已完成通道注册
    await _channel.invokeMethod('ready');
    // 立即同步一次当前状态
    _onPlaybackChanged();
  }

  void _onPlaybackChanged() {
    if (!_bound || !Platform.isAndroid) return;
    final state = _playback.state;

    final track = state.currentTrack;
    final trackChanged = track?.key != _lastTrack?.key;
    final isPlayingChanged = state.isPlaying != _lastIsPlaying;
    final durationChanged = state.duration != _lastDuration;
    final repeatChanged = state.repeatMode != _lastRepeatMode;

    // 无曲目：隐藏通知
    if (track == null) {
      if (_lastTrack != null) {
        _lastTrack = null;
        _channel.invokeMethod('hide');
      }
      _positionSyncTimer?.cancel();
      _positionSyncTimer = null;
      return;
    }

    // 曲目/时长变化：完整同步元数据
    if (trackChanged || durationChanged) {
      _lastTrack = track;
      _lastDuration = state.duration;
      _channel.invokeMethod('updateTrack', {
        'title': track.name,
        'artist': track.artists,
        'album': track.album,
        'artUrl': track.picUrl,
        'durationMs': state.duration.inMilliseconds,
        'positionMs': state.position.inMilliseconds,
        'isPlaying': state.isPlaying,
      });
    } else if (isPlayingChanged) {
      // 仅播放状态变化
      _channel.invokeMethod('updatePlayback', {
        'isPlaying': state.isPlaying,
        'positionMs': state.position.inMilliseconds,
      });
    }

    // 循环模式变化
    if (repeatChanged) {
      _lastRepeatMode = state.repeatMode;
      _channel.invokeMethod('updateRepeatMode', {
        'repeatMode': _repeatModeName(state.repeatMode),
      });
    }

    _lastIsPlaying = state.isPlaying;

    // position 定时同步
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

  void _syncPosition() {
    if (!_bound || !Platform.isAndroid) return;
    _channel.invokeMethod('updatePosition', {
      'positionMs': _playback.state.position.inMilliseconds,
    });
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
