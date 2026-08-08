import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 10 段均衡器（对应原版 PlayerService 的均衡器部分）。
///
/// 与原版同一实现机制：向 libmpv 的 `af` 属性注入 FFmpeg `equalizer`
/// 滤镜链（`equalizer=f=31:width_type=o:width=1:g=1.5,...`），因此仅在
/// media_kit（NativePlayer）后端生效；持久化键名与原版一致
/// （`player_eq_gains` / `player_eq_enabled`），旧数据可直接沿用。
class EqualizerService extends ChangeNotifier {
  EqualizerService._();

  static final EqualizerService instance = EqualizerService._();

  /// 各频段中心频率（Hz），与原版 kEqualizerFrequencies 一致。
  static const List<int> frequencies = [
    31,
    63,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

  /// 单段增益范围 ±12 dB（与原版滑条一致）。
  static const double maxGainDb = 12.0;

  static const _kGains = 'player_eq_gains';
  static const _kEnabled = 'player_eq_enabled';

  Player? _player;
  List<double> _gains = List.filled(frequencies.length, 0.0);
  /// 默认关闭均衡器；仅当用户显式开启时才对音频应用 `af` 滤镜链（原版
  /// 默认开启，但历史残留增益会在每次启动时静默生效，容易造成失真）。
  bool _enabled = false;
  Future<void>? _loading;
  Timer? _saveTimer;

  List<double> get gains => List.unmodifiable(_gains);
  bool get enabled => _enabled;

  /// 绑定播放器并应用当前设置（由 AppDependencies 在创建播放网关时调用）。
  Future<void> attach(Player player) async {
    _player = player;
    await ensureLoaded();
    await _apply();
  }

  /// 载入持久化设置（幂等；均衡器页打开时也会调用，保证未 attach 也能编辑）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kGains);
      if (saved != null && saved.length == frequencies.length) {
        _gains = saved
            .map((value) => double.tryParse(value) ?? 0.0)
            .toList(growable: false);
      }
      _enabled = prefs.getBool(_kEnabled) ?? _enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('[EqualizerService] 加载均衡器设置失败: $e');
    }
  }

  /// 更新 10 段增益并应用（与原版一致：增益写入带 1 秒节流）。
  Future<void> updateGains(List<double> gains) async {
    if (gains.length != frequencies.length) return;
    _gains = List.of(gains, growable: false);
    notifyListeners();
    await _apply();
    _scheduleSaveGains();
  }

  /// 总开关；关闭即清空滤镜链恢复原始输出（立即持久化，不节流）。
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    await _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, enabled);
    } catch (e) {
      debugPrint('[EqualizerService] 保存均衡器开关失败: $e');
    }
  }

  void _scheduleSaveGains() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          _kGains,
          _gains.map((gain) => gain.toString()).toList(growable: false),
        );
      } catch (e) {
        debugPrint('[EqualizerService] 保存均衡器增益失败: $e');
      }
    });
  }

  /// 把当前状态编译成 FFmpeg 滤镜链写入 libmpv。
  ///
  /// 与原版相同的细节：|gain| <= 0.1 的频段跳过；链为空或禁用时写空串清除；
  /// libmpv 属性在 Player 生命周期内保持，切歌无需重设。
  Future<void> _apply() async {
    final platform = _player?.platform;
    if (platform is! NativePlayer) return;
    try {
      if (!_enabled) {
        await platform.setProperty('af', '');
        return;
      }
      final buffer = StringBuffer();
      for (var i = 0; i < frequencies.length; i++) {
        final gain = _gains[i];
        if (gain.abs() <= 0.1) continue;
        if (buffer.isNotEmpty) buffer.write(',');
        buffer.write(
          'equalizer=f=${frequencies[i]}'
          ':width_type=o:width=1:g=${gain.toStringAsFixed(1)}',
        );
      }
      await platform.setProperty('af', buffer.toString());
    } catch (e) {
      debugPrint('[EqualizerService] 应用均衡器失败: $e');
    }
  }
}
