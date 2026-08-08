import 'dart:async';

import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/super_cyrene/super_cyrene_chat_lyrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 与 _ActiveChatText 内部一致的字号/行高常量。
const chatActiveFontSize = 18 * 1.24;
const chatLineHeight = 1.45;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioGateway audio;
  late FakePlaybackSnapshotStore store;
  late PlaybackController controller;

  Future<void> pumpChat(WidgetTester tester, String lyricLine) async {
    final track = Track(
      id: 't1',
      name: '对话',
      artists: '歌手',
      album: '专辑',
      picUrl: '',
      source: MusicSource.netease,
      lyric: lyricLine,
    );
    await controller.playTrack(track);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperCyreneChatLyrics(
            playback: controller,
            track: track,
            cover: null,
          ),
        ),
      ),
    );
  }

  setUp(() {
    audio = FakeAudioGateway();
    store = FakePlaybackSnapshotStore();
    controller = PlaybackController(audio: audio, store: store);
  });

  tearDown(() {
    controller.dispose();
  });

  double measuredTextWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: chatActiveFontSize,
          fontWeight: FontWeight.w400,
          height: chatLineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 513);
    final width = painter.width;
    painter.dispose();
    return width;
  }

  testWidgets('活跃气泡完整显示整行歌词，右侧不裁切最后字符', (tester) async {
    final line = "We don't have";
    await pumpChat(tester, '[00:00.000] $line');

    // 驱动到行尾附近：所有字符都进入渲染/测量范围。
    audio.positions.add(const Duration(seconds: 8));
    await tester.pump();

    // 气泡宽度用真实墙钟驱动的弹簧收敛，widget 测试的 pump 不推进墙钟。
    // 每次 pump 前放行一段真实时间，弹簧逐步逼近目标（单次最多 50ms）。
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    // 活跃气泡的 ClipRect（全文就一个，即 _ActiveChatText 内部那一层）。
    final clipRectFinder = find.byType(ClipRect);
    expect(clipRectFinder, findsOneWidget,
        reason: '活跃气泡内应只有一个 ClipRect');
    final clipWidth = tester.getSize(clipRectFinder).width;

    final textWidth = measuredTextWidth(line);
    // 气泡裁剪宽度应不小于整行文本真实宽度。
    expect(
      clipWidth >= textWidth - 0.5,
      isTrue,
      reason: 'clipWidth=$clipWidth textWidth=$textWidth 活跃气泡宽度小于整行文本宽度，右侧字符会被裁掉',
    );
  });
}

class FakeAudioGateway implements AudioPlayerGateway {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration?>.broadcast();
  final statuses = StreamController<PlaybackStatus>.broadcast();
  double volume = 0;
  int playCalls = 0;
  final loaded = <Uri>[];

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
    return const Duration(minutes: 5);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {
    playCalls += 1;
  }

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
