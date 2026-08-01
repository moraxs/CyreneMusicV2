import 'dart:convert';

import 'package:cyrene_music_reborn/domain/models/audio_quality.dart';
import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:cyrene_music_reborn/infrastructure/storage/shared_preferences_audio_source_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final defaultSource = AudioSourceConfig(
    id: 'official',
    type: AudioSourceType.omniParse,
    name: 'Official',
    url: 'https://official.test',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('新安装和损坏配置回退空列表，不预置官方 OmniParse 占位卡', () async {
    final store = SharedPreferencesAudioSourcePreferencesStore();

    expect((await store.read()).sources, isEmpty);

    SharedPreferences.setMockInitialValues({
      SharedPreferencesAudioSourcePreferencesStore.storageKey: '{broken',
    });
    expect((await store.read()).sources, isEmpty);
  });

  test('兼容 Zustand state 包装并忽略旧 TuneHub 配置', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAudioSourcePreferencesStore.storageKey: jsonEncode({
        'state': {
          'sources': [
            {
              'id': 'tune',
              'type': 2,
              'name': 'Legacy TuneHub',
              'url': 'https://tune.test',
            },
            {
              'id': 'omni',
              'type': 0,
              'name': 'Omni',
              'url': 'https://omni.test',
              'isEnabled': false,
            },
          ],
          'quality': 'lossless',
        },
        'version': 0,
      }),
    });
    final store = SharedPreferencesAudioSourcePreferencesStore();

    final value = await store.read();
    expect(value.sources.single.id, 'omni');
    expect(value.sources.single.isEnabled, isFalse);
    expect(value.quality, AudioQuality.lossless);
  });

  test('写入后保留顺序、启用状态和音质', () async {
    final store = SharedPreferencesAudioSourcePreferencesStore();
    final value = AudioSourcePreferences(
      sources: [
        AudioSourceConfig(
          id: 'lx',
          type: AudioSourceType.lxMusic,
          name: 'Lx',
          url: 'https://lx.test',
          isEnabled: false,
          scriptContent: 'script',
        ),
        defaultSource,
      ],
      quality: AudioQuality.hiRes,
    );

    await store.write(value);
    final restored = await store.read();

    expect(restored.sources.map((source) => source.id), ['lx', 'official']);
    expect(restored.sources.first.isEnabled, isFalse);
    expect(restored.sources.first.scriptContent, 'script');
    expect(restored.quality, AudioQuality.hiRes);
  });
}
