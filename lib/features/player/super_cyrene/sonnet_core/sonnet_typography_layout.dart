import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_poster_blocks_layout.dart';
import 'sonnet_random.dart';
import 'sonnet_shot_flow_layouts.dart';
import 'sonnet_types.dart';
import 'sonnet_typography_roles.dart';

class SonnetTypographyPlacement {
  SonnetTypographyPlacement({
    required this.segmentIndex,
    required this.displayText,
    required this.role,
    required this.fontScale,
    required this.measuredWidth,
    required this.measuredHeight,
    required this.x,
    required this.y,
    required this.rotation,
    required this.enterX,
    required this.enterY,
    required this.vertical,
    required this.layoutDirection,
    required this.timingPhase,
  });

  final int segmentIndex;
  String displayText;
  SonnetSegmentRole role;
  double fontScale;
  double measuredWidth;
  double measuredHeight;
  double x;
  double y;
  double rotation;
  double enterX;
  double enterY;
  bool vertical;
  String layoutDirection;
  double timingPhase;
}

class SonnetTypographyLayoutOptions {
  SonnetTypographyLayoutOptions({
    required this.lines,
    required this.shotKind,
    required this.paragraphKind,
    required this.width,
    required this.height,
    required this.baseFontSize,
    this.fontFamily,
    this.fontWeight,
  });

  final List<List<SonnetSemanticSegment>> lines;
  final SonnetShotKind shotKind;
  final SonnetParagraphKind paragraphKind;
  final double width;
  final double height;
  final double baseFontSize;
  final String? fontFamily;
  final FontWeight? fontWeight;
}

bool isSonnetLayoutSegment(SonnetSemanticSegment segment) =>
    segment.text.trim().isNotEmpty;

final _cjkTextRegex = RegExp(
  r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]',
  unicode: true,
);

bool _shouldRotateNonCjkSegment(
  SonnetSemanticSegment segment,
  bool vertical,
) {
  return vertical &&
      segment.graphemes.where((item) => item.char.trim().isNotEmpty).length >
          1 &&
      !_cjkTextRegex.hasMatch(segment.text);
}

String _verticalText(SonnetSemanticSegment segment) {
  final chars = segment.graphemes.isNotEmpty
      ? segment.graphemes.map((item) => item.char)
      : segment.text.characters;
  return chars.join('\n');
}

final Map<String, double> _measureCache = {};

double measureText(
  String text,
  String? fontFamily,
  FontWeight fontWeight,
  double fontSize,
) {
  if (text.isEmpty) return fontSize * 0.6;
  final cacheKey = '$text|$fontFamily|${fontWeight.value}|$fontSize';
  final cached = _measureCache[cacheKey];
  if (cached != null) return cached;

  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: fontFamily,
        fontWeight: fontWeight,
        fontSize: fontSize,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final width = tp.width;
  tp.dispose();
  if (_measureCache.length > 2000) _measureCache.clear();
  _measureCache[cacheKey] = width;
  return width;
}

List<SonnetTypographyPlacement> resolveSonnetTypographyLayout(
  SonnetTypographyLayoutOptions options,
) {
  final lines = options.lines;
  final shotKind = options.shotKind;
  final width = options.width;
  final height = options.height;
  final baseFontSize = options.baseFontSize;
  final fontFamily = options.fontFamily;
  final fontWeight = options.fontWeight;

  final segments = lines.expand((l) => l).toList();
  if (segments.isEmpty) return const [];

  var offset = 0;
  final heroIndices = <int>[];
  final semiHeroIndices = <int>[];

  for (final lineSegs in lines) {
    final localHero = findSonnetHeroSegmentIndex(lineSegs);
    final globalHero = offset + localHero;
    final localSemiHeroes =
        findSonnetSemiHeroSegmentIndices(lineSegs, localHero);
    heroIndices.add(globalHero);
    for (final localSemiHero in localSemiHeroes) {
      semiHeroIndices.add(offset + localSemiHero);
    }
    offset += lineSegs.length;
  }

  final heroIndex = findSonnetHeroSegmentIndex(segments);
  final midpoints = segments
      .map((segment) => (segment.startTime + segment.endTime) / 2)
      .toList();
  final timelineStart = midpoints.reduce(math.min);
  final timelineEnd = midpoints.reduce(math.max);
  final timelineDuration = timelineEnd - timelineStart;

  final phases = List.generate(segments.length, (index) {
    final midpoint = midpoints[index];
    return timelineDuration > 0.001
        ? (midpoint - timelineStart) / timelineDuration
        : index / math.max(1, segments.length - 1);
  });
  final heroPhase = heroIndex < phases.length ? phases[heroIndex] : 0.5;

  final layoutVariantSeed = segments.fold<int>(
        0,
        (acc, seg) =>
            acc + (seg.text.trim().isNotEmpty ? seg.text.trim().length : 1),
      ) +
      segments.length;
  final posterLayoutSeed =
      hashSonnetSeed(segments.map((s) => s.text).join('\u241f'));

  var editorialVariant = layoutVariantSeed % 5;
  final ribbonVariant = layoutVariantSeed % 3;
  final tableauVariant = layoutVariantSeed % 4;
  final collageVariant = layoutVariantSeed % 3;

  var secondaryHeroIndex = -1;
  if (editorialVariant == 3 && segments.length > 2) {
    var bestScore = -double.infinity;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (index == heroIndex ||
          !segment.isWordLike ||
          getSonnetVisibleSegmentLength(segment) == 0) {
        continue;
      }
      final distanceBonus = (index - heroIndex).abs() > 1 ? 50.0 : 0.0;
      final score = scoreSonnetHeroSegment(segment) + distanceBonus;
      if (score > bestScore) {
        bestScore = score;
        secondaryHeroIndex = index;
      }
    }
    if (secondaryHeroIndex == -1) editorialVariant = 0;
  } else if (editorialVariant == 3) {
    editorialVariant = 0;
  } else if (editorialVariant == 4 && segments.length < 2) {
    editorialVariant = 2;
  }

  final boxes = List.generate(segments.length, (index) {
    final segment = segments[index];
    final isHero = heroIndices.contains(index) ||
        (index == secondaryHeroIndex &&
            shotKind == SonnetShotKind.editorialColumn &&
            editorialVariant == 3);
    final isSemiHero = semiHeroIndices.contains(index) && !isHero;
    final isEmphasized = isHero || isSemiHero;

    var heroFontScale = 1.0;
    var supportFontScale = 1.0;
    var vertical = false;
    var rotation = 0.0;

    switch (shotKind) {
      case SonnetShotKind.editorialColumn:
        if (editorialVariant == 3) {
          heroFontScale = 3.8;
          supportFontScale = 1.3;
          vertical = false;
        } else if (editorialVariant == 4) {
          heroFontScale = 4.2;
          supportFontScale = 1.25;
          vertical = isEmphasized;
        } else {
          heroFontScale = editorialVariant == 2 ? 3.2 : 4.0;
          supportFontScale = 1.2;
          vertical = isEmphasized && editorialVariant != 2;
        }
      case SonnetShotKind.typeImpact:
        heroFontScale = 5.5;
        supportFontScale = 1.5;
      case SonnetShotKind.fragmentCollage:
        heroFontScale = 3.2;
        supportFontScale = 1.35;
        vertical = isSemiHero || (index % 4) == 0;
      case SonnetShotKind.trackingRibbon:
        heroFontScale = 3.5;
        supportFontScale = 1.5;
      case SonnetShotKind.maskReveal:
        heroFontScale = 4.5;
        supportFontScale = 1.6;
        vertical = isEmphasized;
      case SonnetShotKind.posterBlocks:
        heroFontScale = 4.4;
        supportFontScale = 1.15;
      case SonnetShotKind.quietTableau:
        heroFontScale = 3.0;
        supportFontScale = 1.15;
        vertical = isEmphasized && (tableauVariant == 0 || tableauVariant == 1);
    }

    var fontScale = isHero
        ? heroFontScale
        : (isSemiHero
            ? math.max(supportFontScale * 1.35, heroFontScale * 0.72)
            : supportFontScale);

    final rotatesNonCjkSegment =
        _shouldRotateNonCjkSegment(segment, vertical);
    if (rotatesNonCjkSegment) {
      vertical = false;
      rotation += math.pi / 2;
    }

    final displayText = vertical ? _verticalText(segment) : segment.text;
    final renderRole = isHero
        ? SonnetSegmentRole.hero
        : (isSemiHero ? SonnetSegmentRole.semiHero : SonnetSegmentRole.support);
    final renderWeight =
        resolveSonnetRoleFontWeight(fontWeight, renderRole);

    var targetFontSize = baseFontSize * fontScale;

    final horizontalAdvance = rotatesNonCjkSegment
        ? segment.graphemes.fold<double>(0.0, (sum, item) {
            return item.char.trim().isNotEmpty
                ? sum +
                    math.max(
                      targetFontSize * 0.2,
                      measureText(
                        item.char,
                        fontFamily,
                        renderWeight,
                        targetFontSize,
                      ),
                    )
                : sum;
          })
        : measureText(
            displayText,
            fontFamily,
            renderWeight,
            targetFontSize,
          );

    var measuredWidth =
        rotatesNonCjkSegment ? targetFontSize * 1.2 : horizontalAdvance;
    var measuredHeight =
        rotatesNonCjkSegment ? horizontalAdvance : targetFontSize * 1.2;

    if (vertical) {
      final columnChars = segment.graphemes.isNotEmpty
          ? segment.graphemes.map((item) => item.char).toList()
          : segment.text.characters.toList();
      final glyphAdvances = columnChars
          .where((char) => char.trim().isNotEmpty)
          .map((char) => math.max(
                targetFontSize * 0.2,
                measureText(char, fontFamily, renderWeight, targetFontSize),
              ))
          .toList();
      measuredWidth = glyphAdvances.isNotEmpty
          ? glyphAdvances.reduce(math.max)
          : targetFontSize;
      measuredHeight =
          math.max(1, columnChars.length) * targetFontSize * 0.9;
    }

    final maxW = width * 0.82;
    final maxH = height * 0.82;
    var fitScale = 1.0;
    if (measuredWidth > maxW) fitScale = math.min(fitScale, maxW / measuredWidth);
    if (measuredHeight > maxH) {
      fitScale = math.min(fitScale, maxH / measuredHeight);
    }

    if (fitScale < 1.0) {
      targetFontSize *= fitScale;
      fontScale *= fitScale;
      measuredWidth *= fitScale;
      measuredHeight *= fitScale;
    }

    String? posterVerticalDisplayText;
    double? posterVerticalMeasuredWidth;
    double? posterVerticalMeasuredHeight;
    double? posterVerticalFontScale;

    if (shotKind == SonnetShotKind.posterBlocks &&
        _cjkTextRegex.hasMatch(segment.text)) {
      final columnChars = segment.graphemes.isNotEmpty
          ? segment.graphemes.map((item) => item.char).toList()
          : segment.text.characters.toList();
      final glyphAdvances = columnChars
          .where((char) => char.trim().isNotEmpty)
          .map((char) => math.max(
                targetFontSize * 0.2,
                measureText(char, fontFamily, renderWeight, targetFontSize),
              ))
          .toList();
      var columnWidth = glyphAdvances.isNotEmpty
          ? glyphAdvances.reduce(math.max)
          : targetFontSize;
      var columnHeight =
          math.max(1, columnChars.length) * targetFontSize * 0.9;
      final verticalFit =
          math.min(1.0, math.min(maxW / columnWidth, maxH / columnHeight));
      columnWidth *= verticalFit;
      columnHeight *= verticalFit;
      posterVerticalDisplayText = _verticalText(segment);
      posterVerticalMeasuredWidth = columnWidth;
      posterVerticalMeasuredHeight = columnHeight;
      posterVerticalFontScale = fontScale * verticalFit;
    }

    return SonnetPosterBlockBox(
      index: index,
      isHero: isHero,
      isSemiHero: isSemiHero,
      displayText: displayText,
      verticalDisplayText: posterVerticalDisplayText,
      verticalMeasuredWidth: posterVerticalMeasuredWidth,
      verticalMeasuredHeight: posterVerticalMeasuredHeight,
      verticalFontScale: posterVerticalFontScale,
      fontScale: fontScale,
      vertical: vertical,
      layoutDirection: 'horizontal',
      rotation: rotation,
      measuredWidth: measuredWidth,
      measuredHeight: measuredHeight,
      timingPhase: phases[index],
      relativePhase: phases[index] - heroPhase,
      role: renderRole,
      x: 0.0,
      y: 0.0,
      enterX: 0.0,
      enterY: 0.0,
    );
  });

  final heroBox = heroIndex < boxes.length ? boxes[heroIndex] : null;
  if (heroBox != null) {
    if (shotKind == SonnetShotKind.posterBlocks) {
      layoutSonnetPosterBlocks(
        boxes,
        width,
        height,
        baseFontSize,
        posterLayoutSeed,
      );
    } else {
      final gaps = resolveSonnetFlowGaps(baseFontSize);
      final flowCtx = SonnetFlowLayoutContext(
        boxes: boxes,
        heroIndex: heroIndex,
        width: width,
        height: height,
        flowGap: gaps.flowGap,
        stackGap: gaps.stackGap,
      );
      if (shotKind == SonnetShotKind.quietTableau) {
        layoutQuietTableau(flowCtx, tableauVariant);
      } else if (shotKind == SonnetShotKind.trackingRibbon) {
        layoutTrackingRibbon(flowCtx, ribbonVariant);
      } else if (shotKind == SonnetShotKind.editorialColumn) {
        layoutEditorialColumn(flowCtx, editorialVariant, secondaryHeroIndex);
      } else if (shotKind == SonnetShotKind.fragmentCollage) {
        layoutFragmentCollage(flowCtx, collageVariant);
      } else {
        layoutCrossStack(flowCtx);
      }
    }

    heroBox.enterX = 0.0;
    heroBox.enterY = height * 0.15;

    final decorations = <SonnetPosterBlockBox>[];
    if (shotKind != SonnetShotKind.quietTableau &&
        shotKind != SonnetShotKind.posterBlocks) {
      final allHeroes = boxes.where((b) => b.isHero).toList();
      for (var idx = 0; idx < allHeroes.length; idx++) {
        final hBox = allHeroes[idx];
        decorations.add(SonnetPosterBlockBox(
          index: hBox.index,
          isHero: false,
          isSemiHero: false,
          displayText: hBox.displayText,
          role: SonnetSegmentRole.decoration,
          fontScale:
              math.max(2.8, math.min(hBox.fontScale * 3.5, 5.5)),
          vertical: false,
          measuredWidth: hBox.measuredWidth,
          measuredHeight: hBox.measuredHeight,
          x: hBox.x - width * (0.1 - idx * 0.03),
          y: hBox.y - height * (0.05 - idx * 0.02),
          rotation: -0.15 + (idx % 2 == 0 ? 0.0 : 0.05),
          enterX: -width * 0.05,
          enterY: -height * 0.05,
        ));
      }
      if (boxes.length > 1 && allHeroes.isNotEmpty) {
        final dec2 = boxes.last.isHero ? boxes.first : boxes.last;
        decorations.add(SonnetPosterBlockBox(
          index: dec2.index,
          isHero: false,
          isSemiHero: false,
          displayText: dec2.displayText,
          role: SonnetSegmentRole.decoration,
          fontScale: math.max(
            1.8,
            math.min(allHeroes.first.fontScale * 2.2, 3.5),
          ),
          vertical: false,
          measuredWidth: dec2.measuredWidth,
          measuredHeight: dec2.measuredHeight,
          x: allHeroes.first.x + width * 0.25,
          y: allHeroes.first.y + height * 0.15,
          rotation: 0.08,
          enterX: width * 0.05,
          enterY: height * 0.05,
        ));
      }
    }

    boxes.insertAll(0, decorations);
  }

  return boxes.map((box) {
    final SonnetSegmentRole assignedRole = box.role is SonnetSegmentRole
        ? (box.role as SonnetSegmentRole)
        : (box.isHero
            ? SonnetSegmentRole.hero
            : (box.isSemiHero
                ? SonnetSegmentRole.semiHero
                : SonnetSegmentRole.support));

    return SonnetTypographyPlacement(
      segmentIndex: box.index,
      displayText: box.displayText,
      role: assignedRole,
      fontScale: box.fontScale,
      measuredWidth: box.measuredWidth,
      measuredHeight: box.measuredHeight,
      x: box.x,
      y: box.y,
      rotation: box.rotation,
      enterX: box.enterX,
      enterY: box.enterY,
      vertical: box.vertical,
      layoutDirection: box.layoutDirection,
      timingPhase: box.timingPhase,
    );
  }).toList();
}
