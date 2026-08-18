import '../../mobile/compat/lyric_line.dart';

/// Segment role classifications for typography rendering.
enum SonnetSegmentRole { hero, semiHero, support, decoration }

/// Paragraph mood and tempo classification.
enum SonnetParagraphKind { breath, verse, lift, chorus, sectionBreak, outro }

/// Boundary trigger reasons for paragraphs.
enum SonnetParagraphBoundary {
  songStart,
  timeGap,
  metadata,
  durationCap,
  lineCap,
}

/// Available kinetic shot templates.
enum SonnetShotKind {
  editorialColumn,
  typeImpact,
  fragmentCollage,
  trackingRibbon,
  maskReveal,
  posterBlocks,
  quietTableau,
}

/// Transition effect variants.
enum SonnetTransitionKind { fastBlur, monoGlitch, cameraPull }

/// Animation cue kinds for semantic segments.
enum SonnetCueKind { enter, hold, exit, accent }

/// Precise grapheme timing structure.
class GraphemeTiming {
  const GraphemeTiming({
    required this.char,
    required this.startTime,
    required this.endTime,
    this.wordIndex,
  });

  final String char;
  final double startTime; // seconds
  final double endTime; // seconds
  final int? wordIndex;
}

/// A semantic segment of a lyric line with word-boundary and grapheme info.
class SonnetSemanticSegment {
  SonnetSemanticSegment({
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.startTime,
    required this.endTime,
    required this.wordIndices,
    required this.graphemes,
    required this.isWordLike,
  });

  String text;
  int startOffset;
  int endOffset;
  double startTime; // seconds
  double endTime; // seconds
  List<int> wordIndices;
  List<GraphemeTiming> graphemes;
  bool isWordLike;
}

/// A compiled lyric line with semantic segments and render end time.
class SonnetCompiledLine {
  const SonnetCompiledLine({
    required this.sourceIndex,
    required this.line,
    required this.renderEndTime,
    required this.segments,
  });

  final int sourceIndex;
  final LyricLine line;
  final double renderEndTime; // seconds
  final List<SonnetSemanticSegment> segments;
}

/// Animation cue for timing individual segments.
class SonnetAnimationCue {
  const SonnetAnimationCue({
    required this.at,
    required this.duration,
    required this.kind,
    required this.segmentStart,
    required this.segmentEnd,
  });

  final double at; // seconds
  final double duration; // seconds
  final SonnetCueKind kind;
  final int segmentStart;
  final int segmentEnd;
}

/// Camera target orientation for a shot.
class SonnetCameraTarget {
  const SonnetCameraTarget({
    required this.x,
    required this.y,
    required this.zoom,
    required this.rotation,
  });

  final double x;
  final double y;
  final double zoom;
  final double rotation;
}

/// A kinetic shot representing a group of lines and an active camera path.
class SonnetShot {
  const SonnetShot({
    required this.id,
    required this.kind,
    required this.startTime,
    required this.endTime,
    required this.lineIndices,
    required this.cues,
    required this.camera,
  });

  final String id;
  final SonnetShotKind kind;
  final double startTime; // seconds
  final double endTime; // seconds
  final List<int> lineIndices;
  final List<SonnetAnimationCue> cues;
  final SonnetCameraTarget camera;
}

/// A transition between paragraphs.
class SonnetTransition {
  const SonnetTransition({
    required this.kind,
    required this.startTime,
    required this.endTime,
  });

  final SonnetTransitionKind kind;
  final double startTime; // seconds
  final double endTime; // seconds
}

/// A paragraph group containing compiled lines, shots, and transition out.
class SonnetParagraph {
  const SonnetParagraph({
    required this.id,
    required this.kind,
    required this.boundary,
    required this.startTime,
    required this.endTime,
    required this.lines,
    required this.shots,
    required this.transitionOut,
  });

  final String id;
  final SonnetParagraphKind kind;
  final SonnetParagraphBoundary boundary;
  final double startTime; // seconds
  final double endTime; // seconds
  final List<SonnetCompiledLine> lines;
  final List<SonnetShot> shots;
  final SonnetTransition? transitionOut;
}

/// Compiled deterministic Sonnet program for the entire song.
class SonnetProgram {
  const SonnetProgram({
    required this.seed,
    required this.paragraphGapThreshold,
    required this.paragraphs,
  });

  final String seed;
  final double paragraphGapThreshold;
  final List<SonnetParagraph> paragraphs;

  static const empty = SonnetProgram(
    seed: 'sonnet',
    paragraphGapThreshold: 2.0,
    paragraphs: [],
  );
}
