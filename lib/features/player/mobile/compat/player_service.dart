import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide RepeatMode;

import '../../../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../../../application/auth/account_session_controller.dart';
import '../../../../application/playback/playback_controller.dart';
import '../../../../domain/models/track.dart';
import '../../../../domain/playback/queue_navigation.dart';
import '../../../../domain/playback/repeat_mode.dart';
import 'image_utils.dart';
import 'song_detail.dart';

/// 原版 `PlayerService` 的兼容适配层：保持原版单例 API 不变，内部桥接到
/// 新架构的 [PlaybackController]。移植的播放器组件只依赖本类，行为与原版一致：
/// - 高频进度走 [positionNotifier]（每 tick 更新，不触发 notifyListeners）；
/// - 切歌/播放暂停/加载/时长/音量等结构性变化才 notifyListeners；
/// - [themeColorNotifier] 由背景组件提色后写入（与原版相同的数据流向）。
class PlayerService extends ChangeNotifier {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;
  PlayerService._internal();

  PlaybackController? _controller;
  AccountSessionController? account;
  AudioSourcePreferencesController? audioSources;

  final ValueNotifier<Color?> themeColorNotifier = ValueNotifier<Color?>(null);
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<String?> dynamicCoverUrlNotifier = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<List<Map<String, int>>?> chorusTimesNotifier =
      ValueNotifier<List<Map<String, int>>?>(null);

  String? _lastTrackKey;
  bool _lastIsPlaying = false;
  bool _lastIsLoading = false;
  Duration _lastDuration = Duration.zero;
  double _lastVolume = -1;
  SongDetail? _cachedSong;
  // 记录 [_cachedSong] 对应的 Track 实例。同一曲目在音源解析后会被替换为
  // 带歌词的新 Track 实例（key 不变），仅按 key 失效缓存会一直停留在无歌词的
  // 原始 Track 上（切歌时表现为「暂无歌词」），故用实例一致性判断缓存过期。
  Track? _cachedSongTrack;

  /// 暴露底层控制器（用于跳转到需要它的新版页面，如歌手详情）。
  PlaybackController? get playbackController => _controller;

  PlaybackController get _playback {
    final controller = _controller;
    assert(controller != null, 'PlayerService.bind() 必须在打开播放器前调用');
    return controller!;
  }

  /// 绑定新架构控制器（幂等；由 MobilePlayerPage 打开时调用）。
  void bind(
    PlaybackController playback, {
    AccountSessionController? accountController,
    AudioSourcePreferencesController? audioSourcesController,
  }) {
    account = accountController ?? account;
    audioSources = audioSourcesController ?? audioSources;
    if (identical(_controller, playback)) return;
    _controller?.removeListener(_onPlaybackChanged);
    _controller?.positionListenable.removeListener(_onPositionTick);
    _controller = playback;
    playback.addListener(_onPlaybackChanged);
    // 高频进度经 controller 的独立通知转发到 positionNotifier，
    // 不再依赖主 notifyListeners（后者已不含 position tick）。
    playback.positionListenable.addListener(_onPositionTick);
    _onPlaybackChanged();
    _onPositionTick();
  }

  /// 高频进度 tick：只刷新 positionNotifier，供进度条 / 歌词局部重建。
  void _onPositionTick() {
    positionNotifier.value = _playback.state.position;
  }

  void _onPlaybackChanged() {
    final state = _playback.state;

    var structural = false;
    final key = state.currentTrack?.key;
    if (key != _lastTrackKey) {
      _lastTrackKey = key;
      _cachedSong = null;
      _cachedSongTrack = null;
      chorusTimesNotifier.value = state.currentTrack?.chorus
          ?.map(
            (range) => <String, int>{
              'startTime': range.startTime.inMilliseconds,
              'endTime': range.endTime.inMilliseconds,
            },
          )
          .toList();
      structural = true;
    }
    if (state.isPlaying != _lastIsPlaying ||
        state.isLoading != _lastIsLoading ||
        state.duration != _lastDuration ||
        state.volume != _lastVolume) {
      _lastIsPlaying = state.isPlaying;
      _lastIsLoading = state.isLoading;
      _lastDuration = state.duration;
      _lastVolume = state.volume;
      structural = true;
    }
    if (structural) notifyListeners();
  }

  // ==================== 原版只读接口 ====================

  Track? get currentTrack => _controller?.state.currentTrack;

  SongDetail? get currentSong {
    final track = currentTrack;
    if (track == null) return null;
    // 同一曲目解析后会替换为带歌词的新 Track 实例（key 不变），用实例一致性
    // 失效缓存，避免切歌后一直返回无歌词的原始 Track 详情。
    if (!identical(track, _cachedSongTrack)) {
      _cachedSongTrack = track;
      _cachedSong = SongDetail.fromTrack(track);
    }
    return _cachedSong;
  }

  Duration get position => _controller?.state.position ?? Duration.zero;
  Duration get duration => _controller?.state.duration ?? Duration.zero;
  bool get isPlaying => _controller?.state.isPlaying ?? false;
  bool get isLoading => _controller?.state.isLoading ?? false;
  double get volume => _controller?.state.volume ?? 0.8;

  ImageProvider? get currentCoverImageProvider {
    final url = currentTrack?.picUrl;
    if (url == null || url.isEmpty) return null;
    // 本地音轨的内嵌封面是 data:image/...;base64 URI，CachedNetworkImage 不认
    // 该 scheme，需解码为字节后经 MemoryImage 提供，否则背景/封面一直回退占位。
    if (isDataUriImage(url)) {
      final bytes = decodeDataUriImage(url);
      if (bytes == null) return null;
      return MemoryImage(bytes);
    }
    return CachedNetworkImageProvider(url, headers: getImageHeaders(url));
  }

  bool get hasPrevious {
    final state = _playback.state;
    return previousTrack(
          queue: state.queue,
          currentTrack: state.currentTrack,
          repeatMode: state.repeatMode,
        ) !=
        null;
  }

  bool get hasNext {
    final state = _playback.state;
    return nextTrack(
          queue: state.queue,
          currentTrack: state.currentTrack,
          repeatMode: state.repeatMode,
          randomIndex: 0,
        ) !=
        null;
  }

  RepeatMode get repeatMode => _playback.state.repeatMode;
  void setRepeatMode(RepeatMode mode) => _playback.setRepeatMode(mode);
  List<Track> get queue => _controller?.state.queue ?? const [];
  void setQueueTracks(List<Track> tracks) => _playback.setQueue(tracks);

  // ==================== 原版操作接口 ====================

  Future<void> playTrack(
    Track track, {
    Object? quality,
    ImageProvider? coverProvider,
    bool fromPlaylist = false,
    Duration? initialPosition,
  }) => _playback.playTrack(track);

  Future<void> seek(Duration position) => _playback.seek(position);

  Future<void> pause() async {
    if (isPlaying) await _playback.togglePlay();
  }

  Future<void> resume() async {
    if (!isPlaying && currentTrack != null) await _playback.togglePlay();
  }

  Future<void> setVolume(double volume) => _playback.setVolume(volume);
  Future<void> togglePlayPause() => _playback.togglePlay();
  Future<void> playNext() => _playback.playNext();
  Future<void> playPrevious() => _playback.playPrevious();
}
