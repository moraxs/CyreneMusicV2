import 'dart:async';

import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/infrastructure/media_notification/smtc_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cyrene.music/smtc');
  // EventChannel 底层也是 MethodChannel（listen/cancel + 事件信封）。
  const events = MethodChannel('cyrene.music/smtc/events');

  late FakeAudioGateway audio;
  late FakePlaybackSnapshotStore store;
  late PlaybackController controller;
  late SmtcService service;
  final nativeCalls = <MethodCall>[];

  /// 模拟原生端推送一条 SMTC 按钮事件。
  Future<void> pushNativeEvent(Map<Object?, Object?> event) async {
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      'cyrene.music/smtc/events',
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  setUp(() {
    audio = FakeAudioGateway();
    store = FakePlaybackSnapshotStore();
    controller = PlaybackController(audio: audio, store: store);
    service = SmtcService(controller, isWindows: true);
    nativeCalls.clear();
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return call.method == 'init';
    });
    messenger.setMockMethodCallHandler(events, (call) async => null);
  });

  tearDown(() async {
    service.dispose();
    controller.dispose();
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('非 Windows 平台为空操作，不触碰通道', () {
    final other = SmtcService(controller, isWindows: false);
    other.start();
    expect(nativeCalls, isEmpty);
    other.dispose();
  });

  test('初始化成功后同步当前播放状态到原生端', () async {
    final track = _track('one');
    await controller.playTrack(track);
    audio.statuses.add(PlaybackStatus.playing);
    await Future<void>.delayed(Duration.zero);

    service.start();
    // 等待 init 应答与状态同步完成
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls.first.method, 'init');
    final update = nativeCalls.lastWhere((call) => call.method == 'update');
    final args = Map<String, Object?>.from(update.arguments as Map);
    expect(args['title'], track.name);
    expect(args['artist'], track.artists);
    expect(args['album'], track.album);
    expect(args['isPlaying'], isTrue);
    expect(args['durationMs'], const Duration(minutes: 3).inMilliseconds);
    expect(args['repeatMode'], 'all');
  });

  test('原生按钮事件转发到播放控制器', () async {
    final first = _track('one');
    final second = _track('two');
    await controller.playTrack(first, queue: [first, second]);
    audio.statuses.add(PlaybackStatus.playing);
    await Future<void>.delayed(Duration.zero);
    service.start();
    await Future<void>.delayed(Duration.zero);

    // 下一首
    await pushNativeEvent({'event': 'next'});
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.currentTrack, second);

    // 暂停（此时 state 未播放）
    expect(controller.state.isPlaying, isFalse);
    await pushNativeEvent({'event': 'play'});
    audio.statuses.add(PlaybackStatus.playing);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isPlaying, isTrue);

    // seek
    await pushNativeEvent({'event': 'seek', 'positionMs': 30000});
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.position, const Duration(seconds: 30));
  });

  test('清空队列时通知原生端清空媒体控件', () async {
    final track = _track('one');
    await controller.playTrack(track);
    await Future<void>.delayed(Duration.zero);
    service.start();
    await Future<void>.delayed(Duration.zero);
    nativeCalls.clear();

    await controller.clearQueue();
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls.any((call) => call.method == 'clear'), isTrue);
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
    return const Duration(minutes: 3);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async => playCalls += 1;

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double value) async => volume = value;

  @override
  Future<void> stop() async {}
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
