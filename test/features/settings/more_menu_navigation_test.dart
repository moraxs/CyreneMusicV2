import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/features/more/more_menu_drawer.dart';
import 'package:cyrene_music_reborn/features/settings/settings_page.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_overlays.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('更多菜单点设置不等抽屉退场动画直接推入设置页', (tester) async {
    final harness = _Harness(tester);
    await harness.pumpHome();
    final observer = harness.observer;

    await tester.tap(find.byKey(const Key('open-more')));
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenuDrawer), findsOneWidget);

    final pushesBefore = observer.pushed.length;
    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(observer.pushed.length, pushesBefore + 1);
    expect(observer.pushed.last, isA<CupertinoPageRoute<void>>());
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(MoreMenuDrawer), findsNothing);
    expect(find.byKey(const Key('open-login-button')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-more')).hitTestable(), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('同帧重复关闭抽屉只执行一次菜单动作', (tester) async {
    final harness = _Harness(tester);
    await harness.pumpHome();

    await tester.tap(find.byKey(const Key('open-more')));
    await tester.pumpAndSettle();

    final dismiss = tester
        .widget<MoreMenuDrawer>(find.byType(MoreMenuDrawer))
        .dismiss;
    var calls = 0;
    dismiss(() => calls++);
    dismiss(() => calls++);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(MoreMenuDrawer), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('返回键与遮罩关闭抽屉走退场动画且不推入页面', (tester) async {
    final harness = _Harness(tester);
    await harness.pumpHome();
    final observer = harness.observer;

    await tester.tap(find.byKey(const Key('open-more')));
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenuDrawer), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(MoreMenuDrawer), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenuDrawer), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.byKey(const Key('open-more')));
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenuDrawer), findsOneWidget);

    final pushesBefore = observer.pushed.length;
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(find.byType(MoreMenuDrawer), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(MoreMenuDrawer), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(observer.pushed.length, pushesBefore);
  });

  testWidgets('默认 sheet 仍等退场动画结束才返回非空结果', (tester) async {
    final harness = _Harness(tester);
    int? result;
    await harness.pumpHome(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open-sheet'),
            onPressed: () => showCyreneSheet<int>(
              context: context,
              title: '测试抽屉',
              builder: (_, dismiss) => TextButton(
                key: const Key('result'),
                onPressed: () => dismiss(7),
                child: const Text('完成'),
              ),
            ).then((value) => result = value),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('result')));
    await tester.pump();
    expect(result, isNull);
    await tester.pumpAndSettle();
    expect(result, 7);
  });
}

class _RouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

class _Harness {
  _Harness(this.tester)
    : account = AccountSessionController(
        const _AuthRepositoryStub(),
        _MemoryAuthSessionStore(),
      ),
      audioSources = AudioSourcePreferencesController(
        store: _MemoryAudioSourcePreferencesStore(),
        importer: ConfiguredAudioSourceImporter(),
      ),
      playback = _PlaybackControllerStub(),
      observer = _RouteObserver() {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      account.dispose();
      audioSources.dispose();
    });
  }

  final WidgetTester tester;
  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final PlaybackController playback;
  final _RouteObserver observer;

  Future<void> pumpHome({Widget? home}) async {
    await account.restore();
    await tester.pumpWidget(
      MiuixSystemTheme(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
            navigatorObservers: [observer],
            home:
                home ??
                Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        key: const Key('open-more'),
                        onPressed: () => MoreMenuDrawer.show(
                          context,
                          account: account,
                          audioSources: audioSources,
                          playback: playback,
                        ),
                        child: const Text('打开更多'),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _AuthRepositoryStub implements AuthRepository {
  const _AuthRepositoryStub();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlaybackControllerStub implements PlaybackController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryAuthSessionStore implements AuthSessionStore {
  AuthSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession value) async => session = value;
}

class _MemoryAudioSourcePreferencesStore
    implements AudioSourcePreferencesStore {
  AudioSourcePreferences value = const AudioSourcePreferences();

  @override
  Future<AudioSourcePreferences> read() async => value;

  @override
  Future<void> write(AudioSourcePreferences preferences) async {
    value = preferences;
  }
}
