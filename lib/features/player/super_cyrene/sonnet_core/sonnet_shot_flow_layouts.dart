import 'dart:math' as math;

import 'sonnet_poster_blocks_layout.dart';

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

({double flowGap, double stackGap}) resolveSonnetFlowGaps(double baseFontSize) {
  final flowGap = (baseFontSize * 0.35).clamp(16.0, 40.0);
  return (flowGap: flowGap, stackGap: math.max(24.0, flowGap * 1.35));
}

class SonnetFlowLayoutContext {
  SonnetFlowLayoutContext({
    required this.boxes,
    required this.heroIndex,
    required this.width,
    required this.height,
    required this.flowGap,
    required this.stackGap,
  });

  final List<SonnetPosterBlockBox> boxes;
  final int heroIndex;
  final double width;
  final double height;
  final double flowGap;
  final double stackGap;
}

void placeWithGlobalFit(
  SonnetFlowLayoutContext ctx,
  void Function(double globalScale) place,
) {
  final snapshot = ctx.boxes
      .map((box) => (
            fontScale: box.fontScale,
            measuredWidth: box.measuredWidth,
            measuredHeight: box.measuredHeight,
          ))
      .toList();
  final safeHalfW = ctx.width * 0.48;
  final safeHalfH = ctx.height * 0.46;

  for (final globalScale in [1.0, 0.92, 0.84, 0.76, 0.68, 0.6, 0.52]) {
    for (var index = 0; index < ctx.boxes.length; index++) {
      final box = ctx.boxes[index];
      box.fontScale = snapshot[index].fontScale * globalScale;
      box.measuredWidth = snapshot[index].measuredWidth * globalScale;
      box.measuredHeight = snapshot[index].measuredHeight * globalScale;
    }
    place(globalScale);
    final fits = ctx.boxes.every((box) =>
        box.x.abs() + box.measuredWidth / 2 <= safeHalfW + 0.5 &&
        box.y.abs() + box.measuredHeight / 2 <= safeHalfH + 0.5);
    if (fits) return;
  }
}

void layoutQuietTableau(SonnetFlowLayoutContext ctx, int variant) {
  final boxes = ctx.boxes;
  final heroIndex = ctx.heroIndex;
  final height = ctx.height;
  final stackGap = ctx.stackGap;
  final heroBox = boxes[heroIndex];
  final horizontalCard = variant == 2 || variant == 3;

  for (final box in boxes) {
    box.layoutDirection = horizontalCard ? 'horizontal' : 'vertical';
  }
  final safeHalfH = height * 0.46;

  placeWithGlobalFit(ctx, (globalScale) {
    heroBox.x = 0.0;
    heroBox.y = horizontalCard ? 0.0 : -height * 0.1;
    final stagger = variant == 3 ? 70.0 : 0.0;
    final maxW = boxes.map((box) => box.measuredWidth).reduce(math.max);
    final columnStep = maxW + stackGap + stagger;

    double xFor(SonnetPosterBlockBox box, int index) {
      if (variant == 1) {
        return heroBox.x - heroBox.measuredWidth / 2 + box.measuredWidth / 2;
      }
      if (variant == 3) {
        return heroBox.x + ((index % 2 == 0) ? 1.0 : -1.0) * 35.0;
      }
      return heroBox.x;
    }

    var column = 0;
    var currentY = heroBox.y - heroBox.measuredHeight / 2 - stackGap;
    for (var i = heroIndex - 1; i >= 0; i--) {
      final box = boxes[i];
      if (currentY - box.measuredHeight < -safeHalfH) {
        column += 1;
        currentY = safeHalfH;
      }
      box.x = xFor(box, i) + column * columnStep;
      box.y = currentY - box.measuredHeight / 2;
      currentY -= box.measuredHeight + stackGap;
      if (variant == 1) {
        box.enterX = 20.0;
        box.enterY = 0.0;
      } else if (variant == 3) {
        box.enterX = box.x > heroBox.x ? 30.0 : -30.0;
        box.enterY = 0.0;
      } else {
        box.enterX = 0.0;
        box.enterY = 20.0;
      }
    }

    column = 0;
    currentY = heroBox.y + heroBox.measuredHeight / 2 + stackGap;
    for (var i = heroIndex + 1; i < boxes.length; i++) {
      final box = boxes[i];
      if (currentY + box.measuredHeight > safeHalfH) {
        column += 1;
        currentY = -safeHalfH;
      }
      box.x = xFor(box, i) - column * columnStep;
      box.y = currentY + box.measuredHeight / 2;
      currentY += box.measuredHeight + stackGap;
      if (variant == 1) {
        box.enterX = -20.0;
        box.enterY = 0.0;
      } else if (variant == 3) {
        box.enterX = box.x > heroBox.x ? 30.0 : -30.0;
        box.enterY = 0.0;
      } else {
        box.enterX = 0.0;
        box.enterY = -20.0;
      }
    }
  });
}

void layoutTrackingRibbon(SonnetFlowLayoutContext ctx, int variant) {
  final boxes = ctx.boxes;
  final heroIndex = ctx.heroIndex;
  final flowGap = ctx.flowGap;
  final heroBox = boxes[heroIndex];

  for (final box in boxes) {
    box.layoutDirection = 'horizontal';
  }

  placeWithGlobalFit(ctx, (globalScale) {
    heroBox.x = 0.0;
    heroBox.y = 0.0;

    double alignY(SonnetPosterBlockBox box, int index) => variant == 1
        ? heroBox.y + heroBox.measuredHeight / 2 - box.measuredHeight / 2
        : (variant == 2
            ? heroBox.y - heroBox.measuredHeight / 2 + box.measuredHeight / 2
            : heroBox.y + (index % 2 == 0 ? 10.0 : -10.0));

    final enter = variant == 2 ? 20.0 : 30.0;
    var currentX = heroBox.x - heroBox.measuredWidth / 2 - flowGap;
    for (var i = heroIndex - 1; i >= 0; i--) {
      final box = boxes[i];
      box.x = currentX - box.measuredWidth / 2;
      box.y = alignY(box, i);
      currentX -= box.measuredWidth + flowGap;
      box.enterX = enter;
      box.enterY = 0.0;
    }

    currentX = heroBox.x + heroBox.measuredWidth / 2 + flowGap;
    for (var i = heroIndex + 1; i < boxes.length; i++) {
      final box = boxes[i];
      box.x = currentX + box.measuredWidth / 2;
      box.y = alignY(box, i);
      currentX += box.measuredWidth + flowGap;
      box.enterX = -enter;
      box.enterY = 0.0;
    }
  });
}

void layoutEditorialColumn(
  SonnetFlowLayoutContext ctx,
  int variant,
  int secondaryHeroIndex,
) {
  final boxes = ctx.boxes;
  final heroIndex = ctx.heroIndex;
  final width = ctx.width;
  final height = ctx.height;
  final flowGap = ctx.flowGap;
  final stackGap = ctx.stackGap;
  final heroBox = boxes[heroIndex];

  if (variant == 0) {
    for (final box in boxes) {
      box.layoutDirection = 'vertical';
    }
    placeWithGlobalFit(ctx, (globalScale) {
      heroBox.x = -width * 0.15;
      heroBox.y = 0.0;
      var currentY = heroBox.y - heroBox.measuredHeight / 2 + stackGap * 0.5;
      for (var i = 0; i < heroIndex; i++) {
        final box = boxes[i];
        box.x = heroBox.x +
            heroBox.measuredWidth / 2 +
            flowGap +
            box.measuredWidth / 2;
        box.y = currentY + box.measuredHeight / 2;
        currentY += box.measuredHeight + stackGap;
        box.enterX = -20.0;
        box.enterY = 0.0;
      }
      currentY = heroBox.y - heroBox.measuredHeight / 2 + stackGap * 0.5;
      for (var i = heroIndex + 1; i < boxes.length; i++) {
        final box = boxes[i];
        box.x = heroBox.x -
            heroBox.measuredWidth / 2 -
            flowGap -
            box.measuredWidth / 2;
        box.y = currentY + box.measuredHeight / 2;
        currentY += box.measuredHeight + stackGap;
        box.enterX = 20.0;
        box.enterY = 0.0;
      }
    });
  } else if (variant == 1) {
    for (final box in boxes) {
      box.layoutDirection = 'vertical';
    }
    placeWithGlobalFit(ctx, (globalScale) {
      final rightEdge = width * 0.28;
      final safeHalfH = height * 0.46;
      final maxW = boxes.map((box) => box.measuredWidth).reduce(math.max);
      final railStep = maxW + stackGap;
      final totalHeight =
          boxes.fold<double>(0.0, (sum, box) => sum + box.measuredHeight) +
              stackGap * (boxes.length - 1);
      final fitsSingleRail = boxes.fold<double>(
                  0.0, (sum, box) => sum + box.measuredHeight) *
              0.52 +
          stackGap * (boxes.length - 1) <= safeHalfH * 2;

      if (fitsSingleRail) {
        var currentY = -totalHeight / 2;
        for (final box in boxes) {
          box.x = rightEdge - box.measuredWidth / 2;
          box.y = currentY + box.measuredHeight / 2;
          currentY += box.measuredHeight + stackGap;
          box.enterX = 20.0;
          box.enterY = 0.0;
        }
        return;
      }

      var rail = 0;
      var currentY = -safeHalfH;
      for (final box in boxes) {
        if (currentY + box.measuredHeight > safeHalfH) {
          rail += 1;
          currentY = -safeHalfH;
        }
        box.x = (rightEdge - rail * railStep) - box.measuredWidth / 2;
        box.y = currentY + box.measuredHeight / 2;
        currentY += box.measuredHeight + stackGap;
        box.enterX = 20.0;
        box.enterY = 0.0;
      }
    });
  } else if (variant == 2) {
    for (final box in boxes) {
      box.layoutDirection = 'horizontal';
    }
    placeWithGlobalFit(ctx, (globalScale) {
      heroBox.x = 0.0;
      heroBox.y = -height * 0.25;
      final before = boxes.sublist(0, heroIndex);
      final after = boxes.sublist(heroIndex + 1);

      if (before.isNotEmpty) {
        final kickerHeight =
            before.map((box) => box.measuredHeight).reduce(math.max);
        final kickerWidth = before.fold<double>(
                0.0, (sum, box) => sum + box.measuredWidth) +
            flowGap * (before.length - 1);
        final kickerY = heroBox.y -
            heroBox.measuredHeight / 2 -
            stackGap -
            kickerHeight / 2;
        var currentX = heroBox.x - kickerWidth / 2;
        for (final box in before) {
          box.x = currentX + box.measuredWidth / 2;
          box.y = kickerY;
          currentX += box.measuredWidth + flowGap;
          box.enterX = 0.0;
          box.enterY = -20.0;
        }
      }

      final leftAnchor =
          heroBox.x - heroBox.measuredWidth * 0.25 - flowGap;
      final rightAnchor =
          heroBox.x + heroBox.measuredWidth * 0.25 + flowGap;
      var currentY = heroBox.y + heroBox.measuredHeight / 2 + stackGap;

      for (var pair = 0; pair < after.length; pair += 2) {
        final left = after[pair];
        final right = pair + 1 < after.length ? after[pair + 1] : null;
        final rowHeight = math.max(left.measuredHeight, right?.measuredHeight ?? 0.0);
        left.x = leftAnchor - left.measuredWidth / 2;
        left.y = currentY + left.measuredHeight / 2;
        left.enterX = -20.0;
        left.enterY = 0.0;
        if (right != null) {
          right.x = rightAnchor + right.measuredWidth / 2;
          right.y = currentY + right.measuredHeight / 2;
          right.enterX = 20.0;
          right.enterY = 0.0;
        }
        currentY += rowHeight + stackGap;
      }
    });
  } else if (variant == 3) {
    for (final box in boxes) {
      box.layoutDirection = 'horizontal';
    }
    placeWithGlobalFit(ctx, (globalScale) {
      heroBox.x = 0.0;
      heroBox.y = 0.0;
      final firstHero = math.min(heroIndex, secondaryHeroIndex >= 0 ? secondaryHeroIndex : heroIndex);
      final line1 = boxes.sublist(0, firstHero + 1);
      final line2 = boxes.sublist(firstHero + 1);
      final line1Height =
          line1.map((box) => box.measuredHeight).reduce(math.max);
      final line2Height = line2.isNotEmpty
          ? line2.map((box) => box.measuredHeight).reduce(math.max)
          : 0.0;
      final totalHeight = line1Height + stackGap + line2Height;
      final line1Y = heroBox.y - totalHeight / 2 + line1Height / 2;
      final line2Y = line1Y + line1Height / 2 + stackGap + line2Height / 2;

      double layLine(List<SonnetPosterBlockBox> line, double lineY, double enterX) {
        final lineWidth = line.fold<double>(
                0.0, (sum, box) => sum + box.measuredWidth) +
            flowGap * (line.length - 1);
        var currentX = -lineWidth / 2;
        for (final box in line) {
          box.x = currentX + box.measuredWidth / 2;
          box.y = lineY;
          currentX += box.measuredWidth + flowGap;
          box.enterX = enterX;
          box.enterY = 0.0;
        }
        return lineWidth;
      }

      final line1Width = layLine(line1, line1Y, 30.0);
      final line2Width = layLine(line2, line2Y, -30.0);
      final offsetAmount = math.max(line1Width, line2Width) * 0.12;
      for (final box in line1) {
        box.x -= offsetAmount;
      }
      for (final box in line2) {
        box.x += offsetAmount;
      }
    });
  } else if (variant == 4) {
    for (var index = 0; index < boxes.length; index++) {
      boxes[index].layoutDirection =
          index == heroIndex ? 'vertical' : 'horizontal';
    }
    placeWithGlobalFit(ctx, (globalScale) {
      final heroOnRight = heroIndex == boxes.length - 1;
      final blockLeft = -width * 0.40;
      final blockRight = width * 0.40;
      var currentY = -height * 0.34;

      void flowWords(
        List<int> indices,
        ({double left, double right}) Function(double rowTop) regionFor,
      ) {
        var reg = regionFor(currentY);
        var currentX = reg.left;
        var rowHeight = 0.0;

        for (final index in indices) {
          final box = boxes[index];
          if (currentX > reg.left && currentX + box.measuredWidth > reg.right) {
            currentY += rowHeight + stackGap;
            reg = regionFor(currentY);
            currentX = reg.left;
            rowHeight = 0.0;
          }
          box.x = currentX + box.measuredWidth / 2;
          box.y = currentY + box.measuredHeight / 2;
          box.enterX = heroOnRight ? -25.0 : 25.0;
          box.enterY = 0.0;
          currentX += box.measuredWidth + flowGap;
          rowHeight = math.max(rowHeight, box.measuredHeight);
        }
        if (indices.isNotEmpty) currentY += rowHeight;
      }

      final beforeIndices =
          boxes.sublist(0, heroIndex).map((b) => b.index).toList();
      final afterIndices =
          boxes.sublist(heroIndex + 1).map((b) => b.index).toList();
      flowWords(beforeIndices, (_) => (left: blockLeft, right: blockRight));
      currentY += stackGap;

      final pillarLeft = heroOnRight
          ? blockRight - heroBox.measuredWidth
          : blockLeft;
      heroBox.x = pillarLeft + heroBox.measuredWidth / 2;
      heroBox.y = currentY + heroBox.measuredHeight / 2;
      final pillarBottom = currentY + heroBox.measuredHeight + stackGap;
      final besideLeft = heroOnRight
          ? blockLeft
          : pillarLeft + heroBox.measuredWidth + flowGap;
      final besideRight =
          heroOnRight ? pillarLeft - flowGap : blockRight;

      flowWords(afterIndices, (rowTop) => rowTop < pillarBottom - 0.5
          ? (left: besideLeft, right: besideRight)
          : (left: blockLeft, right: blockRight));
    });
  }
}

class _PlacedRect {
  _PlacedRect({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });
  final double left;
  final double right;
  final double top;
  final double bottom;
}

double _rectSeparation(_PlacedRect a, _PlacedRect b) => math.max(
      math.max(a.left - b.right, b.left - a.right),
      math.max(a.top - b.bottom, b.top - a.bottom),
    );

void layoutFragmentCollage(SonnetFlowLayoutContext ctx, int variant) {
  final boxes = ctx.boxes;
  final heroIndex = ctx.heroIndex;
  final flowGap = ctx.flowGap;
  final stackGap = ctx.stackGap;
  final heroBox = boxes[heroIndex];

  for (var index = 0; index < boxes.length; index++) {
    if (index == heroIndex) continue;
    final box = boxes[index];
    if ((box.rotation / (math.pi / 2)).round().abs() % 2 == 1) {
      final rotatedWidth = box.measuredHeight;
      box.measuredHeight = box.measuredWidth;
      box.measuredWidth = rotatedWidth;
    }
    box.rotation = 0.0;
  }

  placeWithGlobalFit(ctx, (globalScale) {
    heroBox.x = 0.0;
    heroBox.y = 0.0;
    final baseRadius =
        _hypot(heroBox.measuredWidth, heroBox.measuredHeight) / 2 +
            stackGap;
    final count = math.max(1, boxes.length - 1);
    const squash = 0.65;

    final placed = <_PlacedRect>[
      _PlacedRect(
        left: heroBox.x - heroBox.measuredWidth / 2,
        right: heroBox.x + heroBox.measuredWidth / 2,
        top: heroBox.y - heroBox.measuredHeight / 2,
        bottom: heroBox.y + heroBox.measuredHeight / 2,
      ),
    ];

    var angle = math.pi / 4;
    var supportIndex = 0;

    for (var i = 0; i < boxes.length; i++) {
      if (i == heroIndex) continue;
      final box = boxes[i];
      var radius = baseRadius;

      if (variant == 1) {
        radius += (35.0 + (supportIndex / count) * 150.0) * globalScale;
      } else if (variant == 2) {
        radius += ((supportIndex % 2 == 1) ? 140.0 : 50.0) * globalScale;
      } else {
        radius += (45.0 + ((supportIndex * 23) % 90)) * globalScale;
      }
      supportIndex += 1;

      var candidate = angle;
      var rect = _PlacedRect(left: 0, right: 0, top: 0, bottom: 0);
      var resolvedRadius = radius;
      var placedClear = false;

      for (var ring = 0; ring < 14 && !placedClear; ring++) {
        for (var attempt = 0; attempt < 400; attempt++) {
          rect = _PlacedRect(
            left: math.cos(candidate) * resolvedRadius - box.measuredWidth / 2,
            right: math.cos(candidate) * resolvedRadius + box.measuredWidth / 2,
            top: math.sin(candidate) * resolvedRadius * squash -
                box.measuredHeight / 2,
            bottom: math.sin(candidate) * resolvedRadius * squash +
                box.measuredHeight / 2,
          );
          if (placed.every((entry) => _rectSeparation(entry, rect) >= flowGap)) {
            placedClear = true;
            break;
          }
          candidate += 0.07;
        }
        if (!placedClear) resolvedRadius += (36.0 + ring * 12.0) * globalScale;
      }

      angle = candidate + 0.02;
      placed.add(rect);
      box.x = heroBox.x + math.cos(candidate) * resolvedRadius;
      box.y = heroBox.y + math.sin(candidate) * resolvedRadius * squash;
      box.layoutDirection =
          math.cos(candidate).abs() >= math.sin(candidate).abs()
              ? 'vertical'
              : 'horizontal';
      box.enterX = math.cos(candidate) * -60.0;
      box.enterY = math.sin(candidate) * -60.0;
    }
  });
}

void layoutCrossStack(SonnetFlowLayoutContext ctx) {
  final boxes = ctx.boxes;
  final heroIndex = ctx.heroIndex;
  final height = ctx.height;
  final flowGap = ctx.flowGap;
  final stackGap = ctx.stackGap;
  final heroBox = boxes[heroIndex];
  final beforeCount = heroIndex;
  final topCount = beforeCount ~/ 2;
  final afterCount = boxes.length - 1 - heroIndex;
  final rightCount = (afterCount / 2).ceil();

  double fillColumn(List<SonnetPosterBlockBox> column) {
    if (column.isEmpty) return 0.0;
    final available =
        math.max(0.0, height * 0.46 - heroBox.measuredHeight / 2 - stackGap);
    if (available <= 0) return 0.0;
    final gaps = stackGap * (column.length - 1);
    final contentHeight =
        column.fold<double>(0.0, (sum, box) => sum + box.measuredHeight);
    final target = available * 0.72;

    if (contentHeight + gaps < target) {
      final boost = math.min(2.2, (target - gaps) / math.max(1.0, contentHeight));
      for (final box in column) {
        final capped = math.min(boost, (heroBox.fontScale * 0.6) / box.fontScale);
        if (capped > 1.05) {
          box.fontScale *= capped;
          box.measuredWidth *= capped;
          box.measuredHeight *= capped;
        }
      }
    }
    if (column.length < 2) return 0.0;
    final grown =
        column.fold<double>(0.0, (sum, box) => sum + box.measuredHeight);
    final pitch = (available * 0.95 - grown) / (column.length - 1);
    return math.max(0.0, math.min(stackGap * 2, pitch - stackGap));
  }

  placeWithGlobalFit(ctx, (globalScale) {
    heroBox.x = 0.0;
    heroBox.y = 0.0;
    final topStretch = fillColumn(boxes.sublist(0, topCount));
    final bottomStretch = fillColumn(boxes.sublist(heroIndex + rightCount + 1));

    var currentX = heroBox.x - heroBox.measuredWidth / 2 - stackGap;
    for (var i = heroIndex - 1; i >= topCount; i--) {
      final box = boxes[i];
      box.layoutDirection = 'horizontal';
      box.x = currentX - box.measuredWidth / 2;
      box.y = heroBox.y + (i % 2 == 0 ? 10.0 : -10.0);
      currentX -= box.measuredWidth + flowGap;
      box.enterX = -30.0;
      box.enterY = 0.0;
    }

    var currentY = heroBox.y - heroBox.measuredHeight / 2 - stackGap;
    for (var i = topCount - 1; i >= 0; i--) {
      final box = boxes[i];
      box.layoutDirection = 'vertical';
      box.x = heroBox.x + (i % 2 == 0 ? 15.0 : -15.0);
      box.y = currentY - box.measuredHeight / 2;
      currentY -= box.measuredHeight + stackGap + topStretch;
      box.enterX = 0.0;
      box.enterY = -30.0;
    }

    currentX = heroBox.x + heroBox.measuredWidth / 2 + stackGap;
    for (var i = heroIndex + 1; i <= heroIndex + rightCount; i++) {
      final box = boxes[i];
      box.layoutDirection = 'horizontal';
      box.x = currentX + box.measuredWidth / 2;
      box.y = heroBox.y + (i % 2 == 0 ? 10.0 : -10.0);
      currentX += box.measuredWidth + flowGap;
      box.enterX = 30.0;
      box.enterY = 0.0;
    }

    currentY = heroBox.y + heroBox.measuredHeight / 2 + stackGap;
    for (var i = heroIndex + rightCount + 1; i < boxes.length; i++) {
      final box = boxes[i];
      box.layoutDirection = 'vertical';
      box.x = heroBox.x + (i % 2 == 0 ? 15.0 : -15.0);
      box.y = currentY + box.measuredHeight / 2;
      currentY += box.measuredHeight + stackGap + bottomStretch;
      box.enterX = 0.0;
      box.enterY = 30.0;
    }
  });
}
