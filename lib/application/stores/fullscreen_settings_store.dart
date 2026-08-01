import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/lyrics/lyric_fonts.dart';
import '../../domain/playback/player_display_settings.dart';

/// 全屏播放器显示设置（对应 Next.js usePlayerSettings 的移动端子集）。
///
/// 单例 ChangeNotifier；[init] 在 app 启动时载入 shared_preferences 持久化值，
/// 各 setter 同步写回。消费方：FullscreenPlayer / PlayerSettingsSheet。
class FullscreenSettingsStore extends ChangeNotifier {
  FullscreenSettingsStore._();

  static final FullscreenSettingsStore instance = FullscreenSettingsStore._();

  static const _kAudioVisualization = 'fullscreen.audioVisualization';
  static const _kImmersiveMode = 'fullscreen.immersiveMode';
  static const _kHideAlbumCover = 'fullscreen.hideAlbumCover';
  static const _kShowTranslation = 'fullscreen.showTranslation';
  static const _kLyricDisplayStyle = 'fullscreen.lyricDisplayStyle';
  static const _kSingleLineAnimation = 'fullscreen.singleLineAnimation';
  static const _kLyricFontFamily = 'fullscreen.lyricFontFamily';
  static const _kLyricFontSize = 'fullscreen.lyricFontSize';
  static const _kLyricBlurStrength = 'fullscreen.lyricBlurStrength';

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

  bool get audioVisualization => _audioVisualization;
  bool get isImmersiveMode => _isImmersiveMode;
  bool get hideAlbumCover => _hideAlbumCover;
  bool get showTranslation => _showTranslation;
  LyricDisplayStyle get lyricDisplayStyle => _lyricDisplayStyle;
  SingleLineAnimation get singleLineAnimation => _singleLineAnimation;
  String get lyricFontFamily => _lyricFontFamily;
  double get lyricFontSize => _lyricFontSize;
  double get lyricBlurStrength => _lyricBlurStrength;

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
}
