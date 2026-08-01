import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoCollapseService extends ChangeNotifier {
  static final AutoCollapseService _instance = AutoCollapseService._internal();

  factory AutoCollapseService() {
    return _instance;
  }

  AutoCollapseService._internal() {
    _loadSettings();
  }

  bool _isAutoCollapseEnabled = false;

  bool get isAutoCollapseEnabled => _isAutoCollapseEnabled;

  static const String _prefKey = 'player_auto_collapse_enabled';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isAutoCollapseEnabled = prefs.getBool(_prefKey) ?? false;
    notifyListeners();
  }

  Future<void> setAutoCollapseEnabled(bool enabled) async {
    if (_isAutoCollapseEnabled == enabled) return;
    _isAutoCollapseEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    notifyListeners();
  }
}
