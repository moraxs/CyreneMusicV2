import 'package:cyrene_music_reborn/app/app_dependencies.dart';
import 'package:cyrene_music_reborn/app/music_app_shell.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/features/home/now_listening_page.dart';
import 'package:cyrene_music_reborn/features/more/more_menu_drawer.dart';
import 'package:cyrene_music_reborn/features/player/mini_player.dart';
import 'package:cyrene_music_reborn/features/settings/settings_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _navTrack = Track(
  id: 'nav-test',
  name: '测试歌曲',
  artists: '测试歌手',
  album: '',
  picUrl: '',
  source: MusicSource.netease,
  playbackUrl: Uri.parse('https://audio.test/song.mp3'),
);

void main() {
  testWidgets('音乐主页使用 HyperOS 4 玻璃底部导航', (tester) async {
    final fixture = _Fixture(tester);
    await fixture.pumpShell();
    final barFinder = find.byType(MiuixGlassNavigationBar);

    expect(barFinder, findsOneWidget);
    expect(find.byType(GlassTabBar), findsNothing);
    // 未登录时首页展示登录引导卡；无网络环境下榜单为空态。
    expect(find.byType(NowListeningPage), findsOneWidget);

    final bar = tester.widget<MiuixGlassNavigationBar>(barFinder);
    expect(bar.items.map((item) => item.label).toList(), [
      '首页',
      '发现',
      '我的',
      '更多',
    ]);
    expect(bar.backdrop, isNotNull);
    final capture = tester.widget<MiuixLayerBackdropCapture>(
      find
          .ancestor(
            of: find.byType(NowListeningPage),
            matching: find.byType(MiuixLayerBackdropCapture),
          )
          .first,
    );
    expect(identical(capture.backdrop, bar.backdrop), isTrue);
    expect(capture.pixelRatio, 1);
    expect(
      find.descendant(
        of: find.byType(MiuixLayerBackdropCapture),
        matching: barFinder,
      ),
      findsNothing,
    );

    await tester.tap(find.descendant(of: barFinder, matching: find.text('发现')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<MiuixGlassNavigationBar>(barFinder).selectedIndex, 1);
    expect(
      tester
          .widget<IndexedStack>(
            find.descendant(
              of: find.byType(MusicAppShell),
              matching: find.byType(IndexedStack),
            ),
          )
          .index,
      1,
    );
    expect(find.text('这个分类还没有歌单'), findsOneWidget);

    await tester.tap(find.descendant(of: barFinder, matching: find.text('我的')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<MiuixGlassNavigationBar>(barFinder).selectedIndex, 2);

    await tester.tap(find.descendant(of: barFinder, matching: find.text('首页')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<MiuixGlassNavigationBar>(barFinder).selectedIndex, 0);

    await tester.tap(find.descendant(of: barFinder, matching: find.text('更多')));
    // Miuix 抽屉：透明路由入场后下一帧才置 show=true，再等弹簧滑入。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('资料库、设置与支持'), findsOneWidget);
    expect(find.text('播放历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.drain();
  });

  testWidgets('更多标签重复触发只开一个抽屉且不选中', (tester) async {
    final fixture = _Fixture(tester);
    await fixture.pumpShell();
    final barFinder = find.byType(MiuixGlassNavigationBar);
    final shellStack = find.descendant(
      of: find.byType(MusicAppShell),
      matching: find.byType(IndexedStack),
    );

    await tester.tap(find.descendant(of: barFinder, matching: find.text('发现')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<IndexedStack>(shellStack).index, 1);

    final onSelect = tester.widget<MiuixGlassNavigationBar>(barFinder).onSelect;
    onSelect(3);
    onSelect(3);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MoreMenuDrawer), findsOneWidget);
    expect(tester.widget<IndexedStack>(shellStack).index, 1);
    expect(tester.widget<MiuixGlassNavigationBar>(barFinder).selectedIndex, 1);

    await tester.binding.handlePopRoute();
    await _pumpUntilGone(tester, find.byType(MoreMenuDrawer));
    expect(find.byType(MoreMenuDrawer), findsNothing);

    onSelect(3);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MoreMenuDrawer), findsOneWidget);

    final settingsItem = find.descendant(
      of: find.byType(MoreMenuDrawer),
      matching: find.text('设置'),
    );
    for (
      var i = 0;
      i < 30 && settingsItem.hitTestable().evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(settingsItem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pumpUntilGone(tester, find.byType(SettingsPage));
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(MoreMenuDrawer), findsNothing);
    expect(tester.widget<MiuixGlassNavigationBar>(barFinder).selectedIndex, 1);
    expect(tester.takeException(), isNull);
    await fixture.drain();
  });

  testWidgets('拖动底部导航滑块不实时切页，松手才提交', (tester) async {
    final fixture = _Fixture(tester);
    await fixture.pumpShell();
    final barFinder = find.byType(MiuixGlassNavigationBar);
    Offset centerOf(String label) => tester.getCenter(
      find.descendant(of: barFinder, matching: find.text(label)),
    );
    int selected() =>
        tester.widget<MiuixGlassNavigationBar>(barFinder).selectedIndex;

    final gesture = await tester.startGesture(centerOf('首页'));
    await tester.pump();
    await gesture.moveTo(centerOf('发现'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected(), 0);
    expect(find.byType(MoreMenuDrawer), findsNothing);
    await gesture.moveTo(centerOf('更多'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected(), 0);
    expect(find.byType(MoreMenuDrawer), findsNothing);
    await gesture.moveTo(centerOf('我的'));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected(), 2);

    final dragMore = await tester.startGesture(centerOf('我的'));
    await tester.pump();
    await dragMore.moveTo(centerOf('更多'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MoreMenuDrawer), findsNothing);
    await dragMore.up();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MoreMenuDrawer), findsOneWidget);
    expect(selected(), 2);
    expect(tester.takeException(), isNull);
    await fixture.drain();
  });

  for (final config in [
    (width: 390.0, height: 844.0, inset: 0.0, scale: 1.0, track: false),
    (width: 390.0, height: 844.0, inset: 34.0, scale: 1.0, track: true),
    (width: 320.0, height: 720.0, inset: 34.0, scale: 2.0, track: false),
    (width: 320.0, height: 720.0, inset: 34.0, scale: 1.0, track: true),
    (width: 844.0, height: 390.0, inset: 0.0, scale: 1.0, track: false),
  ]) {
    testWidgets('底部导航几何 ${config.width}x${config.height} 下沿${config.inset} '
        '字号x${config.scale} ${config.track ? '有歌' : '无歌'}', (tester) async {
      final fixture = _Fixture(
        tester,
        size: Size(config.width, config.height),
        bottomInset: config.inset,
        textScale: config.scale,
        track: config.track ? _navTrack : null,
      );
      await fixture.pumpShell();

      final barRect = tester.getRect(find.byType(MiuixGlassNavigationBar));
      expect(barRect.left, greaterThanOrEqualTo(16));
      expect(barRect.right, lessThanOrEqualTo(config.width - 16));
      expect(barRect.width, lessThanOrEqualTo(520));
      expect(
        barRect.bottom,
        lessThanOrEqualTo(config.height - config.inset - 12 + 0.01),
      );
      expect(barRect.top, greaterThan(0));

      if (config.track) {
        final miniRect = tester.getRect(find.byType(MiniPlayer));
        expect(miniRect.bottom, lessThanOrEqualTo(barRect.top - 12 + 0.01));
      } else {
        expect(find.byType(MiniPlayer), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await fixture.drain();
    });
  }

  testWidgets('深色主题下玻璃底部导航正常渲染', (tester) async {
    final fixture = _Fixture(tester, dark: true);
    await fixture.pumpShell();

    expect(find.byType(MiuixGlassNavigationBar), findsOneWidget);
    expect(find.byType(NowListeningPage), findsOneWidget);
    final navContext = tester.element(find.byType(MiuixGlassNavigationBar));
    expect(MiuixTheme.of(navContext).brightness, Brightness.dark);
    expect(Theme.of(navContext).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await fixture.drain();
  });
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Fixture {
  _Fixture(
    this.tester, {
    this.size = const Size(390, 844),
    this.bottomInset = 0,
    this.textScale = 1,
    this.dark = false,
    this.track,
  }) : deps = AppDependencies.preview() {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0
      ..padding = FakeViewPadding(bottom: bottomInset)
      ..viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(() async {
      await drain();
      deps.dispose();
      tester.view.reset();
    });
  }

  final WidgetTester tester;
  final AppDependencies deps;
  final Size size;
  final double bottomInset;
  final double textScale;
  final bool dark;
  final Track? track;

  Future<void> pumpShell() async {
    if (track != null) {
      await deps.playback.playTrack(track!);
    }
    await deps.account.restore();
    await deps.audioSources.restore();
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MiuixThemeController(
          colorSchemeMode: dark
              ? MiuixColorSchemeMode.dark
              : MiuixColorSchemeMode.light,
          child: Builder(
            builder: (context) => MaterialApp(
              theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: MusicAppShell(
                account: deps.account,
                audioSources: deps.audioSources,
                discover: deps.discover,
                home: deps.home,
                playback: deps.playback,
                playlists: deps.playlists,
                search: deps.search,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> drain() async {
    if (_drained) return;
    _drained = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  bool _drained = false;
}
