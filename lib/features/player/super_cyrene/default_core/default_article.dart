import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import 'default_types.dart';

List<String> splitDefaultGraphemes(String text) => text.characters.toList();

int _hashString(String input) {
  var hash = 2166136261;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xffffffff;
  }
  return hash;
}

double _seeded(String seed) => (_hashString(seed) % 10000) / 10000;

int _renderableCount(String text) => splitDefaultGraphemes(
  text,
).where((value) => value.trim().isNotEmpty).length;

DefaultBlockVariant _naturalVariant(DefaultLine line, int index, int total) {
  final graphemeCount = _renderableCount(line.fullText);
  if (graphemeCount == 0) return DefaultBlockVariant.body;
  if (line.isChorus && graphemeCount <= 22) return DefaultBlockVariant.hero;
  final shortEnough = graphemeCount >= 4 && graphemeCount <= 28;
  final centered = (index - total / 2).abs() / math.max(total, 1);
  final random = _seeded('${line.fullText}:$index');
  return shortEnough &&
          centered < .72 &&
          ((index + 1) % 6 == 0 || random > .965)
      ? DefaultBlockVariant.hero
      : DefaultBlockVariant.body;
}

int _fallbackHeroIndex(List<({DefaultLine line, int index})> entries) {
  if (entries.isEmpty ||
      entries.indexed.any(
        (entry) =>
            _naturalVariant(entry.$2.line, entry.$1, entries.length) ==
            DefaultBlockVariant.hero,
      )) {
    return -1;
  }
  var bestIndex = -1;
  var bestScore = double.negativeInfinity;
  for (var blockIndex = 0; blockIndex < entries.length; blockIndex++) {
    final line = entries[blockIndex].line;
    final count = _renderableCount(line.fullText);
    if (count == 0 || (count > 36)) continue;
    final centered =
        (blockIndex - entries.length / 2).abs() / math.max(entries.length, 1);
    final lengthScore = count >= 6 && count <= 22
        ? 1.0
        : count <= 28
        ? .72
        : .36;
    final score =
        (1 - centered) * .62 +
        lengthScore * .34 +
        (line.isChorus ? .28 : 0) +
        _seeded('${line.fullText}:$blockIndex:fallback-hero') * .04;
    if (score > bestScore) {
      bestScore = score;
      bestIndex = blockIndex;
    }
  }
  if (bestIndex >= 0) return bestIndex;
  var shortestIndex = -1;
  var shortestCount = 1 << 30;
  for (var index = 0; index < entries.length; index++) {
    final count = _renderableCount(entries[index].line.fullText);
    if (count > 0 && count < shortestCount) {
      shortestCount = count;
      shortestIndex = index;
    }
  }
  return shortestIndex;
}

double _measure(String text, double fontPx, DefaultBlockVariant variant) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontPx,
        fontWeight: variant == DefaultBlockVariant.hero
            ? FontWeight.w800
            : FontWeight.w600,
        letterSpacing: variant == DefaultBlockVariant.hero ? -.8 : -.25,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}

({double fontPx, double width}) _fitSingleLine(
  String text,
  double width,
  DefaultBlockVariant variant,
  double densityScale,
) {
  var low = variant == DefaultBlockVariant.hero ? 18.0 : 10.0;
  var high = variant == DefaultBlockVariant.hero ? 58.0 : 30.0;
  var best = low * densityScale;
  var measured = _measure(text, best, variant);
  for (var iteration = 0; iteration < 8; iteration++) {
    final candidate = ((low + high) / 2) * densityScale;
    final candidateWidth = _measure(text, candidate, variant);
    if (candidateWidth <= width) {
      best = candidate;
      measured = candidateWidth;
      low = (low + high) / 2;
    } else {
      high = (low + high) / 2;
    }
  }
  return (fontPx: best, width: measured);
}

List<double> _glyphOffsets(
  List<String> graphemes,
  double fontPx,
  DefaultBlockVariant variant,
) {
  final offsets = <double>[0];
  final prefix = StringBuffer();
  for (final grapheme in graphemes) {
    prefix.write(grapheme);
    offsets.add(_measure(prefix.toString(), fontPx, variant));
  }
  return offsets;
}

List<DefaultWordRange> _wordRanges(DefaultLine line, List<String> graphemes) {
  final ranges = <DefaultWordRange>[];
  var cursor = 0;
  for (final word in line.words) {
    final count = splitDefaultGraphemes(word.text).length;
    final start = cursor.clamp(0, graphemes.length);
    var end = (start + count).clamp(start, graphemes.length);
    while (end < graphemes.length && graphemes[end].trim().isEmpty) {
      end++;
    }
    ranges.add(DefaultWordRange(word: word, start: start, end: end));
    cursor = end;
  }
  return ranges;
}

class _Attempt {
  const _Attempt({required this.height, required this.article});

  final double height;
  final DefaultArticleLayout? article;
}

_Attempt _buildAttempt({
  required List<DefaultLine> lines,
  required Size viewport,
  required double paperWidth,
  required int columns,
  required double gap,
  required double densityScale,
  required String seedKey,
  required bool render,
}) {
  final horizontalMargin = math.max(viewport.width * .86, 280.0);
  final verticalMargin = math.max(viewport.height * .82, 220.0);
  final columnWidth = (paperWidth - gap * (columns - 1)) / columns;
  final entries =
      lines.indexed
          .where((entry) => entry.$2.fullText.trim().isNotEmpty)
          .map((entry) => (line: entry.$2, index: entry.$1))
          .toList()
        ..sort((left, right) {
          final leftSeed = _seeded(
            '$seedKey:${left.index}:${left.line.fullText}',
          );
          final rightSeed = _seeded(
            '$seedKey:${right.index}:${right.line.fullText}',
          );
          return leftSeed.compareTo(rightSeed);
        });
  final forcedHeroIndex = _fallbackHeroIndex(entries);
  final columnHeights = List<double>.filled(columns, verticalMargin);
  final blocks = <DefaultBlock>[];
  var bodyTieCursor = 0;
  var heroTieCursor = 0;

  for (var blockIndex = 0; blockIndex < entries.length; blockIndex++) {
    final entry = entries[blockIndex];
    final natural = _naturalVariant(entry.line, blockIndex, entries.length);
    final variant = blockIndex == forcedHeroIndex
        ? DefaultBlockVariant.hero
        : natural;
    final heroSpan = variant == DefaultBlockVariant.hero
        ? math.min(columns, columns <= 1 ? 1 : 2)
        : 1;
    final heroSpanWidth = heroSpan > 1
        ? columnWidth * heroSpan + gap * (heroSpan - 1)
        : paperWidth;
    final blockWidth = variant == DefaultBlockVariant.hero
        ? heroSpan == 1
              ? paperWidth
              : columns == 2
              ? columnWidth * 1.5 + gap * .5
              : heroSpanWidth
        : columnWidth;
    final fitted = _fitSingleLine(
      entry.line.fullText,
      math.max(blockWidth, 120),
      variant,
      densityScale,
    );
    final lineHeight =
        (fitted.fontPx * (variant == DefaultBlockVariant.hero ? 1.02 : 1.06))
            .roundToDouble();
    final blockGap = variant == DefaultBlockVariant.hero
        ? math.max((lineHeight * .2).round(), 6).toDouble()
        : math.max((lineHeight * .08).round(), 2).toDouble();
    final blockHeight = lineHeight;
    var x = 0.0;
    var y = 0.0;

    if (variant == DefaultBlockVariant.hero) {
      if (heroSpan == 1) {
        y = columnHeights.reduce(math.max);
        x = horizontalMargin;
        columnHeights[0] = y + blockHeight + blockGap;
      } else {
        var bestHeight = double.infinity;
        final starts = <int>[];
        for (var start = 0; start <= columns - heroSpan; start++) {
          var covered = 0.0;
          for (var column = start; column < start + heroSpan; column++) {
            covered = math.max(covered, columnHeights[column]);
          }
          if (covered < bestHeight) {
            bestHeight = covered;
            starts
              ..clear()
              ..add(start);
          } else if (covered == bestHeight) {
            starts.add(start);
          }
        }
        final target = starts.isEmpty
            ? 0
            : starts[heroTieCursor % starts.length];
        heroTieCursor++;
        y = bestHeight;
        x =
            horizontalMargin +
            target * (columnWidth + gap) +
            math.max((heroSpanWidth - blockWidth) * .5, 0);
        for (var column = target; column < target + heroSpan; column++) {
          columnHeights[column] = y + blockHeight + blockGap;
        }
      }
    } else {
      final minimum = columnHeights.reduce(math.min);
      final candidates = <int>[];
      for (var column = 0; column < columns; column++) {
        if (columnHeights[column] == minimum) candidates.add(column);
      }
      final target = candidates[bodyTieCursor % candidates.length];
      bodyTieCursor++;
      x = horizontalMargin + target * (columnWidth + gap);
      y = columnHeights[target];
      columnHeights[target] = y + blockHeight + blockGap;
    }

    if (render) {
      final graphemes = splitDefaultGraphemes(entry.line.fullText);
      blocks.add(
        DefaultBlock(
          id: 'default-${entry.line.startTime}-${entry.index}',
          sourceLineIndex: entry.index,
          line: entry.line,
          variant: variant,
          rect: Rect.fromLTWH(x, y, blockWidth, blockHeight),
          fontPx: fitted.fontPx,
          lineHeight: lineHeight,
          graphemes: graphemes,
          glyphOffsets: _glyphOffsets(graphemes, fitted.fontPx, variant),
          wordRanges: _wordRanges(entry.line, graphemes),
        ),
      );
    }
  }

  final articleHeight = columnHeights.reduce(math.max) + verticalMargin;
  if (!render) return _Attempt(height: articleHeight, article: null);
  final chronological = [...blocks]
    ..sort(
      (left, right) => left.sourceLineIndex.compareTo(right.sourceLineIndex),
    );
  return _Attempt(
    height: articleHeight,
    article: DefaultArticleLayout(
      width: paperWidth + horizontalMargin * 2,
      height: articleHeight,
      viewportHeight: math.max(viewport.height, 240),
      columns: columns,
      gap: gap,
      paperBounds: Rect.fromLTRB(
        horizontalMargin,
        verticalMargin,
        horizontalMargin + paperWidth,
        math.max(articleHeight - verticalMargin, verticalMargin),
      ),
      blocks: blocks,
      blockBySourceLineIndex: {
        for (final block in chronological) block.sourceLineIndex: block,
      },
      chronologicalBlocks: chronological,
      firstRenderableStartTime: chronological.isEmpty
          ? double.infinity
          : chronological.first.line.startTime,
      lastChronologicalRenderEndTime: chronological.isEmpty
          ? double.negativeInfinity
          : chronological.last.line.endTime,
    ),
  );
}

/// Port of default-canvas-article.ts/buildArticleLayout.
DefaultArticleLayout? buildDefaultArticleLayout(
  List<DefaultLine> lines,
  Size viewport,
) {
  if (viewport.width <= 0 || viewport.height <= 0 || lines.isEmpty) return null;
  final paperWidth = defaultClamp(
    math.max(viewport.width * 1.95, viewport.width + 520),
    920,
    2400,
  );
  final maxColumns = paperWidth >= 1120
      ? 4
      : paperWidth >= 760
      ? 3
      : paperWidth >= 500
      ? 2
      : 1;
  final targetHeight = math.max(viewport.height, 240) * 2.45;
  var bestScore = double.infinity;
  var bestColumns = maxColumns;
  var bestGap = 6.0;
  var bestDensity = 1.0;

  for (var columns = maxColumns; columns >= 1; columns--) {
    var low = .82;
    var high = 1.42;
    final gap = defaultClamp(
      (paperWidth *
              (columns >= 4
                  ? .0065
                  : columns == 3
                  ? .0085
                  : .0115))
          .round(),
      6,
      14,
    );
    for (var iteration = 0; iteration < 8; iteration++) {
      final density = (low + high) / 2;
      final attempt = _buildAttempt(
        lines: lines,
        viewport: viewport,
        paperWidth: paperWidth,
        columns: columns,
        gap: gap,
        densityScale: density,
        seedKey: 'Super Cyrene:$columns:$paperWidth',
        render: false,
      );
      final coveragePenalty = (attempt.height - targetHeight).abs();
      final overflowPenalty = attempt.height < targetHeight
          ? 0
          : (attempt.height - targetHeight) * .14;
      final score = coveragePenalty + overflowPenalty;
      if (score < bestScore) {
        bestScore = score;
        bestColumns = columns;
        bestGap = gap;
        bestDensity = density;
      }
      if (attempt.height < targetHeight) {
        low = density;
      } else {
        high = density;
      }
    }
  }
  return _buildAttempt(
    lines: lines,
    viewport: viewport,
    paperWidth: paperWidth,
    columns: bestColumns,
    gap: bestGap,
    densityScale: bestDensity,
    seedKey: 'Super Cyrene:$bestColumns:$paperWidth',
    render: true,
  ).article;
}
