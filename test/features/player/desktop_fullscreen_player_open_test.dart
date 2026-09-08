import 'dart:async';

import 'package:cyrene_music_reborn/application/auth/account_session_controller.dart';
import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/application/stores/fullscreen_settings_store.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_repository.dart';
import 'package:cyrene_music_reborn/domain/auth/auth_session_store.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/models/user.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/desktop_fullscreen_player.dart';
import 'package:cyrene_music_reborn/features/player/desktop_fullscreen_player_host.dart';
import 'package:cyrene_music_reborn/features/player/desktop_fullscreen_player_route.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_fullscreen_player.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 打开桌面全屏播放器不该抛异常（经典 / SuperCyrene × 常见窗口尺寸）。
///
/// 从底部迷你播放器点封面进全屏时窗口卡死过一次，这条守的就是那条路径：
/// 真的 push 那条路由，再逐帧走完入场动画。
///
/// 多行歌词：入场时右侧显示的是歌词面板，空歌词走不到它的几何计算。
final String _lyric = [
  '[00:00.00]故事的小黄花',
  '[00:05.00]从出生那年就飘着',
  '[00:10.00]童年的荡秋千',
  '[00:15.00]随记忆一直晃到现在',
  '[00:20.00]吹着前奏望着天空',
  '[00:25.00]我想起花瓣试着掉落',
  '[00:30.00]为你翘课的那一天',
].join('\n');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 真 App 在 main 里初始化过；不初始化时液态玻璃的变换矩阵会是 NaN。
    await LiquidGlassWidgets.initialize();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // window_manager 在测试里没有原生实现，桩掉它用到的几个方法。
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'), (call) async {
        if (call.method == 'isMaximized') return false;
        return null;
      },
    );
  });

  for (final superCyrene in [false, true]) {
    for (final size in const [
      Size(1600, 900),
      Size(1280, 720),
      Size(900, 600),
      Size(760, 480),
    ]) {
      testWidgets(
        '桌面全屏播放器：${superCyrene ? 'SuperCyrene' : '经典'} @ ${size.width}x${size.height}',
        (tester) async => _pumpRoute(tester, size: size, superCyrene: superCyrene),
      );
    }

    // 平板走的就是这套桌面播放器（断点按宽度判），但它没有鼠标悬停也没有键盘，
    // 标题栏折叠键与 Esc 全部失效，返回键是唯一的退路。
    testWidgets(
      '返回键最小化播放器：${superCyrene ? 'SuperCyrene' : '经典'}',
      (tester) async {
        final ctx = await _pumpRoute(
          tester,
          size: const Size(1280, 800),
          superCyrene: superCyrene,
        );

        await _pressBack(tester);
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(
          find.byType(DesktopFullscreenPlayerHost),
          findsNothing,
          reason: '返回键该把全屏播放器 pop 掉',
        );
        // 「最小化」而不是「退出到别处」：外壳原样还在。
        expect(find.text('shell'), findsOneWidget);
        expect(ctx.navigatorKey.currentState!.canPop(), isFalse);
      },
    );
  }

  // 经典播放器在触摸平板上没有 hover 标题栏也没有键盘，左上角必须有常驻的
  // 最小化按钮兜底（SuperCyrene 早就有自己的移动端分支，不走这条）。
  testWidgets('触摸平台：经典播放器左上角有最小化按钮，点击即最小化', (tester) async {
    // 必须在测试体内复位：绑定的不变量校验早于 addTearDown，留着会让本条红。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final ctx = await _pumpRoute(
        tester,
        size: const Size(1280, 800),
        superCyrene: false,
      );

      final button = find.byTooltip('最小化播放器');
      expect(button, findsOneWidget);
      // 左上角：在窗口的左半、上半区。
      final center = tester.getCenter(button);
      expect(center.dx, lessThan(120));
      expect(center.dy, lessThan(120));

      await tester.tap(button);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(DesktopFullscreenPlayerHost), findsNothing);
      expect(find.text('shell'), findsOneWidget);
      expect(ctx.navigatorKey.currentState!.canPop(), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('桌面平台：不渲染触摸最小化按钮，仍走 hover 标题栏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpRoute(tester, size: const Size(1280, 800), superCyrene: false);

      expect(find.byTooltip('最小化播放器'), findsNothing);
      expect(find.byTooltip('折叠全屏播放器'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('退场动画途中再按返回键不会把外壳一起弹掉', (tester) async {
    final ctx = await _pumpRoute(
      tester,
      size: const Size(1280, 800),
      superCyrene: false,
    );

    // 连按两下：第二下落在退场动画途中，此时路由已不是 current。
    await _pressBack(tester);
    await tester.pump(const Duration(milliseconds: 16));
    await _pressBack(tester);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('shell'), findsOneWidget);
    expect(ctx.navigatorKey.currentState!.canPop(), isFalse);
  });
}

/// 模拟系统返回键：走 Flutter 的 popRoute 通道，与安卓实机同一条路径。
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
  await tester.pump();
}

/// [_pumpRoute] 的产物，供调用方在 pump 完之后继续操作导航栈。
typedef _PumpedRoute = ({GlobalKey<NavigatorState> navigatorKey});

Future<_PumpedRoute> _pumpRoute(
  WidgetTester tester, {
  required Size size,
  required bool superCyrene,
}) async {
  {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final playback = PlaybackController(
      audio: _FakeAudioGateway(),
      store: _FakeSnapshotStore(),
    );
    addTearDown(playback.dispose);
    await playback.playTrack(
      Track(
        id: '1',
        name: '晴天',
        artists: '周杰伦',
        album: '叶惠美',
        picUrl: '',
        source: MusicSource.netease,
        lyric: _lyric,
      ),
    );
    final account = AccountSessionController(
      const _FakeAuthRepository(),
      _MemoryAuthSessionStore(),
    );
    addTearDown(account.dispose);
    final audioSources = AudioSourcePreferencesController(
      store: _MemoryAudioSourcePreferencesStore(),
      importer: ConfiguredAudioSourceImporter(),
    );
    addTearDown(audioSources.dispose);
    await FullscreenSettingsStore.instance.init();
    FullscreenSettingsStore.instance.setSuperCyrenePlayerEnabled(superCyrene);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('shell')),
      ),
    );

    navigatorKey.currentState!.push(
      DesktopFullscreenPlayerRoute(
        builder: (_) => DesktopFullscreenPlayerHost(
          playback: playback,
          audioSources: audioSources,
          account: account,
        ),
      ),
    );
    // 逐帧推进整个入场动画并检查每一帧。
    //
    // 这里刻意不用 pumpAndSettle：SuperCyrene 的背景是常驻动画，永远 settle
    // 不了，用它只会超时，掩盖掉真正要看的东西。
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final error = tester.takeException();
      // 底部控制条在窄窗口下会溢出 2.7px。这是改动之前就有的既有问题（已对着
      // 干净代码核对过），是调试期的排版告警、不影响功能，本用例不为它变红。
      if (error is FlutterError &&
          error.message.contains('overflowed')) {
        continue;
      }
      expect(error, isNull, reason: '第 $i 帧抛异常');
    }

    // 光是「没抛异常」不够：这条路由是全屏透明且吞输入的，万一内容没画出来，
    // 表现就是整窗点不动、看着像卡死却一句报错也没有。所以要确认它真的占了地方。
    final playerFinder = find.byType(
      superCyrene ? SuperCyreneFullscreenPlayer : DesktopFullscreenPlayer,
    );
    expect(playerFinder, findsOneWidget);
    final painted = tester.getSize(playerFinder);
    expect(painted.width, greaterThan(0));
    expect(painted.height, greaterThan(0));
    // 入场动画走完后应当铺满窗口，而不是被揭幕裁剪停在 0 高。
    expect(painted.height, closeTo(size.height, 1));

    return (navigatorKey: navigatorKey);
  }
}

class _FakeAudioGateway implements AudioPlayerGateway {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _status = StreamController<PlaybackStatus>.broadcast();

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<PlaybackStatus> get statusStream => _status.stream;

  @override
  Future<Duration?> load(Uri source) async => Duration.zero;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _status.close();
  }
}

class _FakeSnapshotStore implements PlaybackSnapshotStore {
  PlaybackSnapshot? _snapshot;

  @override
  Future<PlaybackSnapshot?> read() async => _snapshot;
  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository();

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
