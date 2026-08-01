import '../../../../presentation/cyrene/cyrene_toast.dart';

/// 原版 `ToastUtils` 兼容层：转发到应用统一的 [CyreneToast]。
class ToastUtils {
  static void success(String message) => CyreneToast.show(message);
  static void error(String message) => CyreneToast.show(message);
  static void warning(String message) => CyreneToast.show(message);
  static void info(String message) => CyreneToast.show(message);
}
