/// 原版 `ThemeManager` 兼容垫片：新版为纯移动端 Material（Expressive）形态，
/// 桌面 Fluent / Cupertino / Oculus 分支恒为 false。
class ThemeManager {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  bool get isFluentFramework => false;
  bool get isCupertinoFramework => false;
  bool get isMaterialFramework => true;
  bool get isOculusFramework => false;
  bool get isDesktop => false;
  bool get isDesktopFluentUI => false;
  bool get isTablet => false;
}
