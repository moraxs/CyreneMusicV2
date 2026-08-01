import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/queue_navigation.dart';
import 'package:cyrene_music_reborn/domain/playback/repeat_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final first = _track('1');
  final second = _track('2');
  final third = _track('3');
  final queue = [first, second, third];

  group('nextTrack', () {
    test('列表循环在最后一首回到开头', () {
      expect(
        nextTrack(
          queue: queue,
          currentTrack: third,
          repeatMode: RepeatMode.all,
        ),
        first,
      );
    });

    test('关闭循环后在最后一首停止', () {
      expect(
        nextTrack(
          queue: queue,
          currentTrack: third,
          repeatMode: RepeatMode.off,
        ),
        isNull,
      );
    });

    test('单曲循环保持当前曲目', () {
      expect(
        nextTrack(
          queue: queue,
          currentTrack: second,
          repeatMode: RepeatMode.one,
        ),
        second,
      );
    });

    test('随机播放不会选择当前曲目', () {
      expect(
        nextTrack(
          queue: queue,
          currentTrack: second,
          repeatMode: RepeatMode.shuffle,
          randomIndex: 1,
        ),
        third,
      );
    });
  });

  group('previousTrack', () {
    test('列表循环在第一首回到末尾', () {
      expect(
        previousTrack(
          queue: queue,
          currentTrack: first,
          repeatMode: RepeatMode.all,
        ),
        third,
      );
    });

    test('关闭循环后在第一首停止', () {
      expect(
        previousTrack(
          queue: queue,
          currentTrack: first,
          repeatMode: RepeatMode.off,
        ),
        isNull,
      );
    });
  });
}

Track _track(String id) => Track(
  id: id,
  name: '歌曲 $id',
  artists: '歌手',
  album: '专辑',
  picUrl: '',
  source: MusicSource.netease,
);
