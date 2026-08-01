import 'package:flutter_miuix/miuix.dart';

/// 全局轻提示（替代原 ShadSonner/ShadToast）。
///
/// [hostState] 由 main.dart 挂载在 MaterialApp.builder 的根部
/// [MiuixSnackbarHost] 上，因此任何页面（含全屏播放器等路由）都能弹出。
abstract final class CyreneToast {
  static final MiuixSnackbarHostState hostState = MiuixSnackbarHostState();

  static void show(
    String message, {
    String? actionLabel,
    MiuixSnackbarDuration duration = MiuixSnackbarDuration.short,
  }) {
    hostState.showSnackbar(
      message,
      actionLabel: actionLabel,
      duration: duration,
    );
  }
}
