import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/models/track.dart';
import '../../domain/playback/audio_player_gateway.dart';
import '../../domain/playback/audio_source_resolver.dart';
import '../../domain/playback/playback_snapshot.dart';
import '../../domain/playback/playback_snapshot_store.dart';
import '../../domain/playback/playback_state.dart';
import '../../domain/playback/queue_navigation.dart';
import '../../domain/playback/repeat_mode.dart';

class PlaybackController extends ChangeNotifier {
  factory PlaybackController({
    required AudioPlayerGateway audio,
    required PlaybackSnapshotStore store,
    AudioSourceResolver? sourceResolver,
    Random? random,
  }) => PlaybackController._(audio, store, sourceResolver, random ?? Random());

  PlaybackController._(
    this._audio,
    this._store,
    this._sourceResolver,
    this._random,
  ) {
    _subscriptions = [
      _audio.positionStream.listen(_onPosition),
      _audio.durationStream.listen(_onDuration),
      _audio.statusStream.listen(_onStatus),
    ];
  }

  final AudioPlayerGateway _audio;
  final PlaybackSnapshotStore _store;
  final AudioSourceResolver? _sourceResolver;
  final Random _random;
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// 心动模式等「智能续播」供给方。设置后，每次「下一首」（含播放自然结束
  /// 的自动接续）都会先向它要下一曲，拿到非空曲目就播，拿不到才回退普通
  /// 队列导航；「上一首」永不参与。
  Future<Track?> Function()? _smartNextProvider;

  PlaybackState _state = PlaybackState();
  PlaybackState get state => _state;

  // 高频播放进度独立通知：position 每 tick（约 200ms）都变，若走主
  // notifyListeners 会让所有监听整棵 controller 的 widget（如 MusicAppShell
  // 外壳、首页卡片）每 tick 全量重建，与滑动/返回动画抢主线程 → 全局卡顿。
  // 因此进度只经此 ValueListenable 广播，仅进度条 / 歌词 / 听歌统计等真正
  // 需要它的消费者监听；结构性变化（切歌/播放暂停/时长/音量）才走主通知。
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  ValueListenable<Duration> get positionListenable => _positionNotifier;

  int _playRequest = 0;
  bool _disposed = false;

  /// 当前已装载进音频运行时的曲目 key。为 null 表示 [_audio] 手里没有可播放的
  /// 媒体——冷启动恢复出的曲目就是这个状态（快照里只有元数据，播放地址已按
  /// 时效性剥离），此时按下播放要重新解析音源而不是直接 `play()`。
  String? _loadedTrackKey;

  /// 待补的续播定位，见 [_onPosition]。
  Duration? _pendingResume;
  int _resumeSeekRetries = 0;

  /// 判定「已定位到续播点」的容差：libmpv 只能 seek 到最近的关键帧，落点
  /// 通常比请求值早零点几秒，严格比较会导致无谓的补发。
  static const _resumeTolerance = Duration(seconds: 2);

  /// 续播 seek 的最大补发次数。
  static const _maxResumeSeekRetries = 3;

  /// 播放进度的落盘节流。快照包含整条队列，每次写都要 JSON 编码并落
  /// SharedPreferences；跟着 200ms 的进度 tick 走会持续抖动主线程。5 秒一次
  /// 足以把冷启动续播的误差控制在可接受范围内，退到后台/暂停时另有精确落盘。
  static const _positionPersistInterval = Duration(seconds: 5);
  Duration _lastPersistedPosition = Duration.zero;

  Future<void> restore() async {
    final snapshot = await _store.read();
    if (_disposed || snapshot == null) return;

    final currentTrack = snapshot.queue.where(
      (track) => track.key == snapshot.currentTrackKey,
    );
    // 恢复的曲目尚未装载到音频运行时：进度与时长只是「显示值」，让进度条
    // 一进来就停在上次离开的位置，真正的加载推迟到用户按下播放。
    _loadedTrackKey = null;
    _pendingResume = null;
    _lastPersistedPosition = snapshot.position;
    _publish(
      PlaybackState(
        currentTrack: currentTrack.isEmpty ? null : currentTrack.first,
        queue: snapshot.queue,
        volume: snapshot.volume,
        repeatMode: snapshot.repeatMode,
        position: snapshot.position,
        duration: snapshot.duration,
      ),
      persist: false,
    );
    await _audio.setVolume(snapshot.volume);
  }

  /// 播放 [track]；[startAt] 非空时从该位置续播（音源仍会重新解析）。
  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    Duration? startAt,
  }) async {
    final request = ++_playRequest;
    final resumeFrom = startAt != null && startAt > Duration.zero
        ? startAt
        : null;
    // 换曲目即视为旧媒体作废；解析途中按播放不应该走「直接 play」分支。
    _loadedTrackKey = null;
    _pendingResume = null;
    // 续播时保留已知的进度与时长，避免进度条在重新解析音源的这几百毫秒里
    // 先跳回 0:00 再跳回来。
    final restoredDuration = resumeFrom == null ? Duration.zero : _state.duration;
    _publish(
      _state
          .resetForTrack(track)
          .copyWith(position: resumeFrom, duration: restoredDuration),
    );

    try {
      final resolved = await _resolveTrack(track);
      if (_isStale(request)) return;

      final failures = <String>[];
      for (final candidate in resolved.candidates) {
        final playableTrack = candidate.track;
        final source = playableTrack.playbackUrl;
        if (source == null) {
          failures.add('${candidate.sourceId}: 未返回播放地址');
          continue;
        }

        try {
          final duration = await _audio.load(source);
          if (_isStale(request)) return;

          final resolvedQueue = _normalizedQueue(
            queue ?? [..._state.queue, playableTrack],
          );
          final activeQueue = resolvedQueue.any((item) => item == playableTrack)
              ? resolvedQueue
              : _normalizedQueue([...resolvedQueue, playableTrack]);
          _loadedTrackKey = playableTrack.key;
          _publish(
            _state
                .resetForTrack(playableTrack)
                .copyWith(
                  queue: activeQueue,
                  duration:
                      duration ??
                      playableTrack.duration ??
                      restoredDuration,
                  position: resumeFrom,
                  isLoading: false,
                  clearError: true,
                ),
          );
          if (resumeFrom != null) {
            _pendingResume = resumeFrom;
            await _audio.seek(resumeFrom);
          }
          await _audio.play();
          return;
        } catch (error) {
          failures.add('${candidate.sourceId}: $error');
        }
      }

      throw AudioSourceResolutionFailure('所有音源均无法加载。', causes: failures);
    } catch (_) {
      if (_isStale(request)) return;
      _loadedTrackKey = null;
      _pendingResume = null;
      _publish(
        _state.copyWith(
          isLoading: false,
          isPlaying: false,
          errorMessage: '音频加载失败，请稍后重试。',
        ),
      );
    }
  }

  Future<void> togglePlay() async {
    final track = _state.currentTrack;
    if (track == null) return;
    // 冷启动恢复出来的曲目还没有音频源，且旧的 CDN 地址已随快照剥离
    // （限时签名，隔一次启动必失效）。此时按播放要重新解析音源，
    // 再从上次离开的位置续播。
    if (_loadedTrackKey != track.key) {
      await playTrack(track, queue: _state.queue, startAt: _state.position);
      return;
    }
    if (_state.isPlaying) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  Future<void> seek(Duration position) async {
    final duration = _state.duration;
    final safePosition = duration == Duration.zero
        ? position
        : position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    // 用户主动定位优先于待补的续播定位，否则会被补发的 seek 拽回去。
    _pendingResume = null;
    await _audio.seek(safePosition);
    _publish(_state.copyWith(position: safePosition), persist: false);
  }

  /// 立即把当前播放状态（含精确进度）落盘。
  ///
  /// 进度平时按 [_positionPersistInterval] 节流写入，退到后台或退出前调用此
  /// 方法补一次精确值，免得续播位置比实际少几秒。
  Future<void> flush() async {
    if (_disposed) return;
    await _persistSnapshot();
  }

  Future<void> setVolume(double volume) async {
    final safeVolume = volume.clamp(0, 1).toDouble();
    await _audio.setVolume(safeVolume);
    _publish(_state.copyWith(volume: safeVolume));
  }

  void setRepeatMode(RepeatMode repeatMode) =>
      _publish(_state.copyWith(repeatMode: repeatMode));

  void setQueue(List<Track> queue) =>
      _publish(_state.copyWith(queue: _normalizedQueue(queue)));

  void addToQueue(Track track) => _publish(
    _state.copyWith(queue: _normalizedQueue([..._state.queue, track])),
  );

  void removeFromQueue(Track track) => _publish(
    _state.copyWith(
      queue: _state.queue.where((item) => item != track).toList(),
    ),
  );

  Future<void> clearQueue() async {
    ++_playRequest;
    _loadedTrackKey = null;
    _pendingResume = null;
    _lastPersistedPosition = Duration.zero;
    await _audio.stop();
    _publish(
      PlaybackState(volume: _state.volume, repeatMode: _state.repeatMode),
    );
  }

  Future<void> playNext() => _playAdjacent(isNext: true);

  Future<void> playPrevious() => _playAdjacent(isNext: false);

  /// 设置/清除智能续播供给方（见 [_smartNextProvider]）。
  void setSmartNextProvider(Future<Track?> Function()? provider) =>
      _smartNextProvider = provider;

  Future<void> _playAdjacent({required bool isNext}) async {
    // 心动模式（智能续播）：仅「下一首」先问供给方；供给方抛错或返回 null
    // 都回退普通队列导航，避免异常中断播放流。
    if (isNext) {
      final smartProvider = _smartNextProvider;
      if (smartProvider != null) {
        try {
          final smartTrack = await smartProvider();
          if (smartTrack != null) {
            await playTrack(smartTrack, queue: _state.queue);
            return;
          }
        } catch (e) {
          debugPrint('[PlaybackController] 智能续播失败，回退队列导航: $e');
        }
      }
    }
    final track = isNext
        ? nextTrack(
            queue: _state.queue,
            currentTrack: _state.currentTrack,
            repeatMode: _state.repeatMode,
            randomIndex: _random.nextInt(1 << 31),
          )
        : previousTrack(
            queue: _state.queue,
            currentTrack: _state.currentTrack,
            repeatMode: _state.repeatMode,
          );
    if (track == null) {
      _publish(_state.copyWith(isPlaying: false, isLoading: false));
      return;
    }
    await playTrack(track, queue: _state.queue);
  }

  void _onPosition(Duration position) {
    if (_state.currentTrack == null || _disposed) return;
    // 只更新状态并经独立通知广播——不触发主 notifyListeners，避免每 tick
    // 全树重建。state.position 仍同步更新，供机会性读取者（媒体通知栏等）取用。
    _state = _state.copyWith(position: position);
    _positionNotifier.value = position;
    _maybeReapplyResume(position);
    _maybePersistPosition(position);
  }

  /// 续播定位的补发。
  ///
  /// libmpv 在 `open(play: false)` 之后尚未真正载入媒体，此时的 seek 可能被
  /// 直接丢弃，播放会从 0:00 开始。因此续播时记下目标位置，直到运行时报告的
  /// 进度确实落在目标附近才作数；否则补发一次 seek（最多 [_maxResumeSeekRetries]
  /// 次，避免目标位置不可达时无限重试）。
  void _maybeReapplyResume(Duration position) {
    final target = _pendingResume;
    if (target == null) return;

    // 已经到位（或已播过目标点）：续播完成。
    if (position >= target - _resumeTolerance) {
      _pendingResume = null;
      _resumeSeekRetries = 0;
      return;
    }
    // 时长已知且目标越界：这条音源比上次短（换音源/换音质），放弃续播。
    final duration = _state.duration;
    if (duration > Duration.zero && target >= duration) {
      _pendingResume = null;
      _resumeSeekRetries = 0;
      return;
    }
    if (_resumeSeekRetries >= _maxResumeSeekRetries) {
      _pendingResume = null;
      return;
    }
    _resumeSeekRetries += 1;
    unawaited(_audio.seek(target));
  }

  /// 播放进度的节流落盘，见 [_positionPersistInterval]。
  void _maybePersistPosition(Duration position) {
    final delta = position - _lastPersistedPosition;
    if (delta.abs() < _positionPersistInterval) return;
    unawaited(_persistSnapshot());
  }

  Future<void> _persistSnapshot() {
    _lastPersistedPosition = _state.position;
    return _store.write(PlaybackSnapshot.fromState(_state));
  }

  void _onDuration(Duration? duration) {
    if (_state.currentTrack == null || duration == null) return;
    _publish(_state.copyWith(duration: duration), persist: false);
  }

  void _onStatus(PlaybackStatus status) {
    if (_state.currentTrack == null) return;
    switch (status) {
      case PlaybackStatus.loading:
        _publish(_state.copyWith(isLoading: true), persist: false);
      case PlaybackStatus.playing:
        _publish(
          _state.copyWith(isPlaying: true, isLoading: false),
          persist: false,
        );
      case PlaybackStatus.ready:
      case PlaybackStatus.paused:
        _publish(
          _state.copyWith(isPlaying: false, isLoading: false),
          persist: false,
        );
        // 暂停是「用户可能就此离开」的信号：补一次精确进度，绕过节流。
        unawaited(_persistSnapshot());
      case PlaybackStatus.completed:
        unawaited(_playAdjacent(isNext: true));
      case PlaybackStatus.idle:
        break;
    }
  }

  Future<ResolvedAudioSources> _resolveTrack(Track track) async {
    if (track.playbackUrl != null || _sourceResolver == null) {
      return ResolvedAudioSources([
        PlaybackCandidate(track: track, sourceId: 'embedded'),
      ]);
    }
    return _sourceResolver.resolve(track);
  }

  bool _isStale(int request) => _disposed || request != _playRequest;

  List<Track> _normalizedQueue(List<Track> queue) {
    final keys = <String>{};
    return queue.where((track) => keys.add(track.key)).toList(growable: false);
  }

  void _publish(PlaybackState nextState, {bool persist = true}) {
    if (_disposed) return;
    _state = nextState;
    // seek / 切歌重置等结构性变更也会带来新 position，同步到独立通知，
    // 让进度条即时跟随，不必等下一个高频 tick。
    _positionNotifier.value = nextState.position;
    if (persist) {
      unawaited(_persistSnapshot());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _positionNotifier.dispose();
    unawaited(_audio.dispose());
    super.dispose();
  }
}
