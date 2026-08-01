import 'package:cyrene_music_reborn/domain/models/audio_source_config.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_importer.dart';
import 'package:cyrene_music_reborn/infrastructure/services/configured_audio_source_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final importer = ConfiguredAudioSourceImporter();

  test('手动创建 OmniParse 时校验并规范化地址', () {
    final source = importer.createOmniParse(
      name: '  Private Omni  ',
      url: 'https://omni.test///',
      apiKey: ' secret ',
    );

    expect(source.type, AudioSourceType.omniParse);
    expect(source.name, 'Private Omni');
    expect(source.url, 'https://omni.test');
    expect(source.apiKey, 'secret');
    expect(source.supportedPlatforms, contains('spotify'));
  });

  test('拒绝非 HTTP OmniParse 地址', () {
    expect(
      () => importer.createOmniParse(name: 'Invalid', url: 'file:///tmp/api'),
      throwsA(isA<AudioSourceImportFailure>()),
    );
  });

  test('从洛雪脚本提取元数据并保留原始脚本', () async {
    const script = '''
/**
 * @name 测试洛雪源
 * @version 2.1.0
 * @author Cyrene
 * @description Test source
 */
const apiUrl = 'https://lx-api.test/'
const apiKey = 'lx-secret'
const urlPath = '/url/{source}/{songId}/{quality}'
''';

    final source = await importer.importLxMusicScript(
      script,
      sourceLabel: 'source.js',
    );

    expect(source.type, AudioSourceType.lxMusic);
    expect(source.name, '测试洛雪源');
    expect(source.url, 'https://lx-api.test');
    expect(source.version, '2.1.0');
    expect(source.author, 'Cyrene');
    expect(source.scriptSource, 'source.js');
    expect(source.scriptContent, script);
    expect(source.supportedPlatforms, ['netease', 'qq', 'kugou', 'kuwo']);
  });

  test('无法提取 API 地址的洛雪脚本受控失败', () {
    expect(
      importer.importLxMusicScript(
        '/** @name Empty */ const source = {};',
        sourceLabel: 'empty.js',
      ),
      throwsA(isA<AudioSourceImportFailure>()),
    );
  });
}
