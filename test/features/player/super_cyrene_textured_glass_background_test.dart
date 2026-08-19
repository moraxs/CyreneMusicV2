import 'package:cyrene_music_reborn/application/stores/fullscreen_settings_store.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_textured_glass_background.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_textured_glass_params_sheet.dart';
import 'package:cyrene_music_reborn/features/settings/player_style_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SuperCyreneTexturedGlassBackground', () {
    testWidgets('无封面时正常渲染回退背景且不抛异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SuperCyreneTexturedGlassBackground(
              imageProvider: null,
              isPlaying: false,
            ),
          ),
        ),
      );

      expect(find.byType(SuperCyreneTexturedGlassBackground), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('静态渲染正常加载且支持更新 Provider 与自定义参数', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SuperCyreneTexturedGlassBackground(
              imageProvider: null,
              fluteWidth: 20.0,
              refractionStrength: 1.5,
              lightingIntensity: 1.2,
              grooveDepth: 0.8,
              dispersion: 0.5,
            ),
          ),
        ),
      );

      expect(find.byType(SuperCyreneTexturedGlassBackground), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SuperCyreneTexturedGlassBackground(
              imageProvider: null,
              isPlaying: true,
              fluteWidth: 12.0,
              refractionStrength: 0.5,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SuperCyreneTexturedGlassBackground), findsOneWidget);
    });
  });

  group('FullscreenSettingsStore background style and custom params', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认背景样式与默认参数', () async {
      final store = FullscreenSettingsStore.instance;
      await store.init();
      expect(store.superCyreneBackgroundStyle, 'default');
      expect(store.texturedGlassFluteWidth, 16.0);
      expect(store.texturedGlassRefractionStrength, 1.0);
      expect(store.texturedGlassLightingIntensity, 1.0);
      expect(store.texturedGlassGrooveDepth, 1.0);
      expect(store.texturedGlassDispersion, 1.0);
      expect(store.texturedGlassParamsIsDefault, isTrue);
    });

    test('切换自定义参数并测试越界夹紧与重置', () async {
      final store = FullscreenSettingsStore.instance;
      await store.init();

      var notifiedCount = 0;
      void listener() => notifiedCount++;
      store.addListener(listener);

      store.setTexturedGlassFluteWidth(24.0);
      expect(store.texturedGlassFluteWidth, 24.0);
      expect(store.texturedGlassParamsIsDefault, isFalse);

      // 夹紧测试
      store.setTexturedGlassFluteWidth(100.0);
      expect(store.texturedGlassFluteWidth, 32.0);

      store.setTexturedGlassFluteWidth(2.0);
      expect(store.texturedGlassFluteWidth, 8.0);

      store.setTexturedGlassRefractionStrength(1.8);
      expect(store.texturedGlassRefractionStrength, 1.8);

      store.setTexturedGlassLightingIntensity(1.5);
      expect(store.texturedGlassLightingIntensity, 1.5);

      store.setTexturedGlassGrooveDepth(0.6);
      expect(store.texturedGlassGrooveDepth, 0.6);

      store.setTexturedGlassDispersion(1.4);
      expect(store.texturedGlassDispersion, 1.4);

      expect(notifiedCount, greaterThan(0));

      // 重置参数
      store.resetTexturedGlassParams();
      expect(store.texturedGlassFluteWidth, 16.0);
      expect(store.texturedGlassRefractionStrength, 1.0);
      expect(store.texturedGlassLightingIntensity, 1.0);
      expect(store.texturedGlassGrooveDepth, 1.0);
      expect(store.texturedGlassDispersion, 1.0);
      expect(store.texturedGlassParamsIsDefault, isTrue);

      store.removeListener(listener);
    });

    test('superCyreneSubtitle 文案准确反映纹理玻璃状态', () async {
      final store = FullscreenSettingsStore.instance;
      await store.init();

      store.setSuperCyreneLyricsTheme('default');
      store.setSuperCyreneBackgroundStyle('default');
      expect(superCyreneSubtitle(store), '沉浸式背景 · 逐行逐字歌词');

      store.setSuperCyreneBackgroundStyle('textured_glass');
      expect(superCyreneSubtitle(store), '纹理玻璃 · 逐行逐字歌词');

      store.setSuperCyreneLyricsTheme('pixel');
      expect(superCyreneSubtitle(store), '纹理玻璃 · 像素歌词');
    });
  });

  group('SuperCyreneTexturedGlassParamsSheet', () {
    testWidgets('弹出参数调节面板并包含重置与滑块', (tester) async {
      final store = FullscreenSettingsStore.instance;
      await store.init();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    showSuperCyreneTexturedGlassParamsSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('纹理玻璃参数'), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);
      expect(find.text('条纹宽度'), findsOneWidget);
      expect(find.text('折射强度'), findsOneWidget);
      expect(find.text('光泽亮度'), findsOneWidget);
      expect(find.text('凹槽阴影'), findsOneWidget);
      expect(find.text('棱镜色散'), findsOneWidget);
    });
  });
}
