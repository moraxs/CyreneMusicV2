import '../models/audio_quality.dart';
import '../models/lyric_data.dart';
import '../models/track.dart';

/// 一条命中的本地缓存。
class CachedAudio {
  const CachedAudio({required this.uri, this.lyrics, this.duration});

  /// 可直接交给播放器的地址（本地解密服务的回环地址，或兜底的本地文件）。
  final Uri uri;

  /// 缓存时一并落盘的歌词，命中后无需再请求网络（离线可用）。
  final LyricData? lyrics;

  final Duration? duration;
}

abstract interface class AudioCache {
  /// 查找 [track] 在 [quality] 下的本地缓存；未命中返回 null。
  Future<CachedAudio?> lookup(Track track, AudioQuality quality);

  /// 返回真正该交给播放器的地址。
  ///
  /// 实现可以把 [remoteUrl] 换成一个本地中转地址，从而在播放的同时把音频存
  /// 下来（只向源站取一次流）；不缓存或中转不可用时原样返回 [remoteUrl]，
  /// 播放路径不受影响。
  Future<Uri> intercept({
    required Track track,
    required AudioQuality quality,
    required Uri remoteUrl,
  });
}
