import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'monet_drift.dart';
import 'monet_palette.dart';

/// 「莫奈」封面浮动层。
///
/// 上游 `MonetBackgroundLayer`（`backgroundLayout: 'full-overlay'`）的移植：一张
/// 模糊过的封面铺满全屏，被 [MonetDriftTrack] 那条 240s 噪声轨道缓慢地推着走，
/// 再叠上左侧泛光 + 右侧压暗的可读性遮罩。
///
/// **本层不是播放器底色**。底色仍然是 `MobilePlayerBackground` 那套「封面提色 +
/// 顶部封面渐变」，本层只是浮在它上面的一层半透明纹理，[opacity] 因此默认远小于
/// 1——把它调到 1 就等于把底色换掉了，那不是这个组件的职责。
class MonetFloatingCoverLayer extends StatefulWidget {
  const MonetFloatingCoverLayer({
    super.key,
    required this.cover,
    required this.palette,
    this.driftStrength = .5,
    this.opacity = .42,
    this.blurSigma = 6,
    this.bottomFadePx = 0,
    this.animate = true,
  });

  /// 封面图。为 null 时只画遮罩（不会留下一块空洞）。
  final ImageProvider? cover;

  final MonetPalette palette;

  /// 漂移强度 0..1，对应上游 `backgroundDriftStrength`（默认 0.5）。
  final double driftStrength;

  /// 封面纹理相对底色的可见度。
  final double opacity;

  /// 上游 `backgroundBlurPx`（默认 6）。
  final double blurSigma;

  /// 底部让出多高不画漂移封面（含渐隐过渡）。
  ///
  /// 这不是构图需要，是给底部那排液态玻璃胶囊让位。玻璃的边缘描边是**从位移
  /// 采样的背景**算出来的，取样点落在胶囊边框外侧；漂移每帧走亚像素，采样值
  /// 跟着变，那圈白描边就会抖。让漂移层在够高的位置就淡干净，胶囊读到的背景
  /// 才是逐帧一模一样的静态渐变。
  ///
  /// 只作用于漂移封面，静态的泛光/压暗遮罩照常铺满全屏，所以不会露出接缝。
  final double bottomFadePx;

  /// 关掉后停在轨道起点。测试与「减弱动态效果」走这条路。
  final bool animate;

  @override
  State<MonetFloatingCoverLayer> createState() =>
      _MonetFloatingCoverLayerState();
}

class _MonetFloatingCoverLayerState extends State<MonetFloatingCoverLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (kMonetDriftLoopSeconds * 1000).round()),
    );
    if (widget.animate) _drift.repeat();
  }

  @override
  void didUpdateWidget(covariant MonetFloatingCoverLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _drift.repeat();
    } else {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cover = widget.cover;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            _fadeOutBottom(
              _DriftingCover(
                drift: _drift,
                track: MonetDriftTrack.of(widget.driftStrength),
                blurSigma: widget.blurSigma,
                // 换歌时整层交叉淡入，避免新封面「啪」一下顶掉旧封面。
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: Image(
                    key: ValueKey<Object>(cover),
                    image: cover,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    // 整层可见度写进 Image 自己的画笔 alpha，**不要**在外面套
                    // Opacity：Opacity 会为整屏开一层 saveLayer，底部控制胶囊的
                    // 液态玻璃取背景时会读到这层半合成的结果。
                    opacity: AlwaysStoppedAnimation<double>(
                      widget.opacity.clamp(0.0, 1.0),
                    ),
                    errorBuilder: (_, _, _) => const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: CustomPaint(painter: _MonetVeilPainter(widget.palette)),
          ),
        ],
      ),
    );
  }

  /// 把漂移层的底部渐隐掉，见 [MonetFloatingCoverLayer.bottomFadePx]。
  Widget _fadeOutBottom(Widget child) {
    if (widget.bottomFadePx <= 0) return child;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final height = rect.height;
        if (height <= 0) {
          return const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF000000)],
          ).createShader(rect);
        }
        final fade = widget.bottomFadePx.clamp(0.0, height);
        // 上半段渐隐、下半段全空：胶囊那一条必须是「完全没有漂移层」，
        // 只是淡到很低还不够，采样差值仍然会被边缘高光放大。
        final solidEnd = ((height - fade) / height).clamp(0.0, 1.0).toDouble();
        final gone = ((height - fade * .5) / height).clamp(0.0, 1.0).toDouble();
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
            Color(0x00000000),
          ],
          stops: [0, solidEnd, gone, 1],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

/// 把 [child] 挂到漂移轨道上。
///
/// CSS 那边是 `translate3d(x%, y%, 0) scale(k)`，右结合——先缩放，再按**未变换**
/// 盒子的百分比平移。[FractionalTranslation] 正好按孩子的布局尺寸算比例，而
/// [Transform.scale] 不改变布局尺寸，所以这个嵌套顺序与 CSS 一一对应。
class _DriftingCover extends StatelessWidget {
  const _DriftingCover({
    required this.drift,
    required this.track,
    required this.blurSigma,
    required this.child,
  });

  final Animation<double> drift;
  final MonetDriftTrack track;
  final double blurSigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 必须夹在变换与模糊之间：没有它，模糊会在每一帧的新变换
    // 下重算一遍，采样网格逐帧错开半个像素，整屏（尤其是贴边处）就会浮起一层
    // 噪点——底部胶囊的液态玻璃正好压在下边缘，把这层噪点读成了闪动的边框。
    // 有了它，模糊结果被留存成一张纹理，上面的变换只是搬动这张纹理。
    final blurred = RepaintBoundary(
      child: blurSigma <= 0
          ? child
          : ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: child,
            ),
    );

    return AnimatedBuilder(
      animation: drift,
      // child 不进 builder，逐帧只重建两个变换节点。
      child: blurred,
      builder: (context, child) {
        final sample = track.sampleAt(drift.value);
        return FractionalTranslation(
          translation: Offset(sample.dxPercent / 100, sample.dyPercent / 100),
          child: Transform.scale(scale: sample.scale, child: child),
        );
      },
    );
  }
}

/// 上游 `paintMonetOverlay` + `readabilityGradient` 的合并版。
///
/// alpha 整体比上游低：那边这层就是全部背景，这里它只是叠在既有底色上的一层，
/// 照搬 0.5~0.6 的 alpha 会把整个播放器压成一块黑板。
class _MonetVeilPainter extends CustomPainter {
  const _MonetVeilPainter(this.palette);

  final MonetPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // 左上角的 accent 泛光，对应 leftBloom。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .18, size.height * .34),
          size.width * .55,
          [monetAlpha(palette.accent, .16), monetAlpha(palette.accent, 0)],
        ),
    );

    // 自左向右加深，给右侧的封面画框腾出对比度，对应 readabilityGradient。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          [
            monetAlpha(palette.background, .04),
            monetAlpha(palette.background, .12),
            monetAlpha(palette.background, .32),
            monetAlpha(palette.background, .46),
          ],
          const [0, .34, .70, 1],
        ),
    );

    // 18 条竖向丝痕，是「莫奈」海报感的来源，位置按上游的整数序列写死。
    final streak = Paint()..color = monetAlpha(palette.background, .10);
    for (var index = 0; index < 18; index++) {
      final x = (index * 127) % size.width.round();
      final y = ((index * 211) % size.height.round()) - 40;
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, size.height * .28),
        streak,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonetVeilPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
