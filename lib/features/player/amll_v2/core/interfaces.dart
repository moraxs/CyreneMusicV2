/// 1:1 移植 `@applemusic-like-lyrics/core` 的 `src/interfaces.ts`。
///
/// 字段名、语义、时间单位（毫秒）全部照抄。字段可变是刻意的——
/// `LyricPlayerBase.setLyricLines` 会在 `structuredClone` 出来的副本上原地
/// 改写 `startTime` / `endTime`（提早一秒、背景行对齐），见 base.ts。
library;

/// 一个歌词单词。对应 `interfaces.ts` 的 `LyricWord`。
class V2LyricWord {
  V2LyricWord({
    required this.word,
    required this.startTime,
    required this.endTime,
    this.romanWord = '',
    this.obscene = false,
  });

  /// 单词的起始时间，单位为毫秒
  int startTime;

  /// 单词的结束时间，单位为毫秒
  int endTime;

  /// 单词内容
  String word;

  /// 单词的音译内容
  String romanWord;

  /// 单词内容是否包含冒犯性的不雅用语
  bool obscene;

  V2LyricWord clone() => V2LyricWord(
    word: word,
    startTime: startTime,
    endTime: endTime,
    romanWord: romanWord,
    obscene: obscene,
  );
}

/// 一行歌词。对应 `interfaces.ts` 的 `LyricLine`。
class V2LyricLine {
  V2LyricLine({
    required this.words,
    this.translatedLyric = '',
    this.romanLyric = '',
    required this.startTime,
    required this.endTime,
    this.isBG = false,
    this.isDuet = false,
  });

  /// 该行的所有单词
  List<V2LyricWord> words;

  /// 该行的翻译歌词，将会显示在主歌词行的下方
  String translatedLyric;

  /// 该行的音译歌词，将会显示在翻译歌词行的下方
  String romanLyric;

  /// 句子的起始时间，单位为毫秒
  int startTime;

  /// 句子的结束时间，单位为毫秒
  int endTime;

  /// 该行是否为背景歌词行
  bool isBG;

  /// 该行是否为对唱歌词行（即歌词行靠右对齐）
  bool isDuet;

  /// 对应 base.ts 里的 `structuredClone(lines)`。
  V2LyricLine clone() => V2LyricLine(
    words: words.map((w) => w.clone()).toList(),
    translatedLyric: translatedLyric,
    romanLyric: romanLyric,
    startTime: startTime,
    endTime: endTime,
    isBG: isBG,
    isDuet: isDuet,
  );
}
