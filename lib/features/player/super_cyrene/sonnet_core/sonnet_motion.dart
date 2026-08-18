import 'dart:math' as math;
import 'sonnet_types.dart';

double clamp01(double value) => value.clamp(0.0, 1.0);

double _cubicCoordinate(double point1, double point2, double time) {
  final inverse = 1.0 - time;
  return 3.0 * inverse * inverse * time * point1 +
      3.0 * inverse * time * time * point2 +
      time * time * time;
}

double resolveCubicBezier(
  double x1,
  double y1,
  double x2,
  double y2,
  double value,
) {
  final target = clamp01(value);
  if (target == 0.0 || target == 1.0) return target;
  var low = 0.0;
  var high = 1.0;
  var parameter = target;
  for (var iteration = 0; iteration < 12; iteration++) {
    final x = _cubicCoordinate(x1, x2, parameter);
    if (x < target) {
      low = parameter;
    } else {
      high = parameter;
    }
    parameter = (low + high) / 2.0;
  }
  return _cubicCoordinate(y1, y2, parameter);
}

double easeSonnetInOut(double value) =>
    resolveCubicBezier(0.65, 0.0, 0.35, 1.0, value);

double easeSonnetEnter(double value) =>
    resolveCubicBezier(0.22, 1.0, 0.36, 1.0, value);

double easeSonnetExpoOut(double value) =>
    value == 1.0 ? 1.0 : 1.0 - math.pow(2.0, -10.0 * value).toDouble();

double easeSonnetElasticOut(double value) {
  const p = 0.3;
  return math.pow(2.0, -10.0 * value) *
          math.sin((value - p / 4.0) * (2.0 * math.pi) / p) +
      1.0;
}

double resolveShotProgress(SonnetShot shot, double time) =>
    clamp01((time - shot.startTime) /
        math.max(shot.endTime - shot.startTime, 0.001));

double resolveSegmentProgress(
  double startTime,
  double endTime,
  double time,
) =>
    easeSonnetExpoOut(
      clamp01((time - startTime) / math.max(endTime - startTime, 0.08)),
    );

double resolveSonnetSegmentDepth(
  SonnetSegmentRole role, [
  double Function()? random,
]) {
  if (role != SonnetSegmentRole.decoration) return 0.0;
  final r = random ?? math.Random().nextDouble;
  return r() > 0.5 ? 0.5 + r() * 0.8 : -0.5 - r() * 0.8;
}

({double x, double y}) resolveSonnetSegmentNormalOffset(
  SonnetSegmentRole role,
  String layoutDirection,
  double rotation,
  double fontSize,
  double randomValue,
) {
  if (role != SonnetSegmentRole.support) return (x: 0.0, y: 0.0);
  final distance =
      (clamp01(randomValue) * 2.0 - 1.0) * fontSize * 0.3;
  final normalAngle =
      rotation + (layoutDirection == 'vertical' ? 0.0 : math.pi / 2.0);
  return (
    x: math.cos(normalAngle) * distance,
    y: math.sin(normalAngle) * distance,
  );
}

class SonnetShotMotionFrame {
  const SonnetShotMotionFrame({
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
  });

  final double x;
  final double y;
  final double scale;
  final double rotation;
}

const _kSmoothingSamples = [
  (offset: -1.0, weight: 1.0),
  (offset: -0.5, weight: 4.0),
  (offset: 0.0, weight: 6.0),
  (offset: 0.5, weight: 4.0),
  (offset: 1.0, weight: 1.0),
];

({double x, double y}) resolveSonnetSmoothedCameraFocus(
  double time,
  double startTime,
  double endTime,
  ({double x, double y}) Function(double sampleTime) sampleFocus, {
  double smoothingWindow = 0.12,
  double maxBlendDistance = 96.0,
}) {
  final safeStart = math.min(startTime, endTime);
  final safeEnd = math.max(startTime, endTime);
  final radius = math.max(0.0, smoothingWindow);
  if (radius == 0.0 || safeStart == safeEnd) {
    return sampleFocus(time.clamp(safeStart, safeEnd));
  }

  final samples = _kSmoothingSamples.map((s) {
    final sampleTime =
        (time + s.offset * radius).clamp(safeStart, safeEnd);
    return (point: sampleFocus(sampleTime), weight: s.weight);
  }).toList();

  final center = samples[2].point;
  final maxDistSq = maxBlendDistance * maxBlendDistance;
  var sumX = 0.0;
  var sumY = 0.0;
  var totalWeight = 0.0;

  for (final s in samples) {
    final distSq = (s.point.x - center.x) * (s.point.x - center.x) +
        (s.point.y - center.y) * (s.point.y - center.y);
    if (distSq > maxDistSq) continue;
    sumX += s.point.x * s.weight;
    sumY += s.point.y * s.weight;
    totalWeight += s.weight;
  }

  return (
    x: totalWeight > 0 ? sumX / totalWeight : center.x,
    y: totalWeight > 0 ? sumY / totalWeight : center.y,
  );
}

List<double> resolveSonnetFocusWeights(
  List<({double startTime, double endTime})> ranges,
  double time, [
  double sigma = 0.35,
]) {
  if (ranges.isEmpty) return const [];
  final safeSigma = math.max(0.001, sigma);
  final logWeights = ranges.map((range) {
    final startTime = math.min(range.startTime, range.endTime);
    final endTime = math.max(range.startTime, range.endTime);
    final distance = time < startTime
        ? startTime - time
        : (time > endTime ? time - endTime : 0.0);
    return -(distance * distance) / (2.0 * safeSigma * safeSigma);
  }).toList();

  final maxLogWeight = logWeights.reduce(math.max);
  final weights = logWeights.map((w) => math.exp(w - maxLogWeight)).toList();
  final totalWeight = weights.fold<double>(0.0, (sum, w) => sum + w);
  return weights.map((w) => totalWeight > 0 ? w / totalWeight : 0.0).toList();
}

double resolveShotPathProgress(SonnetShotKind kind, double progress) {
  final linear = clamp01(progress);
  if (kind == SonnetShotKind.trackingRibbon ||
      kind == SonnetShotKind.fragmentCollage ||
      kind == SonnetShotKind.quietTableau ||
      kind == SonnetShotKind.posterBlocks) {
    return linear * 0.55 + easeSonnetInOut(linear) * 0.45;
  }
  if (linear < 0.18) return easeSonnetExpoOut(linear / 0.18) * 0.22;
  if (linear < 0.78) return 0.22 + ((linear - 0.18) / 0.6) * 0.56;
  final settle = (linear - 0.78) / 0.22;
  return 0.78 + (1.0 - (1.0 - settle) * (1.0 - settle)) * 0.22;
}

SonnetShotMotionFrame resolveShotMotionFrame(
  SonnetShotKind kind,
  double progress,
) {
  final linear = clamp01(progress);
  final eased = resolveShotPathProgress(kind, linear);

  return switch (kind) {
    SonnetShotKind.editorialColumn => SonnetShotMotionFrame(
        x: -0.055 + eased * 0.095,
        y: 0.025 - eased * 0.04,
        scale: 0.98 + eased * 0.07,
        rotation: -0.006 + eased * 0.01,
      ),
    SonnetShotKind.typeImpact => SonnetShotMotionFrame(
        x: -0.035 + eased * 0.07,
        y: 0.018 - eased * 0.028,
        scale: 1.0 +
            (1.0 - easeSonnetExpoOut(math.min(linear / 0.18, 1.0))) * 0.22 +
            eased * 0.08,
        rotation: -0.01 + eased * 0.016,
      ),
    SonnetShotKind.fragmentCollage => SonnetShotMotionFrame(
        x: -0.045 + eased * 0.085,
        y: 0.028 - math.sin(eased * math.pi) * 0.055,
        scale: 0.97 + eased * 0.09,
        rotation: -0.014 + eased * 0.028,
      ),
    SonnetShotKind.trackingRibbon => SonnetShotMotionFrame(
        x: -0.16 + eased * 0.28,
        y: 0.05 - eased * 0.085,
        scale: 0.98 + eased * 0.07,
        rotation: 0.008 - eased * 0.014,
      ),
    SonnetShotKind.maskReveal => SonnetShotMotionFrame(
        x: 0.035 - eased * 0.065,
        y: 0.1 - eased * 0.135,
        scale: 0.96 + eased * 0.12,
        rotation: -0.006 + eased * 0.009,
      ),
    SonnetShotKind.posterBlocks => SonnetShotMotionFrame(
        x: -0.012 + eased * 0.024,
        y: 0.008 - eased * 0.016,
        scale: 0.99 + eased * 0.025,
        rotation: -0.0015 + eased * 0.003,
      ),
    SonnetShotKind.quietTableau => SonnetShotMotionFrame(
        x: -0.022 + eased * 0.04,
        y: 0.014 - eased * 0.025,
        scale: 1.0 + eased * 0.028,
        rotation: -0.002 + eased * 0.003,
      ),
  };
}

const sonnetCameraBreathMaxOffset = 0.006;
const sonnetCameraBreathMaxScale = 0.002;
const sonnetCameraBreathMaxRotation = 0.0015;

SonnetShotMotionFrame resolveSonnetCameraBreath(
  double time, [
  double phase = 0.0,
]) {
  final tau = time * math.pi * 2.0;
  return SonnetShotMotionFrame(
    x: (math.sin(tau * 0.13 + phase) * 0.65 +
            math.sin(tau * 0.31 + phase * 1.7) * 0.35) *
        sonnetCameraBreathMaxOffset,
    y: (math.cos(tau * 0.11 + phase * 2.3) * 0.65 +
            math.sin(tau * 0.29 + phase * 0.9) * 0.35) *
        sonnetCameraBreathMaxOffset,
    scale: math.sin(tau * 0.09 + phase * 1.3) * sonnetCameraBreathMaxScale,
    rotation:
        math.sin(tau * 0.07 + phase * 2.9) * sonnetCameraBreathMaxRotation,
  );
}

double resolveSonnetBreathWeight(
  double time,
  double revealDoneTime, [
  double rampDuration = 1.2,
]) {
  if (rampDuration <= 0.0) return time >= revealDoneTime ? 1.0 : 0.0;
  return easeSonnetInOut(
    clamp01((time - revealDoneTime) / rampDuration),
  );
}

({double x, double y, double rotation}) resolveTimelineShake(
  double time,
  double intensity,
) {
  if (intensity <= 0.0) return (x: 0.0, y: 0.0, rotation: 0.0);
  final shakeX = math.sin(time * 123.456) * math.cos(time * 789.123);
  final shakeY = math.cos(time * 345.678) * math.sin(time * 901.234);
  final shakeRot = math.sin(time * 567.890);
  return (
    x: shakeX * 0.02 * intensity,
    y: shakeY * 0.02 * intensity,
    rotation: shakeRot * 0.005 * intensity,
  );
}
