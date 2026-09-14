import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/models/discovery.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_source_resolver.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/cyrene_track_tile.dart';
import 'package:cyrene_music_reborn/features/player/track_artwork.dart';
import 'package:cyrene_music_reborn/features/playlist/playlist_detail_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('desktop playlist lazily builds track rows', (tester) async {
    await _pumpPlaylist(
      tester,
      playback: _makePlayback(),
      desktopLayout: true,
      size: const Size(1200, 800),
    );

    // 在线歌单默认最近加入的歌曲在前；这里只检查惰性构建，不改排序语义。
    expect(find.text('Song 499'), findsOneWidget);
    expect(find.text('Song 0'), findsNothing);
    expect(find.byType(TrackArtwork).evaluate().length, lessThan(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile playlist stays lazy during long scrolling', (
    tester,
  ) async {
    await _pumpPlaylist(tester, playback: _makePlayback());
    expect(find.text('Song 499'), findsOneWidget);
    expect(find.text('Song 0'), findsNothing);
    expect(_tiles(tester).length, lessThan(30));

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -600),
      5000,
    );
    await tester.pumpAndSettle();
    _scrollController(tester).jumpTo(12000);
    await tester.pumpAndSettle();

    expect(find.text('Song 499'), findsNothing);
    expect(_tiles(tester), isNotEmpty);
    expect(_tiles(tester).length, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile playlist supports duplicate track IDs', (tester) async {
    final playlist = _makePlaylist(names: ['Echo', 'Another', 'Echo']);
    playlist.tracks[2] = playlist.tracks.first;
    await _pumpPlaylist(tester, playback: _makePlayback(), playlist: playlist);
    expect(_tiles(tester).map((tile) => tile.track.id), ['0', '1', '0']);
    await _selectSort(tester, '默认排序', '歌名 Z-A');
    expect(_tileNames(tester), ['Echo', 'Echo', 'Another']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling does not rebuild the cover subtree', (tester) async {
    await _pumpPlaylist(tester, playback: _makePlayback());
    final flow = tester.widget<Flow>(find.byType(Flow));
    final coverBoundary = flow.children.single as RepaintBoundary;
    final coverElement = tester.element(find.byWidget(coverBoundary.child!));
    var coverRebuilds = 0;
    final previousCallback = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousCallback?.call(element, builtOnce);
      if (element == coverElement) coverRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);

    final controller = _scrollController(tester);
    for (var i = 1; i <= 60; i++) {
      controller.jumpTo(i * 5.0);
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(coverRebuilds, 0);
    expect(tester.widget<Flow>(find.byType(Flow)), same(flow));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover keeps its parallax curve and skips offscreen painting', (
    tester,
  ) async {
    await _pumpPlaylist(tester, playback: _makePlayback());
    final flow = tester.widget<Flow>(find.byType(Flow));
    final size = tester.getSize(find.byType(Flow));
    final controller = _scrollController(tester);

    for (final offset in [-40.0, 0.0, 137.25, size.height, size.height * 1.8]) {
      controller.jumpTo(offset);
      // 在越界回弹前直接验证同一个绘制委托，也覆盖下拉时封面锁定不动。
      final painting = _RecordingFlowPaintingContext(size);
      flow.delegate.paintChildren(painting);
      final progress = (offset / size.height).clamp(0.0, 1.0);
      final scale = 1.0 - progress * 0.05;
      final parallax = offset > 0 ? offset * 0.45 : 0.0;
      expect(painting.paintCount, 1);
      final transform = painting.transform!;
      expect(transform.entry(0, 0), closeTo(scale, 1e-10));
      expect(transform.entry(1, 1), closeTo(scale, 1e-10));
      expect(
        MatrixUtils.transformPoint(
          transform,
          Offset(size.width / 2, size.height),
        ),
        offsetMoreOrLessEquals(Offset(size.width / 2, size.height - parallax)),
      );
      await tester.pumpAndSettle();
    }

    controller.jumpTo(size.height / 0.45 + 1);
    final offscreen = _RecordingFlowPaintingContext(size);
    flow.delegate.paintChildren(offscreen);
    expect(offscreen.paintCount, 0);
    await tester.pumpAndSettle();

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    final returned = _RecordingFlowPaintingContext(size);
    flow.delegate.paintChildren(returned);
    expect(returned.paintCount, 1);
    expect(returned.transform, Matrix4.identity());
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass rows share a backdrop without sharing the floating bar', (
    tester,
  ) async {
    await _pumpPlaylist(tester, playback: _makePlayback());
    final tiles = _tiles(tester);
    expect(tiles.length, greaterThan(1));
    final rowKey = tiles.first.backdropGroupKey;
    expect(rowKey, isNotNull);
    for (final tile in tiles) {
      expect(tile.backdropGroupKey, same(rowKey));
      final filter = tester.renderObject<RenderBackdropFilter>(
        find.descendant(
          of: find.byWidget(tile),
          matching: find.byType(BackdropFilter),
        ),
      );
      expect(filter.backdropKey, same(rowKey));
    }

    final filters = find
        .byType(BackdropFilter)
        .evaluate()
        .map((element) => element.renderObject! as RenderBackdropFilter);
    final toolbarKeys = filters
        .map((filter) => filter.backdropKey)
        .where((key) => key != null && key != rowKey)
        .toSet();
    expect(toolbarKeys, hasLength(1));
    // 播放全部按钮与滚动列表、悬浮栏互相独立，不能错误地合并叠加模糊。
    expect(filters.where((filter) => filter.backdropKey == null), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('only rows whose playback highlight changes rebuild', (
    tester,
  ) async {
    final playback = _makePlayback();
    await _pumpPlaylist(tester, playback: playback);
    final before = {for (final tile in _tiles(tester)) tile.track.key: tile};

    await playback.setVolume(0.4);
    await tester.pump();
    for (final tile in _tiles(tester)) {
      expect(tile, same(before[tile.track.key]));
    }

    final first = before.values.first.track;
    await playback.playTrack(first);
    await tester.pumpAndSettle();
    final afterFirst = {
      for (final tile in _tiles(tester)) tile.track.key: tile,
    };
    expect(afterFirst[first.key]!.isActive, isTrue);
    for (final tile in afterFirst.values.where(
      (tile) => tile.track.key != first.key,
    )) {
      expect(tile, same(before[tile.track.key]));
    }

    final second = before.values.elementAt(1).track;
    await playback.playTrack(second);
    await tester.pumpAndSettle();
    final afterSecond = {
      for (final tile in _tiles(tester)) tile.track.key: tile,
    };
    expect(afterSecond[first.key]!.isActive, isFalse);
    expect(afterSecond[second.key]!.isActive, isTrue);
    for (final tile in afterSecond.values.where(
      (tile) => tile.track.key != first.key && tile.track.key != second.key,
    )) {
      expect(tile, same(afterFirst[tile.track.key]));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('row listeners rebind and detach with the playback controller', (
    tester,
  ) async {
    final oldPlayback = _makePlayback();
    final newPlayback = _makePlayback();
    final playlist = _makePlaylist();
    await _pumpPlaylist(tester, playback: oldPlayback, playlist: playlist);
    await oldPlayback.playTrack(_tiles(tester).first.track);
    await tester.pumpAndSettle();
    expect(_tiles(tester).first.isActive, isTrue);

    await _pumpPlaylist(tester, playback: newPlayback, playlist: playlist);
    expect(_tiles(tester).every((tile) => !tile.isActive), isTrue);
    final mountedTracks = _tiles(tester).map((tile) => tile.track).toList();
    await newPlayback.playTrack(mountedTracks.first);
    await tester.pumpAndSettle();
    expect(_tiles(tester).first.isActive, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    // 两个控制器在卸载后继续通知：未解绑的监听会因高亮改变而 setState after dispose。
    await newPlayback.playTrack(mountedTracks[1]);
    await oldPlayback.setVolume(0.3);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sorting and search keep display and playback queue in sync', (
    tester,
  ) async {
    final playback = _makePlayback();
    final playlist = _makePlaylist(names: ['Beta', 'Zulu', 'alpha']);
    await _pumpPlaylist(tester, playback: playback, playlist: playlist);
    expect(_tileNames(tester), ['alpha', 'Zulu', 'Beta']);

    await _selectSort(tester, '默认排序', '歌名 A-Z');
    expect(_tileNames(tester), ['alpha', 'Beta', 'Zulu']);
    await _selectSort(tester, '歌名 A-Z', '歌名 Z-A');
    expect(_tileNames(tester), ['Zulu', 'Beta', 'alpha']);

    await tester.tap(find.byKey(const Key('playlist-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '  BETA  ');
    await tester.pumpAndSettle();
    expect(_tileNames(tester), ['Beta']);
    expect(find.text('匹配到 1 首歌曲'), findsOneWidget);

    await tester.tap(find.text('播放全部 (3)'));
    await tester.pumpAndSettle();
    expect(playback.state.queue.map((track) => track.name), ['Beta']);

    await tester.tap(find.byKey(const Key('playlist-search-button')));
    await tester.pumpAndSettle();
    expect(_tileNames(tester), ['Zulu', 'Beta', 'alpha']);
    await tester.tap(find.text('播放全部 (3)'));
    await tester.pumpAndSettle();
    expect(playback.state.queue.map((track) => track.name), [
      'Zulu',
      'Beta',
      'alpha',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal playlist keeps newest-first API order after refresh', (
    tester,
  ) async {
    final playback = _makePlayback();
    await _pumpPlaylist(
      tester,
      playback: playback,
      playlist: _makePlaylist(names: ['Beta', 'Zulu', 'alpha']),
      personal: true,
    );
    expect(_tileNames(tester), ['Beta', 'Zulu', 'alpha']);

    await tester
        .widget<CyrenePullToRefresh>(find.byType(CyrenePullToRefresh))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(_tileNames(tester), ['Beta', 'Zulu', 'alpha']);
    await tester.tap(find.text('播放全部 (3)'));
    await tester.pumpAndSettle();
    expect(playback.state.queue.map((track) => track.name), [
      'Beta',
      'Zulu',
      'alpha',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh invalidates cached sorting when tracks change', (
    tester,
  ) async {
    final playlist = _makePlaylist(names: ['Beta', 'Zulu', 'alpha']);
    await _pumpPlaylist(tester, playback: _makePlayback(), playlist: playlist);
    await _selectSort(tester, '默认排序', '歌名 Z-A');
    expect(_tileNames(tester), ['Zulu', 'Beta', 'alpha']);

    playlist.tracks[1] = ToplistTrack(
      id: 'updated',
      name: 'Delta',
      artists: 'Artist',
      album: 'Album',
      picUrl: '',
      source: MusicSource.netease,
    );
    await tester
        .widget<CyrenePullToRefresh>(find.byType(CyrenePullToRefresh))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(_tileNames(tester), ['Delta', 'Beta', 'alpha']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-to-refresh keeps the cover fixed and returns normally', (
    tester,
  ) async {
    await _pumpPlaylist(tester, playback: _makePlayback());
    final gesture = await tester.startGesture(const Offset(180, 140));
    await gesture.moveBy(const Offset(0, 250));
    await tester.pump(const Duration(milliseconds: 100));

    final flow = tester.widget<Flow>(find.byType(Flow));
    final painting = _RecordingFlowPaintingContext(
      tester.getSize(find.byType(Flow)),
    );
    flow.delegate.paintChildren(painting);
    expect(painting.transform, Matrix4.identity());

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Song 499'), findsOneWidget);
    expect(_scrollController(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  for (final config in [(320.0, 1.0), (430.0, 1.4)]) {
    testWidgets('mobile layout survives scrolling at width ${config.$1}', (
      tester,
    ) async {
      await _pumpPlaylist(
        tester,
        playback: _makePlayback(),
        size: Size(config.$1, 844),
        textScaler: TextScaler.linear(config.$2),
      );
      _scrollController(tester).jumpTo(500);
      await tester.pumpAndSettle();
      expect(_tiles(tester), isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

PlaybackController _makePlayback() {
  final playback = PlaybackController(
    audio: const _SilentAudioGateway(),
    store: _MemorySnapshotStore(),
    sourceResolver: const _PlayableTrackResolver(),
  );
  addTearDown(playback.dispose);
  return playback;
}

PlaylistDetail _makePlaylist({List<String>? names}) {
  final tracks = List.generate(
    names?.length ?? 500,
    (index) => ToplistTrack(
      id: '$index',
      name: names?[index] ?? 'Song $index',
      artists: 'Artist',
      album: 'Album',
      picUrl: '',
      source: MusicSource.netease,
    ),
  );
  return PlaylistDetail(
    id: 1,
    name: 'Large playlist',
    coverImgUrl: '',
    description: '',
    tracks: tracks,
    playCount: 0,
    creator: 'Tester',
    trackCount: tracks.length,
    createTime: 0,
    updateTime: 0,
    tags: const [],
  );
}

Future<void> _pumpPlaylist(
  WidgetTester tester, {
  required PlaybackController playback,
  PlaylistDetail? playlist,
  bool desktopLayout = false,
  bool personal = false,
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final detail = playlist ?? _makePlaylist();
  final page = personal
      ? PlaylistDetailPage.personal(
          playlistId: detail.id,
          title: detail.name,
          coverUrl: '',
          token: 'test-token',
          playback: playback,
          initialPlaylist: detail,
          reloadable: false,
        )
      : PlaylistDetailPage(
          playlistId: detail.id,
          title: detail.name,
          coverUrl: '',
          token: 'test-token',
          playback: playback,
          desktopLayout: desktopLayout,
          initialPlaylist: detail,
          reloadable: false,
        );
  await tester.pumpWidget(
    MiuixSystemTheme(
      child: Builder(
        builder: (context) => MaterialApp(
          theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollController _scrollController(WidgetTester tester) =>
    tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;

List<CyreneTrackTile> _tiles(WidgetTester tester) =>
    tester.widgetList<CyreneTrackTile>(find.byType(CyreneTrackTile)).toList();

List<String> _tileNames(WidgetTester tester) =>
    _tiles(tester).map((tile) => tile.track.name).toList();

Future<void> _selectSort(
  WidgetTester tester,
  String current,
  String next,
) async {
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.text(next));
  await tester.pumpAndSettle();
}

class _RecordingFlowPaintingContext implements FlowPaintingContext {
  _RecordingFlowPaintingContext(this.size);

  @override
  final Size size;
  int paintCount = 0;
  Matrix4? transform;

  @override
  int get childCount => 1;

  @override
  Size? getChildSize(int i) => size;

  @override
  void paintChild(int i, {Matrix4? transform, double opacity = 1.0}) {
    paintCount++;
    this.transform = transform?.clone();
  }
}

class _PlayableTrackResolver implements AudioSourceResolver {
  const _PlayableTrackResolver();

  @override
  Future<ResolvedAudioSources> resolve(
    Track track, {
    Set<String>? exclude,
  }) async => ResolvedAudioSources([
    PlaybackCandidate(
      track: track.copyWith(
        playbackUrl: Uri.parse('https://audio.test/track.mp3'),
      ),
      sourceId: track.source.wireName,
    ),
  ]);
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
