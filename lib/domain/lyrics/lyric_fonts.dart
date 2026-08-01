/// 预设的歌词字体选项（对应 Next.js demo/lib/constants/fonts.ts 的 LYRIC_FONT_OPTIONS）。
///
/// Next.js 端 value 为 CSS font-family 字符串，依赖用户系统已安装字体。
/// Flutter 端保留同样的 value（用于持久化与选项匹配），并额外提供
/// [flutterFamily]：从 CSS font stack 中提取的首选字体名，尽力应用到
/// [TextStyle.fontFamily]；系统未安装时 Flutter 会回退到默认字体。
class LyricFontOption {
  const LyricFontOption({
    required this.label,
    required this.value,
    this.flutterFamily,
  });

  /// 显示名称。
  final String label;

  /// 与 Next.js 一致的 CSS font-family 字符串（持久化用）。
  final String value;

  /// 尽力提取的 Flutter fontFamily；null 表示使用默认字体。
  final String? flutterFamily;
}

/// 与 Next.js LYRIC_FONT_OPTIONS 顺序、value 完全一致。
const List<LyricFontOption> lyricFontOptions = [
  LyricFontOption(
    label: 'MiSans（默认）',
    value: "'MiSans', sans-serif",
    flutterFamily: 'MiSans',
  ),
  LyricFontOption(
    label: '思源黑体',
    value: "'Source Han Sans SC', 'Noto Sans CJK SC', sans-serif",
    flutterFamily: 'Source Han Sans SC',
  ),
  LyricFontOption(
    label: '苹方',
    value: "'PingFang SC', -apple-system, sans-serif",
    flutterFamily: 'PingFang SC',
  ),
  LyricFontOption(
    label: '微软雅黑',
    value: "'Microsoft YaHei', sans-serif",
    flutterFamily: 'Microsoft YaHei',
  ),
  LyricFontOption(
    label: '黑体',
    value: "'SimHei', 'Heiti SC', sans-serif",
    flutterFamily: 'SimHei',
  ),
  LyricFontOption(
    label: '宋体',
    value: "'SimSun', 'Songti SC', serif",
    flutterFamily: 'SimSun',
  ),
  LyricFontOption(
    label: '等线',
    value: "'DengXian', sans-serif",
    flutterFamily: 'DengXian',
  ),
  LyricFontOption(
    label: '楷体',
    value: "'KaiTi', 'STKaiti', serif",
    flutterFamily: 'KaiTi',
  ),
  LyricFontOption(label: '系统默认', value: 'sans-serif'),
];

/// 默认歌词字体（与首个选项保持一致，对应 DEFAULT_LYRIC_FONT）。
const String defaultLyricFont = "'MiSans', sans-serif";

/// 根据持久化的 value 找到对应选项的 Flutter fontFamily；找不到返回 null。
String? flutterFamilyForFontValue(String value) {
  for (final option in lyricFontOptions) {
    if (option.value == value) return option.flutterFamily;
  }
  return null;
}
