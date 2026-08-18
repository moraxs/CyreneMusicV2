import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';

/// iOS 锁屏/控制中心媒体卡片桥接服务。
///
/// 监听 [PlaybackController] 的状态变化，通过 MethodChannel
/// `cyrene.music/now_playing` 把曲目元数据、播放状态、进度同步到原生端
/// （AVAudioSession + MPRemoteCommandCenter + MPNowPlayingInfoCenter，
/// 实现在 ios/Runner/NowPlayingBridge.swift）；同时接收原生端回传的按钮
/// 事件（播放/暂停/上一首/下一首/seek），转发到 [PlaybackController]。
///
/// 后台播放能力由 Info.plist 的 `UIBackgroundModes = audio` 放行，由原生端
/// 在启动时激活播放音频会话。仅在 iOS 平台生效；其他平台调用为空操作。
/// 与 Android 的 [MediaNotificationService]、Windows 的 SmtcService 同构。
class IosNowPlayingService {
  IosNowPlayingService(this._playback, {bool? isIOS})
    : _isIOS = isIOS ?? Platform.isIOS;

  final PlaybackController _playback;
  final bool _isIOS;

  static const _channel = MethodChannel('cyrene.music/now_playing');

  // 缓存上次同步的状态，避免高频重复同步。
  Track? _lastTrack;
  bool? _lastIsPlaying;
  Duration? _lastDuration;

  // position 定时同步（播放中每秒一次，避免每帧都走 channel）。
  Timer? _positionSyncTimer;

  bool _initialized = false;
  bool _bound = false;

  /// 绑定到原生端并开始监听播放状态。
  void start() {
    if (_bound || !_isIOS) return;
    _bound = true;
    _channel.setMethodCallHandler(_onMethodCall);
    _playback.addListener(_onPlaybackChanged);
    _ensureInitialized();
  }

  /// 解绑，停止同步并清空系统媒体卡片。
  void stop() {
    if (!_bound) return;
    _bound = false;
    _positionSyncTimer?.cancel();
    _positionSyncTimer = null;
    _playback.removeListener(_onPlaybackChanged);
    _channel.setMethodCallHandler(null);
    if (_isIOS) {
      _channel.invokeMethod('clear');
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
    if (_initialized || !_isIOS) return;
    _initialized = true;
    // 通知原生端已完成通道注册。
    await _channel.invokeMethod('ready');
    // 立即同步一次当前状态。
    _onPlaybackChanged();
  }

  void _onPlaybackChanged() {
    if (!_bound || !_isIOS) return;
    final state = _playback.state;

    final track = state.currentTrack;
    final trackChanged = track?.key != _lastTrack?.key;
    final isPlayingChanged = state.isPlaying != _lastIsPlaying;
    final durationChanged = state.duration != _lastDuration;

    // 无曲目：清空系统媒体卡片。
    if (track == null) {
      if (_lastTrack != null) {
        _lastTrack = null;
        _channel.invokeMethod('clear');
      }
      _positionSyncTimer?.cancel();
      _positionSyncTimer = null;
      return;
    }

    // 曲目/时长变化：完整同步元数据。
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
      // 仅播放状态变化。
      _channel.invokeMethod('updatePlayback', {
        'isPlaying': state.isPlaying,
        'positionMs': state.position.inMilliseconds,
      });
    }

    _lastIsPlaying = state.isPlaying;

    // position 定时同步（播放中每秒一次，与 Android 通知栏一致）。
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
    if (!_bound || !_isIOS) return;
    _channel.invokeMethod('updatePosition', {
      'positionMs': _playback.state.position.inMilliseconds,
    });
  }
}
