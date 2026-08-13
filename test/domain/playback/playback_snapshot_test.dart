import 'dart:convert';

import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/repeat_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('序列化剥掉网络音源的限时播放地址', () {
    final track = _remote.copyWith(
      playbackUrl: Uri.parse('https://cdn.test/expiring.mp3?token=abc'),
    );

    final restored = _roundTrip(
      PlaybackSnapshot(
        queue: [track],
        currentTrackKey: track.key,
        volume: 0.8,
        repeatMode: RepeatMode.all,
      ),
    );

    // 留着它，PlaybackController._resolveTrack 会短路掉音源解析，
    // 拿过期地址去加载并失败。
    expect(restored.queue.single.playbackUrl, isNull);
    expect(restored.queue.single.name, track.name);
  });

  test('保留本地文件地址', () {
    final track = Track(
      id: 'D:/music/song.flac',
      name: '本地歌曲',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.local,
      filePath: 'D:/music/song.flac',
      playbackUrl: Uri.file('D:/music/song.flac'),
    );

    final restored = _roundTrip(
      PlaybackSnapshot(
        queue: [track],
        currentTrackKey: track.key,
        volume: 0.8,
        repeatMode: RepeatMode.all,
      ),
    );

    // 本地音源不参与音源解析，剥掉地址就再也放不出来了。
    expect(restored.queue.single.playbackUrl, Uri.file('D:/music/song.flac'));
  });

  test('往返保留播放进度与时长', () {
    final restored = _roundTrip(
      PlaybackSnapshot(
        queue: [_remote],
        currentTrackKey: _remote.key,
        volume: 0.5,
        repeatMode: RepeatMode.one,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 3, seconds: 20),
      ),
    );

    expect(restored.position, const Duration(seconds: 42));
    expect(restored.duration, const Duration(minutes: 3, seconds: 20));
    expect(restored.volume, 0.5);
    expect(restored.repeatMode, RepeatMode.one);
  });

  test('当前曲目不在队列里时进度一并归零', () {
    final restored = PlaybackSnapshot.fromJson({
      'queue': [_remote.toJson()],
      'currentTrackKey': 'netease:missing',
      'volume': 0.8,
      'repeatMode': 'all',
      'positionMs': 42000,
      'durationMs': 200000,
    });

    expect(restored.currentTrackKey, isNull);
    expect(restored.position, Duration.zero);
    expect(restored.duration, Duration.zero);
  });

  test('容忍缺失或非法的进度字段', () {
    final restored = PlaybackSnapshot.fromJson({
      'queue': [_remote.toJson()],
      'currentTrackKey': _remote.key,
      'volume': 0.8,
      'repeatMode': 'all',
      'positionMs': -1,
    });

    expect(restored.position, Duration.zero);
    expect(restored.duration, Duration.zero);
  });
}

const _remote = Track(
  id: 'one',
  name: '歌曲 one',
  artists: '歌手',
  album: '专辑',
  picUrl: '',
  source: MusicSource.netease,
);

/// 走一遍真实的落盘格式：JSON 字符串编解码，与 SharedPreferences 存的一致。
PlaybackSnapshot _roundTrip(PlaybackSnapshot snapshot) =>
    PlaybackSnapshot.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map,
      ),
    );
