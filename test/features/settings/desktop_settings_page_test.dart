import 'dart:ui' show Tristate;

import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/features/settings/appearance_settings_page.dart';
import 'package:cyrene_music_reborn/features/settings/cache_settings_page.dart';
import 'package:cyrene_music_reborn/features/settings/desktop/desktop_settings_page.dart';
import 'package:cyrene_music_reborn/features/settings/equalizer_page.dart';
import 'package:cyrene_music_reborn/features/settings/together_settings_page.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面设置页的两条不变量：
///
/// 1. 所有设置项真的在**同一页**里（不是一排跳转入口）——所以直接找各段的
///    正文组件，找到入口行是不算数的。
/// 2. 顶部 tab 与滚动位置双向联动。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({
      AccountSessionController account,
      AudioSourcePreferencesController audioSources,
    })
  >
  pumpPage(
    WidgetTester tester, {
    ValueChanged<Widget>? onOpenSecondary,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final account = AccountSessionController(
      const _StubAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    final audioSources = AudioSourcePreferencesController(
      store: _MemoryAudioSourcePreferencesStore(),
      importer: ConfiguredAudioSourceImporter(),
    );
    addTearDown(account.dispose);
    addTearDown(audioSources.dispose);

    await tester.pumpWidget(
      MiuixSystemTheme(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
            home: DesktopSettingsPage(
              account: account,
              audioSources: audioSources,
              onOpenSecondary: onOpenSecondary,
            ),
          ),
        ),
      ),
    );
    // 不用 pumpAndSettle：缓存段落挂着异步统计，settle 不一定到得了。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    return (account: account, audioSources: audioSources);
  }

  testWidgets('设置项摊平在同一页里，不是一排跳转入口', (tester) async {
    await pumpPage(tester);
    expect(tester.takeException(), isNull);

    // 各段正文本体在场 = 内容真的合并进来了。
    expect(find.byType(AppearanceSettingsBody), findsOneWidget);
    expect(find.byType(EqualizerBody), findsOneWidget);
    expect(find.byType(TogetherSettingsBody), findsOneWidget);

    // 八个锚点 tab 都画出来了。
    for (final label in const [
      '账号',
      '播放与音源',
      '音效',
      'AI 助手',
      '一起听',
      '缓存',
      '外观',
      '关于',
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少 tab「$label」');
    }
  });

  testWidgets('往下滚时 tab 高亮跟着走', (tester) async {
    // 必须在测试体内 dispose：句柄的校验发生在 tearDown 之前，
    // 挂 addTearDown 会被判成「句柄泄漏」。
    final semantics = tester.ensureSemantics();

    await pumpPage(tester);
    expect(_selectedTab(tester), '账号');

    // 在内容区里往上拖 = 页面向下滚。按屏幕坐标起手，别按组件找：
    // 靠后的段落此刻还在视口外，拿它当拖拽起点等于没拖。
    for (var round = 0; round < 6; round++) {
      await tester.dragFrom(const Offset(720, 700), const Offset(0, -700));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(tester.takeException(), isNull);

    expect(
      _selectedTab(tester),
      isNot('账号'),
      reason: '滚过好几段之后，高亮不该还停在第一个 tab 上',
    );
    semantics.dispose();
  });

  testWidgets('缓存段不就地铺开歌曲列表，而是给一个二级页入口', (tester) async {
    Widget? opened;
    await pumpPage(tester, onOpenSecondary: (page) => opened = page);

    // 缓存了多少首，这段就有多长——摊在长页里会把页面拉到没边，所以只留入口。
    final entry = find.byKey(const Key('open-cached-songs'));
    expect(entry, findsOneWidget);

    await tester.ensureVisible(entry);
    await tester.pump();
    await tester.tap(entry);
    await tester.pump();

    expect(opened, isA<CachedSongsPage>());
  });

  testWidgets('点 tab 会滚到对应段落', (tester) async {
    await pumpPage(tester);

    // 直接量段落自己的位置，而不是某个 ScrollController 的 offset：这一页里
    // 有两条滚动（顶部 tab 条是横向的），按类型取第一个会取错。
    final section = find.byType(AppearanceSettingsBody);
    final before = tester.getTopLeft(section).dy;

    // '外观' 既是 tab 也是段落标题，取第一个（tab 条在树里更靠前）。
    await tester.tap(find.text('外观').first);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(tester.takeException(), isNull);

    final after = tester.getTopLeft(section).dy;
    expect(after, lessThan(before - 100), reason: '点 tab 后「外观」段应当被滚到视口顶部附近');
  });
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

class _StubAuthRepository implements AuthRepository {
  const _StubAuthRepository();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false, message: '未登录');
  @override
  Future<bool> validateToken(String token) async => false;
  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code,
  ) async => const AuthResponse(success: false);
  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: false);
  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

/// 当前高亮的 tab 文案。tab 用 `Semantics(selected:)` 报选中态，见 _AnchorTab。
String? _selectedTab(WidgetTester tester) {
  const labels = ['账号', '播放与音源', '音效', 'AI 助手', '一起听', '缓存', '外观', '关于'];
  for (final label in labels) {
    final tab = find.byKey(settingsTabKey(label));
    if (tab.evaluate().isEmpty) continue;
    final node = tester.getSemantics(tab);
    if (node.flagsCollection.isSelected == Tristate.isTrue) return label;
  }
  return null;
}
