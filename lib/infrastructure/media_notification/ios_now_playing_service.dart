import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/track.dart';
import '../services/crash_log_service.dart';

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

  /// 原生桥是否可用。`ready` 失败后置 false，后续同步全部跳过——否则每秒一次
  /// 的 updatePosition 会不停抛 MissingPluginException。
  bool _nativeAvailable = true;

  /// 绑定到原生端并开始监听播放状态。
  void start() {
    if (_bound || !_isIOS) return;
    _bound = true;
    _log('服务启动');
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
    if (_isIOS && _nativeAvailable) {
      _channel.invokeMethod('clear');
    }
  }

  void dispose() => stop();

  // ==================== 原生 → Flutter（按钮事件） ====================

  Future<void> _onMethodCall(MethodCall call) async {
    // 锁屏/控制中心按钮：记一笔，能证明卡片确实出现过且按钮能回传。
    const commands = {'play', 'pause', 'playPause', 'next', 'previous', 'seek'};
    if (commands.contains(call.method)) {
      _log(
        '系统媒体按钮: ${call.method}'
        '${call.method == 'seek' ? ' ${call.arguments}ms' : ''}',
      );
    }
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
      case 'diagnostic':
        _report(call.arguments?.toString() ?? '原生端未给出原因');
      case 'log':
        _log(call.arguments?.toString() ?? '');
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
    // 通知原生端已完成通道注册，顺带取回原生端启动时攒下的诊断信息。
    try {
      final status = await _channel.invokeMapMethod<String, Object?>('ready');
      _log(
        '原生桥就绪: category=${status?['category']} '
        'mode=${status?['mode']} '
        'otherAudioPlaying=${status?['otherAudioPlaying']}',
      );
      final sessionError = status?['sessionError'];
      if (sessionError != null) _report(sessionError.toString());
    } on MissingPluginException {
      _nativeAvailable = false;
      _report('原生桥未创建（AppDelegate 未注册 NowPlayingBridge），锁屏/控制中心不会有媒体卡片');
      return;
    } catch (error) {
      _nativeAvailable = false;
      _report('原生桥握手失败: $error');
      return;
    }
    // 立即同步一次当前状态。
    _onPlaybackChanged();
  }

  /// 普通运行日志：只进开发者日志缓冲（关于 → 运行日志），不落 crash.log。
  void _log(String message) => debugPrint('[NowPlaying] $message');

  /// 媒体卡片链路的故障写进 crash.log（同时也进运行日志）。
  ///
  /// iOS 用户反馈「没有媒体控件」时，能拿到的只有从「文件」App 导出的
  /// crash.log（见 CrashLogService._logDirectory），原生端的 NSLog 他们看不到。
  /// 按 crash.log 只记异常的约定，一切正常时不写。
  void _report(String message) {
    _log(message);
    CrashLogService.instance.logException(
      StateError(message),
      null,
      context: 'now_playing',
    );
  }

  void _onPlaybackChanged() {
    if (!_bound || !_isIOS || !_nativeAvailable) return;
    final state = _playback.state;

    final track = state.currentTrack;
    final trackChanged = track?.key != _lastTrack?.key;
    final isPlayingChanged = state.isPlaying != _lastIsPlaying;
    final durationChanged = state.duration != _lastDuration;

    // 无曲目：清空系统媒体卡片。
    if (track == null) {
      if (_lastTrack != null) {
        _lastTrack = null;
        _log('无曲目，清空媒体卡片');
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
      _log(
        '${trackChanged ? '同步曲目' : '更新时长'}: ${track.name} - ${track.artists} '
        '(${state.duration.inSeconds}s, ${state.isPlaying ? '播放中' : '暂停'}, '
        '${track.picUrl.isEmpty ? '无封面' : '有封面'})',
      );
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
      _log(state.isPlaying ? '播放状态: 播放' : '播放状态: 暂停');
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
    if (!_bound || !_isIOS || !_nativeAvailable) return;
    _channel.invokeMethod('updatePosition', {
      'positionMs': _playback.state.position.inMilliseconds,
    });
  }
}
