/// 1:1 移植 `@applemusic-like-lyrics/core` 的 `src/utils/lyric-split-words.ts`
/// 与 `src/utils/is-cjk.ts`、`src/utils/eq-set.ts`。
library;

import 'interfaces.dart';

/// `CJKEXP` / `isCJK`。
///
/// Dart 的 RegExp 不认 `\p{Unified_Ideograph}`，改用等价的码位区间：
/// Unified_Ideograph 覆盖 CJK 统一汉字及各扩展区（含星平面），再并上原式
/// 里额外写出的 `ࠀ-鿼`。
final RegExp cjkExp = RegExp(
  r'^[ࠀ-鿼㐀-䶿一-鿿﨎﨏﨑﨓﨔'
  r'﨟﨡﨣﨤﨧-﨩'
  r'\u{20000}-\u{2A6DF}\u{2A700}-\u{2EBEF}\u{30000}-\u{3134F}]+$',
  unicode: true,
);

bool isCJK(String char) => cjkExp.hasMatch(char);

/// `eqSet`
bool eqSet<T>(Set<T> xs, Set<T> ys) =>
    xs.length == ys.length && xs.every(ys.contains);

/// 分组结果的一项：要么是单个词，要么是一组「之间没有空格」的连写词。
///
/// 对应 JS 的联合类型 `LyricWord | LyricWord[]`。
class V2WordChunk {
  V2WordChunk.single(this.word) : words = const [];
  V2WordChunk.group(this.words) : word = null;

  /// 单词（`chunk` 不是数组时）
  final V2LyricWord? word;

  /// 连写词组（`Array.isArray(chunk)` 为真时）
  final List<V2LyricWord> words;

  bool get isGroup => word == null;
}

final RegExp _singleWordExp = RegExp(r'^\s*[^\s]*\s*$');

/// 1:1 移植 `chunkAndSplitLyricWords`。
///
/// 将输入的单词重新分组，之间没有空格的单词将会组合成一个单词数组。
List<V2WordChunk> chunkAndSplitLyricWords(List<V2LyricWord> words) {
  final resplitedWords = <V2LyricWord>[];

  for (final w in words) {
    final realLength = w.word.replaceAll(RegExp(r'\s'), '').length;
    final splited = w.word
        .split(' ')
        .where((v) => v.trim().isNotEmpty)
        .toList();
    if (splited.length > 1) {
      if (w.word.startsWith(' ')) {
        resplitedWords.add(
          V2LyricWord(word: ' ', romanWord: '', startTime: 0, endTime: 0),
        );
      }
      var charPos = 0;
      for (final s in splited) {
        resplitedWords.add(
          V2LyricWord(
            word: s,
            romanWord: '',
            obscene: w.obscene,
            startTime:
                (w.startTime +
                        (charPos / realLength) * (w.endTime - w.startTime))
                    .round(),
            endTime:
                (w.startTime +
                        ((charPos + s.length) / realLength) *
                            (w.endTime - w.startTime))
                    .round(),
          ),
        );
        resplitedWords.add(
          V2LyricWord(word: ' ', romanWord: '', startTime: 0, endTime: 0),
        );
        charPos += s.length;
      }
      if (!w.word.endsWith(' ')) {
        resplitedWords.removeLast();
      }
    } else {
      resplitedWords.add(w.clone());
    }
  }

  var wordChunk = <String>[];
  var wChunk = <V2LyricWord>[];
  final result = <V2WordChunk>[];

  for (final w in resplitedWords) {
    final word = w.word;
    wordChunk.add(word);
    wChunk.add(w);
    if (word.isNotEmpty && word.trim().isEmpty) {
      wordChunk.removeLast();
      wChunk.removeLast();
      if (wChunk.length == 1) {
        result.add(V2WordChunk.single(wChunk[0]));
      } else if (wChunk.length > 1) {
        result.add(V2WordChunk.group(wChunk));
      }
      result.add(V2WordChunk.single(w));
      wordChunk = <String>[];
      wChunk = <V2LyricWord>[];
    } else if (!_singleWordExp.hasMatch(wordChunk.join()) ||
        cjkExp.hasMatch(word)) {
      wordChunk.removeLast();
      wChunk.removeLast();
      if (wChunk.length == 1) {
        result.add(V2WordChunk.single(wChunk[0]));
      } else if (wChunk.length > 1) {
        result.add(V2WordChunk.group(wChunk));
      }
      wordChunk = <String>[word];
      wChunk = <V2LyricWord>[w];
    }
  }

  if (wChunk.length == 1) {
    result.add(V2WordChunk.single(wChunk[0]));
  } else if (wChunk.isNotEmpty) {
    // JS 侧此处无条件 push 空数组；空数组在 rebuildElement 里会被
    // `chunk.length === 0` 跳过，等价于不产出。
    result.add(V2WordChunk.group(wChunk));
  }

  return result;
}
