import 'dart:math' as math;

/// SuperCyrene「展览馆」蜂窝网格的纯 Dart 数学工具。
///
/// 移植自 folia-major 前端项目 `src/components/folia-grid/hexViewport.ts`
/// 与 `hexCardTransform.ts`：歌曲卡片按中心外扩的六边形螺旋排布，每张卡片的
/// 缩放/透明度/层级/按钮可见性由「到视口中心距离」驱动，形成近大远淡的展览效果。

/// 六边形 cube 坐标（满足 x + y + z = 0）。
class HexCubeCoord {
  const HexCubeCoord(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;
}

/// 单个卡片在蜂巢网格中的稳定位置。
class HexGridCoord {
  const HexGridCoord({required this.index, required this.cube, required this.baseX, required this.baseY});

  final int index;
  final HexCubeCoord cube;

  /// 卡片中心的世界坐标（未加拖拽偏移），以视口中心 (0,0) 为原点。
  final double baseX;
  final double baseY;
}

/// 布局断点参数（照搬参考项目 GridView.tsx 的 layoutConfig）。
class HexLayoutConfig {
  const HexLayoutConfig({
    required this.cardWidth,
    required this.cardHeight,
    required this.spacingX,
    required this.spacingY,
    required this.maxDistance,
    required this.lodStart,
    required this.lodEnd,
  });

  final double cardWidth;
  final double cardHeight;
  final double spacingX;
  final double spacingY;

  /// 缩放/透明度渐变的归一化分母（progress = distance / maxDistance）。
  final double maxDistance;

  /// 「加队列」按钮淡出区间（离中心越远越透明）。
  final double lodStart;
  final double lodEnd;

  /// 按视口宽度选择一组布局参数（与参考项目断点一致）。
  static HexLayoutConfig forViewportWidth(double width) {
    if (width < 768) {
      return const HexLayoutConfig(
        cardWidth: 180, cardHeight: 280, spacingX: 205, spacingY: 270,
        maxDistance: 420, lodStart: 280, lodEnd: 320,
      );
    }
    if (width < 1440) {
      return const HexLayoutConfig(
        cardWidth: 220, cardHeight: 330, spacingX: 250, spacingY: 320,
        maxDistance: 500, lodStart: 340, lodEnd: 385,
      );
    }
    if (width < 2000) {
      return const HexLayoutConfig(
        cardWidth: 250, cardHeight: 375, spacingX: 285, spacingY: 365,
        maxDistance: 580, lodStart: 400, lodEnd: 450,
      );
    }
    return const HexLayoutConfig(
      cardWidth: 280, cardHeight: 420, spacingX: 320, spacingY: 410,
      maxDistance: 660, lodStart: 450, lodEnd: 510,
    );
  }
}

/// 返回第 [index] 个卡片在中心外扩六边形螺旋上的 cube 坐标。
///
/// 与参考项目 `getHexCubicAtIndex` 一致：index 0 在中心，随后按六个方向
/// 逐环向外扩展，保证同一前缀在不同数量下坐标稳定。
HexCubeCoord hexCubicAtIndex(int index) {
  if (index <= 0) return const HexCubeCoord(0, 0, 0);

  var radius = 1;
  while (index >= 1 + 3 * radius * (radius + 1)) {
    radius++;
  }

  final ringStart = 1 + 3 * (radius - 1) * radius;
  final ringOffset = index - ringStart;
  final side = ringOffset ~/ radius;
  final stepsOnSide = ringOffset % radius + 1;

  const dirs = [
    HexCubeCoord(0, 1, -1),
    HexCubeCoord(-1, 1, 0),
    HexCubeCoord(-1, 0, 1),
    HexCubeCoord(0, -1, 1),
    HexCubeCoord(1, -1, 0),
    HexCubeCoord(1, 0, -1),
  ];

  var cube = HexCubeCoord(radius, -radius, 0);
  for (var completedSide = 0; completedSide < side; completedSide++) {
    cube = HexCubeCoord(
      cube.x + dirs[completedSide].x * radius,
      cube.y + dirs[completedSide].y * radius,
      cube.z + dirs[completedSide].z * radius,
    );
  }
  cube = HexCubeCoord(
    cube.x + dirs[side].x * stepsOnSide,
    cube.y + dirs[side].y * stepsOnSide,
    cube.z + dirs[side].z * stepsOnSide,
  );
  return cube;
}

/// 构建 [count] 个卡片的稳定蜂巢坐标前缀。
List<HexGridCoord> buildHexGridCoords(int count, double spacingX, double spacingY) {
  final safeCount = math.max(0, count);
  final coords = <HexGridCoord>[];
  for (var index = 0; index < safeCount; index++) {
    final cube = hexCubicAtIndex(index);
    coords.add(HexGridCoord(
      index: index,
      cube: cube,
      baseX: cube.x * spacingX + cube.z * spacingX / 2,
      baseY: cube.z * spacingY,
    ));
  }
  return coords;
}

/// 卡片在某帧的完整视觉状态。
class HexCardFrame {
  const HexCardFrame({
    required this.visible,
    required this.distance,
    required this.scale,
    required this.opacity,
    required this.zIndex,
    required this.playOpacity,
    required this.playScale,
    required this.queueOpacity,
  });

  final bool visible;
  final double distance;
  final double scale;
  final double opacity;
  final int zIndex;
  final double playOpacity;
  final double playScale;
  final double queueOpacity;
}

/// 计算单个卡片在拖拽偏移 [dx]/[dy] 下的视觉状态。
///
/// 完全照搬参考项目 `computeHexCardFrame`：
/// - progress = distance / maxDistance
/// - scale     = 1.1 - 0.65 * progress
/// - opacity   = 1.0 - 0.60 * progress
/// - zIndex    = 50 - 49 * progress
/// - 播放按钮：distance < 40 时淡入并放大（playOpacity = 1 - d/40）
/// - 队列按钮：lodStart..lodEnd 区间淡出
HexCardFrame computeHexCardFrame(
  HexGridCoord coord,
  double dx,
  double dy, {
  required HexLayoutConfig config,
  double? clipRadius,
}) {
  final centerX = coord.baseX + dx;
  final centerY = coord.baseY + dy;
  final distanceSq = centerX * centerX + centerY * centerY;
  final distance = math.sqrt(distanceSq);

  final visible = clipRadius == null || distance <= clipRadius;
  final progress = math.min(distance / math.max(config.maxDistance, 1), 1);
  final scale = 1.1 - 0.65 * progress;
  final opacity = visible ? 1.0 - 0.60 * progress : 0.0;
  final zIndex = (50 - 49 * progress).round();

  double queueOpacity = 0;
  if (distance < config.lodStart || config.lodEnd <= config.lodStart) {
    queueOpacity = 1;
  } else if (distance <= config.lodEnd) {
    final queueProgress = (distance - config.lodStart) / (config.lodEnd - config.lodStart);
    queueOpacity = (1 - queueProgress).clamp(0.0, 1.0);
  }

  double playOpacity = 0;
  double playScale = 0.8;
  if (distance < 40) {
    final playProgress = distance / 40;
    playOpacity = (1 - playProgress).clamp(0.0, 1.0);
    playScale = 1 - 0.2 * playProgress;
  }

  return HexCardFrame(
    visible: visible,
    distance: distance,
    scale: scale,
    opacity: opacity.clamp(0.0, 1.0),
    zIndex: zIndex,
    playOpacity: playOpacity,
    playScale: playScale,
    queueOpacity: queueOpacity,
  );
}

/// 计算可渲染的卡片索引集合：中心外扩的六边形环 + 像素半径过滤。
///
/// 与参考项目 `resolveVisibleHexIndexes` 一致，用于视口 culling，避免在
/// 拖拽时构建不可见卡片。
List<int> resolveVisibleHexIndexes({
  required List<HexGridCoord> coords,
  required double dx,
  required double dy,
  required double pixelRadius,
}) {
  final radiusSq = pixelRadius * pixelRadius;
  final visible = <int>[];
  for (final coord in coords) {
    final cdx = coord.baseX + dx;
    final cdy = coord.baseY + dy;
    if (cdx * cdx + cdy * cdy <= radiusSq) {
      visible.add(coord.index);
    }
  }
  visible.sort();
  return visible;
}