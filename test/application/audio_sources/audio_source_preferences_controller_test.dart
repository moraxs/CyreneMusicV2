import 'dart:typed_data';

import 'package:cyrene_music_reborn/application/audio_sources/audio_source_preferences_controller.dart';
import 'package:cyrene_music_reborn/domain/models/audio_quality.dart';
import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_importer.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('恢复、增删、启停和排序始终写入同一个偏好存储', () async {
    final store = _MemoryPreferencesStore(
      AudioSourcePreferences(sources: [_source('official')]),
    );
    final controller = AudioSourcePreferencesController(
      store: store,
      importer: _FakeImporter(),
    );
    addTearDown(controller.dispose);

    await controller.restore();
    expect(controller.state.sources.single.id, 'official');

    expect(
      await controller.addOmniParse(name: '备用解析', url: 'https://backup.test/'),
      isTrue,
    );
    expect(controller.state.sources.map((source) => source.id), [
      'official',
      'created-omni',
    ]);

    await controller.reorderSources(1, 0);
    expect(controller.state.sources.first.id, 'created-omni');

    await controller.setSourceEnabled('created-omni', false);
    expect(controller.state.sources.first.isEnabled, isFalse);

    await controller.setQuality(AudioQuality.lossless);
    expect(store.value.quality, AudioQuality.lossless);

    await controller.removeSource('official');
    expect(store.value.sources.single.id, 'created-omni');
    expect(store.writeCount, 5);
  });

  test('持久化失败时回滚乐观更新并暴露稳定错误', () async {
    final store = _MemoryPreferencesStore(
      AudioSourcePreferences(sources: [_source('official')]),
    )..failWrites = true;
    final controller = AudioSourcePreferencesController(
      store: store,
      importer: _FakeImporter(),
    );
    addTearDown(controller.dispose);
    await controller.restore();

    expect(await controller.removeSource('official'), isFalse);
    expect(controller.state.sources.single.id, 'official');
    expect(controller.state.errorMessage, contains('保存音源配置失败'));
  });

  test('Lx Music 导入结果可以持久化但保持类型标识', () async {
    final store = _MemoryPreferencesStore(const AudioSourcePreferences());
    final controller = AudioSourcePreferencesController(
      store: store,
      importer: _FakeImporter(),
    );
    addTearDown(controller.dispose);
    await controller.restore();

    expect(
      await controller.importLxMusicScript('script', sourceLabel: 'source.js'),
      isTrue,
    );
    expect(store.value.sources.single.type, AudioSourceType.lxMusic);
    expect(store.value.sources.single.scriptSource, 'source.js');
  });
}

AudioSourceConfig _source(String id) => AudioSourceConfig(
  id: id,
  type: AudioSourceType.omniParse,
  name: id,
  url: 'https://$id.test',
);

class _MemoryPreferencesStore implements AudioSourcePreferencesStore {
  _MemoryPreferencesStore(this.value);

  AudioSourcePreferences value;
  int writeCount = 0;
  bool failWrites = false;

  @override
  Future<AudioSourcePreferences> read() async => value;

  @override
  Future<void> write(AudioSourcePreferences preferences) async {
    if (failWrites) throw StateError('disk full');
    writeCount++;
    value = preferences;
  }
}

class _FakeImporter implements AudioSourceImporter {
  @override
  AudioSourceConfig createOmniParse({
    required String name,
    required String url,
    String apiKey = '',
    String? id,
  }) => AudioSourceConfig(
    id: id ?? 'created-omni',
    type: AudioSourceType.omniParse,
    name: name,
    url: url.replaceFirst(RegExp(r'/+$'), ''),
    apiKey: apiKey,
  );

  @override
  Future<AudioSourceConfig> importLxMusicScript(
    String script, {
    required String sourceLabel,
  }) async => AudioSourceConfig(
    id: 'imported-lx',
    type: AudioSourceType.lxMusic,
    name: 'Lx Music',
    url: 'https://lx.test',
    scriptSource: sourceLabel,
    scriptContent: script,
  );

  @override
  Future<AudioSourceConfig> importLxMusicUrl(String url) =>
      importLxMusicScript('remote-script', sourceLabel: url);

  @override
  Future<AudioSourceConfig> importOmniParse(Uint8List bytes) async =>
      createOmniParse(name: 'Imported Omni', url: 'https://imported.test');
}
