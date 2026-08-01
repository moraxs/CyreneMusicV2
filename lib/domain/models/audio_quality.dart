/// 音质枚举（对应 Next.js demo/lib/services/audioSourceService.ts 的 AudioQuality）。
///
/// wireName 与 OmniParse / LxMusic 后端约定保持一致。
enum AudioQuality {
  standard('standard'),
  exHigh('exhigh'),
  lossless('lossless'),
  hiRes('hires');

  const AudioQuality(this.wireName);

  final String wireName;

  /// 由后端返回的字符串还原为枚举，无法识别时回退到 [standard]。
  static AudioQuality fromWireName(String? value) {
    if (value == null) return AudioQuality.standard;
    for (final q in AudioQuality.values) {
      if (q.wireName == value) return q;
    }
    return AudioQuality.standard;
  }
}
