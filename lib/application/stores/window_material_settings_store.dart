import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面端窗口材质（背景效果）偏好：不透明 / 云母 Mica / 亚克力 Acrylic。
///
/// 仅 Windows 桌面端生效（Mica / Acrylic 为 Windows 专属窗口效果）；
/// macOS / Linux 保持既有不透明表面。持久化键 `window_material`，默认
/// 「不透明」（对应原版默认窗口背景）。
///
/// 由 main.dart 在首帧前初始化：同时驱动
/// - DWM 窗口效果（flutter_acrylic `setEffect`，见 `_applyWindowBackdrop`）；
/// - 桌面壳层透明策略（`desktop_fluent_theme` 的 backdrop：云母/亚克力走
///   透明让效果透出，不透明用 surface 自绘）。
enum WindowMaterialType {
  /// 默认不透明：关闭窗口背景效果，壳层（标题栏/侧栏/内容区）用不透明
  /// surface 背景。
  opaque,

  /// 云母：Windows 11 Mica，不透明材质、随壁纸与主题明暗取色。
  mica,

  /// 亚克力：Windows 10 1803+ / Windows 11 的半透明模糊材质。
  acrylic,
}

/// 材质的中文名（外观设置页列表与行尾展示用）。
extension WindowMaterialTypeLabel on WindowMaterialType {
  String get label => switch (this) {
    WindowMaterialType.opaque => '默认不透明',
    WindowMaterialType.mica => '云母',
    WindowMaterialType.acrylic => '亚克力',
  };

  /// 列表行副标题：一句话说明该材质的效果。
  String get subtitle => switch (this) {
    WindowMaterialType.opaque => '关闭窗口背景效果，使用纯色背景',
    WindowMaterialType.mica => 'Windows 11 材质，随壁纸与主题取色',
    WindowMaterialType.acrylic => '半透明模糊材质',
  };
}

class WindowMaterialSettingsStore extends ChangeNotifier {
  WindowMaterialSettingsStore._();

  static final WindowMaterialSettingsStore instance =
      WindowMaterialSettingsStore._();

  static const _kMaterial = 'window_material';

  WindowMaterialType _material = WindowMaterialType.opaque;
  WindowMaterialType get material => _material;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_kMaterial);
      if (index != null &&
          index >= 0 &&
          index < WindowMaterialType.values.length) {
        _material = WindowMaterialType.values[index];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[WindowMaterialSettingsStore] 加载窗口材质设置失败: $e');
    }
  }

  Future<void> setMaterial(WindowMaterialType value) async {
    if (_material == value) return;
    _material = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kMaterial, value.index);
    } catch (e) {
      debugPrint('[WindowMaterialSettingsStore] 保存窗口材质设置失败: $e');
    }
  }
}
