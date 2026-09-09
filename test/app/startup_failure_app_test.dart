import 'package:cyrene_music_reborn/app/startup_failure_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这一屏是白屏事故的最后一道防线：它必须在「其它一切都坏了」时还能渲染，
/// 并且把用户反馈问题所需的东西都摆出来——版本号、错误、启动追踪、日志路径。
void main() {
  testWidgets('渲染版本号、错误详情与崩溃日志路径', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(
        error: 'Cannot find Mpv.framework/Mpv',
        appVersion: '2.0.5',
        logFilePath: r'C:\Users\me\AppData\Roaming\Cyrene\crash.log',
      ),
    );

    expect(find.text('Cyrene Music 启动失败'), findsOneWidget);
    expect(find.text('版本 2.0.5'), findsOneWidget);
    expect(find.text('Cannot find Mpv.framework/Mpv'), findsOneWidget);
    expect(
      find.text(r'C:\Users\me\AppData\Roaming\Cyrene\crash.log'),
      findsOneWidget,
    );
  });

  testWidgets('崩溃日志本身没起来时不显示日志段，也不报错', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(error: 'boom', appVersion: '2.0.5'),
    );

    expect(find.text('崩溃日志'), findsNothing);
    expect(find.text('错误'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误文本可选中，便于用户复制反馈', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(error: 'boom', appVersion: '2.0.5'),
    );

    final selectable = tester.widget<SelectableText>(
      find.widgetWithText(SelectableText, 'boom'),
    );
    expect(selectable.data, 'boom');
  });

  // 看门狗那条路径上没有任何异常，追踪就是唯一线索——它必须显示出来，
  // 且标题要跟「抛异常」区分开，否则排查方向会被带偏。
  testWidgets('启动超时：显示自定义标题与启动追踪', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(
        title: '启动超时',
        error: '12 秒仍未渲染首帧',
        appVersion: '2.0.5',
        trace: '  ⟳ liquid_glass  —  ← 卡在这里',
      ),
    );

    expect(find.text('启动超时'), findsOneWidget);
    expect(find.text('Cyrene Music 启动失败'), findsNothing);
    expect(find.text('启动追踪'), findsOneWidget);
    expect(find.text('  ⟳ liquid_glass  —  ← 卡在这里'), findsOneWidget);
  });

  testWidgets('没有追踪信息时不显示追踪段', (tester) async {
    await tester.pumpWidget(
      const StartupFailureApp(error: 'boom', appVersion: '2.0.5'),
    );

    expect(find.text('启动追踪'), findsNothing);
  });

  // 用户多半在群里贴反馈，一键复制比让他们对着屏幕誊写现实得多。
  testWidgets('一键复制汇总版本号、错误、追踪与日志路径', (tester) async {
    const app = StartupFailureApp(
      title: '启动超时',
      error: 'stuck',
      appVersion: '2.0.5',
      trace: 'trace-body',
      logFilePath: '/var/mobile/crash.log',
    );

    final messages = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        messages.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(app);
    await tester.tap(find.text('复制全部信息'));
    await tester.pump();

    final copy = messages.firstWhere((m) => m.method == 'Clipboard.setData');
    final text = (copy.arguments as Map)['text'] as String;
    expect(text, contains('Cyrene Music 2.0.5'));
    expect(text, contains('启动超时'));
    expect(text, contains('stuck'));
    expect(text, contains('trace-body'));
    expect(text, contains('/var/mobile/crash.log'));
    expect(find.text('已复制'), findsOneWidget);
  });
}
