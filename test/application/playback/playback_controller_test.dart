import 'dart:async';

import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_resolver.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/domain/playback/repeat_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAudioGateway audio;
  late FakePlaybackSnapshotStore store;
  late PlaybackController controller;

  setUp(() {
    audio = FakeAudioGateway();
    store = FakePlaybackSnapshotStore();
    controller = PlaybackController(audio: audio, store: store);
  });

  tearDown(() => controller.dispose());

  test('恢复队列与偏好，但不会自动播放', () async {
    final track = _track('one');
    store.snapshot = PlaybackSnapshot(
      queue: [track],
      currentTrackKey: track.key,
      volume: 0.35,
      repeatMode: RepeatMode.shuffle,
    );

    await controller.restore();

    expect(controller.state.currentTrack, track);
    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.volume, 0.35);
    expect(controller.state.repeatMode, RepeatMode.shuffle);
    expect(audio.volume, 0.35);
  });

  test('播放曲目后由运行时状态投影播放进度', () async {
    final track = _track('one');

    await controller.playTrack(track);
    audio.statuses.add(PlaybackStatus.playing);
    audio.positions.add(const Duration(seconds: 12));

    await Future<void>.delayed(Duration.zero);

    expect(audio.loaded, [track.playbackUrl]);
    expect(audio.playCalls, 1);
    expect(controller.state.currentTrack, track);
    expect(controller.state.isPlaying, isTrue);
    expect(controller.state.position, const Duration(seconds: 12));
    expect(store.writeCount, greaterThan(0));
  });

  test('播放结束时按照队列播放下一首', () async {
    final first = _track('one');
    final second = _track('two');

    await controller.playTrack(first, queue: [first, second]);
    audio.statuses.add(PlaybackStatus.completed);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.currentTrack, second);
    expect(audio.loaded.last, second.playbackUrl);
  });

  test('解析成功但首个 CDN 加载失败时继续下一个候选', () async {
    controller.dispose();
    final first = _track('first');
    final second = _track('second');
    audio = FakeAudioGateway()..loadFailures.add(first.playbackUrl!);
    controller = PlaybackController(
      audio: audio,
      store: store,
      sourceResolver: _FakeSourceResolver([first, second]),
    );
    const unresolved = Track(
      id: 'origin',
      name: '待解析歌曲',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.netease,
    );

    await controller.playTrack(unresolved);

    expect(audio.loaded, [first.playbackUrl, second.playbackUrl]);
    expect(controller.state.currentTrack, second);
    expect(controller.state.errorMessage, isNull);
    expect(audio.playCalls, 1);
  });

  test('缺少播放地址时不调用音频运行时', () async {
    final track = Track(
      id: 'empty',
      name: '无地址歌曲',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.netease,
    );

    await controller.playTrack(track);

    expect(audio.loaded, isEmpty);
    expect(controller.state.errorMessage, isNotNull);
  });

  test('设置智能续播供给方后，「下一首」改走供给方', () async {
    final first = _track('one');
    final second = _track('two');
    final smart = _track('smart');
    await controller.playTrack(first, queue: [first, second]);
    controller.setSmartNextProvider(() async => smart);

    await controller.playNext();

    expect(controller.state.currentTrack, smart);
    expect(audio.loaded.last, smart.playbackUrl);
  });

  test('播放自然结束同样走智能续播供给方', () async {
    final first = _track('one');
    final smart = _track('smart');
    await controller.playTrack(first, queue: [first]);
    controller.setSmartNextProvider(() async => smart);

    audio.statuses.add(PlaybackStatus.completed);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.currentTrack, smart);
  });

  test('智能续播返回 null 时回退队列导航', () async {
    final first = _track('one');
    final second = _track('two');
    await controller.playTrack(first, queue: [first, second]);
    controller.setSmartNextProvider(() async => null);

    await controller.playNext();

    expect(controller.state.currentTrack, second);
  });

  test('智能续播抛错时回退队列导航', () async {
    final first = _track('one');
    final second = _track('two');
    await controller.playTrack(first, queue: [first, second]);
    controller.setSmartNextProvider(() async => throw StateError('boom'));

    await controller.playNext();

    expect(controller.state.currentTrack, second);
  });

  test('「上一首」不参与智能续播', () async {
    final first = _track('one');
    final second = _track('two');
    await controller.playTrack(second, queue: [first, second]);
    var consulted = false;
    controller.setSmartNextProvider(() async {
      consulted = true;
      return null;
    });

    await controller.playPrevious();

    expect(controller.state.currentTrack, first);
    expect(consulted, isFalse);
  });

  group('冷启动续播', () {
    test('恢复上次的播放进度与时长', () async {
      final track = _track('one');
      store.snapshot = PlaybackSnapshot(
        queue: [track],
        currentTrackKey: track.key,
        volume: 0.8,
        repeatMode: RepeatMode.all,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 3),
      );

      await controller.restore();

      expect(controller.state.position, const Duration(seconds: 42));
      expect(controller.state.duration, const Duration(minutes: 3));
      // 进度条读的是独立通知，不是 state。
      expect(controller.positionListenable.value, const Duration(seconds: 42));
      // 恢复不加载音频，更不自动播放。
      expect(audio.loaded, isEmpty);
      expect(audio.playCalls, 0);
    });

    test('恢复后按播放会重新解析音源并定位到上次位置', () async {
      controller.dispose();
      // 快照里的曲目不带播放地址（已按时效性剥离），只能靠 resolver 拿新地址。
      const stale = Track(
        id: 'one',
        name: '歌曲 one',
        artists: '歌手',
        album: '专辑',
        picUrl: '',
        source: MusicSource.netease,
      );
      final resolved = _track('one');
      audio = FakeAudioGateway();
      controller = PlaybackController(
        audio: audio,
        store: store,
        sourceResolver: _FakeSourceResolver([resolved]),
      );
      store.snapshot = PlaybackSnapshot(
        queue: const [stale],
        currentTrackKey: stale.key,
        volume: 0.8,
        repeatMode: RepeatMode.all,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 3),
      );
      await controller.restore();

      await controller.togglePlay();

      expect(audio.loaded, [resolved.playbackUrl]);
      expect(audio.seeks, contains(const Duration(seconds: 42)));
      expect(audio.playCalls, 1);
      expect(controller.state.position, const Duration(seconds: 42));
    });

    test('续播期间进度未到位则补发 seek', () async {
      controller.dispose();
      final track = _track('one');
      audio = FakeAudioGateway();
      controller = PlaybackController(audio: audio, store: store);

      await controller.playTrack(track, startAt: const Duration(seconds: 42));
      expect(audio.seeks, [const Duration(seconds: 42)]);

      // 运行时报告的进度仍在片头 —— 说明那次 seek 被丢弃了。
      audio.positions.add(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(audio.seeks.length, 2);

      // 到位之后不再补发。
      audio.positions.add(const Duration(seconds: 42));
      await Future<void>.delayed(Duration.zero);
      audio.positions.add(const Duration(seconds: 43));
      await Future<void>.delayed(Duration.zero);
      expect(audio.seeks.length, 2);
    });

    test('用户主动拖动进度条会取消待补的续播定位', () async {
      controller.dispose();
      final track = _track('one');
      audio = FakeAudioGateway();
      controller = PlaybackController(audio: audio, store: store);
      await controller.playTrack(track, startAt: const Duration(seconds: 42));

      await controller.seek(const Duration(seconds: 5));
      audio.positions.add(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      // 42 秒的续播 seek + 用户的 5 秒，不该有补发的第三次。
      expect(audio.seeks, [
        const Duration(seconds: 42),
        const Duration(seconds: 5),
      ]);
    });

    test('新音源比上次短时放弃续播', () async {
      controller.dispose();
      final track = _track('one');
      audio = FakeAudioGateway();
      controller = PlaybackController(audio: audio, store: store);

      // load 返回 3 分钟，续播点落在 5 分钟——这条音源根本到不了。
      await controller.playTrack(track, startAt: const Duration(minutes: 5));
      audio.positions.add(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      audio.positions.add(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(audio.seeks, [const Duration(minutes: 5)]);
    });

    test('进度落盘按 5 秒节流，暂停时补一次精确值', () async {
      final track = _track('one');
      await controller.playTrack(track);
      final baseline = store.writeCount;

      // 节流窗口内的 tick 不落盘。
      for (final seconds in [1, 2, 3, 4]) {
        audio.positions.add(Duration(seconds: seconds));
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.writeCount, baseline);

      audio.positions.add(const Duration(seconds: 6));
      await Future<void>.delayed(Duration.zero);
      expect(store.writeCount, baseline + 1);
      expect(store.snapshot?.position, const Duration(seconds: 6));

      // 暂停绕过节流，落下精确进度。
      audio.positions.add(const Duration(seconds: 8));
      await Future<void>.delayed(Duration.zero);
      audio.statuses.add(PlaybackStatus.paused);
      await Future<void>.delayed(Duration.zero);
      expect(store.snapshot?.position, const Duration(seconds: 8));
    });

    test('flush 立即落盘当前精确进度', () async {
      final track = _track('one');
      await controller.playTrack(track);
      audio.positions.add(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);

      await controller.flush();

      expect(store.snapshot?.position, const Duration(seconds: 3));
    });

    test('切歌不会把上一首的进度带过去', () async {
      final first = _track('one');
      final second = _track('two');
      await controller.playTrack(first, queue: [first, second]);
      audio.positions.add(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);

      await controller.playNext();

      expect(controller.state.currentTrack, second);
      expect(controller.state.position, Duration.zero);
      expect(audio.seeks, isEmpty);
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
  playbackUrl: Uri.parse('https://example.test/$id.mp3'),
);

class FakeAudioGateway implements AudioPlayerGateway {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration?>.broadcast();
  final statuses = StreamController<PlaybackStatus>.broadcast();
  final loaded = <Uri>[];
  final loadFailures = <Uri>{};
  final seeks = <Duration>[];
  double volume = 0;
  int playCalls = 0;

  @override
  Stream<Duration?> get durationStream => durations.stream;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<PlaybackStatus> get statusStream => statuses.stream;

  @override
  Future<void> dispose() async {
    await positions.close();
    await durations.close();
    await statuses.close();
  }

  @override
  Future<Duration?> load(Uri source) async {
    loaded.add(source);
    if (loadFailures.contains(source)) throw StateError('CDN unavailable');
    return const Duration(minutes: 3);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async => playCalls += 1;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> stop() async {}
}

class _FakeSourceResolver implements AudioSourceResolver {
  _FakeSourceResolver(this.tracks);

  final List<Track> tracks;

  @override
  Future<ResolvedAudioSources> resolve(Track track) async =>
      ResolvedAudioSources([
        for (var index = 0; index < tracks.length; index++)
          PlaybackCandidate(track: tracks[index], sourceId: 'source-$index'),
      ]);
}

class FakePlaybackSnapshotStore implements PlaybackSnapshotStore {
  PlaybackSnapshot? snapshot;
  int writeCount = 0;

  @override
  Future<PlaybackSnapshot?> read() async => snapshot;

  @override
  Future<void> write(PlaybackSnapshot next) async {
    writeCount += 1;
    snapshot = next;
  }
}
