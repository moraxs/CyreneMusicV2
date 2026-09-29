import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../../domain/playback/audio_player_gateway.dart';

/// 媒体没能打开：libmpv 报了错，或迟迟没有出现「已打开」的迹象。
///
/// 由 [MediaKitPlayerGateway.load] 抛出，上层据此把该候选音源记为失败并试下
/// 一个平台（见 `PlaybackController.playTrack`）。
class AudioLoadFailure implements Exception {
  AudioLoadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

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
    : _player =
          player ??
          Player(
            configuration: const PlayerConfiguration(
              logLevel: _verboseLog ? MPVLogLevel.v : MPVLogLevel.error,
            ),
          ),
      _statusController = StreamController<PlaybackStatus>.broadcast() {
    _subscriptions = [
      // 取流失败时 libmpv 的原话只有这里能看到：media_kit 的 error 流只转发
      // 少数几个前缀，连接、重定向、TLS 握手的失败都在普通日志里。
      if (_verboseLog)
        _player.stream.log.listen((log) {
          debugPrint('[libmpv][${log.level}] ${log.prefix}: ${log.text}');
        }),
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
      // 「媒体确实打开了」的两个信号，见 [load]。时长要等解出容器头才有；
      // 没有 Content-Length 的流可能永远拿不到，此时以音频参数为准——它要等
      // 解码器真正吃到数据才会被填上。
      _player.stream.duration.listen((duration) {
        if (duration > Duration.zero) _completeOpen();
      }),
      _player.stream.audioParams.listen((params) {
        if (params.sampleRate != null) _completeOpen();
      }),
      _player.stream.error.listen(_onNativeError),
    ];
    unawaited(_applyNetworkOptions());
  }

  /// 打开 libmpv 的详细日志（mpv 的 `-v` 档）。debug 构建默认开；release 要
  /// 现场诊断时加 `--dart-define=MPV_VERBOSE=true` 重新打包。
  static const bool _verboseLog = bool.fromEnvironment(
    'MPV_VERBOSE',
    defaultValue: kDebugMode,
  );

  /// 「打开媒体」的最长等待。libmpv 自己的读超时（[_networkTimeoutSeconds]）
  /// 只管单次读，整条链路（DNS → TCP → TLS → 可能的 302 → 首个音频包）要留够
  /// 余量；超过这个数还没动静，按失败处理，总好过让界面无限转圈。
  static const _openTimeout = Duration(seconds: 25);

  /// libmpv 的网络读超时（秒）。media_kit 把它写死成 5 秒
  /// （其 `PlayerConfiguration` 初始化），对跨境直连的音频流太紧——一次抖动
  /// 就整条流断掉，而 libmpv 不会自己重连。
  static const _networkTimeoutSeconds = 30;

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

  /// 当前在途的 [load]，由 libmpv 的事件来决定它成功还是失败。
  Completer<void>? _opening;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration?> get durationStream =>
      _player.stream.duration.map<Duration?>((duration) => duration);

  @override
  Stream<PlaybackStatus> get statusStream => _statusController.stream;

  /// 打开媒体，并**等出一个确定结果**后才返回。
  ///
  /// `open()` 只是把媒体排进播放列表就返回了，真正的连接、解复用都在之后异步
  /// 发生。失败时 libmpv 只发一条 error 日志，而 media_kit 把 `END_FILE` 的
  /// 处理注释掉了（它依赖 `--keep-open=yes`），于是 `buffering` 会永远停在
  /// true：不在这里等结果的话，界面就是无限转圈，上层的多音源回退也永远不会
  /// 触发。
  ///
  /// 失败抛 [AudioLoadFailure]。
  @override
  Future<Duration?> load(Uri source) async {
    // 上一次 load 还没落定就换了媒体（快速切歌）：立刻让它失败返回，否则它会
    // 一直挂到超时。
    _failOpen(AudioLoadFailure('已切换到其它媒体'));

    _completed = false;
    _hasSource = true;
    final opening = Completer<void>();
    _opening = opening;
    try {
      // play: false → 保持「先加载后播放」语义，由 PlaybackController 显式调用 play()。
      await _player.open(Media(source.toString()), play: false);
      // 打开极快（本地文件、已缓存流）时事件可能早于订阅到达，补查一次状态。
      if (_isOpened) _completeOpen();
      await opening.future.timeout(_openTimeout);
    } on TimeoutException {
      _hasSource = false;
      _emitStatus();
      throw AudioLoadFailure('打开音频流超时（${_openTimeout.inSeconds} 秒）：$source');
    } catch (_) {
      _hasSource = false;
      _emitStatus();
      rethrow;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }

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
    _failOpen(AudioLoadFailure('播放已停止'));
    await _player.stop();
    _emitStatus();
  }

  @override
  Future<void> dispose() async {
    _failOpen(AudioLoadFailure('播放器已释放'));
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _statusController.close();
    await _player.dispose();
  }

  bool get _isOpened =>
      _player.state.duration > Duration.zero ||
      _player.state.audioParams.sampleRate != null;

  void _completeOpen() {
    final opening = _opening;
    if (opening != null && !opening.isCompleted) opening.complete();
  }

  void _failOpen(AudioLoadFailure failure) {
    final opening = _opening;
    if (opening != null && !opening.isCompleted) opening.completeError(failure);
  }

  /// libmpv 的错误日志（media_kit 只对 `stream` / `ffmpeg` / `ad` / `cplayer`
  /// 等前缀转发）。取流失败的真正原因只能从这里拿到，务必留在日志里。
  void _onNativeError(String message) {
    debugPrint('[MediaKitPlayerGateway] libmpv 报错：$message');
    _failOpen(AudioLoadFailure(message));
  }

  /// 抬高 libmpv 的网络读超时，见 [_networkTimeoutSeconds]。
  ///
  /// media_kit 没有把这个选项开放给 `PlayerConfiguration`，只能在实例建好之后
  /// 改属性。失败不影响播放，记一条日志即可。
  Future<void> _applyNetworkOptions() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.waitForPlayerInitialization;
      if (platform.disposed || platform.ctx == nullptr) return;
      await platform.setProperty('network-timeout', '$_networkTimeoutSeconds');
    } catch (error) {
      debugPrint('[MediaKitPlayerGateway] 设置 network-timeout 失败：$error');
    }
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
