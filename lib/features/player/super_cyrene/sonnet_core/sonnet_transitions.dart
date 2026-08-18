import 'dart:math' as math;
import 'sonnet_motion.dart';
import 'sonnet_types.dart';

class SonnetTransitionEffectFrame {
  const SonnetTransitionEffectFrame({
    required this.alpha,
    required this.blur,
    required this.glitchSliceCount,
    required this.glitchOffset,
    required this.zoomOffset,
    required this.rotationOffset,
    required this.active,
  });

  final double alpha;
  final double blur;
  final int glitchSliceCount;
  final double glitchOffset;
  final double zoomOffset;
  final double rotationOffset;
  final bool active;

  static const neutral = SonnetTransitionEffectFrame(
    alpha: 1.0,
    blur: 0.0,
    glitchSliceCount: 0,
    glitchOffset: 0.0,
    zoomOffset: 0.0,
    rotationOffset: 0.0,
    active: false,
  );
}

SonnetTransitionEffectFrame resolveSonnetExitTransitionFrame(
  SonnetTransitionKind kind,
  double progress,
) {
  final linear = clamp01(progress);
  if (linear <= 0.0) return SonnetTransitionEffectFrame.neutral;

  final eased = easeSonnetInOut(linear);
  final pulse = math.sin(linear * math.pi);

  return switch (kind) {
    SonnetTransitionKind.fastBlur => SonnetTransitionEffectFrame(
        alpha: 1.0 - eased,
        blur: 0.0 + eased * 14.0,
        glitchSliceCount: 0,
        glitchOffset: 0.0,
        zoomOffset: 0.0 - eased * 0.06,
        rotationOffset: 0.0,
        active: true,
      ),
    SonnetTransitionKind.monoGlitch => SonnetTransitionEffectFrame(
        alpha: 1.0 - eased * 0.85,
        blur: pulse * 4.0,
        glitchSliceCount: (eased * 10.0).floor(),
        glitchOffset: pulse * 28.0,
        zoomOffset: 0.0 + pulse * 0.035,
        rotationOffset: (linear * 13.0).floor() % 2 == 0
            ? pulse * 0.02
            : -pulse * 0.02,
        active: true,
      ),
    SonnetTransitionKind.cameraPull => SonnetTransitionEffectFrame(
        alpha: 1.0 - eased,
        blur: eased * 6.0,
        glitchSliceCount: 0,
        glitchOffset: 0.0,
        zoomOffset: 0.0 - eased * 0.22,
        rotationOffset: 0.0 - eased * 0.045,
        active: true,
      ),
  };
}

SonnetTransitionEffectFrame resolveSonnetEnterTransitionFrame(
  SonnetTransitionKind kind,
  double progress,
) {
  final linear = clamp01(progress);
  if (linear >= 1.0) return SonnetTransitionEffectFrame.neutral;

  final remaining = 1.0 - linear;
  final eased = easeSonnetInOut(remaining);
  final pulse = math.sin(remaining * math.pi);

  return switch (kind) {
    SonnetTransitionKind.fastBlur => SonnetTransitionEffectFrame(
        alpha: linear,
        blur: eased * 14.0,
        glitchSliceCount: 0,
        glitchOffset: 0.0,
        zoomOffset: 0.0 + eased * 0.06,
        rotationOffset: 0.0,
        active: true,
      ),
    SonnetTransitionKind.monoGlitch => SonnetTransitionEffectFrame(
        alpha: 0.15 + linear * 0.85,
        blur: pulse * 4.0,
        glitchSliceCount: (eased * 8.0).floor(),
        glitchOffset: pulse * 22.0,
        zoomOffset: 0.0 - pulse * 0.025,
        rotationOffset: (remaining * 11.0).floor() % 2 == 0
            ? pulse * 0.015
            : -pulse * 0.015,
        active: true,
      ),
    SonnetTransitionKind.cameraPull => SonnetTransitionEffectFrame(
        alpha: linear,
        blur: eased * 6.0,
        glitchSliceCount: 0,
        glitchOffset: 0.0,
        zoomOffset: 0.0 + eased * 0.18,
        rotationOffset: 0.0 + eased * 0.035,
        active: true,
      ),
  };
}

SonnetTransitionEffectFrame resolveSonnetShotTransitionFrame(
  SonnetShot shot,
  double time, {
  double leadIn = 0.18,
}) {
  if (time < shot.startTime) {
    final timeBeforeStart = shot.startTime - time;
    if (timeBeforeStart <= leadIn) {
      final progress =
          clamp01(1.0 - timeBeforeStart / math.max(0.001, leadIn));
      return resolveSonnetEnterTransitionFrame(
        SonnetTransitionKind.fastBlur,
        progress,
      );
    }
  }
  return SonnetTransitionEffectFrame.neutral;
}

SonnetTransitionEffectFrame resolveSonnetTransitionEffectFrame(
  SonnetProgram program,
  double time,
) {
  for (final paragraph in program.paragraphs) {
    final transition = paragraph.transitionOut;
    if (transition == null) continue;
    if (time >= transition.startTime && time <= transition.endTime) {
      final duration = transition.endTime - transition.startTime;
      final progress = duration > 0 ? (time - transition.startTime) / duration : 1.0;
      return resolveSonnetExitTransitionFrame(transition.kind, progress);
    }
  }
  return SonnetTransitionEffectFrame.neutral;
}
