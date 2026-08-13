import '../../domain/models/music_source.dart';

/// 音质枚举（对应 Next.js demo/lib/services/audioSourceService.ts 的 AudioQuality）。
///
/// wireName 与 OmniParse / LxMusic 后端约定保持一致。
///
/// 其中 higher / dolby / jyeffect / sky / jymaster 仅网易云后端支持：
/// 这些音质在非网易云来源上会回落为 [fallback]（与「其余平台使用默认音质」
/// 的约定一致，避免把网易云专属 level 透传给 QQ/酷狗/酷我/Apple 等后端）。
enum AudioQuality {
  standard('standard'),
  higher('higher', neteaseOnly: true),
  exHigh('exhigh'),
  lossless('lossless'),
  hiRes('hires'),
  jyeffect('jyeffect', neteaseOnly: true),
  sky('sky', neteaseOnly: true),
  dolby('dolby', neteaseOnly: true),
  jymaster('jymaster', neteaseOnly: true);

  const AudioQuality(this.wireName, {this.neteaseOnly = false});

  final String wireName;

  /// 是否仅网易云后端支持。非网易云来源需回落为 [fallback]。
  final bool neteaseOnly;

  /// 仅网易云支持的音质，在其它来源上的回落音质。
  AudioQuality get fallback => neteaseOnly ? AudioQuality.exHigh : this;

  /// 给定 [source] 实际生效的音质：网易云专属音质仅在网易云来源上生效，
  /// 其余来源回落为极高音质（默认音质）。
  AudioQuality effectiveFor(MusicSource source) =>
      source == MusicSource.netease ? this : fallback;

  /// 由后端返回的字符串还原为枚举，无法识别时回退到 [standard]。
  static AudioQuality fromWireName(String? value) {
    if (value == null) return AudioQuality.standard;
    for (final q in AudioQuality.values) {
      if (q.wireName == value) return q;
    }
    return AudioQuality.standard;
  }
}
