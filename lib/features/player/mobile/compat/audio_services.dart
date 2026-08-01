import 'package:flutter/foundation.dart';

import '../../../../domain/models/audio_quality.dart' as app;
import 'player_service.dart';
import 'song_detail.dart';

/// 原版音源类型（兼容层仅保留区分能力，全部按 omniparse 处理）。
enum AudioSourceType { omniparse, lxmusic, tunehub }

/// 原版 `AudioSourceService` 兼容层。
/// 新架构的音源配置由 AudioSourcePreferencesController 管理，这里视为恒已配置。
class AudioSourceService extends ChangeNotifier {
  static final AudioSourceService _instance = AudioSourceService._internal();
  factory AudioSourceService() => _instance;
  AudioSourceService._internal();

  Object? get activeSource => null;
  AudioSourceType get sourceType => AudioSourceType.omniparse;
  bool get isConfigured => true;
}

/// 原版 `AudioQualityService` 兼容层：音质选择桥接到新架构的
/// AudioSourcePreferencesController，文案与原版完全一致。
class AudioQualityService extends ChangeNotifier {
  static final AudioQualityService _instance = AudioQualityService._internal();
  factory AudioQualityService() => _instance;
  AudioQualityService._internal();

  AudioQuality get currentQuality {
    final wire =
        PlayerService().audioSources?.state.quality.wireName ?? 'exhigh';
    return switch (wire) {
      'standard' => AudioQuality.standard,
      'lossless' => AudioQuality.lossless,
      'hires' => AudioQuality.hires,
      _ => AudioQuality.exhigh,
    };
  }

  Future<void> setQuality(AudioQuality quality) async {
    final target = switch (quality) {
      AudioQuality.standard => app.AudioQuality.standard,
      AudioQuality.lossless => app.AudioQuality.lossless,
      AudioQuality.hires => app.AudioQuality.hiRes,
      _ => app.AudioQuality.exHigh,
    };
    await PlayerService().audioSources?.setQuality(target);
    notifyListeners();
  }

  List<AudioQuality> getSupportedQualities(AudioSourceType sourceType) => const [
    AudioQuality.standard,
    AudioQuality.exhigh,
    AudioQuality.lossless,
    AudioQuality.hires,
  ];

  String getQualityName([AudioQuality? quality]) {
    switch (quality ?? currentQuality) {
      case AudioQuality.standard:
        return '标准音质';
      case AudioQuality.exhigh:
        return '高品质';
      case AudioQuality.lossless:
        return '无损音质';
      case AudioQuality.hires:
        return 'Hi-Res';
      case AudioQuality.jyeffect:
        return 'Audio Vivid';
      case AudioQuality.jymaster:
        return '超清母带';
      default:
        return '高品质';
    }
  }

  String getShortLabel([AudioQuality? quality]) {
    switch (quality ?? currentQuality) {
      case AudioQuality.standard:
        return '128kbps';
      case AudioQuality.exhigh:
        return '320kbps';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hires:
        return 'Hi-Res';
      case AudioQuality.jyeffect:
        return 'Vivid';
      case AudioQuality.jymaster:
        return 'Master';
      default:
        return '320';
    }
  }

  String getQualityDescription([AudioQuality? quality]) {
    switch (quality ?? currentQuality) {
      case AudioQuality.standard:
        return 'MP3 128kbps，节省流量';
      case AudioQuality.exhigh:
        return 'MP3 320kbps，推荐';
      case AudioQuality.lossless:
        return 'FLAC 无损，音质优秀';
      case AudioQuality.hires:
        return 'Hi-Res 24bit/96kHz';
      case AudioQuality.jyeffect:
        return 'Audio Vivid，沉浸体验';
      case AudioQuality.jymaster:
        return '超清母带，极致体验';
      default:
        return 'MP3 320kbps，推荐';
    }
  }
}
