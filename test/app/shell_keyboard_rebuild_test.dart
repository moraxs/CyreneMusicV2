/// 键盘动画期间外壳不许跟着重建的回归测试。
///
/// 外壳曾在 build 里直接读 `MediaQuery.of(context)`（为了给标签页注入顶部
/// 内边距），于是依赖了全部字段。viewInsets 在键盘动画期间逐帧变化，外壳又
/// 常驻在所有路由底下——任何页面弹键盘，外壳连同三个标签页都每帧重建一遍，
/// 安卓上连系统键盘自己的动画都被拖卡（平台线程与 UI 线程合并）。
///
/// 判据：外壳没重建，它传给 IndexedStack 的标签页 widget 就还是同一个实例。
library;

import 'package:cyrene_music_reborn/app/app_dependencies.dart';
import 'package:cyrene_music_reborn/app/music_app_shell.dart';
import 'package:cyrene_music_reborn/features/home/now_listening_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('viewInsets 变化不重建外壳与标签页', (tester) async {
    // 断点 < 900 走移动端布局。
    tester.view
      ..physicalSize = const Size(420, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dependencies = AppDependencies.preview();
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MiuixThemeController(
          colorSchemeMode: MiuixColorSchemeMode.light,
          child: MaterialApp(
            home: MusicAppShell(
              account: dependencies.account,
              audioSources: dependencies.audioSources,
              discover: dependencies.discover,
              home: dependencies.home,
              playback: dependencies.playback,
              playlists: dependencies.playlists,
              search: dependencies.search,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final before = tester.widget(find.byType(NowListeningPage));

    for (final inset in const [80.0, 160.0, 320.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
    }

    expect(
      MediaQuery.viewInsetsOf(tester.element(find.byType(NowListeningPage))),
      const EdgeInsets.only(bottom: 320),
      reason: '前置条件：viewInsets 确实传到了外壳里面',
    );
    expect(
      identical(tester.widget(find.byType(NowListeningPage)), before),
      isTrue,
      reason: '外壳在键盘动画期间重建了，标签页会跟着每帧重建',
    );

    // 外壳 initState 里有 4s 后才跑的启动检查：先拆树再把计时器走完，
    // 回调见 !mounted 直接返回。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
