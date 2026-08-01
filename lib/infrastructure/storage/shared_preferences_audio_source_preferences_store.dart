import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/audio_quality.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/playback/audio_source_preferences_store.dart';

class SharedPreferencesAudioSourcePreferencesStore
    implements AudioSourcePreferencesStore {
  SharedPreferencesAudioSourcePreferencesStore();

  static const storageKey = 'audio-source-storage';

  @override
  Future<AudioSourcePreferences> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    // 新安装/损坏配置：返回空列表，不预置官方 OmniParse 空壳。
    // 官方音源仅在持卡下发（/card/config）后才以稳定 id official-omniparse 落地，
    // 避免未购买 Cyrene Premium 且未导入音源时显示无用的 Cyrene Official 占位卡。
    if (raw == null || raw.isEmpty) return const AudioSourcePreferences();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const AudioSourcePreferences();
      final root = Map<String, Object?>.from(decoded);
      final nestedState = root['state'];
      final payload = nestedState is Map
          ? Map<String, Object?>.from(nestedState)
          : root;
      final rawSources = payload['sources'];
      if (rawSources is! List) return const AudioSourcePreferences();

      final sources = rawSources
          .whereType<Map>()
          .map(
            (item) =>
                AudioSourceConfig.tryFromJson(Map<String, Object?>.from(item)),
          )
          .whereType<AudioSourceConfig>()
          .toList(growable: false);

      if (rawSources.isNotEmpty && sources.isEmpty) {
        return const AudioSourcePreferences();
      }
      final qualityValue = payload['quality']?.toString();
      return AudioSourcePreferences(
        sources: List.unmodifiable(sources),
        quality: qualityValue == null
            ? AudioQuality.exHigh
            : AudioQuality.fromWireName(qualityValue),
      );
    } catch (_) {
      return const AudioSourcePreferences();
    }
  }

  @override
  Future<void> write(AudioSourcePreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode({
        'sources': value.sources.map((source) => source.toJson()).toList(),
        'quality': value.quality.wireName,
        'isInitialized': true,
      }),
    );
  }
}
