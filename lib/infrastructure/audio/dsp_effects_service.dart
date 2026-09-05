import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_filter_chain.dart';

/// 滑条取值 → FFmpeg 选项值的换算方式。
///
/// FFmpeg 若干滤镜的增益/阈值类参数用的是「线性振幅」（1.0 = 0dB），直接拿它
/// 当滑条量纲既不直观也不好调，所以 UI 一律用 dB，下发前再换算。
enum DspParamScale {
  /// 滑条值即 FFmpeg 值。
  direct,

  /// 滑条值是 dB，FFmpeg 侧要线性振幅：10^(dB/20)。
  decibel,

  /// 滑条值取整后下发。
  integer,

  /// 滑条值取整并强制为奇数（`dynaudnorm` 的 gausssize 只接受奇数）。
  oddInteger,
}

/// 单个可调参数。[min]/[max]/[defaultValue] 都是「显示量纲」下的值。
@immutable
class DspParamSpec {
  const DspParamSpec({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit = '',
    this.decimals = 1,
    this.scale = DspParamScale.direct,
  });

  /// FFmpeg 选项名，同时用作持久化键。
  final String key;
  final String label;
  final double min;
  final double max;
  final double defaultValue;
  final String unit;
  final int decimals;
  final DspParamScale scale;

  double clamp(double value) => value.clamp(min, max);

  /// 显示文本，如 `+6.0 dB`、`100 Hz`。
  String format(double value) {
    final rounded = switch (scale) {
      DspParamScale.integer || DspParamScale.oddInteger => value
          .roundToDouble(),
      _ => value,
    };
    final digits = switch (scale) {
      DspParamScale.integer || DspParamScale.oddInteger => 0,
      _ => decimals,
    };
    // dB 类参数带符号更容易读出「提升还是衰减」。
    final sign = unit == 'dB' && rounded > 0 ? '+' : '';
    final text = '$sign${rounded.toStringAsFixed(digits)}';
    return unit.isEmpty ? text : '$text $unit';
  }

  /// 换算成 FFmpeg 选项值。
  String encode(double value) {
    final v = clamp(value);
    switch (scale) {
      case DspParamScale.direct:
        return v.toStringAsFixed(math.max(decimals, 2));
      case DspParamScale.decibel:
        return math.pow(10, v / 20).toStringAsFixed(6);
      case DspParamScale.integer:
        return v.round().toString();
      case DspParamScale.oddInteger:
        // 向下取到最近的奇数，再夹回范围内（min 本身也是奇数）。
        final odd = (v.round() ~/ 2) * 2 + 1;
        return odd.clamp(min.round(), max.round()).toString();
    }
  }
}

/// 一个 FFmpeg 音频滤镜的完整描述。
@immutable
class DspFilterSpec {
  const DspFilterSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.params,
    this.fixedArgs = const {},
  });

  /// FFmpeg 滤镜名，同时用作持久化键。
  final String id;
  final String title;
  final String subtitle;
  final List<DspParamSpec> params;

  /// 不暴露给用户、但必须固定下发的选项（如 `width_type=o`）。
  final Map<String, String> fixedArgs;

  Map<String, double> get defaults => {
    for (final param in params) param.key: param.defaultValue,
  };

  /// 编译成一段 FFmpeg 滤镜串，如
  /// `bass=width_type=o:frequency=100.00:width=0.50:gain=6.00`。
  String build(Map<String, double> values) {
    final args = <String>[
      for (final entry in fixedArgs.entries) '${entry.key}=${entry.value}',
      for (final param in params)
        '${param.key}=${param.encode(values[param.key] ?? param.defaultValue)}',
    ];
    return '$id=${args.join(':')}';
  }
}

/// DSP 音效（10 个 FFmpeg 音频滤镜）。
///
/// 依赖 `packages/` 下两个 path override 指向的 libmpv 定制构建——官方的最小
/// 音频构建只编进了 `equalizer`，这些滤镜会被拒绝。因此只在捆绑了定制构建的
/// 平台可用（[isSupported]），其余平台不注册也不显示入口。
///
/// 与 [EqualizerService] 一样只往 [AudioFilterChain] 登记片段，不直接写 `af`。
class DspEffectsService extends ChangeNotifier {
  DspEffectsService._();

  static final DspEffectsService instance = DspEffectsService._();

  /// 当前平台的 libmpv 是否带这些滤镜：只有 packages/ 下做了 path override 的
  /// 平台用的是定制构建。Linux 接入后加进来即可。
  static const Set<TargetPlatform> _supportedPlatforms = {
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  };

  static bool get isSupported =>
      !kIsWeb && _supportedPlatforms.contains(defaultTargetPlatform);

  static const _kEnabled = 'player_dsp_enabled';
  static const _kState = 'player_dsp_state';

  /// 滤镜定义与下发顺序，即信号链顺序：
  /// 音色 → 声场 → 调制 → 动态 → 限幅（限幅垫底，兜住前级的增益）。
  static const List<DspFilterSpec> filters = [
    DspFilterSpec(
      id: 'bass',
      title: '低音增强',
      subtitle: '低架式滤波器，抬升或压低低频',
      // width_type=o：带宽以「倍频程」计，比 Q 值直观。
      fixedArgs: {'width_type': 'o'},
      params: [
        DspParamSpec(
          key: 'gain',
          label: '增益',
          min: -20,
          max: 20,
          defaultValue: 6,
          unit: 'dB',
        ),
        DspParamSpec(
          key: 'frequency',
          label: '中心频率',
          min: 40,
          max: 250,
          defaultValue: 100,
          unit: 'Hz',
          scale: DspParamScale.integer,
        ),
        DspParamSpec(
          key: 'width',
          label: '带宽',
          min: 0.1,
          max: 2,
          defaultValue: 0.5,
          unit: 'oct',
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'treble',
      title: '高音增强',
      subtitle: '高架式滤波器，抬升或压低高频',
      fixedArgs: {'width_type': 'o'},
      params: [
        DspParamSpec(
          key: 'gain',
          label: '增益',
          min: -20,
          max: 20,
          defaultValue: 4,
          unit: 'dB',
        ),
        DspParamSpec(
          key: 'frequency',
          label: '中心频率',
          min: 1500,
          max: 12000,
          defaultValue: 3000,
          unit: 'Hz',
          scale: DspParamScale.integer,
        ),
        DspParamSpec(
          key: 'width',
          label: '带宽',
          min: 0.1,
          max: 2,
          defaultValue: 0.5,
          unit: 'oct',
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'crossfeed',
      title: '耳机串扰',
      subtitle: '模拟音箱的左右耳串音，缓解耳机的「脑内定位」',
      params: [
        DspParamSpec(
          key: 'strength',
          label: '串扰强度',
          min: 0,
          max: 1,
          defaultValue: 0.2,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'range',
          label: '声场宽度',
          min: 0,
          max: 1,
          defaultValue: 0.5,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'slope',
          label: '曲线斜率',
          min: 0.01,
          max: 1,
          defaultValue: 0.5,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'level_out',
          label: '输出电平',
          min: 0,
          max: 1,
          defaultValue: 1,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'stereowiden',
      title: '立体声扩展',
      subtitle: '延时反馈加宽声场',
      params: [
        DspParamSpec(
          key: 'delay',
          label: '延时',
          min: 1,
          max: 100,
          defaultValue: 20,
          unit: 'ms',
        ),
        DspParamSpec(
          key: 'feedback',
          label: '反馈量',
          min: 0,
          max: 0.9,
          defaultValue: 0.3,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'crossfeed',
          label: '交叉馈送',
          min: 0,
          max: 0.8,
          defaultValue: 0.3,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'drymix',
          label: '干声混合',
          min: 0,
          max: 1,
          defaultValue: 0.8,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'vibrato',
      title: '颤音',
      subtitle: '周期性音高抖动',
      params: [
        DspParamSpec(
          key: 'f',
          label: '频率',
          min: 0.1,
          max: 20,
          defaultValue: 5,
          unit: 'Hz',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'd',
          label: '深度',
          min: 0,
          max: 1,
          defaultValue: 0.5,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'aecho',
      title: '回声',
      subtitle: '单抽头延时回声，营造空间感',
      params: [
        DspParamSpec(
          key: 'in_gain',
          label: '输入增益',
          min: 0,
          max: 1,
          defaultValue: 0.6,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'out_gain',
          label: '输出增益',
          min: 0,
          max: 1,
          defaultValue: 0.3,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'delays',
          label: '延时',
          min: 10,
          max: 2000,
          defaultValue: 500,
          unit: 'ms',
          scale: DspParamScale.integer,
        ),
        // 下限不能取 0：FFmpeg 的 aecho 要求 decay > 0，否则整条滤镜链初始化失败。
        DspParamSpec(
          key: 'decays',
          label: '衰减',
          min: 0.01,
          max: 1,
          defaultValue: 0.5,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'acrusher',
      title: '比特压碎',
      subtitle: '降位深/降采样的 Lo-Fi 音色',
      params: [
        DspParamSpec(
          key: 'bits',
          label: '位深',
          min: 1,
          max: 16,
          defaultValue: 8,
          unit: 'bit',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'samples',
          label: '采样保持',
          min: 1,
          max: 50,
          defaultValue: 1,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'mix',
          label: '干湿比',
          min: 0,
          max: 1,
          defaultValue: 0.5,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'dc',
          label: '直流偏置',
          min: 0.25,
          max: 4,
          defaultValue: 1,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'aa',
          label: '抗锯齿',
          min: 0,
          max: 1,
          defaultValue: 0.5,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'dynaudnorm',
      title: '动态音量均衡',
      subtitle: '拉平不同歌曲/段落的响度差异',
      params: [
        DspParamSpec(
          key: 'framelen',
          label: '帧长',
          min: 10,
          max: 2000,
          defaultValue: 500,
          unit: 'ms',
          scale: DspParamScale.integer,
        ),
        DspParamSpec(
          key: 'gausssize',
          label: '平滑窗口',
          min: 3,
          max: 301,
          defaultValue: 31,
          scale: DspParamScale.oddInteger,
        ),
        DspParamSpec(
          key: 'peak',
          label: '峰值上限',
          min: 0.1,
          max: 1,
          defaultValue: 0.95,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'maxgain',
          label: '最大放大',
          min: 1,
          max: 100,
          defaultValue: 10,
          unit: '×',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'targetrms',
          label: '目标 RMS',
          min: 0,
          max: 1,
          defaultValue: 0,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'compress',
          label: '压缩系数',
          min: 0,
          max: 30,
          defaultValue: 0,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'acompressor',
      title: '动态压缩',
      subtitle: '压低峰值、抬起细节，适合嘈杂环境',
      params: [
        DspParamSpec(
          key: 'threshold',
          label: '阈值',
          min: -60,
          max: 0,
          defaultValue: -18,
          unit: 'dB',
          scale: DspParamScale.decibel,
        ),
        DspParamSpec(
          key: 'ratio',
          label: '压缩比',
          min: 1,
          max: 20,
          defaultValue: 4,
          unit: ': 1',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'attack',
          label: '启动时间',
          min: 1,
          max: 500,
          defaultValue: 20,
          unit: 'ms',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'release',
          label: '释放时间',
          min: 10,
          max: 2000,
          defaultValue: 250,
          unit: 'ms',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'makeup',
          label: '补偿增益',
          min: 0,
          max: 24,
          defaultValue: 2,
          unit: 'dB',
          scale: DspParamScale.decibel,
        ),
        DspParamSpec(
          key: 'knee',
          label: '拐点柔和度',
          min: 1,
          max: 8,
          defaultValue: 2.83,
          decimals: 2,
        ),
        DspParamSpec(
          key: 'mix',
          label: '干湿比',
          min: 0,
          max: 1,
          defaultValue: 1,
          decimals: 2,
        ),
      ],
    ),
    DspFilterSpec(
      id: 'alimiter',
      title: '限幅保护',
      subtitle: '兜住前级增益，防止削顶失真',
      // level=0：关掉 alimiter 的自动电平（默认开），否则它会顺带把安静片段
      // 整体推上去，听感上像音量被莫名改动。这里只要它做纯保护。
      fixedArgs: {'level': '0'},
      params: [
        DspParamSpec(
          key: 'limit',
          label: '限幅点',
          min: -24,
          max: 0,
          defaultValue: -1,
          unit: 'dB',
          scale: DspParamScale.decibel,
        ),
        DspParamSpec(
          key: 'level_in',
          label: '输入电平',
          min: -12,
          max: 12,
          defaultValue: 0,
          unit: 'dB',
          scale: DspParamScale.decibel,
        ),
        DspParamSpec(
          key: 'level_out',
          label: '输出电平',
          min: -12,
          max: 12,
          defaultValue: 0,
          unit: 'dB',
          scale: DspParamScale.decibel,
        ),
        DspParamSpec(
          key: 'attack',
          label: '启动时间',
          min: 0.1,
          max: 80,
          defaultValue: 5,
          unit: 'ms',
          decimals: 2,
        ),
        DspParamSpec(
          key: 'release',
          label: '释放时间',
          min: 1,
          max: 1000,
          defaultValue: 50,
          unit: 'ms',
          decimals: 2,
        ),
      ],
    ),
  ];

  static DspFilterSpec specOf(String id) =>
      filters.firstWhere((filter) => filter.id == id);

  bool _enabled = false;
  final Map<String, bool> _filterEnabled = {};
  final Map<String, Map<String, double>> _values = {};
  Future<void>? _loading;
  Timer? _saveTimer;

  /// 总开关。关闭时整段 DSP 滤镜从链上摘除。
  bool get enabled => _enabled;

  /// 已开启的滤镜个数（供设置页显示摘要）。
  int get activeCount =>
      _enabled ? filters.where((f) => isFilterEnabled(f.id)).length : 0;

  bool isFilterEnabled(String id) => _filterEnabled[id] ?? false;

  /// 取某滤镜某参数的当前值，未设置过则回落到默认值。
  double valueOf(String filterId, String paramKey) =>
      _values[filterId]?[paramKey] ??
      specOf(filterId).params
          .firstWhere((param) => param.key == paramKey)
          .defaultValue;

  /// 载入持久化设置（幂等）。
  Future<void> ensureLoaded() => _loading ??= _load();

  /// 载入并应用——供 App 启动时绑定播放器后调用。
  Future<void> ensureApplied() async {
    if (!isSupported) return;
    await ensureLoaded();
    await _apply();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      final raw = prefs.getString(_kState);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) _restore(decoded);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[DspEffectsService] 加载 DSP 设置失败: $e');
    }
  }

  /// 按 spec 逐项校验地还原，丢弃已不存在的滤镜/参数与越界值——滤镜表以后会
  /// 增删，旧存档不能把非法值喂给 FFmpeg。
  void _restore(Map<dynamic, dynamic> decoded) {
    for (final spec in filters) {
      final entry = decoded[spec.id];
      if (entry is! Map) continue;
      _filterEnabled[spec.id] = entry['on'] == true;
      final params = entry['p'];
      if (params is! Map) continue;
      final values = <String, double>{};
      for (final param in spec.params) {
        final value = params[param.key];
        if (value is num) values[param.key] = param.clamp(value.toDouble());
      }
      if (values.isNotEmpty) _values[spec.id] = values;
    }
  }

  /// 总开关。立即持久化，不节流。
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    await _apply();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, enabled);
    } catch (e) {
      debugPrint('[DspEffectsService] 保存 DSP 开关失败: $e');
    }
  }

  /// 单个滤镜的开关。
  Future<void> setFilterEnabled(String id, bool enabled) async {
    if (isFilterEnabled(id) == enabled) return;
    _filterEnabled[id] = enabled;
    notifyListeners();
    await _apply();
    _scheduleSave();
  }

  /// 调整单个参数（滑条拖动会高频调用，写盘节流 1 秒）。
  Future<void> setParam(String filterId, String paramKey, double value) async {
    final spec = specOf(filterId);
    final param = spec.params.firstWhere((param) => param.key == paramKey);
    final values = _values[filterId] ??= Map.of(spec.defaults);
    final next = param.clamp(value);
    if (values[paramKey] == next) return;
    values[paramKey] = next;
    notifyListeners();
    await _apply();
    _scheduleSave();
  }

  /// 把某个滤镜的参数复位到默认值（不改它的开关）。
  Future<void> resetFilter(String id) async {
    _values[id] = Map.of(specOf(id).defaults);
    notifyListeners();
    await _apply();
    _scheduleSave();
  }

  /// 关掉所有滤镜并复位参数（保留总开关状态）。
  Future<void> resetAll() async {
    _filterEnabled.clear();
    _values.clear();
    notifyListeners();
    await _apply();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _save);
  }

  Future<void> _save() async {
    try {
      final payload = <String, dynamic>{
        for (final spec in filters)
          spec.id: {
            'on': isFilterEnabled(spec.id),
            'p': _values[spec.id] ?? spec.defaults,
          },
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kState, jsonEncode(payload));
    } catch (e) {
      debugPrint('[DspEffectsService] 保存 DSP 参数失败: $e');
    }
  }

  Future<void> _apply() async {
    if (!isSupported) return;
    final segments = <String>[];
    if (_enabled) {
      for (final spec in filters) {
        if (!isFilterEnabled(spec.id)) continue;
        segments.add(spec.build(_values[spec.id] ?? spec.defaults));
      }
    }
    await AudioFilterChain.instance.setSegments(
      AudioFilterChain.dspSlot,
      segments,
    );
  }
}
