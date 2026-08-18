import 'dart:math' as math;
import 'dart:ui';

import 'sonnet_types.dart';

bool isSonnetEmphasisRole(SonnetSegmentRole role) =>
    role == SonnetSegmentRole.hero || role == SonnetSegmentRole.semiHero;

FontWeight resolveSonnetRoleFontWeight(
  FontWeight? configuredFontWeight,
  SonnetSegmentRole role,
) {
  if (configuredFontWeight != null) return configuredFontWeight;
  if (isSonnetEmphasisRole(role)) return FontWeight.w900;
  return role == SonnetSegmentRole.decoration
      ? FontWeight.w300
      : FontWeight.w700;
}

int getSonnetVisibleSegmentLength(SonnetSemanticSegment segment) {
  return segment.graphemes
      .where((item) => item.char.trim().isNotEmpty)
      .length;
}

double scoreSonnetHeroSegment(SonnetSemanticSegment segment) {
  final lengthScore =
      math.min(getSonnetVisibleSegmentLength(segment), 8) * 14.0;
  final durationScore =
      math.min(2.5, math.max(0.0, segment.endTime - segment.startTime)) * 18.0;
  return lengthScore + durationScore;
}

int findSonnetHeroSegmentIndex(List<SonnetSemanticSegment> segments) {
  var bestIndex = segments.indexWhere((segment) => segment.isWordLike);
  var bestScore = -double.infinity;

  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    if (!segment.isWordLike || getSonnetVisibleSegmentLength(segment) == 0) {
      continue;
    }
    final score = scoreSonnetHeroSegment(segment);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }
  return math.max(0, bestIndex);
}

const _kSemiHeroMinGap = 2;
const _kSemiHeroMinVisibleLength = 2;
const _kSemiHeroMinLineWords = 4;
const _kSemiHeroScoreRatio = 0.35;
const _kSemiHeroMultiWordCount = 9;

List<int> findSonnetSemiHeroSegmentIndices(
  List<SonnetSemanticSegment> segments,
  int heroIndex,
) {
  if (heroIndex < 0 || heroIndex >= segments.length) return const [];
  final hero = segments[heroIndex];
  final wordLikeCount = segments
      .where((segment) =>
          segment.isWordLike && getSonnetVisibleSegmentLength(segment) > 0)
      .length;
  if (wordLikeCount < _kSemiHeroMinLineWords) return const [];

  final threshold = scoreSonnetHeroSegment(hero) * _kSemiHeroScoreRatio;
  final candidates = <({SonnetSemanticSegment segment, int index})>[];

  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    if (index != heroIndex &&
        segment.isWordLike &&
        getSonnetVisibleSegmentLength(segment) >= _kSemiHeroMinVisibleLength &&
        (index - heroIndex).abs() >= _kSemiHeroMinGap &&
        scoreSonnetHeroSegment(segment) >= threshold) {
      candidates.add((segment: segment, index: index));
    }
  }

  if (candidates.isEmpty) return const [];

  ({SonnetSemanticSegment segment, int index})? bestOf(
    List<({SonnetSemanticSegment segment, int index})> list,
  ) {
    if (list.isEmpty) return null;
    return list.reduce((best, item) =>
        scoreSonnetHeroSegment(item.segment) > scoreSonnetHeroSegment(best.segment)
            ? item
            : best);
  }

  final heroLeansEarly = heroIndex <= (segments.length - 1) / 2;
  final primarySide = candidates
      .where((item) =>
          heroLeansEarly ? item.index > heroIndex : item.index < heroIndex)
      .toList();
  final secondarySide = candidates
      .where((item) =>
          heroLeansEarly ? item.index < heroIndex : item.index > heroIndex)
      .toList();

  final picks = <int>[];
  final primary = bestOf(primarySide) ?? bestOf(secondarySide);
  if (primary != null) picks.add(primary.index);

  if (wordLikeCount >= _kSemiHeroMultiWordCount && primary != null) {
    final secondaryCandidates = secondarySide
        .where((item) => (item.index - primary.index).abs() >= _kSemiHeroMinGap)
        .toList();
    final secondary = bestOf(secondaryCandidates);
    if (secondary != null) picks.add(secondary.index);
  }

  picks.sort();
  return picks;
}

int findSonnetSemiHeroSegmentIndex(
  List<SonnetSemanticSegment> segments,
  int heroIndex,
) {
  final list = findSonnetSemiHeroSegmentIndices(segments, heroIndex);
  return list.isNotEmpty ? list.first : -1;
}
