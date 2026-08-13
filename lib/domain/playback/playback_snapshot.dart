import '../models/music_source.dart';
import '../models/track.dart';
import 'playback_state.dart';
import 'repeat_mode.dart';

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.currentTrackKey,
    required this.volume,
    required this.repeatMode,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final List<Track> queue;
  final String? currentTrackKey;
  final double volume;
  final RepeatMode repeatMode;

  /// 上次离开时的播放进度，供冷启动续播。
  final Duration position;

  /// 当前曲目时长。单独存一份是因为 [Track.duration] 常为空（多数搜索结果
  /// 不带时长），没有它的话恢复出的进度条会是 `x:xx / 0:00`。
  final Duration duration;

  factory PlaybackSnapshot.fromState(PlaybackState state) => PlaybackSnapshot(
    queue: state.queue,
    currentTrackKey: state.currentTrack?.key,
    volume: state.volume,
    repeatMode: state.repeatMode,
    position: state.position,
    duration: state.duration,
  );

  factory PlaybackSnapshot.fromJson(Map<String, Object?> json) {
    final queueValue = json['queue'];
    final tracks = queueValue is List
        ? queueValue
              .whereType<Map>()
              .map((value) => Track.fromJson(Map<String, Object?>.from(value)))
              .toList(growable: false)
        : const <Track>[];
    final rawKey = json['currentTrackKey'] as String?;
    final currentTrackKey = tracks.any((track) => track.key == rawKey)
        ? rawKey
        : null;

    return PlaybackSnapshot(
      queue: tracks,
      currentTrackKey: currentTrackKey,
      volume: switch (json['volume']) {
        final num value => value.clamp(0, 1).toDouble(),
        _ => 0.8,
      },
      repeatMode: RepeatMode.values.firstWhere(
        (mode) => mode.name == json['repeatMode'],
        orElse: () => RepeatMode.all,
      ),
      // 曲目没能在队列里找回时进度无处安放，一并归零。
      position: currentTrackKey == null
          ? Duration.zero
          : _durationFrom(json['positionMs']),
      duration: currentTrackKey == null
          ? Duration.zero
          : _durationFrom(json['durationMs']),
    );
  }

  Map<String, Object?> toJson() => {
    'queue': queue.map(_persistableTrack).toList(growable: false),
    'currentTrackKey': currentTrackKey,
    'volume': volume,
    'repeatMode': repeatMode.name,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
  };

  /// 序列化单个曲目，并剥掉网络音源的播放地址。
  ///
  /// 各平台返回的都是限时签名 CDN 链接，隔一次启动必然失效。若把它留在快照
  /// 里，`PlaybackController._resolveTrack` 会因 `playbackUrl != null` 直接
  /// 短路，拿着过期地址去加载并失败，永远不会重新请求 API。剥掉之后下次播放
  /// 走完整解析流程，拿到新地址再从 [position] 续播。
  ///
  /// 本地文件的 `file://` 地址不会过期，且本地音源不参与音源解析
  /// （`ConfiguredAudioSourceResolver._supports` 对 local 恒返回 false），
  /// 必须保留，否则本地音乐重启后再也放不出来。
  static Map<String, Object?> _persistableTrack(Track track) {
    final json = track.toJson();
    if (track.source != MusicSource.local) {
      json['playbackUrl'] = null;
    }
    return json;
  }

  static Duration _durationFrom(Object? value) => switch (value) {
    final num milliseconds when milliseconds > 0 => Duration(
      milliseconds: milliseconds.round(),
    ),
    _ => Duration.zero,
  };
}
