import 'is_cjk.dart';
import 'lyric_types.dart';

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _whitespace = RegExp(r'\s');

/// 按空白切分，**保留**空白片段本身。
///
/// 对应 JS 的 `str.split(/(\s+)/)`：JS 会把捕获组一并放进结果，
/// 而 Dart 的 `String.split(RegExp)` 会丢弃分隔符，所以这里手写。
List<String> _splitKeepingWhitespace(String input) {
  final parts = <String>[];
  var last = 0;
  for (final match in _whitespaceRun.allMatches(input)) {
    if (match.start > last) parts.add(input.substring(last, match.start));
    parts.add(match.group(0)!);
    last = match.end;
  }
  if (last < input.length) parts.add(input.substring(last));
  return parts;
}

/// 分组后的一个渲染单元：单个词，或多个「之间没有空格」而需要连写的词。
///
/// 连写的一组词在渲染时共享一个 `emphasizeWrapper`，不会被折行拆开。
class WordChunk {
  WordChunk(this.words);

  WordChunk.single(AmllLyricWord word) : words = <AmllLyricWord>[word];

  final List<AmllLyricWord> words;

  bool get isGroup => words.length > 1;

  AmllLyricWord get first => words.first;
}

/// 把输入的单词重新分组：之间没有空格的单词会组合成一组。
///
/// 例如输入 `["Life", " ", "is", " a", " su", "gar so", "sweet"]`
/// 得到 `["Life", " ", "is", " a", [" su", "gar"], "so", "sweet"]`。
///
/// 同时会把含空格的词按空白切开、把多字 CJK 词拆成单字（无音译时），
/// 并按字符数等比分配时间。
List<WordChunk> chunkAndSplitLyricWords(List<AmllLyricWord> words) {
  final result = <WordChunk>[];
  var currentGroup = <AmllLyricWord>[];

  void flushGroup() {
    if (currentGroup.isNotEmpty) {
      result.add(WordChunk(currentGroup));
      currentGroup = <AmllLyricWord>[];
    }
  }

  void processAtom(AmllLyricWord atom) {
    final isSpace = atom.word.trim().isEmpty;
    final hasRuby = atom.ruby.isNotEmpty;
    final isCjkChar = isCJK(atom.word);

    // 空白、带 ruby、以及 CJK 单字都不参与连写合并
    final isMergeable = !isSpace && !hasRuby && !isCjkChar;

    if (isMergeable) {
      currentGroup.add(atom);
    } else {
      flushGroup();
      result.add(WordChunk.single(atom));
    }
  }

  for (final w in words) {
    final isSpace = w.word.trim().isEmpty;
    final romanWord = w.romanWord;
    final obscene = w.obscene;
    final hasRuby = w.ruby.isNotEmpty;

    if (isSpace || hasRuby) {
      processAtom(w.clone());
      continue;
    }

    final parts = _splitKeepingWhitespace(
      w.word,
    ).where((p) => p.isNotEmpty).toList();

    final strippedLength = w.word.replaceAll(_whitespace, '').length;
    final totalLength = strippedLength == 0 ? 1 : strippedLength;
    final timeSpan = w.endTime - w.startTime;
    final timePerUnit = timeSpan / totalLength;

    var currentOffset = 0;

    for (final part in parts) {
      if (part.trim().isEmpty) {
        final startTime = w.startTime + currentOffset * timePerUnit;
        processAtom(
          AmllLyricWord(
            word: part,
            startTime: startTime.round(),
            endTime: startTime.round(),
            obscene: obscene,
          ),
        );
        continue;
      }

      if (isCJK(part) && part.length > 1 && romanWord.trim().isEmpty) {
        for (final char in part.split('')) {
          final startTime = w.startTime + currentOffset * timePerUnit;
          processAtom(
            AmllLyricWord(
              word: char,
              startTime: startTime.round(),
              endTime: (startTime + timePerUnit).round(),
              obscene: obscene,
            ),
          );
          currentOffset += 1;
        }
      } else {
        final partRealLen = part.length;
        final startTime = w.startTime + currentOffset * timePerUnit;
        final duration = partRealLen * timePerUnit;

        processAtom(
          AmllLyricWord(
            word: part,
            startTime: startTime.round(),
            endTime: (startTime + duration).round(),
            romanWord: romanWord,
            obscene: obscene,
          ),
        );
        currentOffset += partRealLen;
      }
    }
  }

  flushGroup();

  return result;
}

/// 判定歌词单词是否可以应用强调辉光效果。
///
/// 条件：CJK 单词时长 ≥ 1s；非 CJK 单词时长 ≥ 1s 且去空格长度在 (1, 7] 之间。
bool shouldEmphasize(AmllLyricWord word) {
  if (isCJK(word.word)) return word.endTime - word.startTime >= 1000;

  final trimmedLength = word.word.trim().length;
  return word.endTime - word.startTime >= 1000 &&
      trimmedLength <= 7 &&
      trimmedLength > 1;
}
