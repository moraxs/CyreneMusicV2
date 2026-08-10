import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_song_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 展览馆的队列搜索。桌面歌词覆盖层与 SuperCyrene 播放器共用本组件，
/// 因此这里的行为对两端都成立。
void main() {
  Future<PlaybackController> pumpGallery(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final playback = PlaybackController(
      audio: const _SilentAudioGateway(),
      store: _MemorySnapshotStore(),
    );
    addTearDown(playback.dispose);
    playback.setQueue(const [
      Track(
        id: '1',
        name: '晴天',
        artists: '周杰伦',
        album: '叶惠美',
        picUrl: '',
        source: MusicSource.netease,
      ),
      Track(
        id: '2',
        name: '稻香',
        artists: '周杰伦',
        album: '魔杰座',
        picUrl: '',
        source: MusicSource.netease,
      ),
      Track(
        id: '3',
        name: '倔强',
        artists: '五月天',
        album: '神的孩子都在跳舞',
        picUrl: '',
        source: MusicSource.netease,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperCyreneSongGallery(
            playback: playback,
            // 默认背景要拉网络封面，测试里换成纯色。
            backdrop: const ColoredBox(color: Color(0xFF000000)),
            onClose: () {},
          ),
        ),
      ),
    );
    // 入场动画 + 首帧居中。
    await tester.pumpAndSettle();
    return playback;
  }

  testWidgets('搜索词过滤蜂巢卡片与标题计数', (tester) async {
    await pumpGallery(tester);

    expect(find.text('3 首歌曲'), findsOneWidget);
    expect(find.text('倔强'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pumpAndSettle();

    // 命中 2 首，非命中的卡片整个从卡片场移除。
    expect(find.text('2 首匹配 · 共 3 首'), findsOneWidget);
    expect(find.text('倔强'), findsNothing);
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('稻香'), findsOneWidget);
  });

  testWidgets('按专辑名也能匹配', (tester) async {
    await pumpGallery(tester);

    await tester.enterText(find.byType(TextField), '魔杰座');
    await tester.pumpAndSettle();

    expect(find.text('1 首匹配 · 共 3 首'), findsOneWidget);
    expect(find.text('稻香'), findsOneWidget);
    expect(find.text('晴天'), findsNothing);
  });

  testWidgets('无匹配时给出空态而非空白', (tester) async {
    await pumpGallery(tester);

    await tester.enterText(find.byType(TextField), '不存在的歌');
    await tester.pumpAndSettle();

    expect(find.text('没有匹配的歌曲'), findsOneWidget);
    expect(find.text('0 首匹配 · 共 3 首'), findsOneWidget);
  });

  testWidgets('清空搜索后恢复完整队列', (tester) async {
    await pumpGallery(tester);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pumpAndSettle();
    expect(find.text('倔强'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('3 首歌曲'), findsOneWidget);
    expect(find.text('倔强'), findsOneWidget);
  });

  testWidgets('搜索不改写播放队列本身', (tester) async {
    final playback = await pumpGallery(tester);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pumpAndSettle();

    // 搜索只是查找手段：真实队列必须原封不动，否则播完命中的几首就没有
    // 下一首了。
    expect(playback.state.queue.length, 3);
  });
}

class _SilentAudioGateway implements AudioPlayerGateway {
  const _SilentAudioGateway();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<PlaybackStatus> get statusStream => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<Duration?> load(Uri source) async => null;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

class _MemorySnapshotStore implements PlaybackSnapshotStore {
  @override
  Future<PlaybackSnapshot?> read() async => null;

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {}
}
