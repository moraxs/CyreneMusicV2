import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/playback/audio_player_gateway.dart';

/// 基于 media_kit（libmpv）的音频播放实现。
///
/// 替换原 just_audio + audio_session 方案，media_kit 天然跨平台
/// （Windows / Linux / macOS / Android / iOS），为桌面端支持铺路，
/// 且内部自行管理音频会话，无需额外的 audio_session 配置。
///
/// 关键差异（相对 just_audio）：
/// - 音量范围为 0-100，[AudioPlayerGateway] 约定 0-1，[setVolume] 内部换算为 0-100（0 dBFS 无削波）。
/// - [Player.open] 默认自动播放，这里以 `play: false` 打开以匹配「先 load 后 play」语义。
/// - 播放状态由 `playing` / `buffering` / `completed` 等独立流合成为
///   单一的 [PlaybackStatus]。
class MediaKitPlayerGateway implements AudioPlayerGateway {
  MediaKitPlayerGateway({Player? player})
    : _player = player ?? Player(),
      _statusController = StreamController<PlaybackStatus>.broadcast() {
    _subscriptions = [
      _player.stream.playing.listen((playing) {
        _playing = playing;
        _emitStatus();
      }),
      _player.stream.buffering.listen((buffering) {
        _buffering = buffering;
        _emitStatus();
      }),
      _player.stream.completed.listen((completed) {
        _completed = completed;
        _emitStatus();
      }),
    ];
  }

  final Player _player;
  final StreamController<PlaybackStatus> _statusController;
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// 底层 media_kit 播放器（供均衡器等需要直接操作 libmpv 属性的服务使用）。
  Player get player => _player;

  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  bool _hasSource = false;
  PlaybackStatus? _lastStatus;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration?> get durationStream =>
      _player.stream.duration.map<Duration?>((duration) => duration);

  @override
  Stream<PlaybackStatus> get statusStream => _statusController.stream;

  @override
  Future<Duration?> load(Uri source) async {
    _completed = false;
    _hasSource = true;
    // play: false → 保持「先加载后播放」语义，由 PlaybackController 显式调用 play()。
    await _player.open(Media(source.toString()), play: false);
    // media_kit 在打开后异步解析时长，此处返回 null，
    // 交由 durationStream 后续投影（与原 just_audio 行为一致：可能返回 null）。
    final duration = _player.state.duration;
    return duration == Duration.zero ? null : duration;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) {
    final safe = volume.clamp(0.0, 1.0);
    // 所有平台统一映射 0.0-1.0 到 0.0-100.0（0 dBFS 原生输出，零削波失真）。
    return _player.setVolume(safe * 100.0);
  }

  @override
  Future<void> stop() async {
    _hasSource = false;
    _completed = false;
    await _player.stop();
    _emitStatus();
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _statusController.close();
    await _player.dispose();
  }

  void _emitStatus() {
    final status = _mapStatus();
    if (status == _lastStatus) return;
    _lastStatus = status;
    _statusController.add(status);
  }

  PlaybackStatus _mapStatus() {
    if (_completed) return PlaybackStatus.completed;
    if (_buffering) return PlaybackStatus.loading;
    if (_playing) return PlaybackStatus.playing;
    if (_hasSource) return PlaybackStatus.paused;
    return PlaybackStatus.idle;
  }
}
