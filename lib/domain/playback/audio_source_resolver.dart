import '../models/track.dart';

class PlaybackCandidate {
  const PlaybackCandidate({
    required this.track,
    required this.sourceId,
    this.fallbackFrom,
  });

  final Track track;
  final String sourceId;

  /// 该候选是否来自跨平台兜底：非空时表示这是把原曲目（原平台/原id）换成
  /// 其它平台后解析出的候选，值为原始曲目的 [TrackSourceRef]。调用方（播放
  /// 控制器）可据此把新平台持久化回歌单。
  final TrackSourceRef? fallbackFrom;
}

class ResolvedAudioSources {
  const ResolvedAudioSources(this.candidates);

  final List<PlaybackCandidate> candidates;

  bool get isEmpty => candidates.isEmpty;
}

abstract interface class AudioSourceResolver {
  /// 解析 [track] 的可播放候选。
  ///
  /// [exclude] 为已被排除的平台 wireName（加载失败欲回退到更低优先级平台时
  /// 由调用方传入），实现应跳过这些平台。实现只对该次调用命中（所有未排除
  /// 平台里按优先级**第一个**可解析）的平台产出候选。
  Future<ResolvedAudioSources> resolve(Track track, {Set<String>? exclude});
}

class AudioSourceResolutionFailure implements Exception {
  const AudioSourceResolutionFailure(this.message, {this.causes = const []});

  final String message;
  final List<String> causes;

  @override
  String toString() => message;
}
