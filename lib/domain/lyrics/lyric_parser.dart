import '../models/music_source.dart';
import 'lyric.dart';
import 'lyric_timing.dart';

class LyricParser {
  const LyricParser({this.introDelay = lyricIntroDelay});

  final Duration introDelay;

  List<LyricLine> parse({
    required MusicSource source,
    String? lyric,
    String? yrc,
    String? translation,
    String? verbatimTranslation,
  }) {
    final hasYrc = yrc?.trim().isNotEmpty ?? false;
    final primarySource = hasYrc ? yrc! : lyric;
    if (primarySource == null || primarySource.trim().isEmpty) return const [];

    final offset = _parseOffset(primarySource);
    final lines = _parsePrimary(
      source: source,
      raw: primarySource,
      offset: hasYrc ? Duration.zero : offset,
    )..sort((left, right) => left.start.compareTo(right.start));

    final completedLines = _completeLineEnds(lines);
    final translationSource = hasYrc ? verbatimTranslation : translation;
    final translations = _parseTranslations(translationSource, offset);

    return List.unmodifiable(
      completedLines
          .map(
            (line) => line.copyWith(
              translation: _nearestTranslation(line.start, translations),
            ),
          )
          .toList(),
    );
  }

  List<LyricLine> _parsePrimary({
    required MusicSource source,
    required String raw,
    required Duration offset,
  }) => raw
      .split(RegExp(r'\r?\n'))
      .map(
        (line) => _parseLine(source: source, raw: line.trim(), offset: offset),
      )
      .expand((lines) => lines)
      .toList();

  List<LyricLine> _parseLine({
    required MusicSource source,
    required String raw,
    required Duration offset,
  }) {
    if (raw.isEmpty || raw.startsWith('{')) return const [];

    final yrcMatch = RegExp(r'^\[(\d+),(\d+)\](.*)$').firstMatch(raw);
    if (yrcMatch != null) {
      return _parseVerbatimLine(
        source: source,
        payload: yrcMatch.group(3) ?? '',
        start:
            Duration(milliseconds: int.parse(yrcMatch.group(1)!)) + introDelay,
        duration: Duration(milliseconds: int.parse(yrcMatch.group(2)!)),
      );
    }

    final matches = RegExp(
      r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]',
    ).allMatches(raw).toList();
    if (matches.isEmpty) return const [];

    final text = raw.substring(matches.last.end).trim();
    if (text.isEmpty) return const [];

    return matches.map((match) {
      final start =
          _timestamp(
            minutes: int.parse(match.group(1)!),
            seconds: int.parse(match.group(2)!),
            fraction: match.group(3),
          ) +
          introDelay +
          offset;
      return LyricLine(
        start: start,
        end: start + const Duration(seconds: 2),
        words: [LyricWord(text: text, start: start, end: start)],
        isVerbatim: false,
      );
    }).toList();
  }

  List<LyricLine> _parseVerbatimLine({
    required MusicSource source,
    required String payload,
    required Duration start,
    required Duration duration,
  }) {
    final qishuiWords = _parseQishuiWords(payload, start);
    final qrcWords = source == MusicSource.qq
        ? _parseQrcWords(payload)
        : const <LyricWord>[];
    final yrcWords = source == MusicSource.qq
        ? const <LyricWord>[]
        : _parseYrcWords(payload);
    final words = qishuiWords.isNotEmpty
        ? qishuiWords
        : qrcWords.isNotEmpty
        ? qrcWords
        : yrcWords;

    if (words.isEmpty) return const [];
    return [
      LyricLine(
        start: start,
        end: start + duration,
        words: words,
        isVerbatim: true,
      ),
    ];
  }

  List<LyricWord> _parseYrcWords(String payload) =>
      RegExp(r'\((\d+),(\d+),\d+\)([^\(\[\r\n]+)').allMatches(payload).map((
        match,
      ) {
        final start =
            Duration(milliseconds: int.parse(match.group(1)!)) + introDelay;
        final duration = Duration(milliseconds: int.parse(match.group(2)!));
        return LyricWord(
          text: match.group(3)!,
          start: start,
          end: start + duration,
        );
      }).toList();

  List<LyricWord> _parseQishuiWords(String payload, Duration lineStart) =>
      RegExp(r'<(\d+),(\d+),\d+>([^<\[\r\n]+)').allMatches(payload).map((
        match,
      ) {
        final start =
            lineStart + Duration(milliseconds: int.parse(match.group(1)!));
        final duration = Duration(milliseconds: int.parse(match.group(2)!));
        return LyricWord(
          text: match.group(3)!,
          start: start,
          end: start + duration,
        );
      }).toList();

  List<LyricWord> _parseQrcWords(String payload) =>
      RegExp(r'([^\(\[\]<>]+?)\((\d+),(\d+)\)')
          .allMatches(payload)
          .map((match) {
            final start =
                Duration(milliseconds: int.parse(match.group(2)!)) + introDelay;
            final duration = Duration(milliseconds: int.parse(match.group(3)!));
            return LyricWord(
              text: match.group(1)!.trim(),
              start: start,
              end: start + duration,
            );
          })
          .where((word) => word.text.isNotEmpty)
          .toList();

  List<LyricLine> _completeLineEnds(List<LyricLine> lines) =>
      List.generate(lines.length, (index) {
        final line = lines[index];
        if (line.isVerbatim) return line;
        final nextStart = index + 1 < lines.length
            ? lines[index + 1].start
            : line.start + const Duration(seconds: 5);
        final end = nextStart > line.start
            ? nextStart
            : line.start + const Duration(seconds: 2);
        return LyricLine(
          start: line.start,
          end: end,
          words: [LyricWord(text: line.text, start: line.start, end: end)],
          isVerbatim: false,
        );
      });

  List<_TimedText> _parseTranslations(String? raw, Duration offset) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final lines = <_TimedText>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final matches = RegExp(
        r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]',
      ).allMatches(line).toList();
      final text = matches.isEmpty
          ? ''
          : line.substring(matches.last.end).trim();
      for (final match in matches) {
        if (text.isEmpty) continue;
        lines.add(
          _TimedText(
            time:
                _timestamp(
                  minutes: int.parse(match.group(1)!),
                  seconds: int.parse(match.group(2)!),
                  fraction: match.group(3),
                ) +
                introDelay +
                offset,
            text: text,
          ),
        );
      }
    }
    return lines;
  }

  String? _nearestTranslation(Duration start, List<_TimedText> translations) {
    _TimedText? closest;
    var smallestDifference = const Duration(milliseconds: 501);
    for (final translation in translations) {
      final difference = (translation.time - start).abs();
      if (difference < smallestDifference) {
        closest = translation;
        smallestDifference = difference;
      }
    }
    return closest?.text;
  }

  Duration _parseOffset(String raw) {
    final match = RegExp(
      r'\[offset:\s*(-?\d+)\]',
      caseSensitive: false,
    ).firstMatch(raw);
    return match == null
        ? Duration.zero
        : Duration(milliseconds: int.parse(match.group(1)!));
  }

  Duration _timestamp({
    required int minutes,
    required int seconds,
    required String? fraction,
  }) {
    final milliseconds = fraction == null
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
}

class _TimedText {
  const _TimedText({required this.time, required this.text});

  final Duration time;
  final String text;
}
