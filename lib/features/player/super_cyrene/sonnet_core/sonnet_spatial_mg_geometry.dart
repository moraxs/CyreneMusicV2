import 'package:flutter/material.dart';
import 'sonnet_animated_graphics.dart';

const sonnetGeoVariantCount = 100;

int resolveSonnetGeoVariant(int seed) =>
    ((seed % sonnetGeoVariantCount) + sonnetGeoVariantCount) %
    sonnetGeoVariantCount;

int _resolveSonnetGeoCycle(int seed) => (seed / sonnetGeoVariantCount).floor();

int _resolveSonnetGeoSubVariant(int seed, int count) {
  final cycle = _resolveSonnetGeoCycle(seed);
  return ((cycle % count) + count) % count;
}

int resolveSonnetMoleculeVariant(int seed) =>
    _resolveSonnetGeoSubVariant(seed, 3);

int resolveSonnetHudRotationQuarterTurns(int seed) =>
    _resolveSonnetGeoSubVariant(seed, 4);

void _tracePolygon(AnimatedGraphics target, List<Offset> points) {
  if (points.isEmpty) return;
  target.moveTo(points[0].dx, points[0].dy);
  for (var i = 1; i < points.length; i++) {
    target.lineTo(points[i].dx, points[i].dy);
  }
  target.lineTo(points[0].dx, points[0].dy);
}

void _drawFace(
  AnimatedGraphics target,
  List<Offset> points,
  Color color,
  double fillAlpha,
) {
  _tracePolygon(target, points);
  target.fill(color: color, alpha: fillAlpha);
}

void drawSonnetSolidCuboid(
  AnimatedGraphics target,
  double x,
  double y,
  double width,
  double height,
  double depthX,
  double depthY,
  Color color,
  double alpha,
) {
  final left = x - width / 2;
  final right = x + width / 2;
  final top = y - height / 2;
  final bottom = y + height / 2;

  final front = [
    Offset(left, top),
    Offset(right, top),
    Offset(right, bottom),
    Offset(left, bottom),
  ];
  final topFace = [
    Offset(left, top),
    Offset(left + depthX, top + depthY),
    Offset(right + depthX, top + depthY),
    Offset(right, top),
  ];
  final sideFace = [
    Offset(right, top),
    Offset(right + depthX, top + depthY),
    Offset(right + depthX, bottom + depthY),
    Offset(right, bottom),
  ];

  _drawFace(target, topFace, color, alpha * 0.42);
  _drawFace(target, sideFace, color, alpha * 0.68);
  _drawFace(target, front, color, alpha * 0.24);
}

void _drawSonnetExtrudedPolygon(
  AnimatedGraphics target,
  List<Offset> front,
  double depthX,
  double depthY,
  Color color,
  double alpha,
) {
  final back = front.map((p) => Offset(p.dx + depthX, p.dy + depthY)).toList();
  for (var index = 0; index < front.length; index++) {
    final next = (index + 1) % front.length;
    _drawFace(
      target,
      [front[index], back[index], back[next], front[next]],
      color,
      alpha * (0.34 + (index % 3) * 0.12),
    );
  }
  _drawFace(target, front, color, alpha * 0.22);
}

void drawSonnetTriangularPrism(
  AnimatedGraphics target,
  double x,
  double y,
  double width,
  double height,
  double depthX,
  double depthY,
  Color color,
  double alpha,
) =>
    _drawSonnetExtrudedPolygon(
      target,
      [
        Offset(x, y - height / 2),
        Offset(x + width / 2, y + height / 2),
        Offset(x - width / 2, y + height / 2),
      ],
      depthX,
      depthY,
      color,
      alpha,
    );

void drawSonnetHexagonalPrism(
  AnimatedGraphics target,
  double x,
  double y,
  double width,
  double height,
  double depthX,
  double depthY,
  Color color,
  double alpha,
) =>
    _drawSonnetExtrudedPolygon(
      target,
      [
        Offset(x - width * 0.25, y - height / 2),
        Offset(x + width * 0.25, y - height / 2),
        Offset(x + width / 2, y),
        Offset(x + width * 0.25, y + height / 2),
        Offset(x - width * 0.25, y + height / 2),
        Offset(x - width / 2, y),
      ],
      depthX,
      depthY,
      color,
      alpha,
    );

void drawSonnetTrapezoidPrism(
  AnimatedGraphics target,
  double x,
  double y,
  double topWidth,
  double bottomWidth,
  double height,
  double depthX,
  double depthY,
  Color color,
  double alpha,
) =>
    _drawSonnetExtrudedPolygon(
      target,
      [
        Offset(x - topWidth / 2, y - height / 2),
        Offset(x + topWidth / 2, y - height / 2),
        Offset(x + bottomWidth / 2, y + height / 2),
        Offset(x - bottomWidth / 2, y + height / 2),
      ],
      depthX,
      depthY,
      color,
      alpha,
    );
