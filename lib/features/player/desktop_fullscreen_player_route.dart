import 'package:flutter/material.dart';

/// Desktop fullscreen player route matching the player's vertical expansion.
///
/// The player is revealed from the bottom instead of translating a full-screen
/// surface by one viewport. A full-height slide leaves only the player's plain
/// background visible after its foreground content has moved off-screen during
/// a pop, which looks like a second solid-colour sheet folding underneath it.
class DesktopFullscreenPlayerRoute extends PageRouteBuilder<void> {
  DesktopFullscreenPlayerRoute({required WidgetBuilder builder})
    : super(
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: false,
        allowSnapshotting: false,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return AnimatedBuilder(
            animation: curved,
            child: RepaintBoundary(child: child),
            builder: (context, child) => ClipRect(
              clipper: _BottomUpRevealClipper(curved.value),
              child: Transform.translate(
                offset: Offset(0, (1 - curved.value) * 28),
                child: child,
              ),
            ),
          );
        },
      );
}

class _BottomUpRevealClipper extends CustomClipper<Rect> {
  const _BottomUpRevealClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    final top = size.height * (1 - progress.clamp(0.0, 1.0));
    return Rect.fromLTRB(0, top, size.width, size.height);
  }

  @override
  bool shouldReclip(_BottomUpRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
