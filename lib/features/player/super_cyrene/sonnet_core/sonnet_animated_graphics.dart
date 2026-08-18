import 'dart:math' as math;
import 'package:flutter/material.dart';

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

class PathOp {
  PathOp.moveTo(this.x, this.y)
      : type = 'moveTo',
        len = 0.0,
        lastX = x,
        lastY = y;

  PathOp.lineTo(this.x, this.y, this.lastX, this.lastY)
      : type = 'lineTo',
        len = _hypot(x - lastX, y - lastY);

  PathOp.rectHint(this.x, this.y, this.w, this.h)
      : type = 'rect_hint',
        len = 0.0,
        lastX = x,
        lastY = y;

  PathOp.arc(
    this.cx,
    this.cy,
    this.r,
    this.start,
    this.end,
    this.anticlockwise,
    this.diff,
  )   : type = 'arc',
        len = diff.abs() * r,
        x = cx + math.cos(end) * r,
        y = cy + math.sin(end) * r,
        lastX = cx + math.cos(start) * r,
        lastY = cy + math.sin(start) * r;

  PathOp.circle(this.cx, this.cy, this.r, this.start, this.diff)
      : type = 'circle',
        anticlockwise = diff < 0,
        end = start + diff,
        len = math.pi * 2.0 * r,
        x = cx + math.cos(start + diff) * r,
        y = cy + math.sin(start + diff) * r,
        lastX = cx + math.cos(start) * r,
        lastY = cy + math.sin(start) * r;

  PathOp.quadraticCurveTo(
    this.cx,
    this.cy,
    this.tx,
    this.ty,
    this.lastX,
    this.lastY,
  )   : type = 'quadraticCurveTo',
        x = tx,
        y = ty,
        len = _hypot(cx - lastX, cy - lastY) + _hypot(tx - cx, ty - cy);

  PathOp.bezierCurveTo(
    this.c1x,
    this.c1y,
    this.c2x,
    this.c2y,
    this.tx,
    this.ty,
    this.lastX,
    this.lastY,
  )   : type = 'bezierCurveTo',
        x = tx,
        y = ty,
        len = _hypot(c1x - lastX, c1y - lastY) +
            _hypot(c2x - c1x, c2y - c1y) +
            _hypot(tx - c2x, ty - c2y);

  final String type;
  double x = 0;
  double y = 0;
  double lastX = 0;
  double lastY = 0;
  double len = 0;
  double cx = 0;
  double cy = 0;
  double tx = 0;
  double ty = 0;
  double c1x = 0;
  double c1y = 0;
  double c2x = 0;
  double c2y = 0;
  double r = 0;
  double start = 0;
  double end = 0;
  double diff = 0;
  bool anticlockwise = false;
  double w = 0;
  double h = 0;
}

class AnimatedGraphicsCommand {
  AnimatedGraphicsCommand({
    required this.type,
    required this.path,
    required this.length,
    required this.color,
    required this.alpha,
    this.strokeWidth = 1.0,
  });

  final String type; // 'stroke' | 'fill'
  final List<PathOp> path;
  final double length;
  final Color color;
  final double alpha;
  final double strokeWidth;
  double staggerDelay = 0.0;
  double staggerSpan = 1.0;
}

class AnimatedGraphics {
  final List<AnimatedGraphicsCommand> _commands = [];
  List<PathOp> _currentPath = [];
  double _currentLength = 0.0;
  double _lastX = 0.0;
  double _lastY = 0.0;
  bool _staggerScheduled = false;

  AnimatedGraphics moveTo(double x, double y) {
    _currentPath.add(PathOp.moveTo(x, y));
    _lastX = x;
    _lastY = y;
    return this;
  }

  AnimatedGraphics lineTo(double x, double y) {
    final op = PathOp.lineTo(x, y, _lastX, _lastY);
    _currentPath.add(op);
    _currentLength += op.len;
    _lastX = x;
    _lastY = y;
    return this;
  }

  AnimatedGraphics quadraticCurveTo(
    double cx,
    double cy,
    double tx,
    double ty,
  ) {
    final op = PathOp.quadraticCurveTo(cx, cy, tx, ty, _lastX, _lastY);
    _currentPath.add(op);
    _currentLength += op.len;
    _lastX = tx;
    _lastY = ty;
    return this;
  }

  AnimatedGraphics bezierCurveTo(
    double c1x,
    double c1y,
    double c2x,
    double c2y,
    double tx,
    double ty,
  ) {
    final op = PathOp.bezierCurveTo(c1x, c1y, c2x, c2y, tx, ty, _lastX, _lastY);
    _currentPath.add(op);
    _currentLength += op.len;
    _lastX = tx;
    _lastY = ty;
    return this;
  }

  AnimatedGraphics arc(
    double cx,
    double cy,
    double r,
    double start,
    double end, [
    bool anticlockwise = false,
  ]) {
    var diff = end - start;
    if (anticlockwise && diff > 0) {
      diff -= math.pi * 2.0;
    } else if (!anticlockwise && diff < 0) {
      diff += math.pi * 2.0;
    }
    final op = PathOp.arc(cx, cy, r, start, end, anticlockwise, diff);
    _currentPath.add(op);
    _currentLength += op.len;
    _lastX = cx + math.cos(end) * r;
    _lastY = cy + math.sin(end) * r;
    return this;
  }

  AnimatedGraphics circle(double x, double y, double r) {
    final start = math.Random().nextDouble() * math.pi * 2.0;
    final anticlockwise = math.Random().nextBool();
    final diff = anticlockwise ? -math.pi * 2.0 : math.pi * 2.0;
    final startX = x + math.cos(start) * r;
    final startY = y + math.sin(start) * r;

    moveTo(startX, startY);
    final op = PathOp.circle(x, y, r, start, diff);
    _currentPath.add(op);
    _currentLength += op.len;
    _lastX = x + math.cos(start + diff) * r;
    _lastY = y + math.sin(start + diff) * r;
    return this;
  }

  AnimatedGraphics rect(double x, double y, double w, double h) {
    _currentPath.add(PathOp.rectHint(x, y, w, h));
    moveTo(x, y)
        .lineTo(x + w, y)
        .lineTo(x + w, y + h)
        .lineTo(x, y + h)
        .lineTo(x, y);
    return this;
  }

  AnimatedGraphics poly(List<double> points) {
    if (points.length < 2) return this;
    moveTo(points[0], points[1]);
    for (var i = 2; i < points.length; i += 2) {
      lineTo(points[i], points[i + 1]);
    }
    lineTo(points[0], points[1]);
    return this;
  }

  AnimatedGraphics stroke({
    required Color color,
    double width = 1.0,
    double alpha = 1.0,
  }) {
    if (_currentPath.isNotEmpty) {
      _commands.add(AnimatedGraphicsCommand(
        type: 'stroke',
        path: List.of(_currentPath),
        length: _currentLength,
        color: color,
        alpha: alpha,
        strokeWidth: width,
      ));
      _currentPath = [];
      _currentLength = 0.0;
    }
    return this;
  }

  AnimatedGraphics fill({
    required Color color,
    double alpha = 1.0,
  }) {
    if (_currentPath.isNotEmpty) {
      _commands.add(AnimatedGraphicsCommand(
        type: 'fill',
        path: List.of(_currentPath),
        length: _currentLength,
        color: color,
        alpha: alpha,
      ));
      _currentPath = [];
      _currentLength = 0.0;
    }
    return this;
  }

  void scheduleStagger() {
    const golden = 0.6180339887498949;
    var strokeIndex = 0;
    var fillIndex = 0;

    for (final cmd in _commands) {
      final isStroke = cmd.type == 'stroke';
      final index = isStroke ? strokeIndex++ : fillIndex++;
      final slot = (index * golden) % 1.0;
      final jitter = ((index * 2654435761) & 0xFFFFFFFF) / 4294967296.0;
      final delay = slot * (isStroke ? 0.5 : 0.45);
      final span = isStroke ? 0.32 + jitter * 0.26 : 0.4 + jitter * 0.25;
      cmd.staggerDelay = delay;
      cmd.staggerSpan = math.min(span, 1.0 - delay);
    }
    _staggerScheduled = true;
  }

  void paint(Canvas canvas, double rawProgress) {
    if (!_staggerScheduled) scheduleStagger();

    for (final cmd in _commands) {
      if (cmd.type == 'fill') {
        final localRaw = ((rawProgress - cmd.staggerDelay) / cmd.staggerSpan)
            .clamp(0.0, 1.0);
        if (localRaw <= 0) continue;
        final localProgress = 1.0 - math.pow(1.0 - localRaw, 3.0);
        final alphaProgress = 1.0 -
            math.pow(1.0 - math.min(1.0, localRaw * 2.0), 3.0);
        final finalAlpha = (cmd.alpha * alphaProgress).clamp(0.0, 1.0);

        final paint = Paint()
          ..style = PaintingStyle.fill
          ..color = cmd.color.withValues(alpha: finalAlpha);

        if (cmd.path.isNotEmpty && cmd.path.first.type == 'rect_hint') {
          final r = cmd.path.first;
          canvas.drawRect(
            Rect.fromLTWH(r.x, r.y, r.w * localProgress, r.h),
            paint,
          );
        } else {
          final path = Path();
          for (final p in cmd.path) {
            if (p.type == 'rect_hint') continue;
            if (p.type == 'moveTo') {
              path.moveTo(p.x, p.y);
            } else if (p.type == 'lineTo') {
              path.lineTo(p.x, p.y);
            } else if (p.type == 'circle') {
              path.addOval(Rect.fromCircle(center: Offset(p.cx, p.cy), radius: p.r));
            } else if (p.type == 'arc') {
              path.arcTo(
                Rect.fromCircle(center: Offset(p.cx, p.cy), radius: p.r),
                p.start,
                p.diff,
                false,
              );
            } else if (p.type == 'quadraticCurveTo') {
              path.quadraticBezierTo(p.cx, p.cy, p.tx, p.ty);
            } else if (p.type == 'bezierCurveTo') {
              path.cubicTo(p.c1x, p.c1y, p.c2x, p.c2y, p.tx, p.ty);
            }
          }
          canvas.drawPath(path, paint);
        }
      } else if (cmd.type == 'stroke') {
        if (cmd.length <= 0) continue;
        final localRaw = ((rawProgress - cmd.staggerDelay) / cmd.staggerSpan)
            .clamp(0.0, 1.0);
        if (localRaw <= 0) continue;
        final localProgress = 1.0 - math.pow(1.0 - localRaw, 3.0);
        final targetLen = cmd.length * localProgress;
        var currentLen = 0.0;

        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cmd.strokeWidth
          ..color = cmd.color.withValues(alpha: cmd.alpha);

        final path = Path();

        for (final p in cmd.path) {
          if (p.type == 'rect_hint') continue;
          if (p.type == 'moveTo') {
            path.moveTo(p.x, p.y);
          } else {
            if (currentLen >= targetLen) break;
            if (currentLen + p.len <= targetLen) {
              if (p.type == 'lineTo') {
                path.lineTo(p.x, p.y);
              } else if (p.type == 'circle') {
                path.arcTo(
                  Rect.fromCircle(center: Offset(p.cx, p.cy), radius: p.r),
                  p.start,
                  p.diff,
                  false,
                );
              } else if (p.type == 'arc') {
                path.arcTo(
                  Rect.fromCircle(center: Offset(p.cx, p.cy), radius: p.r),
                  p.start,
                  p.diff,
                  false,
                );
              } else if (p.type == 'quadraticCurveTo') {
                path.quadraticBezierTo(p.cx, p.cy, p.tx, p.ty);
              } else if (p.type == 'bezierCurveTo') {
                path.cubicTo(p.c1x, p.c1y, p.c2x, p.c2y, p.tx, p.ty);
              }
              currentLen += p.len;
            } else {
              final ratio = (targetLen - currentLen) / math.max(0.001, p.len);
              if (p.type == 'lineTo') {
                final x = p.lastX + (p.x - p.lastX) * ratio;
                final y = p.lastY + (p.y - p.lastY) * ratio;
                path.lineTo(x, y);
              } else if (p.type == 'circle') {
                path.arcTo(
                  Rect.fromCircle(center: Offset(p.cx, p.cy), radius: p.r),
                  p.start,
                  p.diff * ratio,
                  false,
                );
              } else if (p.type == 'arc') {
                path.arcTo(
                  Rect.fromCircle(center: Offset(p.cx, p.cy), radius: p.r),
                  p.start,
                  p.diff * ratio,
                  false,
                );
              } else if (p.type == 'quadraticCurveTo') {
                final newCpX = p.lastX + ratio * (p.cx - p.lastX);
                final newCpY = p.lastY + ratio * (p.cy - p.lastY);
                final newTx = (1 - ratio) * (1 - ratio) * p.lastX +
                    2 * (1 - ratio) * ratio * p.cx +
                    ratio * ratio * p.tx;
                final newTy = (1 - ratio) * (1 - ratio) * p.lastY +
                    2 * (1 - ratio) * ratio * p.cy +
                    ratio * ratio * p.ty;
                path.quadraticBezierTo(newCpX, newCpY, newTx, newTy);
              } else if (p.type == 'bezierCurveTo') {
                final q0x = p.lastX + ratio * (p.c1x - p.lastX);
                final q0y = p.lastY + ratio * (p.c1y - p.lastY);
                final q1x = p.c1x + ratio * (p.c2x - p.c1x);
                final q1y = p.c1y + ratio * (p.c2y - p.c1y);
                final q2x = p.c2x + ratio * (p.tx - p.c2x);
                final q2y = p.c2y + ratio * (p.ty - p.c2y);
                final r0x = q0x + ratio * (q1x - q0x);
                final r0y = q0y + ratio * (q1y - q0y);
                final r1x = q1x + ratio * (q2x - q1x);
                final r1y = q1y + ratio * (q2y - q1y);
                final bx = r0x + ratio * (r1x - r0x);
                final by = r0y + ratio * (r1y - r0y);
                path.cubicTo(q0x, q0y, r0x, r0y, bx, by);
              }
              currentLen = targetLen;
              break;
            }
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }
}
