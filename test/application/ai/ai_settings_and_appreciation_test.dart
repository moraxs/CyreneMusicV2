import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music_reborn/application/ai/song_appreciation_controller.dart';
import 'package:cyrene_music_reborn/application/ai/song_context.dart';
import 'package:cyrene_music_reborn/application/stores/ai_settings_store.dart';
import 'package:cyrene_music_reborn/domain/ai/ai_models.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/infrastructure/ai/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final settings = AiSettingsStore.instance;

  const track = Track(
    id: '123',
    name: '晴天',
    artists: '周杰伦',
    album: '叶惠美',
    picUrl: '',
    source: MusicSource.netease,
  );

  group('AI 设置存储', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await settings.init();
    });

    test('API Key 不以明文落盘，重新读出来仍是原值', () async {
      await settings.setApiKey('sk-super-secret-value');
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('ai_api_key_sealed');

      expect(stored, isNotNull);
      expect(stored, isNot(contains('sk-super-secret-value')));
      expect(
        utf8.decode(base64Decode(stored!), allowMalformed: true),
        isNot(contains('sk-super-secret-value')),
      );
      expect(settings.apiKey, 'sk-super-secret-value');
    });

    test('打码只露头尾', () async {
      await settings.setApiKey('sk-abcdefghijklmnop');
      expect(settings.maskedApiKey, startsWith('sk-a'));
      expect(settings.maskedApiKey, endsWith('mnop'));
      expect(settings.maskedApiKey, isNot(contains('defghij')));
    });

    test('换路由会把还是上一家默认值的模型/地址一并换掉', () async {
      await settings.setRoute(AiRoute.openai);
      await settings.setBaseUrl(AiRoute.openai.baseUrlHint);
      await settings.setModel(AiRoute.openai.suggestedModel);

      await settings.setRoute(AiRoute.anthropic);
      expect(settings.model, AiRoute.anthropic.suggestedModel);
      expect(settings.baseUrl, AiRoute.anthropic.baseUrlHint);
    });

    test('用户手填过的模型/地址不会被换路由覆盖', () async {
      await settings.setRoute(AiRoute.openai);
      await settings.setBaseUrl('https://my-gateway.example.com/v1');
      await settings.setModel('my-own-model');

      await settings.setRoute(AiRoute.anthropic);
      expect(settings.model, 'my-own-model');
      expect(settings.baseUrl, 'https://my-gateway.example.com/v1');
    });

    test('isConfigured 要求开关开着且三项都填了', () async {
      await settings.setEnabled(true);
      await settings.setBaseUrl('https://x.example.com');
      await settings.setModel('m');
      await settings.setApiKey('');
      expect(settings.isConfigured, isFalse);

      await settings.setApiKey('k');
      expect(settings.isConfigured, isTrue);

      await settings.setEnabled(false);
      expect(settings.isConfigured, isFalse);
    });
  });

  group('单曲赏析', () {
    late _StubAiClient client;
    late SongAppreciationController controller;

    setUp(() {
      client = _StubAiClient();
      controller = SongAppreciationController.forTest(
        client: client,
        // 热评要走网络，单测里关掉，只验本地材料的拼装。
        contextBuilder: const _NoCommentsBuilder(),
      );
    });

    test('不点就不发请求', () async {
      expect(controller.of(track).isEmpty, isTrue);
      expect(client.calls, 0);
    });

    test('生成后按曲目缓存，再点不重复付费', () async {
      client.chunks = ['这首', '很好听'];
      await controller.generate(track);
      expect(controller.of(track).text, '这首很好听');
      expect(controller.of(track).streaming, isFalse);
      expect(client.calls, 1);

      await controller.generate(track);
      expect(client.calls, 1); // 命中缓存，没有再发

      await controller.generate(track, force: true);
      expect(client.calls, 2); // 「重新生成」才会再发
    });

    test('失败时把可读原因留在状态里', () async {
      client.error = const AiException('Invalid API key provided');
      await controller.generate(track);
      expect(controller.of(track).error, 'Invalid API key provided');
      expect(controller.of(track).streaming, isFalse);
    });

    test('模型返回空内容按失败处理，不留一张空卡片', () async {
      client.chunks = ['   '];
      await controller.generate(track);
      expect(controller.of(track).text, isEmpty);
      expect(controller.of(track).error, isNotNull);
    });

    test('材料会进提示词：歌词、曲风、歌手简介都要喂给模型', () async {
      const withLyric = Track(
        id: '9',
        name: 'Lost Soul',
        artists: 'Agera',
        album: '',
        picUrl: '',
        source: MusicSource.netease,
        lyric: '[00:12.34]I am a lost soul\n[00:18.00]walking in the rain',
      );
      await controller.generate(
        withLyric,
        styles: const ['Future Bass'],
        bpm: '128',
        artistBio: '瑞典电子音乐制作人。',
      );

      final prompt = client.lastPrompt!;
      expect(prompt, contains('I am a lost soul'));
      // 时间戳要清掉，别浪费 token 也别干扰模型。
      expect(prompt, isNot(contains('00:12.34')));
      expect(prompt, contains('Future Bass'));
      expect(prompt, contains('128'));
      expect(prompt, contains('瑞典电子音乐制作人'));
      // 明确告诉模型依据是什么。
      expect(prompt, contains('歌词'));

      // 系统提示要把任务定成「读材料」，而不是「回忆这首歌」。
      expect(client.lastSystem, contains('不是回忆'));
    });

    test('一点材料都没有时，提示词要求直说资料不足', () async {
      await controller.generate(track);
      expect(client.lastPrompt, contains('资料不足'));
    });
  });
}

/// 不取热评的材料收集器：单测只验本地材料拼装，不打网络。
class _NoCommentsBuilder extends SongContextBuilder {
  const _NoCommentsBuilder();

  @override
  Future<SongContext> build(
    Track track, {
    List<String> styles = const [],
    String language = '',
    String bpm = '',
    String artistBio = '',
    bool includeComments = true,
  }) => super.build(
    track,
    styles: styles,
    language: language,
    bpm: bpm,
    artistBio: artistBio,
    includeComments: false,
  );
}

/// 顶替 [AiClient]，不发真实请求。
class _StubAiClient implements AiClient {
  int calls = 0;
  List<String> chunks = const ['ok'];
  AiException? error;
  String? lastPrompt;
  String? lastSystem;

  @override
  Stream<String> stream({
    required String prompt,
    String? system,
    int maxTokens = AiClient.defaultMaxTokens,
  }) async* {
    calls += 1;
    lastPrompt = prompt;
    lastSystem = system;
    final failure = error;
    if (failure != null) throw failure;
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  @override
  Future<String> complete({
    required String prompt,
    String? system,
    int maxTokens = AiClient.defaultMaxTokens,
  }) async => chunks.join();

  @override
  Future<String> testConnection() async => '可用';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
