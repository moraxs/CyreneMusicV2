class LyricWord {
  const LyricWord({required this.text, required this.start, required this.end});

  final String text;
  final Duration start;
  final Duration end;

  Duration get duration => end - start;
}

class LyricLine {
  LyricLine({
    required this.start,
    required this.end,
    required List<LyricWord> words,
    required this.isVerbatim,
    this.translation,
  }) : words = List.unmodifiable(words);

  final Duration start;
  final Duration end;
  final List<LyricWord> words;
  final bool isVerbatim;
  final String? translation;

  String get text => words.map((word) => word.text).join();

  LyricLine copyWith({Duration? end, String? translation}) => LyricLine(
    start: start,
    end: end ?? this.end,
    words: words,
    isVerbatim: isVerbatim,
    translation: translation ?? this.translation,
  );
}
