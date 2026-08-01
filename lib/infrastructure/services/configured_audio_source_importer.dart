import 'dart:typed_data';

import '../../domain/models/audio_source_config.dart';
import '../../domain/models/lx_music_config.dart';
import '../../domain/playback/audio_source_importer.dart';
import 'cyrene_config_service.dart';
import 'lx_music_source_service.dart';

class ConfiguredAudioSourceImporter implements AudioSourceImporter {
  ConfiguredAudioSourceImporter({
    CyreneConfigService? cyreneConfigs,
    LxMusicSourceService? lxMusicSources,
  }) : _cyreneConfigs = cyreneConfigs ?? CyreneConfigService.instance,
       _lxMusicSources = lxMusicSources ?? LxMusicSourceService.instance;

  final CyreneConfigService _cyreneConfigs;
  final LxMusicSourceService _lxMusicSources;

  static const _omniPlatforms = [
    'netease',
    'qq',
    'kugou',
    'kuwo',
    'apple',
    'spotify',
    'qishui',
  ];

  static const _lxPlatforms = ['netease', 'qq', 'kugou', 'kuwo'];

  @override
  AudioSourceConfig createOmniParse({
    required String name,
    required String url,
    String apiKey = '',
    String? id,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const AudioSourceImportFailure('请输入音源名称。');
    }
    _requireHttpUrl(url, label: 'OmniParse API 地址');
    return AudioSourceConfig(
      id: id ?? _nextId('omni'),
      type: AudioSourceType.omniParse,
      name: normalizedName,
      url: _normalizeUrl(url),
      apiKey: apiKey.trim(),
      supportedPlatforms: _omniPlatforms,
    );
  }

  @override
  Future<AudioSourceConfig> importOmniParse(Uint8List bytes) async {
    final imported = await _cyreneConfigs.decrypt(bytes);
    if (imported == null) {
      throw const AudioSourceImportFailure('配置文件无法解密或格式不受支持。');
    }
    return createOmniParse(
      name: imported.name.trim().isEmpty ? 'OmniParse' : imported.name,
      url: imported.url,
      apiKey: imported.apiKey,
    );
  }

  @override
  Future<AudioSourceConfig> importLxMusicScript(
    String script, {
    required String sourceLabel,
  }) async {
    final imported = _lxMusicSources.parseScript(script);
    if (imported == null) {
      throw const AudioSourceImportFailure('脚本解析失败，请确认它是有效的洛雪音源脚本。');
    }
    return _fromLxConfig(imported, sourceLabel: sourceLabel);
  }

  @override
  Future<AudioSourceConfig> importLxMusicUrl(String url) async {
    _requireHttpUrl(url, label: '洛雪脚本链接');
    final normalized = url.trim();
    final imported = await _lxMusicSources.fetchAndParse(normalized);
    if (imported == null) {
      throw const AudioSourceImportFailure('脚本下载或解析失败，请检查链接是否可直接访问。');
    }
    return _fromLxConfig(imported, sourceLabel: normalized);
  }

  AudioSourceConfig _fromLxConfig(
    LxMusicConfig config, {
    required String sourceLabel,
  }) {
    _requireHttpUrl(config.apiUrl, label: '洛雪音源 API 地址');
    return AudioSourceConfig(
      id: _nextId('lx'),
      type: AudioSourceType.lxMusic,
      name: config.name.trim().isEmpty ? 'Lx Music' : config.name.trim(),
      url: _normalizeUrl(config.apiUrl),
      apiKey: config.apiKey.trim(),
      supportedPlatforms: _lxPlatforms,
      version: config.version.trim(),
      author: config.author.trim(),
      description: config.description.trim(),
      scriptSource: sourceLabel,
      scriptContent: config.scriptContent,
      urlPathTemplate: config.urlPathTemplate,
    );
  }

  void _requireHttpUrl(String value, {required String label}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw AudioSourceImportFailure('$label无效。');
    }
  }

  String _normalizeUrl(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
