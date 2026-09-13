import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Apple Music 风格的播放控制按钮。
///
/// 对标 AMLL（applemusic-like-lyrics）`react-full` 的 `MediaButton`
/// （`components/MediaButton/index.module.css`）：
///
/// - 圆形、1:1，底色平时全透明，按下时 `#fff2`（白 13%），0.3s 过渡。
/// - 按下触发一段带回弹的缩放关键帧，0.7s：
///   `scale 1 → 0.85 (20%) → 1.1 (50%) → 1 (100%)`。
///   先缩后涨过冲再落回，是「点下去有肉感」的来源，别简化成单纯的 0.9 缩放。
///
/// 图标走 [asset] 指向的 SVG（assets/icons/icon_*.svg，同样取自 AMLL），
/// 统一用 srcIn 上色 —— 这些 SVG 里混用了 `currentColor` 与写死的 fill，
/// 只有 srcIn 能把两种都盖住。
class AppleMusicMediaButton extends StatefulWidget {
  const AppleMusicMediaButton({
    super.key,
    required this.asset,
    required this.onPressed,
    this.size = 64,
    this.iconSize = 32,
    this.color = Colors.white,
    this.semanticLabel,
  });

  final String asset;

  /// 为 null 时按钮置灰且不可点（例如没有上一首）。
  final VoidCallback? onPressed;

  /// 圆形触摸区直径。
  final double size;

  /// 图标本身的边长。
  final double iconSize;

  final Color color;
  final String? semanticLabel;

  @override
  State<AppleMusicMediaButton> createState() => _AppleMusicMediaButtonState();
}

class _AppleMusicMediaButtonState extends State<AppleMusicMediaButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  /// AMLL 的 `pressed-animation` 关键帧：1 → 0.85 → 1.1 → 1。
  /// 关键帧落在 20% / 50% / 100%，权重按区间长度分配。
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.85)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 20,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.85, end: 1.1)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.1, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
  ]).animate(_controller);

  bool _held = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fire() {
    _controller.forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final tint = enabled
        ? widget.color
        : widget.color.withValues(alpha: 0.35);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _held = true) : null,
        onTapCancel: enabled ? () => setState(() => _held = false) : null,
        onTap: enabled
            ? () {
                setState(() => _held = false);
                _fire();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // CSS `&:hover / &:active { background-color: #fff2 }`。
            color: _held
                ? Colors.white.withValues(alpha: 0.13)
                : Colors.transparent,
          ),
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: SvgPicture.asset(
                widget.asset,
                width: widget.iconSize,
                height: widget.iconSize,
                colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
