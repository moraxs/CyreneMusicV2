import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final track = Track(
    id: '42',
    name: '测试歌曲',
    artists: '测试歌手',
    album: '测试专辑',
    picUrl: '',
    source: MusicSource.qq,
  );

  test('Track 接受数字 ID 的序列化输入', () {
    final restored = Track.fromJson({...track.toJson(), 'id': 42});

    expect(restored.id, '42');
    expect(restored, track);
  });

  test('PlaybackState 对队列做不可变快照且支持清除当前歌曲', () {
    final queue = [track];
    final state = PlaybackState(currentTrack: track, queue: queue);
    queue.clear();

    expect(state.queue, [track]);
    expect(state.copyWith(clearCurrentTrack: true).currentTrack, isNull);
  });
}
