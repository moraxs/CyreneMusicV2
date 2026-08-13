import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/desktop/window_taskbar_player.dart';
import '../../domain/lyrics/lyric_fonts.dart';
import '../../domain/playback/player_display_settings.dart';

/// 全屏播放器显示设置（对应 Next.js usePlayerSettings 的移动端子集）。
///
/// 单例 ChangeNotifier；[init] 在 app 启动时载入 shared_preferences 持久化值，
/// 各 setter 同步写回。消费方：FullscreenPlayer / PlayerSettingsSheet。
class FullscreenSettingsStore extends ChangeNotifier {
  FullscreenSettingsStore._();

  static final FullscreenSettingsStore instance = FullscreenSettingsStore._();

  /// 桌面歌词缩放的取值区间。
  static const double minDesktopLyricScale = 0.5;
  static const double maxDesktopLyricScale = 2;

  /// 单轴旋转的最大幅度（弧度，±45°）。再大歌词就难以辨读了。
  static const double maxDesktopLyricRotation = math.pi / 4;

  static const _kAudioVisualization = 'fullscreen.audioVisualization';
  static const _kImmersiveMode = 'fullscreen.immersiveMode';
  static const _kHideAlbumCover = 'fullscreen.hideAlbumCover';
  static const _kShowTranslation = 'fullscreen.showTranslation';
  static const _kLyricDisplayStyle = 'fullscreen.lyricDisplayStyle';
  static const _kSingleLineAnimation = 'fullscreen.singleLineAnimation';
  static const _kLyricFontFamily = 'fullscreen.lyricFontFamily';
  static const _kLyricFontSize = 'fullscreen.lyricFontSize';
  static const _kLyricBlurStrength = 'fullscreen.lyricBlurStrength';
  static const _kSuperCyrenePlayerEnabled =
      'fullscreen.superCyrenePlayerEnabled';
  static const _kSuperCyreneLyricsTheme = 'fullscreen.superCyreneLyricsTheme';
  static const _kWallpaperPlayerEnabled = 'fullscreen.wallpaperPlayerEnabled';
  static const _kTaskbarPlayerEnabled = 'fullscreen.taskbarPlayerEnabled';
  static const _kTaskbarPlayerAlignment = 'fullscreen.taskbarPlayerAlignment';
  static const _kTaskbarPlayerMode = 'fullscreen.taskbarPlayerMode';
  static const _kTaskbarPlayerFloatingX = 'fullscreen.taskbarPlayerFloatingX';
  static const _kTaskbarPlayerFloatingY = 'fullscreen.taskbarPlayerFloatingY';

  // 桌面歌词的自由变换（编辑模式）。仅对「经典 / 像素 / 对话」生效——
  // 「默认」样式自带精心设计的逐行逐字排版，不参与变换（见 desktop_player_view）。
  static const _kDesktopLyricOffsetX = 'fullscreen.desktopLyricOffsetX';
  static const _kDesktopLyricOffsetY = 'fullscreen.desktopLyricOffsetY';
  static const _kDesktopLyricScale = 'fullscreen.desktopLyricScale';
  static const _kDesktopLyricRotX = 'fullscreen.desktopLyricRotX';
  static const _kDesktopLyricRotY = 'fullscreen.desktopLyricRotY';
  static const _kDesktopLyricRotZ = 'fullscreen.desktopLyricRotZ';

  SharedPreferences? _prefs;

  bool _audioVisualization = true;
  bool _isImmersiveMode = false;
  bool _hideAlbumCover = false;
  bool _showTranslation = true;
  LyricDisplayStyle _lyricDisplayStyle = LyricDisplayStyle.scroll;
  SingleLineAnimation _singleLineAnimation = SingleLineAnimation.slideUp;
  String _lyricFontFamily = defaultLyricFont;
  double _lyricFontSize = 34;
  double _lyricBlurStrength = 10;
  bool _superCyrenePlayerEnabled = false;
  String _superCyreneLyricsTheme = 'default';
  bool _wallpaperPlayerEnabled = false;
  bool _taskbarPlayerEnabled = false;
  TaskbarPlayerAlignment _taskbarPlayerAlignment =
      TaskbarPlayerAlignment.center;
  TaskbarPlayerMode _taskbarPlayerMode = TaskbarPlayerMode.pinned;

  /// 悬浮形态下的窗口左上角坐标，**物理像素**（与原生 GetWindowRect 同一
  /// 坐标系，不做逻辑像素换算——换算会在多 DPI 下把窗口放偏）。
  int _taskbarPlayerFloatingX = 0;
  int _taskbarPlayerFloatingY = 0;

  /// 相对默认居中位置的平移量，逻辑像素。
  double _desktopLyricOffsetX = 0;
  double _desktopLyricOffsetY = 0;

  /// 缩放倍率，取值 [minDesktopLyricScale] ~ [maxDesktopLyricScale]。
  double _desktopLyricScale = 1;

  /// 三轴旋转，**弧度**（不是角度）。UI 上以度显示，读写时换算。
  double _desktopLyricRotX = 0;
  double _desktopLyricRotY = 0;
  double _desktopLyricRotZ = 0;

  bool get audioVisualization => _audioVisualization;
  bool get isImmersiveMode => _isImmersiveMode;
  bool get hideAlbumCover => _hideAlbumCover;
  bool get showTranslation => _showTranslation;
  LyricDisplayStyle get lyricDisplayStyle => _lyricDisplayStyle;
  SingleLineAnimation get singleLineAnimation => _singleLineAnimation;
  String get lyricFontFamily => _lyricFontFamily;
  double get lyricFontSize => _lyricFontSize;
  double get lyricBlurStrength => _lyricBlurStrength;
  bool get superCyrenePlayerEnabled => _superCyrenePlayerEnabled;
  String get superCyreneLyricsTheme => _superCyreneLyricsTheme;
  bool get wallpaperPlayerEnabled => _wallpaperPlayerEnabled;
  bool get taskbarPlayerEnabled => _taskbarPlayerEnabled;
  TaskbarPlayerAlignment get taskbarPlayerAlignment => _taskbarPlayerAlignment;
  TaskbarPlayerMode get taskbarPlayerMode => _taskbarPlayerMode;
  int get taskbarPlayerFloatingX => _taskbarPlayerFloatingX;
  int get taskbarPlayerFloatingY => _taskbarPlayerFloatingY;
  double get desktopLyricOffsetX => _desktopLyricOffsetX;
  double get desktopLyricOffsetY => _desktopLyricOffsetY;
  double get desktopLyricScale => _desktopLyricScale;
  double get desktopLyricRotX => _desktopLyricRotX;
  double get desktopLyricRotY => _desktopLyricRotY;
  double get desktopLyricRotZ => _desktopLyricRotZ;

  /// 变换参数是否全为默认值。面板据此决定「重置」按钮是否可用。
  bool get desktopLyricTransformIsDefault =>
      _desktopLyricOffsetX == 0 &&
      _desktopLyricOffsetY == 0 &&
      _desktopLyricScale == 1 &&
      _desktopLyricRotX == 0 &&
      _desktopLyricRotY == 0 &&
      _desktopLyricRotZ == 0;

  Future<void> init() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _audioVisualization =
        prefs.getBool(_kAudioVisualization) ?? _audioVisualization;
    _isImmersiveMode = prefs.getBool(_kImmersiveMode) ?? _isImmersiveMode;
    _hideAlbumCover = prefs.getBool(_kHideAlbumCover) ?? _hideAlbumCover;
    _showTranslation = prefs.getBool(_kShowTranslation) ?? _showTranslation;
    _lyricDisplayStyle = LyricDisplayStyle.fromWireName(
      prefs.getString(_kLyricDisplayStyle) ?? _lyricDisplayStyle.wireName,
    );
    _singleLineAnimation = SingleLineAnimation.fromWireName(
      prefs.getString(_kSingleLineAnimation) ?? _singleLineAnimation.wireName,
    );
    _lyricFontFamily = prefs.getString(_kLyricFontFamily) ?? _lyricFontFamily;
    _lyricFontSize = prefs.getDouble(_kLyricFontSize) ?? _lyricFontSize;
    _lyricBlurStrength =
        prefs.getDouble(_kLyricBlurStrength) ?? _lyricBlurStrength;
    _superCyrenePlayerEnabled =
        prefs.getBool(_kSuperCyrenePlayerEnabled) ?? _superCyrenePlayerEnabled;
    final storedSuperCyreneTheme = prefs.getString(_kSuperCyreneLyricsTheme);
    _superCyreneLyricsTheme =
        (storedSuperCyreneTheme == 'chat' ||
            storedSuperCyreneTheme == 'pixel')
        ? storedSuperCyreneTheme!
        : 'default';
    _wallpaperPlayerEnabled =
        prefs.getBool(_kWallpaperPlayerEnabled) ?? _wallpaperPlayerEnabled;
    _taskbarPlayerEnabled =
        prefs.getBool(_kTaskbarPlayerEnabled) ?? _taskbarPlayerEnabled;
    _taskbarPlayerAlignment = TaskbarPlayerAlignment.fromName(
      prefs.getString(_kTaskbarPlayerAlignment),
    );
    _taskbarPlayerMode = TaskbarPlayerMode.fromName(
      prefs.getString(_kTaskbarPlayerMode),
    );
    _taskbarPlayerFloatingX =
        prefs.getInt(_kTaskbarPlayerFloatingX) ?? _taskbarPlayerFloatingX;
    _taskbarPlayerFloatingY =
        prefs.getInt(_kTaskbarPlayerFloatingY) ?? _taskbarPlayerFloatingY;
    // 读回时一律夹紧：手改过 prefs 或旧版本写入越界值时，不至于把歌词
    // 变换成不可读的形态而用户又找不到怎么复原。
    _desktopLyricOffsetX =
        prefs.getDouble(_kDesktopLyricOffsetX) ?? _desktopLyricOffsetX;
    _desktopLyricOffsetY =
        prefs.getDouble(_kDesktopLyricOffsetY) ?? _desktopLyricOffsetY;
    _desktopLyricScale = (prefs.getDouble(_kDesktopLyricScale) ?? _desktopLyricScale)
        .clamp(minDesktopLyricScale, maxDesktopLyricScale);
    _desktopLyricRotX = (prefs.getDouble(_kDesktopLyricRotX) ?? _desktopLyricRotX)
        .clamp(-maxDesktopLyricRotation, maxDesktopLyricRotation);
    _desktopLyricRotY = (prefs.getDouble(_kDesktopLyricRotY) ?? _desktopLyricRotY)
        .clamp(-maxDesktopLyricRotation, maxDesktopLyricRotation);
    _desktopLyricRotZ = (prefs.getDouble(_kDesktopLyricRotZ) ?? _desktopLyricRotZ)
        .clamp(-maxDesktopLyricRotation, maxDesktopLyricRotation);
    notifyListeners();
  }

  void toggleAudioVisualization() {
    _audioVisualization = !_audioVisualization;
    _prefs?.setBool(_kAudioVisualization, _audioVisualization);
    notifyListeners();
  }

  void setIsImmersiveMode(bool value) {
    if (_isImmersiveMode == value) return;
    _isImmersiveMode = value;
    _prefs?.setBool(_kImmersiveMode, value);
    notifyListeners();
  }

  void setHideAlbumCover(bool value) {
    if (_hideAlbumCover == value) return;
    _hideAlbumCover = value;
    _prefs?.setBool(_kHideAlbumCover, value);
    notifyListeners();
  }

  void toggleTranslation() {
    _showTranslation = !_showTranslation;
    _prefs?.setBool(_kShowTranslation, _showTranslation);
    notifyListeners();
  }

  void setLyricDisplayStyle(LyricDisplayStyle value) {
    if (_lyricDisplayStyle == value) return;
    _lyricDisplayStyle = value;
    _prefs?.setString(_kLyricDisplayStyle, value.wireName);
    notifyListeners();
  }

  void setSingleLineAnimation(SingleLineAnimation value) {
    if (_singleLineAnimation == value) return;
    _singleLineAnimation = value;
    _prefs?.setString(_kSingleLineAnimation, value.wireName);
    notifyListeners();
  }

  void setLyricFontFamily(String value) {
    if (_lyricFontFamily == value) return;
    _lyricFontFamily = value;
    _prefs?.setString(_kLyricFontFamily, value);
    notifyListeners();
  }

  void setLyricFontSize(double value) {
    if (_lyricFontSize == value) return;
    _lyricFontSize = value;
    _prefs?.setDouble(_kLyricFontSize, value);
    notifyListeners();
  }

  void setLyricBlurStrength(double value) {
    if (_lyricBlurStrength == value) return;
    _lyricBlurStrength = value;
    _prefs?.setDouble(_kLyricBlurStrength, value);
    notifyListeners();
  }

  void setSuperCyrenePlayerEnabled(bool value) {
    if (_superCyrenePlayerEnabled == value) return;
    _superCyrenePlayerEnabled = value;
    _prefs?.setBool(_kSuperCyrenePlayerEnabled, value);
    notifyListeners();
  }

  void setSuperCyreneLyricsTheme(String value) {
    final normalized =
        (value == 'chat' || value == 'pixel') ? value : 'default';
    if (_superCyreneLyricsTheme == normalized) return;
    _superCyreneLyricsTheme = normalized;
    _prefs?.setString(_kSuperCyreneLyricsTheme, normalized);
    notifyListeners();
  }

  void setWallpaperPlayerEnabled(bool value) {
    if (_wallpaperPlayerEnabled == value) return;
    _wallpaperPlayerEnabled = value;
    _prefs?.setBool(_kWallpaperPlayerEnabled, value);
    notifyListeners();
  }

  void setTaskbarPlayerEnabled(bool value) {
    if (_taskbarPlayerEnabled == value) return;
    _taskbarPlayerEnabled = value;
    _prefs?.setBool(_kTaskbarPlayerEnabled, value);
    notifyListeners();
  }

  void setTaskbarPlayerAlignment(TaskbarPlayerAlignment value) {
    if (_taskbarPlayerAlignment == value) return;
    _taskbarPlayerAlignment = value;
    _prefs?.setString(_kTaskbarPlayerAlignment, value.wireName);
    notifyListeners();
  }

  /// 记录拖拽后的形态与位置。由原生经 onModeChanged 回报，用于下次启动时
  /// 把窗口放回原处。
  void setTaskbarPlayerPlacement(TaskbarPlayerMode mode, int x, int y) {
    final changed =
        _taskbarPlayerMode != mode ||
        _taskbarPlayerFloatingX != x ||
        _taskbarPlayerFloatingY != y;
    if (!changed) return;
    _taskbarPlayerMode = mode;
    _prefs?.setString(_kTaskbarPlayerMode, mode.wireName);
    // 固定形态下的坐标没有意义（位置由空白扫描算），不覆盖已保存的悬浮位置
    // ——否则「拖回任务栏 → 重启 → 再拖出来」会丢掉用户上次的悬浮落点。
    if (mode == TaskbarPlayerMode.floating) {
      _taskbarPlayerFloatingX = x;
      _taskbarPlayerFloatingY = y;
      _prefs?.setInt(_kTaskbarPlayerFloatingX, x);
      _prefs?.setInt(_kTaskbarPlayerFloatingY, y);
    }
    notifyListeners();
  }

  /// 拖拽歌词时高频调用（每帧一次），不夹紧——用户可以把歌词拖到屏幕外，
  /// 由「重置」找回。夹紧反而会在边缘产生粘滞感。
  void setDesktopLyricOffset(double x, double y) {
    if (_desktopLyricOffsetX == x && _desktopLyricOffsetY == y) return;
    _desktopLyricOffsetX = x;
    _desktopLyricOffsetY = y;
    _prefs?.setDouble(_kDesktopLyricOffsetX, x);
    _prefs?.setDouble(_kDesktopLyricOffsetY, y);
    notifyListeners();
  }

  void setDesktopLyricScale(double value) {
    final clamped = value.clamp(minDesktopLyricScale, maxDesktopLyricScale);
    if (_desktopLyricScale == clamped) return;
    _desktopLyricScale = clamped;
    _prefs?.setDouble(_kDesktopLyricScale, clamped);
    notifyListeners();
  }

  void setDesktopLyricRotX(double value) {
    final clamped = value.clamp(
      -maxDesktopLyricRotation,
      maxDesktopLyricRotation,
    );
    if (_desktopLyricRotX == clamped) return;
    _desktopLyricRotX = clamped;
    _prefs?.setDouble(_kDesktopLyricRotX, clamped);
    notifyListeners();
  }

  void setDesktopLyricRotY(double value) {
    final clamped = value.clamp(
      -maxDesktopLyricRotation,
      maxDesktopLyricRotation,
    );
    if (_desktopLyricRotY == clamped) return;
    _desktopLyricRotY = clamped;
    _prefs?.setDouble(_kDesktopLyricRotY, clamped);
    notifyListeners();
  }

  void setDesktopLyricRotZ(double value) {
    final clamped = value.clamp(
      -maxDesktopLyricRotation,
      maxDesktopLyricRotation,
    );
    if (_desktopLyricRotZ == clamped) return;
    _desktopLyricRotZ = clamped;
    _prefs?.setDouble(_kDesktopLyricRotZ, clamped);
    notifyListeners();
  }

  /// 一次性把六个参数清零。
  ///
  /// 不复用上面的 setter：逐个调会连发 6 次 notifyListeners，歌词层在一帧内
  /// 重建 6 次。
  void resetDesktopLyricTransform() {
    if (desktopLyricTransformIsDefault) return;
    _desktopLyricOffsetX = 0;
    _desktopLyricOffsetY = 0;
    _desktopLyricScale = 1;
    _desktopLyricRotX = 0;
    _desktopLyricRotY = 0;
    _desktopLyricRotZ = 0;
    _prefs
      ?..setDouble(_kDesktopLyricOffsetX, 0)
      ..setDouble(_kDesktopLyricOffsetY, 0)
      ..setDouble(_kDesktopLyricScale, 1)
      ..setDouble(_kDesktopLyricRotX, 0)
      ..setDouble(_kDesktopLyricRotY, 0)
      ..setDouble(_kDesktopLyricRotZ, 0);
    notifyListeners();
  }
}
