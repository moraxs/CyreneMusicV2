import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 开发者模式（对应原版 developer_mode_service.dart 的移动端子集）。
///
/// 与原版一致：2 秒内连点版本号 5 次开启，从第 2 次起提示剩余次数；
/// 键名照抄（`developer_mode` / `show_performance_overlay` /
/// `search_result_merge_enabled`）；内存日志缓冲上限 1000 条。
///
/// 与原版差异：不直接弹 toast，而是把提示文案返回给调用方展示，
/// 避免基础设施层反向依赖表现层。
class DeveloperModeService extends ChangeNotifier {
  DeveloperModeService._();

  static final DeveloperModeService instance = DeveloperModeService._();

  static const _kDeveloperMode = 'developer_mode';
  static const _kShowPerformanceOverlay = 'show_performance_overlay';
  static const _kSearchResultMerge = 'search_result_merge_enabled';
  static const _requiredClicks = 5;
  static const _maxLogs = 1000;

  bool _isDeveloperMode = false;
  bool _showPerformanceOverlay = false;
  bool _searchResultMergeEnabled = true;
  bool _loaded = false;
  int _clickCount = 0;
  DateTime? _lastClickTime;

  final List<String> _logs = [];

  /// 日志版本号：每追加一条 +1。日志页监听它而非本服务，
  /// 避免高频 debugPrint 反复重建设置页等无关监听方。
  final ValueNotifier<int> logRevision = ValueNotifier<int>(0);

  bool get isDeveloperMode => _isDeveloperMode;
  bool get showPerformanceOverlay => _showPerformanceOverlay;
  bool get isSearchResultMergeEnabled => _searchResultMergeEnabled;
  List<String> get logs => List.unmodifiable(_logs);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDeveloperMode = prefs.getBool(_kDeveloperMode) ?? false;
      _showPerformanceOverlay =
          prefs.getBool(_kShowPerformanceOverlay) ?? false;
      _searchResultMergeEnabled =
          prefs.getBool(_kSearchResultMerge) ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('[DeveloperModeService] 加载失败: $e');
    }
  }

  /// 版本号被点击一次；返回需要展示给用户的提示文案（无需提示时为 null）。
  String? onVersionClicked() {
    final now = DateTime.now();
    // 与原版一致：距上次点击超过 2 秒则计数清零。
    if (_lastClickTime != null &&
        now.difference(_lastClickTime!).inSeconds > 2) {
      _clickCount = 0;
    }
    _lastClickTime = now;
    _clickCount++;

    if (_isDeveloperMode) {
      if (_clickCount >= _requiredClicks) {
        _clickCount = 0;
        return '您已处于开发者模式';
      }
      return null;
    }
    if (_clickCount >= _requiredClicks) {
      _clickCount = 0;
      _setDeveloperMode(true);
      return '开发者模式已启用';
    }
    if (_clickCount >= 2) {
      return '再点击 ${_requiredClicks - _clickCount} 次即可开启开发者模式';
    }
    return null;
  }

  /// 退出开发者模式（同时关闭性能叠加层）。
  Future<void> disableDeveloperMode() async {
    if (!_isDeveloperMode) return;
    _showPerformanceOverlay = false;
    await _setDeveloperMode(false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShowPerformanceOverlay, false);
    } catch (e) {
      debugPrint('[DeveloperModeService] 保存失败: $e');
    }
  }

  Future<void> setShowPerformanceOverlay(bool value) async {
    if (_showPerformanceOverlay == value) return;
    _showPerformanceOverlay = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShowPerformanceOverlay, value);
    } catch (e) {
      debugPrint('[DeveloperModeService] 保存失败: $e');
    }
  }

  /// 切换搜索结果合并开关（true=聚合多平台同名歌曲，false=按平台分别展示标签）。
  Future<void> setSearchResultMergeEnabled(bool value) async {
    if (_searchResultMergeEnabled == value) return;
    _searchResultMergeEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSearchResultMerge, value);
    } catch (e) {
      debugPrint('[DeveloperModeService] 保存失败: $e');
    }
  }

  /// 追加一条运行日志（由 main() 挂接的 debugPrint 钩子调用；
  /// 本方法内严禁再调 debugPrint，否则递归）。
  void addLog(String message) {
    _logs.add('${DateTime.now().toIso8601String().substring(11, 23)} $message');
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    logRevision.value++;
  }

  void clearLogs() {
    _logs.clear();
    logRevision.value++;
  }

  Future<void> _setDeveloperMode(bool value) async {
    _isDeveloperMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDeveloperMode, value);
    } catch (e) {
      debugPrint('[DeveloperModeService] 保存失败: $e');
    }
  }
}
