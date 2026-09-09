import 'dart:async';

import 'package:flutter/foundation.dart';

/// 启动步骤的面包屑，兼做「哪一步卡住了」的唯一证据。
///
/// 白屏有两种成因，且第二种是前一次修复完全没覆盖到的：
///
/// 1. **抛异常**：`_bootstrap` 中断，`runApp` 不执行。这种有 try/catch 兜底，
///    能落到 `StartupFailureApp`。
/// 2. **卡住**：某一步的 `await` 永远不返回（平台通道没人应答、插件在当前
///    平台没注册却又不报错、原生侧死锁……）。**try/catch 对此毫无作用**——
///    没有异常，只是永远不往下走。`runApp` 同样不执行，屏幕上还是 iOS 的
///    白色 LaunchScreen，一行日志都没有。用户能反馈的就只有「打开就是白的」。
///
/// 本类针对第二种：每一步启动都经 [guard] 登记并**带超时**，于是
/// - 单步卡死不再拖垮整个启动（超时即降级继续，那一步的功能失效而已）；
/// - 万一还是没能渲染首帧，看门狗把 [report] 直接画到屏幕上，
///   「卡在第几步」变成用户随手一张截图就能反馈的信息。
///
/// 只依赖 `dart:async`：它服务的正是「其它一切都可能是坏的」那个场景。
abstract final class StartupTrace {
  /// 单步默认超时。
  ///
  /// 取值权衡：正常冷启动每一步都在百毫秒级（偏好读取、着色器预热），6 秒
  /// 足够宽松到不会误伤老设备；同时又远小于用户失去耐心的时间，卡住时
  /// 只赔上 6 秒就能继续启动，而不是白屏到用户强杀。
  static const Duration defaultTimeout = Duration(seconds: 6);

  static final Stopwatch _clock = Stopwatch()..start();
  static final List<StartupStep> _steps = <StartupStep>[];
  static bool _firstFrame = false;
  static bool _runAppCalled = false;

  /// 已登记的步骤（按开始顺序）。
  static List<StartupStep> get steps => List.unmodifiable(_steps);

  /// 首帧是否已经画出来了。看门狗据此判断「白屏」是否真的发生。
  static bool get firstFrameRendered => _firstFrame;

  /// `runApp` 是否已被调用。
  ///
  /// 首帧判定要用到它：挂上根 widget 之前引擎也可能画出一帧空树（窗口尺寸
  /// 变化等会触发），那种帧照样是白的，不能当作「起来了」。
  static bool get runAppCalled => _runAppCalled;

  /// 由 `runApp` 调用点登记。
  static void markRunApp() {
    if (_runAppCalled) return;
    _runAppCalled = true;
    mark('run_app');
  }

  /// 有没有步骤超时或失败——决定要不要提示用户「本次启动有功能降级」。
  static bool get hasIssues => _steps.any((step) => step.status.isIssue);

  /// 出问题的步骤名，用于给用户的一句话提示。
  static List<String> get issueNames => _steps
      .where((step) => step.status.isIssue)
      .map((step) => step.name)
      .toList(growable: false);

  /// 由首帧回调调用，停止看门狗的判定。
  static void markFirstFrame() {
    if (_firstFrame) return;
    _firstFrame = true;
    mark('first_frame');
  }

  /// 记录一个瞬时里程碑（如 `run_app`），不计时长。
  static void mark(String name) {
    _steps.add(
      StartupStep._(name, _clock.elapsed)
        ..status = StartupStepStatus.ok
        ..end = _clock.elapsed,
    );
  }

  /// 跑一步启动逻辑：登记、限时、**绝不向上抛**。
  ///
  /// 超时不会取消 [body]（Dart 没有这个能力），只是不再等它——后台跑完了
  /// 该 store 照样会 notify，UI 自然刷新。相比之下继续等下去的代价是整个
  /// 应用永远起不来，孰轻孰重很清楚。
  ///
  /// 返回值：成功时是 [body] 的结果，超时或失败时是 null。
  static Future<T?> guard<T>(
    String name,
    Future<T> Function() body, {
    Duration? timeout,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    final step = StartupStep._(name, _clock.elapsed);
    _steps.add(step);
    try {
      final result = await body().timeout(timeout ?? defaultTimeout);
      step
        ..status = StartupStepStatus.ok
        ..end = _clock.elapsed;
      return result;
    } on TimeoutException {
      step
        ..status = StartupStepStatus.timedOut
        ..end = _clock.elapsed;
      debugPrint('[启动] 步骤「$name」超时，已跳过继续启动');
      return null;
    } catch (error, stack) {
      step
        ..status = StartupStepStatus.failed
        ..end = _clock.elapsed
        ..error = error;
      debugPrint('[启动] 步骤「$name」失败，已跳过继续启动: $error');
      onError?.call(error, stack);
      return null;
    }
  }

  /// 人类可读的追踪报告：给用户截图、给崩溃日志留档，两处共用。
  ///
  /// 未结束的步骤标 `← 卡在这里`，那一行就是排查的起点。
  static String report() {
    if (_steps.isEmpty) return '（没有任何启动步骤被记录，卡点在 main 最开头）';
    final buffer = StringBuffer('已耗时 ${_ms(_clock.elapsed)}\n');
    for (final step in _steps) {
      buffer.writeln(step._line());
    }
    return buffer.toString().trimRight();
  }

  static String _ms(Duration duration) => '${duration.inMilliseconds}ms';

  /// 仅供测试重置。
  @visibleForTesting
  static void resetForTesting() {
    _steps.clear();
    _firstFrame = false;
    _runAppCalled = false;
    _clock
      ..reset()
      ..start();
  }
}

/// 单个启动步骤的结局。
enum StartupStepStatus {
  /// 还没回来——报告生成时它就是卡住的那一步。
  running('⟳', '未完成'),

  ok('✓', ''),

  /// 超过限时，已放弃等待继续启动。
  timedOut('⏱', '超时'),

  failed('✗', '失败');

  const StartupStepStatus(this.glyph, this.label);

  final String glyph;
  final String label;

  /// 需要提示用户「有功能降级」的结局。
  bool get isIssue => this == timedOut || this == failed;
}

/// 一步启动逻辑的记录。
class StartupStep {
  StartupStep._(this.name, this.start);

  final String name;
  final Duration start;

  Duration? end;
  StartupStepStatus status = StartupStepStatus.running;
  Object? error;

  /// 该步骤耗时；未结束时为 null。
  Duration? get duration => end == null ? null : end! - start;

  String _line() {
    final elapsed = duration;
    final buffer = StringBuffer(
      '  ${status.glyph} ${name.padRight(22)} '
      '${elapsed == null ? '—' : StartupTrace._ms(elapsed)}',
    );
    if (status.label.isNotEmpty) buffer.write('  ${status.label}');
    if (status == StartupStepStatus.running) buffer.write('  ← 卡在这里');
    if (error != null) buffer.write('  $error');
    return buffer.toString();
  }
}
