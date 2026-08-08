import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生真·亚克力（毛玻璃）桥。
///
/// 对应 windows/runner/accent_acrylic_handler.cpp 的 MethodChannel
/// "cyrene/accent_acrylic"。flutter_acrylic 的 WindowEffect.acrylic 在
/// Win11 22H2+ 走 DWMWA_SYSTEMBACKDROP_TYPE backdrop（只喷涂壁纸的 Mica
/// 系材质，无实时模糊），达不到参考实现（cyrene_music_tauri 的
/// apply_wallpaper_acrylic）那种 ACCENT 毛玻璃，故亚克力材质改走这条原生
/// 通道：SetWindowCompositionAttribute + ACCENT_ENABLE_ACRYLICBLURBEHIND，
/// 由 DWM 实时采样并模糊窗口背后的内容。
class WindowAccentAcrylic {
  WindowAccentAcrylic._();

  static final WindowAccentAcrylic instance = WindowAccentAcrylic._();

  static const _channel = MethodChannel('cyrene/accent_acrylic');

  /// 应用 ACCENT 亚克力。argb 为 AARRGGBB 着色（A 在高字节），明暗模式
  /// 由调用方传入对应的半透明着色；原生端会先复位 Mica/系统 backdrop。
  Future<void> apply({required int argb}) async {
    try {
      await _channel.invokeMethod<void>('apply', {'argb': argb});
    } catch (e) {
      debugPrint('[亚克力] 应用原生 ACCENT 效果失败: $e');
    }
  }
}
