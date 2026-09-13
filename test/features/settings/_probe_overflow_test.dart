import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/stores/appearance_settings_store.dart';
import 'package:cyrene_music_reborn/application/stores/fullscreen_settings_store.dart';
import 'package:cyrene_music_reborn/application/stores/window_material_settings_store.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_font_service.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_style_service.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/player_background_service.dart';
import 'package:cyrene_music_reborn/features/settings/appearance_settings_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await MiuixGlassRendering.load();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('probe page alone scale=$scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await AppearanceSettingsStore.instance.init();
      await FullscreenSettingsStore.instance.init();
      await WindowMaterialSettingsStore.instance.init();
      await LyricFontService().initialize();
      await LyricStyleService().initialize();
      await PlayerBackgroundService().initialize();
      final account = AccountSessionController(
        const _StubRepo(),
        _MemStore(),
      );
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MiuixTheme(
          data: MiuixThemeData.dark(),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: AppearanceSettingsPage(account: account),
          ),
        ),
      );
      await tester.pumpAndSettle();
      debugPrint('PROBE scale=$scale page exception: ${tester.takeException()}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('probe params menu 390', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await AppearanceSettingsStore.instance.init();
    final fullscreen = FullscreenSettingsStore.instance;
    await fullscreen.init();
    fullscreen
      ..setSuperCyrenePlayerEnabled(true)
      ..setSuperCyreneBackgroundStyle('default');
    await WindowMaterialSettingsStore.instance.init();
    await LyricFontService().initialize();
    await LyricStyleService().initialize();
    await PlayerBackgroundService().initialize();
    final account = AccountSessionController(const _StubRepo(), _MemStore());
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MiuixTheme(
        data: MiuixThemeData.light(),
        child: MaterialApp(home: AppearanceSettingsPage(account: account)),
      ),
    );
    await tester.pumpAndSettle();
    final pageErr = tester.takeException();
    debugPrint('PROBE page exception: $pageErr');
    for (final row in tester.elementList(find.byType(CyreneMenuRow))) {
      void walk(Element e) {
        final ro = e.renderObject;
        if (ro is RenderFlex && ro.direction == Axis.horizontal) {
          final need = ro.getMaxIntrinsicWidth(1000);
          if (need > ro.size.width + .01) {
            debugPrint(
              'OVERFLOW flex need=$need have=${ro.size.width} in row '
              '${(row.widget as CyreneMenuRow).title} (row size=${(row.renderObject! as RenderBox).size})',
            );
          }
        }
        e.visitChildren(walk);
      }

      row.visitChildren(walk);
    }
    final row = find.widgetWithText(CyreneMenuRow, '纹理玻璃参数');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    debugPrint(
      'PROBE menu open: ${find.byType(MiuixGlassPopup).evaluate().length}',
    );
    debugPrint('PROBE menu exception: ${tester.takeException()}');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _StubRepo implements AuthRepository {
  const _StubRepo();
  @override
  Future<AuthResponse> login(String a, String b) async =>
      const AuthResponse(success: false);
  @override
  Future<bool> validateToken(String t) async => false;
  @override
  Future<AuthResponse> register(
    String e,
    String u,
    String p,
    String c, {
    String? inviteCode,
  }) async => const AuthResponse(success: false);
  @override
  Future<AuthResponse> sendRegisterCode(String e, String u) async =>
      const AuthResponse(success: false);
  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

class _MemStore implements AuthSessionStore {
  @override
  Future<void> clear() async {}
  @override
  Future<AuthSession?> read() async => null;
  @override
  Future<void> write(AuthSession v) async {}
}
