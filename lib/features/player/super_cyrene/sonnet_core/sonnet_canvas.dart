import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'sonnet_animated_graphics.dart';
import 'sonnet_background_decor.dart';
import 'sonnet_background_mg_variants.dart';
import 'sonnet_camera_tracking.dart';
import 'sonnet_credits.dart';
import 'sonnet_fixed_geo_variants.dart';
import 'sonnet_frame_decor.dart';
import 'sonnet_glyph_layout.dart';
import 'sonnet_guides.dart';
import 'sonnet_interlude_dots.dart';
import 'sonnet_motion.dart';
import 'sonnet_program.dart';
import 'sonnet_random.dart';
import 'sonnet_spatial_mg_geometry.dart';
import 'sonnet_staff_view.dart';
import 'sonnet_text_fixed_geo.dart';
import 'sonnet_transitions.dart';
import 'sonnet_tuning.dart';
import 'sonnet_types.dart';
import 'sonnet_typography_layout.dart';
import 'sonnet_typography_roles.dart';

class SonnetRenderSegment {
  SonnetRenderSegment({
    required this.segment,
    required this.placement,
    required this.glyphs,
    required this.trackingGlyphs,
    this.guide,
    this.frameDecor,
    this.textFixedGeo,
    this.staffView,
  });

  final SonnetSemanticSegment segment;
  final SonnetTypographyPlacement placement;
  final List<SonnetGlyphPlacement> glyphs;
  final List<SonnetTrackingGlyph> trackingGlyphs;
  final SonnetGuideView? guide;
  final SonnetFrameDecorView? frameDecor;
  final AnimatedGraphics? textFixedGeo;
  final SonnetStaffView? staffView;
}

class SonnetShotRenderScene {
  SonnetShotRenderScene({
    required this.shot,
    required this.paragraph,
    required this.segments,
    required this.trackingGlyphs,
    required this.bgHudGraphics,
    required this.spatialGeoGraphics,
    required this.fixedGeoGraphics,
    required this.particles,
    required this.revealDoneTime,
    required this.width,
    required this.height,
  });

  final SonnetShot shot;
  final SonnetParagraph paragraph;
  final List<SonnetRenderSegment> segments;
  final List<SonnetTrackingGlyph> trackingGlyphs;
  final AnimatedGraphics bgHudGraphics;
  final AnimatedGraphics spatialGeoGraphics;
  final List<AnimatedGraphics> fixedGeoGraphics;
  final List<SonnetParticleItem> particles;
  final double revealDoneTime;
  final double width;
  final double height;
}

class SonnetSceneBuilder {
  static final Map<String, SonnetShotRenderScene> _sceneCache = {};

  static void clearCache() => _sceneCache.clear();

  static SonnetShotRenderScene build({
    required SonnetShot shot,
    required SonnetParagraph paragraph,
    required double width,
    required double height,
    required double lyricsFontScale,
    required Color primaryColor,
    required Color secondaryColor,
    required Color accentColor,
    String? fontFamily,
  }) {
    final cacheKey =
        '${shot.id}|${paragraph.id}|$width|$height|$lyricsFontScale|${primaryColor.toARGB32()}|${secondaryColor.toARGB32()}|${accentColor.toARGB32()}';
    final cached = _sceneCache[cacheKey];
    if (cached != null) return cached;

    final lines = paragraph.lines
        .where((l) => shot.lineIndices.contains(l.sourceIndex))
        .map((l) => l.segments)
        .toList();

    final baseFontSize =
        math.max(16.0, math.min(width * 0.05, 34.0)) * lyricsFontScale;

    final typographyPlacements = resolveSonnetTypographyLayout(
      SonnetTypographyLayoutOptions(
        lines: lines,
        shotKind: shot.kind,
        paragraphKind: paragraph.kind,
        width: width,
        height: height,
        baseFontSize: baseFontSize,
        fontFamily: fontFamily,
      ),
    );

    final allFlatSegments = lines.expand((l) => l).toList();
    final renderSegments = <SonnetRenderSegment>[];
    final allTrackingGlyphs = <SonnetTrackingGlyph>[];

    var revealDoneTime = shot.startTime;

    for (final placement in typographyPlacements) {
      final segIdx = placement.segmentIndex;
      final segment = segIdx < allFlatSegments.length
          ? allFlatSegments[segIdx]
          : SonnetSemanticSegment(
              text: placement.displayText,
              startOffset: 0,
              endOffset: placement.displayText.length,
              startTime: shot.startTime,
              endTime: shot.endTime,
              wordIndices: const [],
              graphemes: const [],
              isWordLike: true,
            );

      final glyphs = buildSonnetGlyphLayout(
        segment: segment,
        placement: placement,
        fontSize: baseFontSize * placement.fontScale,
        measureGlyph: (char) => measureText(
          char,
          fontFamily,
          resolveSonnetRoleFontWeight(null, placement.role),
          baseFontSize * placement.fontScale,
        ),
        shotStartTime: shot.startTime,
        shotEndTime: shot.endTime,
      );

      for (final g in glyphs) {
        if (g.settleTime > revealDoneTime) revealDoneTime = g.settleTime;
      }

      final segTrackingGlyphs = <SonnetTrackingGlyph>[];
      if (placement.role != SonnetSegmentRole.decoration) {
        for (final g in glyphs) {
          if (g.char.trim().isEmpty) continue;
          final tg = SonnetTrackingGlyph(
            baseX: g.baseX,
            baseY: g.baseY,
            startTime: g.startTime,
          );
          segTrackingGlyphs.add(tg);
          allTrackingGlyphs.add(tg);
        }
      }

      final guide = placement.role != SonnetSegmentRole.decoration
          ? createSonnetGuide(
              segment: segment,
              placement: placement,
              accentColor: accentColor,
              secondaryColor: secondaryColor,
              fontSize: baseFontSize * placement.fontScale,
            )
          : null;

      final frameDecor = buildSonnetFrameDecor(
        segment: segment,
        placement: placement,
        primaryColor: primaryColor,
        fontSize: baseFontSize * placement.fontScale,
        shotStartTime: shot.startTime,
        shotEndTime: shot.endTime,
        firstGlyphStartTime:
            glyphs.isNotEmpty ? glyphs.first.startTime : shot.startTime,
      );

      final isChorus = paragraph.kind == SonnetParagraphKind.chorus;
      final textFixedGeo = placement.role != SonnetSegmentRole.decoration
          ? buildSonnetTextFixedGeo(SonnetTextFixedGeoOptions(
              seed: hashSonnetSeed(segment.text),
              isChorusEffect: isChorus,
              fontSize: baseFontSize * placement.fontScale,
              layoutWidth: width,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              accentColor: accentColor,
            ))
          : null;

      renderSegments.add(SonnetRenderSegment(
        segment: segment,
        placement: placement,
        glyphs: glyphs,
        trackingGlyphs: segTrackingGlyphs,
        guide: guide,
        frameDecor: frameDecor,
        textFixedGeo: textFixedGeo,
      ));
    }

    final seed = hashSonnetSeed('${shot.id}:${paragraph.id}');
    final bgHudGraphics = AnimatedGraphics();
    drawSonnetBackgroundMgHud(SonnetBackgroundMgOptions(
      target: bgHudGraphics,
      variant: resolveSonnetBackgroundMgVariant(seed),
      width: width,
      height: height,
      seed: seed,
      primary: primaryColor,
      secondary: secondaryColor,
    ));

    final spatialGeoGraphics = AnimatedGraphics();
    final geoVariant = resolveSonnetGeoVariant(seed);
    if (geoVariant % 4 == 0) {
      drawSonnetSolidCuboid(
        spatialGeoGraphics,
        0.0,
        0.0,
        width * 0.28,
        height * 0.22,
        width * 0.08,
        height * 0.06,
        primaryColor,
        0.5,
      );
    } else if (geoVariant % 4 == 1) {
      drawSonnetTriangularPrism(
        spatialGeoGraphics,
        0.0,
        0.0,
        width * 0.26,
        height * 0.24,
        width * 0.06,
        height * 0.05,
        accentColor,
        0.5,
      );
    } else if (geoVariant % 4 == 2) {
      drawSonnetHexagonalPrism(
        spatialGeoGraphics,
        0.0,
        0.0,
        width * 0.24,
        height * 0.24,
        width * 0.07,
        height * 0.05,
        primaryColor,
        0.45,
      );
    } else {
      drawSonnetTrapezoidPrism(
        spatialGeoGraphics,
        0.0,
        0.0,
        width * 0.2,
        width * 0.3,
        height * 0.22,
        width * 0.07,
        height * 0.05,
        secondaryColor,
        0.5,
      );
    }

    final fixedGeoVariant = resolveSonnetFixedGeoVariant(seed);
    final fixedGeoList = buildSonnetFixedGeo(SonnetFixedGeoOptions(
      variant: fixedGeoVariant,
      radius: math.min(width, height) * 0.45,
      seed: seed,
      primary: primaryColor,
      secondary: secondaryColor,
    ));

    final particles = buildSonnetBackgroundDecor(
      kind: shot.kind,
      width: width,
      height: height,
      seed: seed,
      primary: primaryColor,
      secondary: secondaryColor,
    );

    final scene = SonnetShotRenderScene(
      shot: shot,
      paragraph: paragraph,
      segments: renderSegments,
      trackingGlyphs: allTrackingGlyphs,
      bgHudGraphics: bgHudGraphics,
      spatialGeoGraphics: spatialGeoGraphics,
      fixedGeoGraphics: fixedGeoList,
      particles: particles,
      revealDoneTime: revealDoneTime,
      width: width,
      height: height,
    );

    if (_sceneCache.length > 50) _sceneCache.clear();
    _sceneCache[cacheKey] = scene;
    return scene;
  }
}

class SonnetPainter extends CustomPainter {
  SonnetPainter({
    required this.program,
    required this.currentTime,
    required this.tuning,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.creditsMetadata,
    this.lyricsFontScale = 1.0,
    this.fontFamily,
  });

  final SonnetProgram program;
  final double currentTime;
  final SonnetTuning tuning;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final SonnetCreditsMetadata creditsMetadata;
  final double lyricsFontScale;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final width = size.width;
    final height = size.height;

    final finalLyricEndTime = program.paragraphs.isNotEmpty
        ? program.paragraphs.last.endTime
        : 0.0;
    final creditsFrame = tuning.creditsPoster && finalLyricEndTime > 0
        ? resolveSonnetCreditsFrame(currentTime, finalLyricEndTime)
        : SonnetCreditsFrame.inactive;

    if (creditsFrame.posterAlpha > 0.001) {
      paintSonnetCreditsPoster(
        canvas: canvas,
        metadata: creditsMetadata,
        width: width,
        height: height,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        accentColor: accentColor,
        fontFamily: fontFamily,
        alpha: creditsFrame.posterAlpha,
        offsetYRatio: creditsFrame.posterOffsetY,
        scale: creditsFrame.posterScale,
        lyricsFontScale: lyricsFontScale,
      );
    }

    // Pure Instrumental / No Lyrics Mode
    if (program.paragraphs.isEmpty) {
      final introScene = SonnetSceneBuilder.build(
        shot: const SonnetShot(
          id: 'pure-shot',
          kind: SonnetShotKind.quietTableau,
          startTime: 0.0,
          endTime: 99999.0,
          lineIndices: [],
          camera: SonnetCameraTarget(x: 0, y: 0, zoom: 1.0, rotation: 0),
          cues: [],
        ),
        paragraph: const SonnetParagraph(
          id: 'pure-para',
          kind: SonnetParagraphKind.verse,
          boundary: SonnetParagraphBoundary.songStart,
          startTime: 0.0,
          endTime: 99999.0,
          lines: [],
          shots: [],
          transitionOut: null,
        ),
        width: width,
        height: height,
        lyricsFontScale: lyricsFontScale,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        accentColor: accentColor,
        fontFamily: fontFamily,
      );

      final breath = tuning.cameraBreath
          ? resolveSonnetCameraBreath(currentTime)
          : const SonnetShotMotionFrame(x: 0, y: 0, scale: 0, rotation: 0);

      canvas.save();
      canvas.translate(width / 2.0, height / 2.0);
      canvas.scale(1.0 + breath.scale * 0.5, 1.0 + breath.scale * 0.5);
      canvas.rotate(breath.rotation * 0.5);

      if (tuning.hudBackground) introScene.bgHudGraphics.paint(canvas, (currentTime * 0.08) % 1.0);
      if (tuning.spatial3d) introScene.spatialGeoGraphics.paint(canvas, (currentTime * 0.04) % 1.0);
      if (tuning.particleDecor) {
        for (final p in introScene.particles) {
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rotation);
          drawSonnetDecorShape(canvas, p.shape, p.size, p.color, p.alpha);
          canvas.restore();
        }
      }
      canvas.restore();

      paintSonnetIntroPoster(
        canvas: canvas,
        metadata: creditsMetadata,
        width: width,
        height: height,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        accentColor: accentColor,
        fontFamily: fontFamily,
        alpha: 1.0,
        offsetYRatio: 0.0,
        scale: 1.0,
        lyricsFontScale: lyricsFontScale,
      );

      final dotsElapsed = currentTime % 3.0;
      final dotsState = resolveSonnetInterludeDotsState(
        currentTime: dotsElapsed,
        startTime: 0.0,
        endTime: 3.0,
      );
      paintSonnetInterludeDots(
        canvas: canvas,
        state: dotsState,
        width: width,
        height: height,
        primaryColor: primaryColor,
        accentColor: accentColor,
      );
      return;
    }

    if (creditsFrame.lyricAlpha <= 0.001) {
      return;
    }

    final firstLyricStartTime = program.paragraphs.first.startTime;
    final introFrame = resolveSonnetIntroFrame(currentTime, firstLyricStartTime);

    if (introFrame.posterAlpha > 0.001) {
      paintSonnetIntroPoster(
        canvas: canvas,
        metadata: creditsMetadata,
        width: width,
        height: height,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        accentColor: accentColor,
        fontFamily: fontFamily,
        alpha: introFrame.posterAlpha,
        offsetYRatio: introFrame.posterOffsetY,
        scale: introFrame.posterScale,
        lyricsFontScale: lyricsFontScale,
      );
    }

    final paragraphIdx =
        findSonnetParagraphIndexAtTime(program, currentTime);
    final paragraph = program.paragraphs[paragraphIdx];

    if (paragraph.shots.isEmpty) return;

    // Strictly determine the single active shot within this scene (never drops to null during gaps)
    var activeShotIndex = 0;
    for (var i = paragraph.shots.length - 1; i >= 0; i--) {
      if (currentTime >= paragraph.shots[i].startTime) {
        activeShotIndex = i;
        break;
      }
    }
    final activeShot = paragraph.shots[activeShotIndex];

    final scene = SonnetSceneBuilder.build(
      shot: activeShot,
      paragraph: paragraph,
      width: width,
      height: height,
      lyricsFontScale: lyricsFontScale,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      accentColor: accentColor,
      fontFamily: fontFamily,
    );

    final shotProgress = resolveShotProgress(activeShot, currentTime);
    final paragraphTransFrame =
        resolveSonnetTransitionEffectFrame(program, currentTime);
    final shotTransFrame =
        resolveSonnetShotTransitionFrame(activeShot, currentTime);
    final transFrame = paragraphTransFrame.active
        ? paragraphTransFrame
        : shotTransFrame;

    final baseFontSize =
        math.max(16.0, math.min(width * 0.05, 34.0)) * lyricsFontScale;

    final shotMotion = resolveShotMotionFrame(activeShot.kind, shotProgress);
    var shotMotionX = shotMotion.x;
    var shotMotionY = shotMotion.y;
    var shotMotionScale = shotMotion.scale;
    var shotMotionRotation = shotMotion.rotation;

    // Smooth tail drift during time gap after shot ends
    final gapTime = math.max(0.0, currentTime - activeShot.endTime);
    if (gapTime > 0) {
      final tailStart = resolveShotMotionFrame(activeShot.kind, 0.8);
      final dx = shotMotion.x - tailStart.x;
      final dy = shotMotion.y - tailStart.y;
      final dScale = shotMotion.scale - tailStart.scale;
      final dRot = shotMotion.rotation - tailStart.rotation;
      final driftSpeed = (1.0 - math.exp(-gapTime * 0.4)) * 2.0;
      shotMotionX += dx * driftSpeed;
      shotMotionY += dy * driftSpeed;
      shotMotionScale += dScale * driftSpeed;
      shotMotionRotation += dRot * driftSpeed;
    }

    final breathWeight = tuning.cameraBreath
        ? resolveSonnetBreathWeight(currentTime, scene.revealDoneTime)
        : 0.0;
    final breath = tuning.cameraBreath && breathWeight > 0
        ? resolveSonnetCameraBreath(currentTime)
        : const SonnetShotMotionFrame(x: 0, y: 0, scale: 0, rotation: 0);

    // Multi-segment smooth camera tracking with bilateral Gaussian weighting
    final trackSegments = scene.segments
        .where((s) =>
            s.placement.role != SonnetSegmentRole.decoration &&
            s.trackingGlyphs.isNotEmpty)
        .toList();

    var smoothedFocus = const (x: 0.0, y: 0.0);
    if (tuning.cameraTracking && trackSegments.isNotEmpty) {
      final focusRanges = trackSegments.map((s) => (
            startTime: s.trackingGlyphs.first.startTime,
            endTime: s.trackingGlyphs.last.startTime,
          )).toList();

      ({double x, double y}) resolveFocusAtTime(double focusTime) {
        var focusX = 0.0;
        var focusY = 0.0;
        final focusWeights = resolveSonnetFocusWeights(focusRanges, focusTime);
        for (var i = 0; i < trackSegments.length; i++) {
          final seg = trackSegments[i];
          final w = i < focusWeights.length ? focusWeights[i] : 0.0;
          if (w <= 0.0001) continue;
          final pos = resolveSonnetSegmentCameraFocus(
            seg.trackingGlyphs,
            focusTime,
            0.5,
          );
          focusX += pos.x * w;
          focusY += pos.y * w;
        }
        return (x: focusX, y: focusY);
      }

      final focusTime = currentTime.clamp(activeShot.startTime, activeShot.endTime);
      smoothedFocus = resolveSonnetSmoothedCameraFocus(
        focusTime,
        activeShot.startTime,
        activeShot.endTime,
        resolveFocusAtTime,
      );
    }

    final totalZoom = activeShot.camera.zoom *
        shotMotionScale *
        (1.0 + breath.scale * breathWeight) *
        (1.0 + transFrame.zoomOffset);
    final totalRot = activeShot.camera.rotation +
        shotMotionRotation +
        breath.rotation * breathWeight +
        transFrame.rotationOffset;

    canvas.save();

    final overallAlpha = (creditsFrame.lyricAlpha * transFrame.alpha).clamp(0.0, 1.0);

    // Apply Camera Transform: screen center translation -> zoom/rot -> pivot focus translation
    canvas.translate(
      width / 2.0 + (shotMotionX + breath.x * breathWeight) * width,
      height / 2.0 + (shotMotionY + breath.y * breathWeight) * height,
    );
    canvas.scale(totalZoom, totalZoom);
    canvas.rotate(totalRot);
    canvas.translate(-smoothedFocus.x, -smoothedFocus.y);

    // 1. Background HUD graphics
    if (tuning.hudBackground) {
      scene.bgHudGraphics.paint(canvas, shotProgress);
    }

    // 2. Spatial 3D Wireframes
    if (tuning.spatial3d) {
      scene.spatialGeoGraphics.paint(canvas, shotProgress);
    }

    // 3. Fixed Geometry & Hatching
    if (tuning.fixedGeometry) {
      for (final fg in scene.fixedGeoGraphics) {
        fg.paint(canvas, shotProgress);
      }
    }

    // 4. Background Decor Particles
    if (tuning.particleDecor) {
      for (final p in scene.particles) {
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.rotation);
        drawSonnetDecorShape(
          canvas,
          p.shape,
          p.size,
          p.color,
          (p.alpha * overallAlpha).clamp(0.0, 1.0),
        );
        canvas.restore();
      }
    }

    // 5. Lead-in Guides
    if (tuning.guides) {
      for (final rSeg in scene.segments) {
        final guide = rSeg.guide;
        if (guide != null &&
            currentTime >= guide.startTime &&
            currentTime <= guide.endTime) {
          final dur = guide.endTime - guide.startTime;
          final prog = dur > 0 ? (currentTime - guide.startTime) / dur : 1.0;
          guide.paint(canvas, prog);
        }
      }
    }

    // 6. Text Fixed Geo behind words
    if (tuning.fixedGeometry) {
      for (final rSeg in scene.segments) {
        final tfg = rSeg.textFixedGeo;
        if (tfg != null) {
          canvas.save();
          canvas.translate(rSeg.placement.x, rSeg.placement.y);
          tfg.paint(canvas, shotProgress);
          canvas.restore();
        }
      }
    }

    // 7. Open Frame Decors
    if (tuning.frameDecor) {
      for (final rSeg in scene.segments) {
        final fd = rSeg.frameDecor;
        if (fd != null && currentTime >= fd.startTime) {
          final dur = fd.endTime - fd.startTime;
          final prog = dur > 0 ? (currentTime - fd.startTime) / dur : 1.0;
          fd.paint(canvas, prog);
        }
      }
    }

    // 8. Staff View
    for (final rSeg in scene.segments) {
      final staff = rSeg.staffView;
      if (staff != null) {
        staff.paint(canvas, currentTime, overallAlpha);
      }
    }

    // 9. Kinetic Typography Glyphs with Chromatic Aberration & Ghost Echoes
    for (final rSeg in scene.segments) {
      final placement = rSeg.placement;
      final isDeco = placement.role == SonnetSegmentRole.decoration;
      final isHero = placement.role == SonnetSegmentRole.hero;
      final isSemiHero = placement.role == SonnetSegmentRole.semiHero;
      final fontSize = baseFontSize * placement.fontScale;
      final fontWeight = resolveSonnetRoleFontWeight(null, placement.role);

      for (final glyph in rSeg.glyphs) {
        if (glyph.char.trim().isEmpty) continue;
        if (currentTime < glyph.startTime) continue;

        final rawProg = clamp01(
          (currentTime - glyph.startTime) /
              math.max(glyph.settleTime - glyph.startTime, 0.08),
        );
        final prog = easeSonnetExpoOut(rawProg);

        final curX = glyph.baseX + glyph.enterX * (1.0 - prog);
        final curY = glyph.baseY + glyph.enterY * (1.0 - prog);
        final curRot = placement.rotation + glyph.entryRotation * (1.0 - prog);
        final glyphAlpha = (prog * overallAlpha).clamp(0.0, 1.0);

        canvas.save();
        canvas.translate(curX, curY);
        canvas.rotate(curRot);

        // Chromatic Aberration (Cyan & Red offsets)
        if (tuning.chromaticAberration && rawProg < 0.95) {
          final split = (1.0 - rawProg) * (isHero ? 7.0 : 4.0);
          final caAlpha = ((1.0 - rawProg) * 0.7 * glyphAlpha).clamp(0.0, 1.0);

          if (caAlpha > 0.01) {
            // Cyan offset (-split)
            final cyanTp = TextPainter(
              text: TextSpan(
                text: glyph.char,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: const Color(0xFF00FFFF).withValues(alpha: caAlpha),
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            cyanTp.paint(canvas, Offset(-cyanTp.width / 2.0 - split, -cyanTp.height / 2.0));
            cyanTp.dispose();

            // Red/Magenta offset (+split)
            final redTp = TextPainter(
              text: TextSpan(
                text: glyph.char,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: const Color(0xFFFF0055).withValues(alpha: caAlpha),
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            redTp.paint(canvas, Offset(-redTp.width / 2.0 + split, -redTp.height / 2.0));
            redTp.dispose();
          }
        }

        // Semi-Hero Hollow Echo Ghost Copies
        if (tuning.ghostEchoes && isSemiHero && rawProg < 0.85) {
          final echoOffset = (1.0 - rawProg) * fontSize * 0.35;
          final echoAlpha = ((1.0 - rawProg) * 0.5 * glyphAlpha).clamp(0.0, 1.0);

          for (final side in [-1.0, 1.0]) {
            final ghostTp = TextPainter(
              text: TextSpan(
                text: glyph.char,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1.2
                    ..color = accentColor.withValues(alpha: echoAlpha),
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            ghostTp.paint(
              canvas,
              Offset(
                -ghostTp.width / 2.0,
                -ghostTp.height / 2.0 + side * echoOffset,
              ),
            );
            ghostTp.dispose();
          }
        }

        // Core Glyph Rendering
        final textColor = isHero
            ? accentColor
            : (isSemiHero ? primaryColor : primaryColor.withValues(alpha: 0.85));

        final tp = TextPainter(
          text: TextSpan(
            text: glyph.char,
            style: isDeco
                ? TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 1.2
                      ..color = primaryColor.withValues(
                        alpha: (0.28 * glyphAlpha).clamp(0.0, 1.0),
                      ),
                  )
                : TextStyle(
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    color: textColor.withValues(alpha: glyphAlpha),
                  ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        // Hero subtle core halo glow
        if (isHero && glyphAlpha > 0.3) {
          canvas.drawCircle(
            Offset.zero,
            fontSize * 0.45,
            Paint()
              ..style = PaintingStyle.fill
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0)
              ..color = accentColor.withValues(
                alpha: (0.2 * glyphAlpha).clamp(0.0, 1.0),
              ),
          );
        }

        tp.paint(canvas, Offset(-tp.width / 2.0, -tp.height / 2.0));
        tp.dispose();

        canvas.restore();
      }
    }

    canvas.restore();

    // Glitch horizontal slices overlay
    if (tuning.glitchTransitions && transFrame.glitchSliceCount > 0) {
      final sliceCount = transFrame.glitchSliceCount;
      final sliceHeight = height / sliceCount;
      final gPaint = Paint()..style = PaintingStyle.fill;

      for (var s = 0; s < sliceCount; s++) {
        if (s % 2 == 0) continue;
        final sy = s * sliceHeight;
        final offset = (s % 3 - 1) * transFrame.glitchOffset;
        canvas.drawRect(
          Rect.fromLTWH(offset, sy, width, sliceHeight),
          gPaint..color = primaryColor.withValues(alpha: 0.12),
        );
      }
    }

    // 10. Interlude breathing dots indicator [ • • • ]
    final interlude = findActiveSonnetInterlude(program, currentTime);
    if (interlude != null) {
      final dotsState = resolveSonnetInterludeDotsState(
        currentTime: currentTime,
        startTime: interlude.startTime,
        endTime: interlude.endTime,
      );
      if (dotsState.isVisible) {
        paintSonnetInterludeDots(
          canvas: canvas,
          state: dotsState,
          width: width,
          height: height,
          primaryColor: primaryColor,
          accentColor: accentColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SonnetPainter oldDelegate) {
    return oldDelegate.currentTime != currentTime ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.lyricsFontScale != lyricsFontScale;
  }
}
