import 'package:flutter/material.dart';

/// 移动端 SuperCyrene 全屏播放器的路由。
///
/// 移动端进全屏播放器走的是竖屏流体云，SuperCyrene 需要横屏全屏铺满，用
/// 淡入淡出让横竖屏切换不那么生硬。桌面端有专属的 [DesktopFullscreenPlayerRoute]
/// （底部展开），两者不共用。
class MobileFullscreenPlayerRoute extends PageRouteBuilder<void> {
  MobileFullscreenPlayerRoute({required WidgetBuilder builder})
    : super(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      );
}