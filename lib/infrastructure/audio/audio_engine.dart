import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../services/crash_log_service.dart';

/// 原生音频引擎（media_kit / libmpv）的可用性。
///
/// 存在的理由是一次真实事故：iOS/macOS 的自定义 libmpv 因构建期校验和失配
/// 而根本没被打进包（podspec 里 `system("make")` 的失败被丢弃，见
/// `packages/media_kit_libs_ios_audio/ios/media_kit_libs_ios_audio.podspec`），
/// `MediaKit.ensureInitialized()` 于是在 `runApp` 之前抛异常，整个应用白屏。
/// 没有崩溃、没有报错、用户拿不到控制台——最难查的一类故障。
///
/// 所以初始化失败不再向上冒泡：这里把它记下来，应用照常起来（播放走
/// `SilentAudioPlayerGateway`，除了不出声其余功能都在），由 UI 明确告知用户。
///
/// 状态在启动时定一次，之后不再变化，故用静态字段而非 Listenable。
abstract final class AudioEngine {
  static bool _available = false;
  static bool _initialized = false;
  static Object? _error;

  /// 原生播放器是否可用。为 false 时全应用无声，但界面与其余功能正常。
  static bool get isAvailable => _available;

  /// 初始化失败的原因（[isAvailable] 为 true 时恒为 null）。
  static Object? get error => _error;

  /// 给用户看的一行摘要（异常的 toString 往往很长，这里截断）。
  static String get errorSummary {
    final text = _error?.toString().trim() ?? '';
    if (text.isEmpty) return '未知错误';
    final firstLine = text.split('\n').first;
    return firstLine.length > 160
        ? '${firstLine.substring(0, 160)}…'
        : firstLine;
  }

  /// 加载 libmpv。**绝不抛出**——失败时只置位状态并落崩溃日志。
  ///
  /// 必须在构造任何 [MediaKitPlayerGateway] 之前调用一次（见 main 的
  /// `_bootstrap`）。重复调用是幂等的。
  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    try {
      MediaKit.ensureInitialized();
      _available = true;
    } catch (error, stack) {
      markUnavailable(error, stack);
    }
  }

  /// 标记引擎不可用。
  ///
  /// 除了 [ensureInitialized] 自身，`Player()` 的构造也可能失败（libmpv 加载
  /// 成功不等于实例建得起来），那条路径同样汇聚到这里，见
  /// `AppDependencies._createAudioGateway`。
  static void markUnavailable(Object error, StackTrace stack) {
    _initialized = true;
    _available = false;
    _error = error;
    CrashLogService.instance.logException(
      error,
      stack,
      context: 'audio_engine',
    );
    debugPrint('[音频引擎] libmpv 不可用，已降级为静音模式: $error');
  }

  /// 仅供测试重置。
  @visibleForTesting
  static void resetForTesting({bool available = false}) {
    _initialized = available;
    _available = available;
    _error = null;
  }
}
