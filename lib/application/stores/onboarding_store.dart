import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动引导的进度（对应原版 `terms_accepted` 等散落在
/// PersistentStorageService 里的标记，这里收敛成一个 store）。
///
/// 单例 ChangeNotifier；[init] 必须在首帧前完成（见 main），否则老用户启动会
/// 先闪一帧引导页。消费方是 [AppGate]，它把这些标记与登录态一起解析成当前
/// 应该停在哪一步（见 `app_gate.dart` 的 resolveOnboardingStep）。
///
/// 只存「协议已读 / 引导已走完 / 音源步已过 / 样式步已过」等标记：登录态由
/// AccountSessionController 提供，音源是否已配置由
/// AudioSourcePreferencesController 提供，不在这里重复一份，免得两边不同步。
class OnboardingStore extends ChangeNotifier {
  OnboardingStore._();

  static final OnboardingStore instance = OnboardingStore._();

  static const _kTermsAccepted = 'onboarding.termsAccepted';
  static const _kCompleted = 'onboarding.completed';
  static const _kAudioSourceDone = 'onboarding.audioSourceDone';
  static const _kStyleSettingsDone = 'onboarding.styleSettingsDone';

  SharedPreferences? _prefs;
  bool _termsAccepted = false;
  bool _completed = false;
  bool _audioSourceDone = false;
  bool _styleSettingsDone = false;

  /// 用户是否已阅读并同意免责协议（引导第一步）。
  bool get termsAccepted => _termsAccepted;

  /// 三步引导是否已整体走完。
  ///
  /// 置位后用户即便退出登录也不用重走音源那一步——退出登录只会回到第二步
  /// （见 [AppGate]），重新登录即回到主界面。
  bool get completed => _completed;

  /// 是否已越过音源配置步（启用过音源，或选择跳过）。
  bool get audioSourceDone => _audioSourceDone;

  /// 是否已完成样式设置步。
  bool get styleSettingsDone => _styleSettingsDone;

  Future<void> init() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _termsAccepted = prefs.getBool(_kTermsAccepted) ?? false;
    _completed = prefs.getBool(_kCompleted) ?? false;
    _audioSourceDone = prefs.getBool(_kAudioSourceDone) ?? false;
    _styleSettingsDone = prefs.getBool(_kStyleSettingsDone) ?? false;
    notifyListeners();
  }

  /// 同意协议。先落盘再通知：通知会让 [AppGate] 立刻切到下一步，此时磁盘上
  /// 的标记必须已经是新值，否则中途被杀进程会退回协议页。
  Future<void> acceptTerms() async {
    if (_termsAccepted) return;
    await _prefs?.setBool(_kTermsAccepted, true);
    _termsAccepted = true;
    notifyListeners();
  }

  /// 越过音源配置步（引导由第三步推进到第四步）。
  Future<void> setAudioSourceDone(bool value) async {
    if (_audioSourceDone == value) return;
    await _prefs?.setBool(_kAudioSourceDone, value);
    _audioSourceDone = value;
    notifyListeners();
  }

  /// 越过样式设置步。
  Future<void> setStyleSettingsDone(bool value) async {
    if (_styleSettingsDone == value) return;
    await _prefs?.setBool(_kStyleSettingsDone, value);
    _styleSettingsDone = value;
    notifyListeners();
  }

  Future<void> complete() async {
    if (_completed) return;
    await _prefs?.setBool(_kCompleted, true);
    await _prefs?.setBool(_kAudioSourceDone, true);
    await _prefs?.setBool(_kStyleSettingsDone, true);
    _completed = true;
    _audioSourceDone = true;
    _styleSettingsDone = true;
    notifyListeners();
  }
}
