import 'package:flutter/material.dart';

import 'sonnet_animated_graphics.dart';
import 'sonnet_random.dart';

const sonnetFixedGeoVariantCount = 8;

const List<String> sonnetFixedGeoVariants = [
  'classic-blocks',
  'twin-pillars',
  'disc-ring',
  'diamond-pair',
  'stripe-stack',
  'corner-els',
  'twin-wedges',
  'cross-ring',
];

class SonnetFixedGeoOptions {
  const SonnetFixedGeoOptions({
    required this.variant,
    required this.radius,
    required this.seed,
    required this.primary,
    required this.secondary,
  });

  final int variant;
  final double radius;
  final int seed;
  final Color primary;
  final Color secondary;
}

int resolveSonnetFixedGeoVariant(int seed) =>
    mixSonnetSeed(seed, 0x85ebca6b) % sonnetFixedGeoVariantCount;

class _VariantContext {
  _VariantContext({
    required this.options,
    required this.geo,
    required this.parts,
    required this.accent,
  });

  final SonnetFixedGeoOptions options;
  final AnimatedGraphics geo;
  final List<AnimatedGraphics> parts;
  final Color accent;

  double get radius => options.radius;
  Color get primary => options.primary;
  int get seed => options.seed;
}

AnimatedGraphics _drawHatching(
  Color primary,
  double x,
  double y,
  double w,
  double h,
  double spacing,
) {
  final hatch = AnimatedGraphics();
  for (var i = -w; i < w + h; i += spacing) {
    hatch
        .moveTo(x + i, y)
        .lineTo(x + i + h, y + h)
        .stroke(color: primary, width: 1.0, alpha: 0.15);
  }
  return hatch;
}

void _addHatch(
  _VariantContext context,
  double x,
  double y,
  double w,
  double h, [
  double spacing = 6.0,
]) {
  context.parts.add(
    _drawHatching(context.primary, x, y, w, h, spacing),
  );
}

void _drawClassicBlocks(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;

  geo
      .rect(-r * 0.4, -r * 0.2, r * 0.6, r * 0.15)
      .fill(color: primary, alpha: 0.7);
  geo
      .rect(-r * 0.1, r * 0.1, r * 0.5, r * 0.3)
      .stroke(color: primary, width: 2.0, alpha: 0.6);
  _addHatch(context, -r * 0.3, -r * 0.4, r * 0.4, r * 0.25);
}

void _drawTwinPillars(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;

  geo
      .rect(-r * 0.34, -r * 0.28, r * 0.12, r * 0.56)
      .fill(color: accent, alpha: 0.65);
  geo
      .rect(-r * 0.34 + r * 0.035, -r * 0.28 + r * 0.035, r * 0.05, r * 0.49)
      .fill(color: primary, alpha: 0.35);
  geo
      .rect(r * 0.06, -r * 0.34, r * 0.28, r * 0.68)
      .stroke(color: primary, width: 2.0, alpha: 0.6);
  geo
      .rect(r * 0.06 + r * 0.04, -r * 0.34 + r * 0.04, r * 0.2, r * 0.6)
      .stroke(color: primary, width: 1.0, alpha: 0.3);
  _addHatch(context, -r * 0.14, -r * 0.2, r * 0.12, r * 0.4, 5.0);
}

void _drawDiscRing(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;

  geo.circle(-r * 0.2, r * 0.12, r * 0.15).fill(color: accent, alpha: 0.7);
  geo.circle(-r * 0.2, r * 0.12, r * 0.06).fill(color: primary, alpha: 0.5);
  geo.circle(r * 0.14, -r * 0.06, r * 0.3).stroke(color: primary, width: 2.0, alpha: 0.6);
  geo.circle(r * 0.14, -r * 0.06, r * 0.22).stroke(color: primary, width: 1.0, alpha: 0.3);
  _addHatch(context, r * 0.02, -r * 0.14, r * 0.24, r * 0.16, 5.0);
}

void _drawDiamondPair(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;
  final seed = context.seed;

  final direction = seed % 2 == 0 ? 1.0 : -1.0;
  final dr = r * 0.3;
  final cx = -r * 0.08 * direction;

  geo
      .moveTo(cx, -dr)
      .lineTo(cx + dr, 0.0)
      .lineTo(cx, dr)
      .lineTo(cx - dr, 0.0)
      .lineTo(cx, -dr)
      .stroke(color: primary, width: 2.0, alpha: 0.6);
  geo
      .moveTo(cx, -dr * 0.7)
      .lineTo(cx + dr * 0.7, 0.0)
      .lineTo(cx, dr * 0.7)
      .lineTo(cx - dr * 0.7, 0.0)
      .lineTo(cx, -dr * 0.7)
      .stroke(color: primary, width: 1.0, alpha: 0.3);

  final sr = r * 0.11;
  final sx = r * 0.3 * direction;
  final sy = -r * 0.2;
  geo
      .moveTo(sx, sy - sr)
      .lineTo(sx + sr, sy)
      .lineTo(sx, sy + sr)
      .lineTo(sx - sr, sy)
      .lineTo(sx, sy - sr)
      .fill(color: accent, alpha: 0.7);

  _addHatch(context, sx - sr * 0.8, r * 0.16, sr * 1.6, sr * 1.2, 4.0);
}

void _drawStripeStack(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;
  final seed = context.seed;

  final direction = seed % 2 == 0 ? 1.0 : -1.0;
  geo
      .rect(-r * 0.36 * direction - r * 0.2, -r * 0.26, r * 0.56, r * 0.09)
      .fill(color: accent, alpha: 0.7);
  geo
      .rect(-r * 0.28, -r * 0.06, r * 0.56, r * 0.16)
      .stroke(color: primary, width: 2.0, alpha: 0.6);
  geo
      .rect(-r * 0.2 * direction, r * 0.2, r * 0.4, r * 0.045)
      .fill(color: primary, alpha: 0.5);
  _addHatch(context, r * 0.26 * direction, -r * 0.3, r * 0.12, r * 0.6, 5.0);
}

void _drawCornerEls(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;
  final seed = context.seed;

  final direction = seed % 2 == 0 ? 1.0 : -1.0;
  final arm = r * 0.24;
  final thick = r * 0.07;

  final x1 = -r * 0.3 * direction;
  final y1 = -r * 0.24;
  geo
      .rect(x1 - (direction < 0 ? arm : 0.0), y1, arm, thick)
      .fill(color: accent, alpha: 0.7);
  geo
      .rect(direction < 0 ? x1 - arm : x1, y1, thick, arm)
      .fill(color: accent, alpha: 0.7);

  final x2 = r * 0.3 * direction;
  final y2 = r * 0.24;
  geo
      .rect(direction < 0 ? x2 : x2 - arm, y2 - thick, arm, thick)
      .fill(color: primary, alpha: 0.55);
  geo
      .rect(
        direction < 0 ? x2 + arm - thick : x2 - thick,
        y2 - arm,
        thick,
        arm,
      )
      .fill(color: primary, alpha: 0.55);

  geo
      .rect(-r * 0.13, -r * 0.13, r * 0.26, r * 0.26)
      .stroke(color: primary, width: 2.0, alpha: 0.6);
  _addHatch(context, -r * 0.09 * direction, r * 0.02, r * 0.16, r * 0.1, 4.0);
}

void _drawTwinWedges(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;
  final seed = context.seed;

  final direction = seed % 2 == 0 ? 1.0 : -1.0;
  final wx = -r * 0.14 * direction;
  geo
      .moveTo(wx, -r * 0.3)
      .lineTo(wx + r * 0.24, r * 0.02)
      .lineTo(wx - r * 0.24, r * 0.02)
      .lineTo(wx, -r * 0.3)
      .fill(color: accent, alpha: 0.6);

  final hx = r * 0.16 * direction;
  geo
      .moveTo(hx, r * 0.3)
      .lineTo(hx + r * 0.24, -r * 0.02)
      .lineTo(hx - r * 0.24, -r * 0.02)
      .lineTo(hx, r * 0.3)
      .stroke(color: primary, width: 2.0, alpha: 0.6);
  geo
      .moveTo(hx, r * 0.2)
      .lineTo(hx + r * 0.15, 0.0)
      .lineTo(hx - r * 0.15, 0.0)
      .lineTo(hx, r * 0.2)
      .stroke(color: primary, width: 1.0, alpha: 0.3);

  _addHatch(
    context,
    -r * 0.3 * direction - r * 0.05,
    r * 0.1,
    r * 0.2,
    r * 0.18,
    5.0,
  );
}

void _drawCrossRing(_VariantContext context) {
  final geo = context.geo;
  final r = context.radius;
  final primary = context.primary;
  final accent = context.accent;
  final seed = context.seed;

  final cx = (seed % 3 - 1) * r * 0.08;
  final arm = r * 0.17;
  final thick = r * 0.075;

  geo.rect(cx - arm, -thick / 2.0, arm * 2.0, thick).fill(color: accent, alpha: 0.7);
  geo.rect(cx - thick / 2.0, -arm, thick, arm * 2.0).fill(color: accent, alpha: 0.7);
  geo.circle(cx, 0.0, r * 0.3).stroke(color: primary, width: 2.0, alpha: 0.6);
  geo.circle(cx, 0.0, r * 0.36).stroke(color: primary, width: 1.0, alpha: 0.25);
  _addHatch(context, cx + r * 0.18, r * 0.14, r * 0.16, r * 0.16, 4.0);
}

List<AnimatedGraphics> buildSonnetFixedGeo(SonnetFixedGeoOptions options) {
  final geo = AnimatedGraphics();
  final context = _VariantContext(
    options: options,
    geo: geo,
    parts: [geo],
    accent: options.seed % 2 == 0 ? options.secondary : options.primary,
  );

  switch (options.variant % sonnetFixedGeoVariantCount) {
    case 1:
      _drawTwinPillars(context);
    case 2:
      _drawDiscRing(context);
    case 3:
      _drawDiamondPair(context);
    case 4:
      _drawStripeStack(context);
    case 5:
      _drawCornerEls(context);
    case 6:
      _drawTwinWedges(context);
    case 7:
      _drawCrossRing(context);
    default:
      _drawClassicBlocks(context);
  }
  return context.parts;
}
