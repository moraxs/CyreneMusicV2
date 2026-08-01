/// AMLL 引擎内部使用的歌词数据结构。
///
/// 1:1 对应 `@applemusic-like-lyrics/core` 的 `interfaces.ts`。
/// 时间单位统一为**毫秒**（与 JS 侧一致），可变字段是刻意的：
/// [optimizeLyricLines] 会原地修改这些对象，调用前必须先深拷贝。
library;

/// 一个歌词单词的音译片段（ruby / 振假名）。
class AmllRuby {
  AmllRuby({required this.word, required this.startTime, required this.endTime});

  String word;
  int startTime;
  int endTime;

  AmllRuby clone() =>
      AmllRuby(word: word, startTime: startTime, endTime: endTime);
}

/// 一个歌词单词。
class AmllLyricWord {
  AmllLyricWord({
    required this.word,
    required this.startTime,
    required this.endTime,
    this.romanWord = '',
    this.obscene = false,
    List<AmllRuby>? ruby,
  }) : ruby = ruby ?? <AmllRuby>[];

  /// 单词内容
  String word;

  /// 起始时间，单位毫秒
  int startTime;

  /// 结束时间，单位毫秒
  int endTime;

  /// 音译内容
  String romanWord;

  /// 是否包含冒犯性用语
  bool obscene;

  /// 逐字音译片段
  List<AmllRuby> ruby;

  int get duration => endTime - startTime;

  AmllLyricWord clone() => AmllLyricWord(
    word: word,
    startTime: startTime,
    endTime: endTime,
    romanWord: romanWord,
    obscene: obscene,
    ruby: ruby.map((r) => r.clone()).toList(),
  );
}

/// 一行歌词。
class AmllLyricLine {
  AmllLyricLine({
    required this.words,
    required this.startTime,
    required this.endTime,
    this.translatedLyric = '',
    this.romanLyric = '',
    this.isBG = false,
    this.isDuet = false,
  });

  /// 该行的所有单词。逐行歌词（如 LRC）只会有一个单词，
  /// 且其始末时间通常与行的 [startTime] / [endTime] 相同。
  List<AmllLyricWord> words;

  /// 翻译歌词，显示在主歌词行下方
  String translatedLyric;

  /// 音译歌词，显示在翻译歌词行下方
  String romanLyric;

  /// 起始时间，单位毫秒
  int startTime;

  /// 结束时间，单位毫秒
  int endTime;

  /// 是否为背景人声行。上一句非背景歌词被激活时，本行会一同显示。
  /// 每个非背景歌词行下方只允许有一个背景歌词行。
  bool isBG;

  /// 是否为对唱歌词行（靠右对齐）
  bool isDuet;

  String get text => words.map((w) => w.word).join();

  AmllLyricLine clone() => AmllLyricLine(
    words: words.map((w) => w.clone()).toList(),
    startTime: startTime,
    endTime: endTime,
    translatedLyric: translatedLyric,
    romanLyric: romanLyric,
    isBG: isBG,
    isDuet: isDuet,
  );
}

/// 深拷贝一组歌词行。
///
/// 对应 JS 侧的 `structuredClone`：[optimizeLyricLines] 会原地改写，
/// 必须先拷贝，避免污染调用方持有的原始数据。
List<AmllLyricLine> cloneLyricLines(List<AmllLyricLine> lines) =>
    lines.map((line) => line.clone()).toList();

/// 歌词优化项开关，默认全部开启。
class OptimizeLyricOptions {
  const OptimizeLyricOptions({
    this.normalizeSpaces = true,
    this.resetLineTimestamps = true,
    this.convertExcessiveBackgroundLines = true,
    this.syncMainAndBackgroundLines = true,
    this.cleanUnintentionalOverlaps = true,
    this.tryAdvanceStartTime = true,
  });

  /// 把连续空格规范化为单个空格
  final bool normalizeSpaces;

  /// 用字级时间戳校正行级时间戳
  final bool resetLineTimestamps;

  /// 把连续多行背景人声压缩成单行
  final bool convertExcessiveBackgroundLines;

  /// 同步主歌词与背景人声的始末时间
  final bool syncMainAndBackgroundLines;

  /// 清洗非刻意的行间重叠
  final bool cleanUnintentionalOverlaps;

  /// 让歌词行适当提前开始，用于提前滚动
  final bool tryAdvanceStartTime;
}

/// 歌词行的渲染模式。
enum LyricLineRenderMode {
  /// 纯色渲染（非活跃行）
  solid,

  /// 渐变推进渲染（活跃行）
  gradient,
}

/// 布局对齐锚点。
enum LayoutAlignAnchor { top, center, bottom }

/// 不雅用语掩码模式。
enum MaskObsceneWordsMode {
  /// 不做掩码
  disabled,

  /// 完全掩码
  fullMask,

  /// 保留首尾字符，掩码中间
  partialMask,
}
