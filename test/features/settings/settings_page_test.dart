import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/stores/appearance_settings_store.dart';
import 'package:cyrene_music_reborn/application/stores/fullscreen_settings_store.dart';
import 'package:cyrene_music_reborn/application/stores/window_material_settings_store.dart';
import 'package:cyrene_music_reborn/app/desktop/window_taskbar_player.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_font_service.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_style_service.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/player_background_service.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_textured_glass_params_sheet.dart';
import 'package:cyrene_music_reborn/features/settings/appearance_settings_page.dart';
import 'package:cyrene_music_reborn/features/settings/login_page.dart';
import 'package:cyrene_music_reborn/features/settings/settings_page.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await MiuixGlassRendering.load();
  });

  testWidgets('未登录用户通过独立二级登录页完成登录', (tester) async {
    final store = _MemoryAuthSessionStore();
    final controller = AccountSessionController(
      const _SuccessfulAuthRepository(),
      store,
    );
    final audioSources = _audioSources();
    addTearDown(controller.dispose);
    addTearDown(audioSources.dispose);

    await tester.pumpWidget(
      _testApp(SettingsPage(account: controller, audioSources: audioSources)),
    );
    expect(find.text('登录账号'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-login-button')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('欢迎回来'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-account-field')),
      'cyrene',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'secret',
    );
    // 大标题顶栏使内容下移，先滚动到提交按钮再点击。
    await tester.ensureVisible(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Cyrene'), findsOneWidget);
    expect(find.text('cyrene@example.com'), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(store.session?.token, 'token-123');
  });

  testWidgets('登录失败时在表单中显示服务端错误', (tester) async {
    final controller = AccountSessionController(
      const _FailedAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    final audioSources = _audioSources();
    addTearDown(controller.dispose);
    addTearDown(audioSources.dispose);

    await tester.pumpWidget(
      _testApp(SettingsPage(account: controller, audioSources: audioSources)),
    );
    await tester.tap(find.byKey(const Key('open-login-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-account-field')),
      'cyrene',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'wrong',
    );
    // 大标题顶栏使内容下移，先滚动到提交按钮再点击。
    await tester.ensureVisible(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-error-message')), findsOneWidget);
    expect(find.text('欢迎回来'), findsOneWidget);
  });

  testWidgets('音源入口打开 Shad 管理页并可添加 OmniParse', (tester) async {
    final account = AccountSessionController(
      const _FailedAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    final audioStore = _MemoryAudioSourcePreferencesStore(
      initialValue: AudioSourcePreferences(
        sources: [
          AudioSourceConfig(
            id: 'official',
            type: AudioSourceType.omniParse,
            name: 'Official Omni',
            url: 'https://official.test',
          ),
        ],
      ),
    );
    final audioSources = AudioSourcePreferencesController(
      store: audioStore,
      importer: ConfiguredAudioSourceImporter(),
    );
    addTearDown(account.dispose);
    addTearDown(audioSources.dispose);
    await audioSources.restore();

    await tester.pumpWidget(
      _testApp(SettingsPage(account: account, audioSources: audioSources)),
    );
    await tester.tap(find.byKey(const Key('open-audio-source-settings')));
    await tester.pumpAndSettle();

    expect(find.text('音源配置'), findsOneWidget);
    expect(find.text('Official Omni'), findsOneWidget);
    // Miuix 组件行高更高，Lx 提示位于首屏之外的惰性列表区域，需先滚动到可见。
    await tester.scrollUntilVisible(
      find.text('Lx Music 运行时未启用'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Lx Music 运行时未启用'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-audio-source-button')),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );

    await tester.tap(find.byKey(const Key('add-audio-source-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-omniparse-source')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('omniparse-name-field')),
      '备用解析',
    );
    await tester.enterText(
      find.byKey(const Key('omniparse-url-field')),
      'https://backup.test/',
    );
    await tester.tap(find.byKey(const Key('save-omniparse-source')));
    await tester.pumpAndSettle();

    expect(find.text('备用解析'), findsOneWidget);
    expect(audioStore.value.sources.last.url, 'https://backup.test');
  });

  Future<AccountSessionController> pumpAppearance(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool dark = false,
    bool embedded = false,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    final appearance = AppearanceSettingsStore.instance;
    await appearance.init();
    appearance
      ..setThemeMode(ThemeMode.system)
      ..setFollowSystemColor(false)
      ..setSeedColor(null);
    final fullscreen = FullscreenSettingsStore.instance;
    await fullscreen.init();
    fullscreen
      ..setSuperCyrenePlayerEnabled(false)
      ..setSuperCyreneBackgroundStyle('default')
      ..setTaskbarPlayerEnabled(false)
      ..resetTexturedGlassParams();
    await WindowMaterialSettingsStore.instance.init();
    await LyricFontService().initialize();
    await LyricStyleService().initialize();
    await PlayerBackgroundService().initialize();

    final account = AccountSessionController(
      const _FailedAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    addTearDown(account.dispose);

    final Widget home = embedded
        ? Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AppearanceSettingsBody(account: account, embedded: true),
              ),
            ),
          )
        : AppearanceSettingsPage(account: account);

    await tester.pumpWidget(
      MiuixTheme(
        data: dark ? MiuixThemeData.dark() : MiuixThemeData.light(),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return account;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Finder menuRow(String title) => find.widgetWithText(CyreneMenuRow, title);

  Finder popupItem(String text) =>
      find.widgetWithText(MiuixGlassPopupItem, text);

  void drainExceptions(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> openMenu(WidgetTester tester, String title) async {
    final row = menuRow(title);
    await Scrollable.ensureVisible(
      tester.element(row),
      duration: const Duration(milliseconds: 100),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    drainExceptions(tester);
    final rect = tester.getRect(row);
    final viewSize =
        tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(
      Offset(
        rect.center.dx.clamp(1.0, viewSize.width - 1),
        rect.center.dy.clamp(1.0, viewSize.height - 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsOneWidget);
    expect(find.byType(MiuixOverlayBottomSheet), findsNothing);
  }

  Future<void> tapPopupItem(WidgetTester tester, String text) async {
    final item = popupItem(text);
    await tester.ensureVisible(item);
    await tester.pump();
    await tester.tap(item);
  }

  testWidgets('外观设置深色模式走锚定玻璃菜单而非底部抽屉', (tester) async {
    await pumpAppearance(tester);
    final row = menuRow('深色模式');
    final rowRect = tester.getRect(row);

    await openMenu(tester, '深色模式');
    final popup = tester.widget<MiuixGlassPopup>(
      find.byType(MiuixGlassPopup),
    );
    expect(popup.backdrop, isNotNull);
    expect(popup.backdrop!.snapshot, isNotNull);
    expect(popup.anchorBounds, rowRect);

    await tester.tap(find.text('暗色'));
    await tester.pumpAndSettle();
    expect(AppearanceSettingsStore.instance.themeMode, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('theme_mode'), ThemeMode.dark.index);
    expect(find.byType(MiuixGlassPopup), findsNothing);
    expect(find.byType(AppearanceSettingsPage), findsOneWidget);

    await openMenu(tester, '深色模式');
    final darkItem = tester
        .widgetList<MiuixGlassPopupItem>(find.byType(MiuixGlassPopupItem))
        .singleWhere((item) => item.text == '暗色');
    expect(darkItem.selected, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);
    expect(find.byType(AppearanceSettingsPage), findsOneWidget);

    await openMenu(tester, '深色模式');
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);

    await openMenu(tester, '深色模式');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('主题色菜单实时更新种子色，自定义弹调色板，跟随后不再弹出', (tester) async {
    await pumpAppearance(tester);
    final store = AppearanceSettingsStore.instance;

    await openMenu(tester, '主题色');
    await tester.tap(find.text('蓝色'));
    await tester.pump();
    expect(store.seedColor, Colors.blue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('seed_color'), Colors.blue.toARGB32());
    expect(find.byType(MiuixGlassPopup), findsOneWidget);

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('自定义颜色'), findsOneWidget);
    expect(find.byType(MiuixColorPalette), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixColorPalette), findsNothing);
    expect(find.byType(MiuixGlassPopup), findsOneWidget);

    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);

    store.setFollowSystemColor(true);
    await tester.pumpAndSettle();
    await tester.tap(menuRow('主题色'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);
    expect(store.seedColor, Colors.blue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('播放器样式、背景与纹理玻璃参数均走玻璃菜单并可实时调参', (tester) async {
    await pumpAppearance(tester);
    final fullscreen = FullscreenSettingsStore.instance;

    await openMenu(tester, '播放器样式');
    await tapPopupItem(tester, 'SuperCyrene');
    await tester.pumpAndSettle();
    drainExceptions(tester);
    expect(fullscreen.superCyrenePlayerEnabled, isTrue);
    expect(find.byType(MiuixGlassPopup), findsNothing);

    await openMenu(tester, 'SuperCyrene 背景');
    await tapPopupItem(tester, '纹理玻璃');
    await tester.pumpAndSettle();
    expect(fullscreen.superCyreneBackgroundStyle, 'textured_glass');
    expect(find.byType(MiuixGlassPopup), findsNothing);

    await openMenu(tester, '纹理玻璃参数');
    expect(find.byType(MiuixSliderPreference), findsNWidgets(5));
    tester
        .widget<MiuixSliderPreference>(find.byType(MiuixSliderPreference).first)
        .onValueChange(20);
    await tester.pump();
    expect(fullscreen.texturedGlassFluteWidth, 20);
    await tester.tap(find.text('重置'));
    await tester.pump();
    expect(
      fullscreen.texturedGlassFluteWidth,
      FullscreenSettingsStore.defaultTexturedGlassFluteWidth,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('纹理玻璃参数不传锚点时仍为底部抽屉', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await FullscreenSettingsStore.instance.init();
    await tester.pumpWidget(
      MiuixTheme(
        data: MiuixThemeData.light(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: MiuixButton(
                  onPressed: () =>
                      showSuperCyreneTexturedGlassParamsSheet(context),
                  child: const Text('打开参数'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开参数'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixOverlayBottomSheet), findsOneWidget);
    expect(find.byType(MiuixGlassPopup), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MiuixOverlayBottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('歌词字体与播放器背景菜单内实时选择并保留赞助门槛', (tester) async {
    await pumpAppearance(tester);
    final fonts = LyricFontService();
    final prefs = await SharedPreferences.getInstance();

    await openMenu(tester, '歌词字体');
    final target = LyricFontService.platformFonts.firstWhere(
      (font) => font.id != fonts.presetFontId,
    );
    await tapPopupItem(tester, target.name);
    await tester.pumpAndSettle();
    expect(fonts.presetFontId, target.id);
    expect(prefs.getString('lyric_preset_font_id'), target.id);
    expect(find.byType(MiuixGlassPopup), findsOneWidget);
    final selectedItem = tester
        .widgetList<MiuixGlassPopupItem>(find.byType(MiuixGlassPopupItem))
        .singleWhere((item) => item.text == target.name);
    expect(selectedItem.selected, isTrue);
    expect(find.text('选择字体文件'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);

    final background = PlayerBackgroundService();
    await openMenu(tester, '播放器背景');
    await tapPopupItem(tester, '纯色背景');
    await tester.pumpAndSettle();
    expect(background.backgroundType, PlayerBackgroundType.solidColor);
    expect(
      prefs.getInt('player_background_type'),
      PlayerBackgroundType.solidColor.index,
    );
    expect(find.byType(MiuixGlassPopup), findsOneWidget);
    expect(find.text('选择颜色'), findsOneWidget);
    await tester.tap(find.text('选择颜色'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixColorPalette), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixColorPalette), findsNothing);
    expect(find.byType(MiuixGlassPopup), findsOneWidget);

    await tapPopupItem(tester, '动态背景');
    await tester.pumpAndSettle();
    expect(background.backgroundType, PlayerBackgroundType.dynamic);
    expect(
      prefs.getInt('player_background_type'),
      PlayerBackgroundType.dynamic.index,
    );
    expect(find.byType(MiuixGlassPopup), findsOneWidget);

    final imageItem = tester
        .widgetList<MiuixGlassPopupItem>(find.byType(MiuixGlassPopupItem))
        .singleWhere((item) => item.text == '图片背景');
    // 普通玻璃菜单只有选项本身，不带描述文字。
    expect(imageItem.summary, isNull);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassPopup), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final config in [
    (
      size: const Size(320, 640),
      scale: 2.0,
      dark: true,
      direction: TextDirection.rtl,
      embedded: false,
    ),
    (
      size: const Size(1440, 900),
      scale: 1.0,
      dark: false,
      direction: TextDirection.ltr,
      embedded: true,
    ),
  ]) {
    testWidgets('外观玻璃菜单在各形态下不溢出且面板在视口内：'
        '${config.size.width}x${config.size.height}'
        ' x${config.scale}'
        ' ${config.dark ? 'dark' : 'light'}'
        ' ${config.direction == TextDirection.rtl ? 'rtl' : 'ltr'}'
        ' ${config.embedded ? 'embedded' : 'page'}', (tester) async {
      await pumpAppearance(
        tester,
        size: config.size,
        textScale: config.scale,
        dark: config.dark,
        embedded: config.embedded,
        direction: config.direction,
      );
      final fullscreen = FullscreenSettingsStore.instance;
      fullscreen
        ..setSuperCyrenePlayerEnabled(true)
        ..setSuperCyreneBackgroundStyle('textured_glass')
        ..setTaskbarPlayerEnabled(true)
        ..setTaskbarPlayerPlacement(TaskbarPlayerMode.pinned, 0, 0);
      await tester.pumpAndSettle();
      drainExceptions(tester);

      final viewport =
          Offset.zero &
          (tester.view.physicalSize / tester.view.devicePixelRatio);

      Future<void> exercise(String title) async {
        await openMenu(tester, title);
        final popupFinder = find.byType(MiuixGlassPopup);
        final scrollable = find.descendant(
          of: popupFinder,
          matching: find.byType(SingleChildScrollView),
        );
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -400));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final panels = find.descendant(
          of: popupFinder,
          matching: find.byType(MiuixGlassPanel),
        );
        expect(panels, findsWidgets);
        for (final element in panels.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(
            viewport.contains(rect.topLeft) &&
                viewport.contains(rect.bottomRight),
            isTrue,
            reason: '「$title」玻璃面板应完整落在视口内',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byType(MiuixGlassPopup), findsNothing);
      }

      await exercise('深色模式');
      await exercise('主题色');
      await exercise('歌词字体');
      await exercise('播放器背景');
      await exercise('纹理玻璃参数');
      if (config.embedded) {
        await exercise('窗口材质');
        await exercise('任务栏位置');
      }
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}

Widget _testApp(Widget home) => MiuixSystemTheme(
  child: Builder(
    builder: (context) => MaterialApp(
      theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
      home: home,
    ),
  ),
);

AudioSourcePreferencesController _audioSources() =>
    AudioSourcePreferencesController(
      store: _MemoryAudioSourcePreferencesStore(),
      importer: ConfiguredAudioSourceImporter(),
    );

class _MemoryAudioSourcePreferencesStore
    implements AudioSourcePreferencesStore {
  _MemoryAudioSourcePreferencesStore({
    AudioSourcePreferences initialValue = const AudioSourcePreferences(),
  }) : value = initialValue;

  AudioSourcePreferences value;

  @override
  Future<AudioSourcePreferences> read() async => value;

  @override
  Future<void> write(AudioSourcePreferences preferences) async {
    value = preferences;
  }
}

const _user = User(
  id: 7,
  email: 'cyrene@example.com',
  username: 'Cyrene',
  isVerified: true,
  isSponsor: false,
);

class _SuccessfulAuthRepository implements AuthRepository {
  const _SuccessfulAuthRepository();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(
        success: true,
        user: _user,
        data: {'token': 'token-123'},
      );

  @override
  Future<bool> validateToken(String token) async => true;

  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code, {
    String? inviteCode,
  }) async => const AuthResponse(success: true);

  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: true);

  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
}

class _FailedAuthRepository implements AuthRepository {
  const _FailedAuthRepository();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false, message: '账号或密码错误');

  @override
  Future<bool> validateToken(String token) async => false;

  @override
  Future<AuthResponse> register(
    String email,
    String username,
    String password,
    String code, {
    String? inviteCode,
  }) async => const AuthResponse(success: false);

  @override
  Future<AuthResponse> sendRegisterCode(String email, String username) async =>
      const AuthResponse(success: false);

  @override
  Future<({bool success, bool enabled})> checkRegistrationStatus() async =>
      (success: true, enabled: true);
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
