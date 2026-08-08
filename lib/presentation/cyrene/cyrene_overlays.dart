import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'breakpoints.dart';

/// 弹层内容构建器。`dismiss([result])` 走 Miuix 退场动画后再关闭路由并返回结果；
/// 不要在弹层内容里直接 `Navigator.pop`（会跳过退场动画）。
typedef CyreneOverlayBuilder<T> =
    Widget Function(BuildContext context, void Function([T? result]) dismiss);

/// 命令式弹出 Miuix 风格对话框（替代原 showShadDialog）。
///
/// Miuix 的 Dialog 是声明式 `show` 状态驱动、依赖弹层宿主的组件；这里用一条
/// 透明路由自建 [MiuixPopupScope] + [MiuixPopupHost] 承载，保持调用点命令式。
Future<T?> showCyreneDialog<T>({
  required BuildContext context,
  String? title,
  String? summary,
  required CyreneOverlayBuilder<T> builder,
  bool barrierDismissible = true,
}) {
  final compact = isDesktopLayout(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => _CyreneOverlayPage<T>(
        builder: builder,
        barrierDismissible: barrierDismissible,
        overlayBuilder: (state, content) => MiuixOverlayDialog(
          show: state.show,
          title: title,
          summary: summary,
          onDismissRequest: barrierDismissible ? state.dismiss : null,
          onDismissFinished: state.onDismissFinished,
          maxWidth: compact ? 360 : 420,
          insideMargin: Size.square(compact ? 18 : 24),
          cornerRadius: compact ? 24 : null,
          content: content,
        ),
      ),
    ),
  );
}

/// 命令式弹出 Miuix 底部抽屉（替代原 showShadSheet / showCyreneDrawer）。
Future<T?> showCyreneSheet<T>({
  required BuildContext context,
  String? title,
  Widget? startAction,
  Widget? endAction,
  bool allowDismiss = true,
  /// 内容水平内边距；null 走 [MiuixOverlayBottomSheet] 默认 24。
  /// 内容较密集的设置面板可传更小值（如 16）收紧两侧留白。
  double? insideMargin,
  required CyreneOverlayBuilder<T> builder,
}) {
  final compact = isDesktopLayout(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => _CyreneOverlayPage<T>(
        builder: builder,
        barrierDismissible: allowDismiss,
        overlayBuilder: (state, content) => MiuixOverlayBottomSheet(
          show: state.show,
          title: title,
          startAction: startAction,
          endAction: endAction,
          allowDismiss: allowDismiss,
          insideMargin: Size(insideMargin ?? (compact ? 18 : 24), 0),
          sheetMaxWidth: compact ? 520 : 640,
          cornerRadius: compact ? 22 : 28,
          onDismissRequest: state.dismiss,
          onDismissFinished: state.onDismissFinished,
          content: content,
        ),
      ),
    ),
  );
}

/// 透明路由页：托管一个声明式 Miuix 弹层的完整生命周期。
///
/// 进入后下一帧把 `show` 置 true 触发入场动画；`dismiss` 只把 `show` 置 false，
/// 等 `onDismissFinished`（退场动画结束）再真正 pop 路由并带出结果。
class _CyreneOverlayPage<T> extends StatefulWidget {
  const _CyreneOverlayPage({
    required this.builder,
    required this.overlayBuilder,
    required this.barrierDismissible,
  });

  final CyreneOverlayBuilder<T> builder;
  final Widget Function(_CyreneOverlayPageState<T> state, Widget content)
  overlayBuilder;
  final bool barrierDismissible;

  @override
  State<_CyreneOverlayPage<T>> createState() => _CyreneOverlayPageState<T>();
}

class _CyreneOverlayPageState<T> extends State<_CyreneOverlayPage<T>> {
  bool show = false;
  T? _result;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => show = true);
    });
  }

  void dismiss([T? result]) {
    if (_popped || !show) return;
    _result = result;
    setState(() => show = false);
  }

  void onDismissFinished() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) {
    final content = Material(
      type: MaterialType.transparency,
      child: Builder(builder: (context) => widget.builder(context, dismiss)),
    );
    return PopScope(
      // 系统返回键先走 Miuix 退场动画，动画结束后再由 onDismissFinished pop。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) dismiss();
      },
      child: MiuixPopupScope(
        establishRoot: true,
        child: MiuixPopupHost(
          child: SizedBox.expand(child: widget.overlayBuilder(this, content)),
        ),
      ),
    );
  }
}
