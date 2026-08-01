/// 桌面外壳侧栏的回归测试。
///
/// 侧栏从 fluent_ui 的 NavigationPane 换成了 Miuix 的 [MiuixNavigationRail]，
/// 这里守住三件事：rail 真的渲染出来了（不是编译过就算）、点击导航项能切
/// 内容页、顶部那枚 sidebar 按钮能展开/折叠侧栏。
library;

import 'package:cyrene_music_reborn/app/app_dependencies.dart';
import 'package:cyrene_music_reborn/app/desktop/desktop_shell.dart';
import 'package:cyrene_music_reborn/app/desktop/desktop_title_bar.dart';
import 'package:cyrene_music_reborn/features/discover/discover_page.dart';
import 'package:cyrene_music_reborn/features/home/now_listening_page.dart';
import 'package:cyrene_music_reborn/features/profile/profile_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 融合标题栏在 initState 里问 window_manager 当前是否最大化；测试环境没有
  // 原生实现，不打桩会抛 MissingPluginException。
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          null,
        );
  });

  testWidgets('桌面侧栏用 Miuix NavigationRail 并能切换内容页', (tester) async {
    await _pumpShell(tester);

    // 侧栏是 Miuix 的，不再有 fluent 的 NavigationPane/NavigationView。
    expect(find.byType(MiuixNavigationRail), findsOneWidget);
    expect(find.byType(MiuixNavigationRailItem), findsNWidgets(8));

    // 首屏是「正在听」，标题栏与 rail 的措辞各自独立。
    // 默认 finder 跳过 offstage，而 IndexedStack 只把选中页当 onstage，
    // 所以「找得到」== 当前显示；要查是否仍在树里得显式 skipOffstage: false。
    expect(find.byType(NowListeningPage), findsOneWidget);
    expect(find.text('正在听'), findsOneWidget);
    expect(find.byType(DiscoverPage), findsNothing);

    await _tapRailItem(tester, '发现');
    expect(find.byType(DiscoverPage), findsOneWidget);
    expect(find.byType(NowListeningPage), findsNothing);

    await _tapRailItem(tester, '我的');
    expect(find.byType(ProfilePage), findsOneWidget);
    // IndexedStack 保活：切走的页面仍在树里（只是 offstage），不会重新拉取。
    expect(
      find.byType(NowListeningPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(DiscoverPage, skipOffstage: false), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  // 防住的问题：侧栏原来用 fluent NavigationView，窗口背景是它顺带画的。
  // 换成 Miuix rail 后没人铺底色，整个窗口露出黑色清屏色（浅色模式下白卡
  // 黑底，非常明显）。Material 的 color 救不了——MaterialType.transparency
  // 不画任何东西，color 参数被忽略。
  testWidgets('外壳自己铺 surface 底色，不露窗口黑底', (tester) async {
    await _pumpShell(tester);

    final context = tester.element(find.byType(MiuixNavigationRail));
    final surface = MiuixTheme.of(context).colors.surface;

    // 标题栏往上找：外壳最外层那个铺底色的 ColoredBox。
    final painted = tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.byType(DesktopTitleBar),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((box) => box.color);
    expect(painted, contains(surface));
    // 浅色模式下 surface 是 HyperOS 灰而非黑，确认取到的确实是页面底色。
    expect(surface, isNot(const Color(0xFF000000)));
  });

  testWidgets('侧栏可展开折叠，展开后变宽', (tester) async {
    await _pumpShell(tester);

    final rail = find.byType(MiuixNavigationRail);
    final collapsedWidth = tester.getSize(rail).width;
    // 折叠态取库默认 minWidth 80（外壳没有覆盖它）。
    expect(collapsedWidth, closeTo(80, 1));

    // rail 顶部那枚 sidebar 图标即展开/折叠切换按钮。
    await tester.tap(find.bySemanticsLabel('Expand navigation rail'));
    await tester.pumpAndSettle();
    expect(tester.getSize(rail).width, greaterThan(collapsedWidth));

    await tester.tap(find.bySemanticsLabel('Collapse navigation rail'));
    await tester.pumpAndSettle();
    expect(tester.getSize(rail).width, closeTo(collapsedWidth, 1));

    expect(tester.takeException(), isNull);
  });
}

/// 点击 rail 上指定文案的导航项。限定在 [MiuixNavigationRail] 子树内查找，
/// 免得撞上内容页里同名的文字（如「发现」也可能出现在页面标题上）。
Future<void> _tapRailItem(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MiuixNavigationRail),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

/// 以桌面尺寸挂载 [DesktopShell]。preview 依赖走静音网关与空数据仓库，
/// 不打网络。
Future<void> _pumpShell(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final dependencies = AppDependencies.preview();
  addTearDown(dependencies.dispose);

  await tester.pumpWidget(
    MiuixSystemTheme(
      child: Builder(
        builder: (context) => MaterialApp(
          theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
          localizationsDelegates: const [FluentLocalizations.delegate],
          home: DesktopShell(
            account: dependencies.account,
            audioSources: dependencies.audioSources,
            discover: dependencies.discover,
            home: dependencies.home,
            playback: dependencies.playback,
            playlists: dependencies.playlists,
            search: dependencies.search,
            onOpenPlayer: () {},
            onOpenHomePlaylist: (_, _, _) {},
            onOpenDiscoverPlaylist: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
