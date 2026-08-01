/// 原始歌词字符串集合（对应 playerService 中歌词载荷 {lyric, tlyric, yrc, ytlrc}）。
///
/// 与 `domain/lyrics/lyric.dart` 的解析后歌词行不同，这里是后端返回的原始 LRC/YRC 文本。
class LyricData {
  const LyricData({
    this.lyric = '',
    this.tlyric = '',
    this.yrc = '',
    this.ytlrc = '',
  });

  final String lyric;
  final String tlyric;
  final String yrc;
  final String ytlrc;

  bool get isEmpty => lyric.isEmpty && yrc.isEmpty;
  bool get isNotEmpty => !isEmpty;
}
