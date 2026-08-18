import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_animated_graphics.dart';
import 'sonnet_random.dart';

const sonnetBackgroundMgVariantCount = 8;

const List<String> sonnetBackgroundMgVariants = [
  'classic-cross',
  'corner-brackets',
  'marquee-strips',
  'diagonal-corners',
  'dotted-columns',
  'double-frame',
  'ruler-frame',
  'arc-gauge',
];

class SonnetBackgroundMgOptions {
  const SonnetBackgroundMgOptions({
    required this.target,
    required this.variant,
    required this.width,
    required this.height,
    required this.seed,
    required this.primary,
    required this.secondary,
  });

  final AnimatedGraphics target;
  final int variant;
  final double width;
  final double height;
  final int seed;
  final Color primary;
  final Color secondary;
}

int resolveSonnetBackgroundMgVariant(int seed) =>
    mixSonnetSeed(seed, 0x9e3779b9) % sonnetBackgroundMgVariantCount;

class _FrameContext {
  _FrameContext({
    required this.target,
    required this.variant,
    required this.width,
    required this.height,
    required this.seed,
    required this.primary,
    required this.secondary,
    required this.hw,
    required this.hh,
    required this.marginX,
    required this.marginY,
  });

  final AnimatedGraphics target;
  final int variant;
  final double width;
  final double height;
  final int seed;
  final Color primary;
  final Color secondary;
  final double hw;
  final double hh;
  final double marginX;
  final double marginY;
}

_FrameContext _withFrame(SonnetBackgroundMgOptions options) => _FrameContext(
      target: options.target,
      variant: options.variant,
      width: options.width,
      height: options.height,
      seed: options.seed,
      primary: options.primary,
      secondary: options.secondary,
      hw: options.width / 2.0,
      hh: options.height / 2.0,
      marginX: options.width * 0.05,
      marginY: options.height * 0.05,
    );

void _drawCross(
  AnimatedGraphics target,
  double x,
  double y,
  double size,
  Color color, [
  double alpha = 0.5,
]) {
  target
      .moveTo(x - size, y - size)
      .lineTo(x + size, y + size)
      .stroke(color: color, width: 1.0, alpha: alpha);
  target
      .moveTo(x + size, y - size)
      .lineTo(x - size, y + size)
      .stroke(color: color, width: 1.0, alpha: alpha);
}

void _drawClassicCross(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;

  const size = 4.0;
  _drawCross(target, -hw + marginX, -hh + marginY, size, primary, 0.4);
  _drawCross(target, hw - marginX, -hh + marginY, size, primary, 0.4);
  _drawCross(target, -hw + marginX, hh - marginY, size, primary, 0.4);
  _drawCross(target, hw - marginX, hh - marginY, size, primary, 0.4);

  for (var i = 0; i < 8; i++) {
    _drawCross(
      target,
      -hw + marginX,
      -hh + marginY + i * 20.0 + 30.0,
      3.0,
      primary,
      0.3,
    );
  }

  final barY = hh - marginY - 10.0;
  target
      .moveTo(-hw + marginX + 20.0, barY)
      .lineTo(hw - marginX - 20.0, barY)
      .stroke(color: primary, width: 1.0, alpha: 0.3);
  _drawCross(target, -hw + marginX + 10.0, barY, 3.0, primary, 0.5);
  _drawCross(target, -hw + marginX + 30.0, barY, 3.0, primary, 0.5);
  _drawCross(target, hw - marginX - 10.0, barY, 3.0, primary, 0.5);
  target.circle(0.0, barY, 2.0).fill(color: secondary, alpha: 0.8);
}

void _drawCornerBrackets(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;
  final seed = context.seed;

  final arm = math.min(hw, hh) * 0.08;
  const inset = 6.0;
  final corners = [
    [-hw + marginX, -hh + marginY, 1.0, 1.0],
    [hw - marginX, -hh + marginY, -1.0, 1.0],
    [-hw + marginX, hh - marginY, 1.0, -1.0],
    [hw - marginX, hh - marginY, -1.0, -1.0],
  ];

  for (var index = 0; index < corners.length; index++) {
    final c = corners[index];
    final cx = c[0];
    final cy = c[1];
    final sx = c[2];
    final sy = c[3];

    target
        .moveTo(cx + sx * arm, cy)
        .lineTo(cx, cy)
        .lineTo(cx, cy + sy * arm)
        .stroke(color: primary, width: 2.0, alpha: 0.55);

    target
        .moveTo(cx + sx * (arm + inset), cy + sy * inset)
        .lineTo(cx + sx * inset, cy + sy * inset)
        .lineTo(cx + sx * inset, cy + sy * (arm + inset))
        .stroke(color: primary, width: 1.0, alpha: 0.25);

    if (index % 2 == 0) {
      target
          .rect(cx + sx * arm * 0.4 - 2.0, cy + sy * arm * 0.4 - 2.0, 4.0, 4.0)
          .fill(color: secondary, alpha: 0.6);
    }
  }

  final rulerY = hh - marginY + inset;
  target
      .moveTo(-hw + marginX + arm + 12.0, rulerY)
      .lineTo(hw - marginX - arm - 12.0, rulerY)
      .stroke(color: primary, width: 1.0, alpha: 0.3);
  const ticks = 24;
  final span = (hw - marginX - arm - 12.0) * 2.0;
  for (var i = 0; i <= ticks; i++) {
    final x = -hw + marginX + arm + 12.0 + (span * i) / ticks;
    final isLong = i % 6 == 0;
    target
        .moveTo(x, rulerY)
        .lineTo(x, rulerY - (isLong ? 8.0 : 4.0))
        .stroke(
          color: isLong ? secondary : primary,
          width: 1.0,
          alpha: isLong ? 0.55 : 0.3,
        );
  }

  for (var i = 0; i < 5; i++) {
    final y = -hh + marginY + arm + 14.0 + i * ((hh - marginY - arm - 14.0) * 2.0) / 5.0;
    target.circle(-hw + marginX - 4.0, y, 1.5).fill(color: primary, alpha: 0.35);
    target.circle(hw - marginX + 4.0, y + (seed % 7), 1.5).fill(color: primary, alpha: 0.35);
  }
}

void _drawMarqueeStrips(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;

  final left = -hw + marginX;
  final right = hw - marginX;
  for (final direction in [-1.0, 1.0]) {
    final stripY = hh - marginY;
    final y = direction * stripY;
    target
        .moveTo(left, y)
        .lineTo(right, y)
        .stroke(color: primary, width: 2.0, alpha: 0.45);
    target
        .moveTo(left, y + direction * 6.0)
        .lineTo(right, y + direction * 6.0)
        .stroke(color: primary, width: 1.0, alpha: 0.2);

    target.rect(left, y - 3.0, 14.0, 6.0).fill(color: secondary, alpha: 0.55);
    target.rect(right - 14.0, y - 3.0, 14.0, 6.0).fill(color: secondary, alpha: 0.55);

    const ticks = 18;
    for (var i = 1; i < ticks; i++) {
      final x = left + ((right - left) * i) / ticks;
      if (i % 3 == 0) {
        target
            .moveTo(x, y)
            .lineTo(x, y + direction * 6.0)
            .stroke(color: primary, width: 1.0, alpha: 0.35);
      }
    }
  }

  _drawCross(target, 0.0, -hh + marginY, 4.0, primary, 0.5);
  target
      .moveTo(-6.0, hh - marginY - 14.0)
      .lineTo(0.0, hh - marginY - 8.0)
      .lineTo(6.0, hh - marginY - 14.0)
      .stroke(color: secondary, width: 1.0, alpha: 0.6);
}

void _drawDiagonalCorners(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;

  final corner = math.min(hw, hh) * 0.12;
  final corners = [
    [-hw + marginX, -hh + marginY, 1.0, 1.0],
    [hw - marginX, -hh + marginY, -1.0, 1.0],
    [-hw + marginX, hh - marginY, 1.0, -1.0],
    [hw - marginX, hh - marginY, -1.0, -1.0],
  ];

  for (var index = 0; index < corners.length; index++) {
    final c = corners[index];
    final cx = c[0];
    final cy = c[1];
    final sx = c[2];
    final sy = c[3];

    target
        .moveTo(cx + sx * corner, cy)
        .lineTo(cx, cy)
        .lineTo(cx, cy + sy * corner)
        .lineTo(cx + sx * corner, cy)
        .stroke(color: primary, width: 1.5, alpha: 0.5);

    target
        .moveTo(cx + sx * corner * 0.55, cy)
        .lineTo(cx, cy + sy * corner * 0.55)
        .stroke(
          color: index % 2 == 0 ? secondary : primary,
          width: 1.0,
          alpha: 0.4,
        );

    target
        .moveTo(cx + sx * corner * 0.3, cy)
        .lineTo(cx, cy + sy * corner * 0.3)
        .stroke(color: primary, width: 1.0, alpha: 0.25);
  }

  final barY = hh - marginY - 12.0;
  target
      .moveTo(-hw + marginX + corner + 10.0, barY)
      .lineTo(hw - marginX - corner - 10.0, barY)
      .stroke(color: primary, width: 1.0, alpha: 0.3);

  for (var i = 0; i < 5; i++) {
    final x = -hw + marginX + corner + 30.0 + i * 26.0;
    final s = i == 2 ? 5.0 : 3.0;
    target
        .moveTo(x, barY - s)
        .lineTo(x + s, barY)
        .lineTo(x, barY + s)
        .lineTo(x - s, barY)
        .lineTo(x, barY - s)
        .stroke(color: i == 2 ? secondary : primary, width: 1.0, alpha: 0.55);
  }
}

void _drawDottedColumns(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;

  const rows = 14;
  for (var i = 0; i < rows; i++) {
    final y = -hh + marginY + 10.0 + i * ((hh - marginY - 10.0) * 2.0) / (rows - 1);
    final strong = i % 4 == 0;
    target
        .circle(-hw + marginX, y, strong ? 2.4 : 1.4)
        .fill(color: strong ? secondary : primary, alpha: strong ? 0.6 : 0.3);
    target
        .circle(hw - marginX, y, strong ? 2.4 : 1.4)
        .fill(color: strong ? secondary : primary, alpha: strong ? 0.6 : 0.3);
  }

  target
      .moveTo(-18.0, 0.0)
      .lineTo(18.0, 0.0)
      .stroke(color: primary, width: 1.0, alpha: 0.22);
  target
      .moveTo(0.0, -18.0)
      .lineTo(0.0, 18.0)
      .stroke(color: primary, width: 1.0, alpha: 0.22);
  target.circle(0.0, 0.0, 6.0).stroke(color: primary, width: 1.0, alpha: 0.3);

  final barY = hh - marginY - 8.0;
  target
      .moveTo(-hw + marginX + 16.0, barY)
      .lineTo(hw - marginX - 16.0, barY)
      .stroke(color: primary, width: 1.0, alpha: 0.3);
  _drawCross(target, -hw + marginX + 8.0, barY, 3.0, primary, 0.5);
  _drawCross(target, hw - marginX - 8.0, barY, 3.0, primary, 0.5);
}

void _drawDoubleFrame(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;

  final left = -hw + marginX;
  final right = hw - marginX;
  final top = -hh + marginY;
  final bottom = hh - marginY;
  final gapX = (right - left) * 0.18;
  final gapY = (bottom - top) * 0.22;
  final cx = (left + right) / 2.0;
  final cy = (top + bottom) / 2.0;

  target.moveTo(left, top).lineTo(cx - gapX / 2.0, top).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(cx + gapX / 2.0, top).lineTo(right, top).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(left, bottom).lineTo(cx - gapX / 2.0, bottom).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(cx + gapX / 2.0, bottom).lineTo(right, bottom).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(left, top).lineTo(left, cy - gapY / 2.0).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(left, cy + gapY / 2.0).lineTo(left, bottom).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(right, top).lineTo(right, cy - gapY / 2.0).stroke(color: primary, width: 2.0, alpha: 0.45);
  target.moveTo(right, cy + gapY / 2.0).lineTo(right, bottom).stroke(color: primary, width: 2.0, alpha: 0.45);

  const inset = 7.0;
  target
      .rect(left + inset, top + inset, right - left - inset * 2.0, bottom - top - inset * 2.0)
      .stroke(color: primary, width: 1.0, alpha: 0.18);

  final corners = [
    [left, top],
    [right, top],
    [left, bottom],
    [right, bottom],
  ];
  for (var i = 0; i < corners.length; i++) {
    final pt = corners[i];
    target.rect(pt[0] - 3.0, pt[1] - 3.0, 6.0, 6.0).fill(
          color: i % 2 == 0 ? secondary : primary,
          alpha: 0.6,
        );
  }

  target.moveTo(cx - 5.0, top).lineTo(cx + 5.0, top).stroke(color: secondary, width: 3.0, alpha: 0.5);
  target.moveTo(cx - 5.0, bottom).lineTo(cx + 5.0, bottom).stroke(color: secondary, width: 3.0, alpha: 0.5);
}

void _drawRulerFrame(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;

  final left = -hw + marginX;
  final right = hw - marginX;
  final top = -hh + marginY;
  final bottom = hh - marginY;
  const xTicks = 32;
  const yTicks = 18;

  for (var i = 0; i <= xTicks; i++) {
    final x = left + ((right - left) * i) / xTicks;
    final major = i % 8 == 0;
    final mid = i % 4 == 0;
    final len = major ? 12.0 : (mid ? 7.0 : 4.0);
    final color = major ? secondary : primary;
    target.moveTo(x, top).lineTo(x, top + len).stroke(color: color, width: 1.0, alpha: major ? 0.55 : 0.32);
    target.moveTo(x, bottom).lineTo(x, bottom - len).stroke(color: color, width: 1.0, alpha: major ? 0.55 : 0.32);
  }

  for (var i = 0; i <= yTicks; i++) {
    final y = top + ((bottom - top) * i) / yTicks;
    final major = i % 6 == 0;
    final len = major ? 12.0 : (i % 3 == 0 ? 7.0 : 4.0);
    final color = major ? secondary : primary;
    target.moveTo(left, y).lineTo(left + len, y).stroke(color: color, width: 1.0, alpha: major ? 0.55 : 0.32);
    target.moveTo(right, y).lineTo(right - len, y).stroke(color: color, width: 1.0, alpha: major ? 0.55 : 0.32);
  }

  target.circle(0.0, 0.0, 10.0).stroke(color: primary, width: 1.0, alpha: 0.25);
  target.circle(0.0, 0.0, 3.0).fill(color: secondary, alpha: 0.4);
}

void _drawArcGauge(_FrameContext context) {
  final target = context.target;
  final hw = context.hw;
  final hh = context.hh;
  final marginX = context.marginX;
  final marginY = context.marginY;
  final primary = context.primary;
  final secondary = context.secondary;
  final seed = context.seed;

  final arcR = math.min(hw, hh) * 0.11;
  final corners = [
    [-hw + marginX, -hh + marginY, 0.0, math.pi / 2.0],
    [hw - marginX, -hh + marginY, math.pi / 2.0, math.pi],
    [hw - marginX, hh - marginY, math.pi, math.pi * 1.5],
    [-hw + marginX, hh - marginY, math.pi * 1.5, math.pi * 2.0],
  ];

  for (var i = 0; i < corners.length; i++) {
    final c = corners[i];
    final cx = c[0];
    final cy = c[1];
    final start = c[2];
    final end = c[3];

    target.arc(cx, cy, arcR, start, end).stroke(color: primary, width: 2.0, alpha: 0.5);
    target.arc(cx, cy, arcR * 0.72, start, end).stroke(color: primary, width: 1.0, alpha: 0.25);
    final mid = (start + end) / 2.0;
    target
        .circle(cx + math.cos(mid) * arcR, cy + math.sin(mid) * arcR, 2.0)
        .fill(color: i % 2 == 0 ? secondary : primary, alpha: 0.6);
  }

  target.circle(0.0, -hh + marginY, 2.0).fill(color: primary, alpha: 0.45);
  target.circle(-hw + marginX, 0.0, 2.0).fill(color: primary, alpha: 0.45);
  target.circle(hw - marginX, 0.0, 2.0).fill(color: primary, alpha: 0.45);

  final gaugeY = hh - marginY + arcR * 0.4;
  final gaugeR = math.min(hw, hh) * 0.16;
  target.arc(0.0, gaugeY, gaugeR, math.pi, math.pi * 2.0).stroke(color: primary, width: 1.5, alpha: 0.4);

  for (var i = 0; i <= 8; i++) {
    final angle = math.pi + (i / 8.0) * math.pi;
    target
        .moveTo(math.cos(angle) * (gaugeR - 5.0), gaugeY + math.sin(angle) * (gaugeR - 5.0))
        .lineTo(math.cos(angle) * gaugeR, gaugeY + math.sin(angle) * gaugeR)
        .stroke(color: i % 4 == 0 ? secondary : primary, width: 1.0, alpha: 0.45);
  }

  final needle = math.pi + (((seed % 100) / 100.0) * math.pi);
  target
      .moveTo(0.0, gaugeY)
      .lineTo(math.cos(needle) * (gaugeR - 8.0), gaugeY + math.sin(needle) * (gaugeR - 8.0))
      .stroke(color: secondary, width: 2.0, alpha: 0.6);
  target.circle(0.0, gaugeY, 2.5).fill(color: primary, alpha: 0.7);
}

void drawSonnetBackgroundMgHud(SonnetBackgroundMgOptions options) {
  final context = _withFrame(options);
  switch (options.variant % sonnetBackgroundMgVariantCount) {
    case 1:
      _drawCornerBrackets(context);
    case 2:
      _drawMarqueeStrips(context);
    case 3:
      _drawDiagonalCorners(context);
    case 4:
      _drawDottedColumns(context);
    case 5:
      _drawDoubleFrame(context);
    case 6:
      _drawRulerFrame(context);
    case 7:
      _drawArcGauge(context);
    default:
      _drawClassicCross(context);
  }
}
