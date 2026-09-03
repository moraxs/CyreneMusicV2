import 'package:flutter/material.dart';

/// 适用于歌单卡等卡片无缝放大展开为详情页面的丝滑路由。
///
/// 核心特性：
/// 1. **整页协同缩放**：整页作为一个连贯实体从卡片原位（[originAlignment]）缩放放大（Scale 0.82 -> 1.0），
///    彻底根除仅封面孤立飞行导致的“上半部有图、下半部透出首页旧卡片”的重影割裂感。
/// 2. **动态大圆角延展**：外层容器随着展开过程从大卡片圆角（`38px`）平滑收紧到直角（`0px`），
///    形成极具弹性与沉浸感的物理卡片延展质感。
/// 3. **从容优雅的时长**：460ms 饱满的展开时长 + 360ms 返回收缩时长，节奏从容舒缓。
/// 4. **阻尼物理曲线**：基于 HyperOS / Folme `Cubic(0.2, 0.0, 0.0, 1.0)` 灵动曲线。
class CyreneHeroExpandPageRoute<T> extends PageRouteBuilder<T> {
  CyreneHeroExpandPageRoute({
    required WidgetBuilder builder,
    this.originAlignment = Alignment.center,
    this.initialCornerRadius = 38.0,
    super.settings,
    Duration duration = const Duration(milliseconds: 460),
    Duration reverseDuration = const Duration(milliseconds: 360),
  }) : super(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.18),
          barrierDismissible: false,
          transitionDuration: duration,
          reverseTransitionDuration: reverseDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
          ) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.2, 0.0, 0.0, 1.0),
              reverseCurve: Curves.easeInCubic,
            );

            // 柔和快速淡入（前 32% 迅速建立实体感，消除透光）
            final fastFade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.32, curve: Curves.easeOut),
              reverseCurve: const Interval(0.68, 1.0, curve: Curves.easeIn),
            );

            return AnimatedBuilder(
              animation: curved,
              child: child,
              builder: (context, child) {
                final t = curved.value;
                final radius = initialCornerRadius * (1.0 - t);

                return FadeTransition(
                  opacity: fastFade,
                  child: Transform.scale(
                    scale: 0.82 + (0.18 * t),
                    alignment: originAlignment,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: child,
                    ),
                  ),
                );
              },
            );
          },
        );

  final Alignment originAlignment;
  final double initialCornerRadius;
}
