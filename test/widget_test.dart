import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:cyrene_music_reborn/main.dart';

void main() {
  testWidgets('音乐主页使用 Miuix 组件与液态玻璃底部导航', (tester) async {
    await tester.pumpWidget(LiquidGlassWidgets.wrap(child: const MyApp()));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(MiuixTextField), findsOneWidget);
    expect(find.byType(GlassTabBar), findsOneWidget);
    // 未登录时首页展示登录引导卡；无网络环境下榜单为空态。
    expect(find.text('登录后查看更多内容'), findsOneWidget);
    expect(find.text('暂无榜单内容'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.compass).first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('这个分类还没有歌单'), findsOneWidget);
    expect(find.byType(MiuixCard), findsWidgets);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis).first);
    // Miuix 抽屉：透明路由入场后下一帧才置 show=true，再等弹簧滑入。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('资料库、设置与支持'), findsOneWidget);
    expect(find.text('播放历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
