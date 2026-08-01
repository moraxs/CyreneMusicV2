import 'lyric.dart';

class LyricTimeline {
  const LyricTimeline(this.lines);

  final List<LyricLine> lines;

  int activeLineIndexAt(Duration position) {
    var low = 0;
    var high = lines.length - 1;
    var candidate = -1;

    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].start <= position) {
        candidate = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    if (candidate < 0 || position >= lines[candidate].end) return -1;
    return candidate;
  }

  LyricLine? activeLineAt(Duration position) {
    final index = activeLineIndexAt(position);
    return index < 0 ? null : lines[index];
  }

  int activeWordIndexAt(Duration position) {
    final line = activeLineAt(position);
    if (line == null || !line.isVerbatim) return -1;
    return line.words.indexWhere(
      (word) => position >= word.start && position < word.end,
    );
  }
}
