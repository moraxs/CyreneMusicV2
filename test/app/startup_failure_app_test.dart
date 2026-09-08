import 'package:cyrene_music_reborn/app/startup_failure_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这一屏是白屏事故的最后一道防线：它必须在「其它一切都坏了」时还能渲染，
/// 并且把用户反馈问题所需的三样东西都摆出来——版本号、错误、日志路径。
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
}
