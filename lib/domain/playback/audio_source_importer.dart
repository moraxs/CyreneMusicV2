import 'dart:typed_data';

import '../models/audio_source_config.dart';

class AudioSourceImportFailure implements Exception {
  const AudioSourceImportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AudioSourceImporter {
  AudioSourceConfig createOmniParse({
    required String name,
    required String url,
    String apiKey = '',
    String? id,
  });

  Future<AudioSourceConfig> importOmniParse(Uint8List bytes);

  Future<AudioSourceConfig> importLxMusicScript(
    String script, {
    required String sourceLabel,
  });

  Future<AudioSourceConfig> importLxMusicUrl(String url);
}
