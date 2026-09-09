import 'dart:async';

import 'package:cyrene_music_reborn/app/startup_trace.dart';
import 'package:flutter_test/flutter_test.dart';

/// StartupTrace 存在的意义是覆盖白屏的第二种成因：启动某一步**卡住**
/// （不是抛异常）。所以这里的重点不是「记录得对不对」，而是两条硬约束：
/// 卡住的一步不能拖垮启动，且它必须在报告里被指认出来。
void main() {
  setUp(StartupTrace.resetForTesting);

  test('正常完成的步骤记为 ok 并透传返回值', () async {
    final result = await StartupTrace.guard('ok_step', () async => 42);

    expect(result, 42);
    expect(StartupTrace.steps.single.name, 'ok_step');
    expect(StartupTrace.steps.single.status, StartupStepStatus.ok);
    expect(StartupTrace.hasIssues, isFalse);
  });

  test('卡住的步骤超时后放行，不抛异常也不阻塞后续启动', () async {
    // 永不完成的 future：正是 iOS 上「平台通道没人应答」的样子。
    final stuck = Completer<void>();
    var reachedNextStep = false;

    await StartupTrace.guard(
      'stuck_step',
      () => stuck.future,
      timeout: const Duration(milliseconds: 50),
    );
    await StartupTrace.guard('next_step', () async => reachedNextStep = true);

    // 关键断言：卡住的一步没有把启动挡死，后面的步骤照常跑完。
    expect(reachedNextStep, isTrue);
    expect(StartupTrace.steps.first.status, StartupStepStatus.timedOut);
    expect(StartupTrace.steps.last.status, StartupStepStatus.ok);
  });

  test('抛异常的步骤记为 failed 并留下错误，同样不向上抛', () async {
    final result = await StartupTrace.guard<int>(
      'boom_step',
      () async => throw StateError('libmpv 没打进包'),
    );

    expect(result, isNull);
    expect(StartupTrace.steps.single.status, StartupStepStatus.failed);
    expect(StartupTrace.steps.single.error, isStateError);
  });

  test('guard 把错误交给 onError，便于调用方落崩溃日志', () async {
    Object? seen;
    await StartupTrace.guard<void>(
      'boom_step',
      () async => throw StateError('x'),
      onError: (error, _) => seen = error,
    );

    expect(seen, isStateError);
  });

  test('超时与失败都算「有问题」，用于提示用户功能降级', () async {
    await StartupTrace.guard<void>(
      'stuck',
      () => Completer<void>().future,
      timeout: const Duration(milliseconds: 20),
    );
    await StartupTrace.guard<void>('boom', () async => throw StateError('x'));
    await StartupTrace.guard('fine', () async {});

    expect(StartupTrace.hasIssues, isTrue);
    expect(StartupTrace.issueNames, ['stuck', 'boom']);
  });

  test('未完成的步骤在报告里被标成卡点——这是用户唯一能反馈的线索', () async {
    await StartupTrace.guard('done', () async {});
    // 不 await：模拟看门狗触发时这一步还挂着。
    unawaited(StartupTrace.guard('hanging', () => Completer<void>().future));
    await Future<void>.delayed(Duration.zero);

    final report = StartupTrace.report();
    expect(report, contains('hanging'));
    expect(report, contains('卡在这里'));
    // 已完成的步骤不该被误标成卡点。
    expect(
      report.split('\n').firstWhere((l) => l.contains('done')),
      isNot(contains('卡在这里')),
    );
  });

  test('一步都没跑到时报告也要说人话，而不是空字符串', () {
    expect(StartupTrace.report(), contains('main 最开头'));
  });

  test('runApp 之前不认首帧：空树那一帧同样是白的', () {
    expect(StartupTrace.runAppCalled, isFalse);
    StartupTrace.markRunApp();
    expect(StartupTrace.runAppCalled, isTrue);
    expect(StartupTrace.firstFrameRendered, isFalse);

    StartupTrace.markFirstFrame();
    expect(StartupTrace.firstFrameRendered, isTrue);
  });
}
