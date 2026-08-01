import 'package:cyrene_music_reborn/features/player/amll/render/text_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const TextStyle kStyle = TextStyle(fontSize: 32, fontWeight: FontWeight.w700);

void main() {
  setUp(() => LyricTextCache.instance.clear());

  group('LyricTextCache', () {
    test('相同参数第二次命中缓存', () {
      final cache = LyricTextCache.instance;

      cache.paragraph(
        text: 'hello',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      expect(cache.misses, 1);
      expect(cache.hits, 0);

      cache.paragraph(
        text: 'hello',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      expect(cache.hits, 1);
      expect(cache.misses, 1);
    });

    test('返回的是同一个段落实例', () {
      final cache = LyricTextCache.instance;
      final a = cache.paragraph(
        text: 'same',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      final b = cache.paragraph(
        text: 'same',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      expect(identical(a, b), isTrue);
    });

    test('透明度被量化：细微差异仍然命中', () {
      final cache = LyricTextCache.instance;

      cache.paragraph(
        text: 'x',
        style: kStyle,
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.500),
      );
      // 0.5 与 0.502 落在同一量化档
      cache.paragraph(
        text: 'x',
        style: kStyle,
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.502),
      );

      expect(cache.hits, 1, reason: '量化后应命中同一条缓存');
    });

    test('透明度差异明显时不复用', () {
      final cache = LyricTextCache.instance;
      cache.paragraph(
        text: 'x',
        style: kStyle,
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
      );
      cache.paragraph(
        text: 'x',
        style: kStyle,
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.9),
      );
      expect(cache.misses, 2);
    });

    test('文本、字号、字重、颜色任一不同都各自成条目', () {
      final cache = LyricTextCache.instance;
      const white = Color(0xFFFFFFFF);

      cache.paragraph(text: 'a', style: kStyle, color: white);
      cache.paragraph(text: 'b', style: kStyle, color: white);
      cache.paragraph(
        text: 'a',
        style: kStyle.copyWith(fontSize: 20),
        color: white,
      );
      cache.paragraph(
        text: 'a',
        style: kStyle.copyWith(fontWeight: FontWeight.w400),
        color: white,
      );
      cache.paragraph(text: 'a', style: kStyle, color: const Color(0xFFFF0000));

      expect(cache.misses, 5);
      expect(cache.hits, 0);
    });

    test('模拟逐帧绘制：命中率应远高于未命中', () {
      final cache = LyricTextCache.instance;
      const words = <String>['Never', 'gonna', 'give', 'you', 'up'];

      // 60 帧 × 5 个词，透明度在少数几档之间变化
      for (var frame = 0; frame < 60; frame++) {
        for (final word in words) {
          final alpha = 0.2 + (frame % 3) * 0.3;
          cache.paragraph(
            text: word,
            style: kStyle,
            color: const Color(0xFFFFFFFF).withValues(alpha: alpha),
          );
        }
      }

      // 5 词 × 3 档 = 15 条缓存，其余 285 次都应命中
      expect(cache.misses, lessThanOrEqualTo(15));
      expect(cache.hits, greaterThan(cache.misses * 10));
    });

    test('容量超限后仍可继续工作', () {
      final cache = LyricTextCache.instance;
      for (var i = 0; i < 2600; i++) {
        cache.paragraph(
          text: 'word$i',
          style: kStyle,
          color: const Color(0xFFFFFFFF),
        );
      }
      expect(cache.length, lessThanOrEqualTo(2048));

      // 淘汰后新条目照样可用
      final p = cache.paragraph(
        text: 'fresh',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      expect(p.width, greaterThan(0));
    });

    test('段落已完成 layout，尺寸可用', () {
      final p = LyricTextCache.instance.paragraph(
        text: 'measure me',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      expect(p.width, greaterThan(0));
      expect(p.height, greaterThan(0));
    });

    test('clear 会重置计数与容量', () {
      final cache = LyricTextCache.instance;
      cache.paragraph(
        text: 'x',
        style: kStyle,
        color: const Color(0xFFFFFFFF),
      );
      cache.clear();
      expect(cache.length, 0);
      expect(cache.hits, 0);
      expect(cache.misses, 0);
    });
  });
}
