import 'package:flutter/material.dart';

import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/models/track.dart';
import '../mobile/compat/lyric_line.dart';
import '../mobile/compat/lyric_parser.dart';
import 'default_core/default_canvas.dart';
import 'default_core/default_types.dart';
import 'super_cyrene_lyric_timing.dart';

/// Direct Flutter counterpart of SuperCyrenePlayer/DefaultLyrics.tsx.
///
/// This layer only adapts parsed lyrics and the playback clock. Article layout,
/// print styling and camera tracking live in the matching default_core modules.
class SuperCyreneClassicLyrics extends StatefulWidget {
  const SuperCyreneClassicLyrics({
    super.key,
    required this.playback,
    required this.track,
    required this.onTranslationChanged,
    this.onRomajiChanged,
  });

  final PlaybackController playback;
  final Track track;
  final ValueChanged<String?> onTranslationChanged;
  final ValueChanged<String?>? onRomajiChanged;

  @override
  State<SuperCyreneClassicLyrics> createState() =>
      _SuperCyreneClassicLyricsState();
}

class _SuperCyreneClassicLyricsState extends State<SuperCyreneClassicLyrics> {
  List<DefaultLine> _lines = const [];
  int _lastLineIndex = -2;

  @override
  void initState() {
    super.initState();
    widget.playback.positionListenable.addListener(_updateTranslation);
    _adaptTrack();
  }

  @override
  void didUpdateWidget(covariant SuperCyreneClassicLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.positionListenable.removeListener(_updateTranslation);
      widget.playback.positionListenable.addListener(_updateTranslation);
    }
    if (_lyricSignature(oldWidget.track) != _lyricSignature(widget.track)) {
      _adaptTrack();
    }
  }

  int _lyricSignature(Track track) =>
      Object.hash(track.key, track.lyric, track.yrc, track.tlyric, track.ytlrc, track.romaji);

  @override
  void dispose() {
    widget.playback.positionListenable.removeListener(_updateTranslation);
    super.dispose();
  }

  void _adaptTrack() {
    final lyric = widget.track.lyric;
    final parsed = lyric == null || lyric.isEmpty
        ? const <LyricLine>[]
        : switch (widget.track.source) {
            MusicSource.qq => LyricParser.parseQQLyric(
              lyric,
              translation: widget.track.tlyric,
              qrcLyric: widget.track.yrc,
              qrcTranslation: widget.track.ytlrc,
              romaji: widget.track.romaji,
            ),
            MusicSource.kugou => LyricParser.parseKugouLyric(
              lyric,
              translation: widget.track.tlyric,
              romaji: widget.track.romaji,
            ),
            _ => LyricParser.parseNeteaseLyric(
              lyric,
              translation: widget.track.tlyric,
              yrcLyric: widget.track.yrc,
              yrcTranslation: widget.track.ytlrc,
              romaji: widget.track.romaji,
            ),
          };
    _lines = parsed.indexed
        .where((entry) => entry.$2.text.trim().isNotEmpty)
        .map((entry) => _adaptLine(entry.$2, entry.$1, parsed))
        .toList(growable: false);
    _lastLineIndex = -2;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateTranslation());
  }

  DefaultLine _adaptLine(LyricLine line, int index, List<LyricLine> source) {
    final fallbackEnd = index + 1 < source.length
        ? source[index + 1].startTime
        : line.startTime + (line.lineDuration ?? const Duration(seconds: 4));
    final lineEnd =
        line.startTime + (line.lineDuration ?? fallbackEnd - line.startTime);
    final words = buildSuperCyreneWordTimeline(line: line, lineEnd: lineEnd);
    return DefaultLine(
      id: '${line.startTime.inMilliseconds}-$index',
      fullText: words.map((word) => word.text).join(),
      startTime: line.startTime.inMicroseconds / 1000000,
      endTime: lineEnd.inMicroseconds / 1000000,
      translation: line.translation,
      romaji: line.romanization,
      words: words,
    );
  }

  void _updateTranslation() {
    if (!mounted) return;
    final time = widget.playback.positionListenable.value.inMilliseconds + 300;
    var index = -1;
    for (var cursor = 0; cursor < _lines.length; cursor++) {
      if (time < _lines[cursor].startTime * 1000) break;
      index = cursor;
    }
    if (index == _lastLineIndex) return;
    _lastLineIndex = index;
    widget.onTranslationChanged(
      index >= 0 ? _lines[index].translation?.trim() : null,
    );
    widget.onRomajiChanged?.call(
      index >= 0 ? _lines[index].romaji?.trim() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .3),
            fontSize: 14,
            letterSpacing: 2.8,
          ),
        ),
      );
    }
    return SuperCyreneDefaultCanvas(
      lines: _lines,
      position: widget.playback.positionListenable,
    );
  }
}
