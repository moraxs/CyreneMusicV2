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

  Future<void> restore() async {
    final snapshot = await _store.read();
    if (_disposed || snapshot == null) return;

    final currentTrack = snapshot.queue.where(
      (track) => track.key == snapshot.currentTrackKey,
    );
    _publish(
      PlaybackState(
        currentTrack: currentTrack.isEmpty ? null : currentTrack.first,
        queue: snapshot.queue,
        volume: snapshot.volume,
        repeatMode: snapshot.repeatMode,
      ),
      persist: false,
    );
    await _audio.setVolume(snapshot.volume);
  }

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    final request = ++_playRequest;
    _publish(_state.resetForTrack(track));

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
          _publish(
            _state
                .resetForTrack(playableTrack)
                .copyWith(
                  queue: activeQueue,
                  duration: duration ?? playableTrack.duration ?? Duration.zero,
                  isLoading: false,
                  clearError: true,
                ),
          );
          await _audio.play();
          return;
        } catch (error) {
          failures.add('${candidate.sourceId}: $error');
        }
      }

      throw AudioSourceResolutionFailure('所有音源均无法加载。', causes: failures);
    } catch (_) {
      if (_isStale(request)) return;
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
    if (_state.currentTrack == null) return;
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
    await _audio.seek(safePosition);
    _publish(_state.copyWith(position: safePosition), persist: false);
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
    await _audio.stop();
    _publish(
      PlaybackState(volume: _state.volume, repeatMode: _state.repeatMode),
    );
  }

  Future<void> playNext() => _playAdjacent(isNext: true);

  Future<void> playPrevious() => _playAdjacent(isNext: false);

  Future<void> _playAdjacent({required bool isNext}) async {
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
      unawaited(_store.write(PlaybackSnapshot.fromState(nextState)));
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
