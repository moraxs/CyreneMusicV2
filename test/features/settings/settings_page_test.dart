import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/features/settings/login_page.dart';
import 'package:cyrene_music_reborn/features/settings/settings_page.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

class _FailedAuthRepository implements AuthRepository {
  const _FailedAuthRepository();

  @override
  Future<AuthResponse> login(String account, String password) async =>
      const AuthResponse(success: false, message: '账号或密码错误');

  @override
  Future<bool> validateToken(String token) async => false;
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
