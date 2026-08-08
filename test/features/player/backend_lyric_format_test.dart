import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the exact Netease YRC shape returned by the backend', () {
    const raw =
        '[20570,1900](20570,360,0)初(20930,150,0)め'
        '(21080,120,0)て(21200,170,0)の';

    final lines = LyricParser.parseNeteaseYrcLyric(raw);

    expect(lines, hasLength(1));
    expect(lines.single.startTime.inMilliseconds, 20570);
    expect(lines.single.lineDuration?.inMilliseconds, 1900);
    expect(lines.single.text, '初めての');
    expect(lines.single.words, hasLength(4));
    expect(lines.single.words!.first.duration.inMilliseconds, 360);
    expect(lines.single.words!.last.startTime.inMilliseconds, 21200);
  });

  test('parses backend QQ QRC two-field word timestamps', () {
    const raw = '[1000,400]你(1000,200)好(1200,200)';

    final lines = LyricParser.parseQQQrcLyric(raw);

    expect(lines, hasLength(1));
    expect(lines.single.text, '你好');
    expect(lines.single.words, hasLength(2));
    expect(lines.single.words!.first.startTime.inMilliseconds, 1000);
    expect(lines.single.words!.last.startTime.inMilliseconds, 1200);
    expect(lines.single.words!.last.duration.inMilliseconds, 200);
  });

  test('also accepts QQ QRC timestamps carrying a third flag field', () {
    const raw = '[1000,400]你(1000,200,0)好(1200,200,0)';

    final lines = LyricParser.parseQQQrcLyric(raw);

    expect(lines.single.text, '你好');
    expect(lines.single.words, hasLength(2));
  });
}
