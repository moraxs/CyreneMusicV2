import 'dart:ui';

enum DefaultBlockVariant { body, hero }

class DefaultWord {
  const DefaultWord({
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  final String text;
  final double startTime;
  final double endTime;
}

class DefaultLine {
  const DefaultLine({
    required this.id,
    required this.fullText,
    required this.startTime,
    required this.endTime,
    required this.words,
    this.translation,
    this.isChorus = false,
  });

  final String id;
  final String fullText;
  final double startTime;
  final double endTime;
  final List<DefaultWord> words;
  final String? translation;
  final bool isChorus;
}

class DefaultWordRange {
  const DefaultWordRange({
    required this.word,
    required this.start,
    required this.end,
  });

  final DefaultWord word;
  final int start;
  final int end;
}

class DefaultBlock {
  const DefaultBlock({
    required this.id,
    required this.sourceLineIndex,
    required this.line,
    required this.variant,
    required this.rect,
    required this.fontPx,
    required this.lineHeight,
    required this.graphemes,
    required this.glyphOffsets,
    required this.wordRanges,
  });

  final String id;
  final int sourceLineIndex;
  final DefaultLine line;
  final DefaultBlockVariant variant;
  final Rect rect;
  final double fontPx;
  final double lineHeight;
  final List<String> graphemes;
  final List<double> glyphOffsets;
  final List<DefaultWordRange> wordRanges;

  double get textWidth => glyphOffsets.isEmpty ? 0 : glyphOffsets.last;
}

class DefaultArticleLayout {
  const DefaultArticleLayout({
    required this.width,
    required this.height,
    required this.viewportHeight,
    required this.columns,
    required this.gap,
    required this.paperBounds,
    required this.blocks,
    required this.blockBySourceLineIndex,
    required this.chronologicalBlocks,
    required this.firstRenderableStartTime,
    required this.lastChronologicalRenderEndTime,
  });

  final double width;
  final double height;
  final double viewportHeight;
  final int columns;
  final double gap;
  final Rect paperBounds;
  final List<DefaultBlock> blocks;
  final Map<int, DefaultBlock> blockBySourceLineIndex;
  final List<DefaultBlock> chronologicalBlocks;
  final double firstRenderableStartTime;
  final double lastChronologicalRenderEndTime;
}

class DefaultCamera {
  DefaultCamera({
    required this.x,
    required this.y,
    this.velocityX = 0,
    this.velocityY = 0,
    double? focusX,
    double? focusY,
    this.scale = 1.18,
    this.velocityScale = 0,
    double? focusScale,
  }) : focusX = focusX ?? x,
       focusY = focusY ?? y,
       focusScale = focusScale ?? scale;

  double x;
  double y;
  double velocityX;
  double velocityY;
  double focusX;
  double focusY;
  double scale;
  double velocityScale;
  double focusScale;
}

const defaultCameraScaleMin = .22;
const defaultCameraScaleMax = 2.24;

double defaultClamp(num value, num minimum, num maximum) =>
    value.clamp(minimum, maximum).toDouble();

double defaultMix(double from, double to, double amount) =>
    from + (to - from) * amount;

double defaultEaseOutCubic(double value) =>
    1 -
    (1 - defaultClamp(value, 0, 1)) *
        (1 - defaultClamp(value, 0, 1)) *
        (1 - defaultClamp(value, 0, 1));

double defaultEaseInCubic(double value) {
  final normalized = defaultClamp(value, 0, 1);
  return normalized * normalized * normalized;
}

double defaultEaseInOutCubic(double value) {
  final normalized = defaultClamp(value, 0, 1);
  return normalized < .5
      ? 4 * normalized * normalized * normalized
      : 1 -
            ((-2 * normalized + 2) *
                    (-2 * normalized + 2) *
                    (-2 * normalized + 2)) /
                2;
}
