import 'dart:math' as math;

import '../../mobile/compat/lyric_line.dart';
import 'sonnet_random.dart';
import 'sonnet_semantic.dart';
import 'sonnet_types.dart';

const List<SonnetShotKind> sonnetShotKinds = [
  SonnetShotKind.editorialColumn,
  SonnetShotKind.typeImpact,
  SonnetShotKind.fragmentCollage,
  SonnetShotKind.trackingRibbon,
  SonnetShotKind.maskReveal,
  SonnetShotKind.posterBlocks,
  SonnetShotKind.quietTableau,
];

const List<SonnetTransitionKind> sonnetTransitionKinds = [
  SonnetTransitionKind.fastBlur,
  SonnetTransitionKind.monoGlitch,
  SonnetTransitionKind.cameraPull,
];

double _median(List<double> values) {
  if (values.isEmpty) return 0.5;
  final sorted = List.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length % 2 == 0
      ? (sorted[middle - 1] + sorted[middle]) / 2
      : sorted[middle];
}

double resolveSonnetParagraphGapThreshold(List<LyricLine> lines) {
  if (lines.length <= 1) return 2.0;
  final gaps = <double>[];
  for (var i = 1; i < lines.length; i++) {
    final prev = lines[i - 1];
    final curr = lines[i];
    final prevStart = prev.startTime.inMicroseconds / 1000000.0;
    final prevDur = (prev.lineDuration ?? const Duration(seconds: 4))
            .inMicroseconds /
        1000000.0;
    final prevEnd = prevStart + prevDur;
    final currStart = curr.startTime.inMicroseconds / 1000000.0;
    final gap = currStart - math.min(prevEnd, currStart);
    if (gap > 0) gaps.add(gap);
  }
  return (_median(gaps) * 2.5).clamp(1.25, 3.5);
}

class _ParagraphDraft {
  _ParagraphDraft({required this.lines, required this.boundary});
  List<SonnetCompiledLine> lines;
  SonnetParagraphBoundary boundary;
}

List<_ParagraphDraft> _splitOversizedDraft(_ParagraphDraft draft) {
  final output = <_ParagraphDraft>[];
  var remaining = draft.lines;
  var boundary = draft.boundary;
  var loopGuard = 0;

  while (remaining.length > 6 ||
      (remaining.length > 1 &&
          (remaining.last.renderEndTime -
                  (remaining.first.line.startTime.inMicroseconds /
                      1000000.0)) >
              18)) {
    if (loopGuard++ > 1000) break;
    var bestSplit = math.min(4, remaining.length - 1);
    var bestGap = -double.infinity;

    for (var offset = 0; offset < remaining.length - 3; offset++) {
      final splitIndex = offset + 2;
      final lineStart =
          remaining[splitIndex].line.startTime.inMicroseconds / 1000000.0;
      final prevEnd = remaining[splitIndex - 1].renderEndTime;
      final gap = lineStart - prevEnd;
      if (!gap.isNaN && gap > bestGap) {
        bestGap = gap;
        bestSplit = splitIndex;
      }
    }

    final splitIndex = math.max(1, bestSplit);
    output.add(_ParagraphDraft(
      lines: remaining.sublist(0, splitIndex),
      boundary: boundary,
    ));
    remaining = remaining.sublist(splitIndex);
    boundary = output.last.lines.length >= 6
        ? SonnetParagraphBoundary.lineCap
        : SonnetParagraphBoundary.durationCap;
  }
  output.add(_ParagraphDraft(lines: remaining, boundary: boundary));
  return output;
}

SonnetParagraphKind _classifyParagraph(
  List<SonnetCompiledLine> lines,
  int index,
  int total,
) {
  if (lines.any((item) =>
      item.line.translation != null &&
      RegExp(r'chorus|副歌', caseSensitive: false)
          .hasMatch(item.line.translation!))) {
    return SonnetParagraphKind.chorus;
  }
  if (index == total - 1) return SonnetParagraphKind.outro;

  final firstStart =
      lines.first.line.startTime.inMicroseconds / 1000000.0;
  final duration = lines.last.renderEndTime - firstStart;
  final segmentCount = lines.fold<int>(
    0,
    (sum, line) =>
        sum + line.segments.where((seg) => seg.isWordLike).length,
  );
  final punctCount = lines.fold<int>(
    0,
    (sum, line) =>
        sum + RegExp(r'[!?！？…]').allMatches(line.line.text).length,
  );

  if (duration <= 3.5 || segmentCount <= 3) return SonnetParagraphKind.breath;
  if (punctCount >= 2 || segmentCount / math.max(duration, 1.0) > 2.5) {
    return SonnetParagraphKind.lift;
  }
  return SonnetParagraphKind.verse;
}

T _chooseWithoutRepeat<T>(List<T> choices, String seed, T? previous) {
  final start = hashSonnetSeed(seed) % choices.length;
  for (var offset = 0; offset < choices.length; offset++) {
    final candidate = choices[(start + offset) % choices.length];
    if (candidate != previous) return candidate;
  }
  return choices[start];
}

List<SonnetAnimationCue> _buildCues(List<SonnetCompiledLine> lines) {
  final segments = lines
      .expand((line) => line.segments)
      .where((seg) => seg.text.isNotEmpty)
      .toList();

  return List.generate(segments.length, (index) {
    final seg = segments[index];
    return SonnetAnimationCue(
      at: seg.startTime,
      duration: math.max(0.08, seg.endTime - seg.startTime),
      kind: index == segments.length - 1
          ? SonnetCueKind.accent
          : SonnetCueKind.enter,
      segmentStart: index,
      segmentEnd: index + 1,
    );
  });
}

List<List<SonnetCompiledLine>> _groupShotLines(List<SonnetCompiledLine> lines) {
  final groups = <List<SonnetCompiledLine>>[];
  var currentGroup = <SonnetCompiledLine>[];
  var groupStartTime = 0.0;

  for (final line in lines) {
    final lineStart = line.line.startTime.inMicroseconds / 1000000.0;
    if (currentGroup.isEmpty) {
      currentGroup.add(line);
      groupStartTime = lineStart;
    } else {
      final durationSoFar = line.renderEndTime - groupStartTime;
      if (currentGroup.length < 4 && durationSoFar <= 6.0) {
        currentGroup.add(line);
      } else {
        groups.add(currentGroup);
        currentGroup = [line];
        groupStartTime = lineStart;
      }
    }
  }
  if (currentGroup.isNotEmpty) groups.add(currentGroup);
  return groups;
}

List<SonnetShot> _buildShots(
  List<SonnetCompiledLine> lines,
  SonnetParagraphKind kind,
  int paragraphIndex,
  String seed,
  SonnetShotKind? previousKind,
) {
  var lastKind = previousKind;
  final groups = _groupShotLines(lines);

  return List.generate(groups.length, (shotIndex) {
    final group = groups[shotIndex];
    final signature = group.map((item) => item.line.text).join('|');
    var shotKind = _chooseWithoutRepeat(
      sonnetShotKinds,
      '$seed:$paragraphIndex:$shotIndex:$signature',
      lastKind,
    );

    final wordCount = group.fold<int>(
      0,
      (sum, item) =>
          sum + item.segments.where((s) => s.isWordLike).length,
    );

    if (kind == SonnetParagraphKind.breath &&
        shotIndex == 0 &&
        wordCount <= 2) {
      shotKind = SonnetShotKind.quietTableau;
    }
    if (kind == SonnetParagraphKind.chorus &&
        shotKind == SonnetShotKind.quietTableau) {
      shotKind = SonnetShotKind.typeImpact;
    }
    lastKind = shotKind;

    final random = hashSonnetSeed('$seed:$paragraphIndex:$shotIndex:camera');
    final zoomRandom = ((random >> 16) & 255) / 255.0;
    final zoomBase = shotKind == SonnetShotKind.posterBlocks
        ? 1.02
        : (shotKind == SonnetShotKind.quietTableau ? 1.12 : 1.22);
    final zoomSpan = shotKind == SonnetShotKind.posterBlocks
        ? 0.16
        : (shotKind == SonnetShotKind.quietTableau ? 0.2 : 0.26);

    final firstStart =
        group.first.line.startTime.inMicroseconds / 1000000.0;
    return SonnetShot(
      id: 'p$paragraphIndex-s$shotIndex',
      kind: shotKind,
      startTime: firstStart,
      endTime: group.last.renderEndTime,
      lineIndices: group.map((item) => item.sourceIndex).toList(),
      cues: _buildCues(group),
      camera: SonnetCameraTarget(
        x: ((random & 255) / 255.0 - 0.5) * 0.18,
        y: (((random >> 8) & 255) / 255.0 - 0.5) * 0.14,
        zoom: zoomBase + zoomRandom * zoomSpan,
        rotation: (((random >> 24) & 255) / 255.0 - 0.5) * 0.08,
      ),
    );
  });
}

SonnetProgram compileSonnetProgram(
  List<LyricLine> lines, [
  String seed = 'sonnet',
]) {
  if (lines.isEmpty) return SonnetProgram.empty;

  final compiled = List.generate(lines.length, (sourceIndex) {
    final line = lines[sourceIndex];
    final lineStartSec = line.startTime.inMicroseconds / 1000000.0;
    final lineDurSec = (line.lineDuration ?? const Duration(seconds: 4))
            .inMicroseconds /
        1000000.0;
    final naturalEnd = lineStartSec + lineDurSec;
    final nextStart = sourceIndex + 1 < lines.length
        ? lines[sourceIndex + 1].startTime.inMicroseconds / 1000000.0
        : double.infinity;

    final renderEndTime = math.max(
      lineStartSec,
      math.min(naturalEnd, nextStart),
    );

    return SonnetCompiledLine(
      sourceIndex: sourceIndex,
      line: line,
      renderEndTime: renderEndTime,
      segments: buildSonnetSemanticSegments(line),
    );
  });

  final gapThreshold = resolveSonnetParagraphGapThreshold(lines);
  final drafts = <_ParagraphDraft>[];
  var current = _ParagraphDraft(
    lines: [],
    boundary: SonnetParagraphBoundary.songStart,
  );

  for (var index = 0; index < compiled.length; index++) {
    final line = compiled[index];
    final prev = index > 0 ? compiled[index - 1] : null;
    final lineStart = line.line.startTime.inMicroseconds / 1000000.0;
    final gap = prev != null ? lineStart - prev.renderEndTime : 0.0;

    final boundary = prev != null && gap >= gapThreshold
        ? SonnetParagraphBoundary.timeGap
        : null;

    if (boundary != null && current.lines.isNotEmpty) {
      drafts.addAll(_splitOversizedDraft(current));
      current = _ParagraphDraft(lines: [], boundary: boundary);
    }
    current.lines.add(line);
  }
  if (current.lines.isNotEmpty) {
    drafts.addAll(_splitOversizedDraft(current));
  }

  SonnetShotKind? previousShot;
  SonnetTransitionKind? previousTransition;

  final paragraphs = List.generate(drafts.length, (index) {
    final draft = drafts[index];
    final kind = _classifyParagraph(draft.lines, index, drafts.length);
    final shots = _buildShots(
      draft.lines,
      kind,
      index,
      seed,
      previousShot,
    );
    if (shots.isNotEmpty) previousShot = shots.last.kind;

    final next = index + 1 < drafts.length ? drafts[index + 1] : null;
    final endTime = draft.lines.last.renderEndTime;
    final nextStart = next?.lines.first.line.startTime.inMicroseconds != null
        ? next!.lines.first.line.startTime.inMicroseconds / 1000000.0
        : endTime;
    final gap = next != null ? nextStart - endTime : 0.0;

    final transitionKind = next != null
        ? _chooseWithoutRepeat(
            sonnetTransitionKinds,
            '$seed:$index:transition',
            previousTransition,
          )
        : null;
    if (transitionKind != null) previousTransition = transitionKind;

    final transitionDuration = next != null
        ? math.min(0.3, math.max(0.16, gap > 0 ? gap * 0.5 : 0.2))
        : 0.0;
    final transitionEndTime = nextStart;

    final firstLineStart =
        draft.lines.first.line.startTime.inMicroseconds / 1000000.0;

    return SonnetParagraph(
      id: 'sonnet-p$index',
      kind: kind,
      boundary: draft.boundary,
      startTime: firstLineStart,
      endTime: endTime,
      lines: draft.lines,
      shots: shots,
      transitionOut: transitionKind != null
          ? SonnetTransition(
              kind: transitionKind,
              startTime: math.max(
                firstLineStart,
                transitionEndTime - transitionDuration,
              ),
              endTime: transitionEndTime,
            )
          : null,
    );
  });

  return SonnetProgram(
    seed: seed,
    paragraphGapThreshold: gapThreshold,
    paragraphs: paragraphs,
  );
}

int findSonnetParagraphIndexAtTime(SonnetProgram program, double time) {
  for (var index = program.paragraphs.length - 1; index >= 0; index--) {
    if (time >= program.paragraphs[index].startTime) return index;
  }
  return 0;
}
