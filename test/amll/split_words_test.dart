import 'package:cyrene_music_reborn/features/player/amll/core/is_cjk.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/lyric_types.dart';
import 'package:cyrene_music_reborn/features/player/amll/core/split_words.dart';
import 'package:flutter_test/flutter_test.dart';

AmllLyricWord w(String text, int start, int end) =>
    AmllLyricWord(word: text, startTime: start, endTime: end);

/// 把分组结果摊平成可读的字符串，便于断言。
List<Object> shape(List<WordChunk> chunks) => chunks
    .map<Object>(
      (c) => c.isGroup ? c.words.map((x) => x.word).toList() : c.first.word,
    )
    .toList();

void main() {
  group('isCJK', () {
    test('汉字为真', () {
      expect(isCJK('歌'), isTrue);
      expect(isCJK('歌词'), isTrue);
    });

    test('拉丁字母为假', () {
      expect(isCJK('a'), isFalse);
      expect(isCJK('Life'), isFalse);
    });

    test('空串为假', () {
      expect(isCJK(''), isFalse);
    });

    test('混合内容为假', () {
      expect(isCJK('歌a'), isFalse);
    });
  });

  group('chunkAndSplitLyricWords', () {
    test('连写的拉丁词被合并成一组', () {
      final result = chunkAndSplitLyricWords([
        w('Li', 0, 500),
        w('fe', 500, 1000),
      ]);
      expect(shape(result), [
        ['Li', 'fe'],
      ]);
    });

    test('空格会切断分组并作为独立原子保留', () {
      final result = chunkAndSplitLyricWords([
        w('Life', 0, 500),
        w(' ', 500, 500),
        w('is', 500, 1000),
      ]);
      expect(shape(result), ['Life', ' ', 'is']);
    });

    test('含空格的词被拆开，时间按字符数等比分配', () {
      final result = chunkAndSplitLyricWords([w('so sweet', 0, 8000)]);
      // 去空格共 7 字符，每字符 8000/7 ms
      expect(shape(result), ['so', ' ', 'sweet']);

      final so = result[0].first;
      final sweet = result[2].first;
      expect(so.startTime, 0);
      expect(so.endTime, closeTo(8000 * 2 / 7, 1));
      expect(sweet.startTime, closeTo(8000 * 2 / 7, 1));
      expect(sweet.endTime, closeTo(8000, 1));
    });

    test('多字 CJK 词被拆成单字，且每字独立成组', () {
      final result = chunkAndSplitLyricWords([w('歌词很好', 0, 4000)]);
      expect(shape(result), ['歌', '词', '很', '好']);

      final first = result[0].first;
      final last = result[3].first;
      expect(first.startTime, 0);
      expect(first.endTime, 1000);
      expect(last.startTime, 3000);
      expect(last.endTime, 4000);
    });

    test('带音译的 CJK 词不拆字', () {
      final result = chunkAndSplitLyricWords([
        AmllLyricWord(
          word: '歌词',
          startTime: 0,
          endTime: 2000,
          romanWord: 'gecí',
        ),
      ]);
      expect(shape(result), ['歌词']);
    });

    test('带 ruby 的词原样保留为独立原子', () {
      final result = chunkAndSplitLyricWords([
        AmllLyricWord(
          word: '本気',
          startTime: 0,
          endTime: 1000,
          ruby: [AmllRuby(word: 'ほんき', startTime: 0, endTime: 1000)],
        ),
      ]);
      expect(shape(result), ['本気']);
      expect(result[0].first.ruby, hasLength(1));
    });

    test('CJK 与拉丁混排时 CJK 不并入拉丁组', () {
      final result = chunkAndSplitLyricWords([
        w('ba', 0, 300),
        w('by', 300, 600),
        w('宝', 600, 900),
      ]);
      expect(shape(result), [
        ['ba', 'by'],
        '宝',
      ]);
    });

    test('空输入返回空结果', () {
      expect(chunkAndSplitLyricWords([]), isEmpty);
    });

    test('不修改输入的原始对象', () {
      final input = [w('hello world', 0, 1000)];
      chunkAndSplitLyricWords(input);
      expect(input[0].word, 'hello world');
      expect(input[0].endTime, 1000);
    });
  });

  group('shouldEmphasize', () {
    test('CJK 词只看时长是否 ≥1s', () {
      expect(shouldEmphasize(w('啊', 0, 1000)), isTrue);
      expect(shouldEmphasize(w('啊', 0, 999)), isFalse);
    });

    test('非 CJK 词需要 ≥1s 且长度在 2..7', () {
      expect(shouldEmphasize(w('love', 0, 1500)), isTrue);
      expect(shouldEmphasize(w('a', 0, 1500)), isFalse, reason: '单字符不强调');
      expect(
        shouldEmphasize(w('extraordinary', 0, 1500)),
        isFalse,
        reason: '超过 7 字符不强调',
      );
      expect(shouldEmphasize(w('love', 0, 800)), isFalse, reason: '时长不足');
    });

    test('长度判定忽略首尾空格', () {
      expect(shouldEmphasize(w('  love  ', 0, 1500)), isTrue);
    });
  });
}
