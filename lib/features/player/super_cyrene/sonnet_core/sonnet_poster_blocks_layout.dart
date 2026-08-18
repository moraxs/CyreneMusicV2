import 'dart:math' as math;

class SonnetPosterBlockBox {
  SonnetPosterBlockBox({
    required this.index,
    required this.isHero,
    required this.isSemiHero,
    required this.displayText,
    this.verticalDisplayText,
    this.verticalMeasuredWidth,
    this.verticalMeasuredHeight,
    this.verticalFontScale,
    required this.fontScale,
    required this.measuredWidth,
    required this.measuredHeight,
    this.x = 0.0,
    this.y = 0.0,
    this.rotation = 0.0,
    this.vertical = false,
    this.layoutDirection = 'horizontal',
    this.enterX = 0.0,
    this.enterY = 0.0,
    this.role,
    this.timingPhase = 0.0,
    this.relativePhase = 0.0,
  });

  int index;
  bool isHero;
  bool isSemiHero;
  String displayText;
  String? verticalDisplayText;
  double? verticalMeasuredWidth;
  double? verticalMeasuredHeight;
  double? verticalFontScale;
  double fontScale;
  double measuredWidth;
  double measuredHeight;
  double x;
  double y;
  double rotation;
  bool vertical;
  String layoutDirection;
  double enterX;
  double enterY;
  dynamic role;
  double timingPhase;
  double relativePhase;
}

class _FlowRect {
  _FlowRect({
    required this.u,
    required this.v,
    required this.uSize,
    required this.vSize,
  });
  double u;
  double v;
  double uSize;
  double vSize;
}

class _FlowPlacement {
  _FlowPlacement({
    required this.box,
    required this.rect,
    required this.scale,
    required this.vertical,
  });
  final SonnetPosterBlockBox box;
  final _FlowRect rect;
  double scale;
  final bool vertical;
}

class _ZoneFloat {
  _ZoneFloat({required this.extent, required this.vBottom});
  final double extent;
  final double vBottom;
}

class _FlowItem {
  _FlowItem.zone(this.zone) : kind = 'zone', group = null;
  _FlowItem.group(this.group) : kind = 'group', zone = null;
  final String kind;
  final SonnetPosterBlockBox? zone;
  final List<SonnetPosterBlockBox>? group;
}

List<_FlowItem> _partitionFlowItems(List<SonnetPosterBlockBox> boxes) {
  final items = <_FlowItem>[];
  var group = <SonnetPosterBlockBox>[];

  for (final box in boxes) {
    if (box.isHero || box.isSemiHero) {
      if (group.isNotEmpty) items.add(_FlowItem.group(group));
      group = [];
      items.add(_FlowItem.zone(box));
    } else {
      group.add(box);
    }
  }
  if (group.isNotEmpty) items.add(_FlowItem.group(group));
  return items;
}

class _FlowSpace {
  _FlowSpace({
    required this.orientation,
    required this.u,
    required this.v,
  });
  final String orientation; // 'horizontal' | 'vertical'
  final double u;
  final double v;
}

({double x, double y, double width, double height}) _flowToScreen(
  _FlowSpace space,
  _FlowRect rect,
  ({double x, double y, double width, double height}) canvas,
) {
  if (space.orientation == 'horizontal') {
    return (
      x: canvas.x + rect.u,
      y: canvas.y + rect.v,
      width: rect.uSize,
      height: rect.vSize,
    );
  }
  return (
    x: canvas.x + canvas.width - rect.v - rect.vSize,
    y: canvas.y + rect.u,
    width: rect.vSize,
    height: rect.uSize,
  );
}

class _FlowAttempt {
  _FlowAttempt({required this.placements, required this.vTotal});
  final List<_FlowPlacement> placements;
  double vTotal;
}

_FlowAttempt _attemptFlowLayout(
  List<SonnetPosterBlockBox> boxes,
  _FlowSpace space,
  double globalScale,
  double chipGap,
  double lineGap,
  int seed,
) {
  final items = _partitionFlowItems(boxes);
  final placements = <_FlowPlacement>[];
  final floats = <_ZoneFloat>[];
  var vCursor = 0.0;
  var ownBandOnEndSide = ((seed >> 1) & 1) == 1;

  ({bool useVertical, double baseScale, double width, double height}) measure(
    SonnetPosterBlockBox box,
  ) {
    final useVertical = space.orientation == 'vertical' &&
        box.verticalMeasuredWidth != null &&
        box.verticalMeasuredHeight != null &&
        box.verticalFontScale != null;
    final baseScale = useVertical ? box.verticalFontScale! : box.fontScale;
    final width = (useVertical ? box.verticalMeasuredWidth! : box.measuredWidth) *
        globalScale;
    final height =
        (useVertical ? box.verticalMeasuredHeight! : box.measuredHeight) *
            globalScale;
    return (
      useVertical: useVertical,
      baseScale: baseScale,
      width: width,
      height: height,
    );
  }

  ({double uSize, double vSize}) toFlowSize(double width, double height) =>
      space.orientation == 'horizontal'
          ? (uSize: width, vSize: height)
          : (uSize: height, vSize: width);

  void pruneFloats() {
    for (var index = floats.length - 1; index >= 0; index--) {
      if (floats[index].vBottom <= vCursor) floats.removeAt(index);
    }
  }

  for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
    final item = items[itemIndex];
    pruneFloats();

    if (item.kind == 'group') {
      final reservedU = floats.fold<double>(
        0.0,
        (sum, entry) => sum + entry.extent,
      );
      final capacity = math.max(chipGap * 2, space.u - reservedU);
      final uStart = reservedU;
      final chips = item.group!.map((box) {
        final dims = measure(box);
        final flow = toFlowSize(dims.width, dims.height);
        return (
          box: box,
          dims: dims,
          uSize: flow.uSize,
          vSize: flow.vSize,
          shrink: 1.0,
        );
      }).toList();

      var line = <({
        SonnetPosterBlockBox box,
        ({bool useVertical, double baseScale, double width, double height}) dims,
        double uSize,
        double vSize,
        double shrink,
      })>[];
      var lineUsedU = 0.0;

      void flushLine() {
        if (line.isEmpty) return;
        final lineV = line.map((c) => c.vSize * c.shrink).reduce(math.max);
        final leftover = capacity - lineUsedU;
        final spread = line.length > 1 && leftover > 0
            ? math.min(leftover / (line.length - 1), chipGap * 2.5)
            : 0.0;
        var uCursor = uStart;
        for (final chip in line) {
          final finalScale = chip.dims.baseScale * globalScale * chip.shrink;
          placements.add(_FlowPlacement(
            box: chip.box,
            rect: _FlowRect(
              u: uCursor,
              v: vCursor,
              uSize: chip.uSize * chip.shrink,
              vSize: chip.vSize * chip.shrink,
            ),
            scale: finalScale,
            vertical: chip.dims.useVertical,
          ));
          uCursor += chip.uSize * chip.shrink + chipGap + spread;
        }
        vCursor += lineV + lineGap;
        pruneFloats();
        line = [];
        lineUsedU = 0.0;
      }

      for (var chip in chips) {
        final needed = lineUsedU + (line.isNotEmpty ? chipGap : 0) + chip.uSize;
        if (needed > capacity && line.isNotEmpty) flushLine();
        if (chip.uSize > capacity) {
          final shrink = math.max(0.5, capacity / chip.uSize);
          chip = (
            box: chip.box,
            dims: chip.dims,
            uSize: chip.uSize,
            vSize: chip.vSize,
            shrink: shrink,
          );
          lineUsedU = 0.0;
          line.add(chip);
          flushLine();
          continue;
        }
        lineUsedU += (line.isNotEmpty ? chipGap : 0) + chip.uSize;
        line.add(chip);
      }
      flushLine();
      continue;
    }

    final zone = item.zone!;
    final floatBottoms = floats.map((e) => e.vBottom).toList();
    vCursor = math.max(
      vCursor,
      floatBottoms.isNotEmpty ? floatBottoms.reduce(math.max) : 0.0,
    );
    floats.clear();

    final dims = measure(zone);
    final flow = toFlowSize(dims.width, dims.height);
    final followedByGroup = itemIndex + 1 < items.length &&
        items[itemIndex + 1].kind == 'group';
    final zoneShrink = math.min(
      1.0,
      math.min(
        (space.u * (followedByGroup ? 0.62 : 0.9)) / flow.uSize,
        (space.v * 0.66) / flow.vSize,
      ),
    );
    final uSize = flow.uSize * zoneShrink;
    final vSize = flow.vSize * zoneShrink;
    final onlyZone = items.length == 1;
    final u = onlyZone
        ? (space.u - uSize) / 2
        : (followedByGroup
            ? 0.0
            : (ownBandOnEndSide ? space.u - uSize : 0.0));

    placements.add(_FlowPlacement(
      box: zone,
      rect: _FlowRect(u: u, v: vCursor, uSize: uSize, vSize: vSize),
      scale: dims.baseScale * globalScale * zoneShrink,
      vertical: dims.useVertical,
    ));

    if (followedByGroup) {
      floats.add(_ZoneFloat(
        extent: uSize + chipGap,
        vBottom: vCursor + vSize + lineGap,
      ));
    } else {
      vCursor += vSize + lineGap;
      ownBandOnEndSide = !ownBandOnEndSide;
    }
  }

  final vTotal = placements.fold<double>(
    0.0,
    (maxVal, placement) =>
        math.max(maxVal, placement.rect.v + placement.rect.vSize),
  );
  return _FlowAttempt(placements: placements, vTotal: vTotal);
}

void layoutSonnetPosterBlocks(
  List<SonnetPosterBlockBox> boxes,
  double width,
  double height,
  double baseFontSize, [
  int seed = 0,
]) {
  if (boxes.isEmpty) return;
  final gap = (baseFontSize * 0.35).clamp(16.0, 40.0);
  final chipGap = gap;
  final lineGap = gap * 1.15;

  final canvas = (
    x: -width * 0.42,
    y: -height * 0.40,
    width: width * 0.84,
    height: height * 0.80,
  );

  final orientation = (seed % 2 == 0) ? 'horizontal' : 'vertical';
  final space = orientation == 'horizontal'
      ? _FlowSpace(orientation: orientation, u: canvas.width, v: canvas.height)
      : _FlowSpace(orientation: orientation, u: canvas.height, v: canvas.width);

  var attempt =
      _attemptFlowLayout(boxes, space, 1.0, chipGap, lineGap, seed);
  for (final globalScale in [0.92, 0.84, 0.76, 0.68, 0.6, 0.52]) {
    if (attempt.vTotal <= space.v + 0.5) break;
    attempt =
        _attemptFlowLayout(boxes, space, globalScale, chipGap, lineGap, seed);
  }

  if (attempt.vTotal > space.v) {
    final fitScale = space.v / attempt.vTotal;
    for (final placement in attempt.placements) {
      placement.rect.u *= fitScale;
      placement.rect.v *= fitScale;
      placement.rect.uSize *= fitScale;
      placement.rect.vSize *= fitScale;
      placement.scale *= fitScale;
    }
    attempt.vTotal = space.v;
  }

  final vShift = math.max(0.0, (space.v - attempt.vTotal) / 2);
  for (final placement in attempt.placements) {
    final box = placement.box;
    final rect = _FlowRect(
      u: placement.rect.u,
      v: placement.rect.v + vShift,
      uSize: placement.rect.uSize,
      vSize: placement.rect.vSize,
    );
    final screen = _flowToScreen(space, rect, canvas);
    box.fontScale = placement.scale;
    box.measuredWidth = screen.width;
    box.measuredHeight = screen.height;
    box.x = screen.x + screen.width / 2;
    box.y = screen.y + screen.height / 2;
    box.rotation = 0.0;
    box.vertical = placement.vertical;
    if (placement.vertical && box.verticalDisplayText != null) {
      box.displayText = box.verticalDisplayText!;
    }
    box.layoutDirection = orientation == 'vertical' ? 'vertical' : 'horizontal';
    if (orientation == 'horizontal') {
      box.enterX = (screen.x + screen.width / 2 < 0 ? -1 : 1) *
          math.min(28.0, baseFontSize * 0.45);
      box.enterY = math.min(18.0, baseFontSize * 0.25);
    } else {
      box.enterX = math.min(18.0, baseFontSize * 0.25);
      box.enterY = (screen.y + screen.height / 2 < 0 ? -1 : 1) *
          math.min(28.0, baseFontSize * 0.45);
    }
  }
}
