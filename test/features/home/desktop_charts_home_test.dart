import 'package:cyrene_music_reborn/domain/models/discovery.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/models/track.dart';
import 'package:cyrene_music_reborn/features/home/desktop_charts/desktop_charts_home.dart';
import 'package:cyrene_music_reborn/infrastructure/services/discovery_service.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('排行榜默认展示第一张，切换榜单后播放与详情都跟着走', (tester) async {
    final entries = _entries();
    Track? played;
    List<Track>? queue;
    Toplist? opened;
    await _pumpPage(
      tester,
      entries: entries,
      onPlay: (track, tracks) {
        played = track;
        queue = tracks;
      },
      onOpen: (chart) => opened = chart,
    );

    await _tap(tester, _action('播放全球热门 50'));
    expect(played, entries.first.tracks.first);
    expect(queue, entries.first.tracks);

    await _tap(tester, _action('查看华语热门'));
    await tester.pumpAndSettle();
    expect(_action('播放全球热门 50'), findsNothing);
    await _tap(tester, _action('查看华语热门完整榜单'));
    expect(opened, entries[1].toplist);

    // 点 Top 10 里的一首：从这首开播，队列仍是整张榜单。
    final second = entries[1].tracks[1];
    await _tap(tester, _action('播放 ${second.name}，${second.artists}'));
    expect(played, second);
    expect(queue, entries[1].tracks);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Top 10 只露前十，其余曲目入口打开完整榜单', (tester) async {
    final entry = _entry(0, '全球热门 50', count: 14);
    Toplist? opened;
    await _pumpPage(
      tester,
      entries: [entry],
      onOpen: (chart) => opened = chart,
    );
    final explorer = find.byKey(const ValueKey('desktop-chart-explorer'));
    Finder row(Track track) => find.descendant(
      of: explorer,
      matching: _action('播放 ${track.name}，${track.artists}'),
    );
    expect(row(entry.tracks[9]), findsOneWidget);
    expect(row(entry.tracks[10]), findsNothing);
    expect(find.text('还有 4 首'), findsOneWidget);
    await _tap(tester, _action('查看全球热门 50其余曲目'));
    expect(opened, entry.toplist);
  });

  testWidgets('随机播放合并所有榜单且按平台和 ID 去重', (tester) async {
    const shared = Track(
      id: 'shared',
      name: '共同曲目',
      artists: '歌手',
      album: '',
      picUrl: '',
      source: MusicSource.spotify,
    );
    const otherSource = Track(
      id: 'shared',
      name: '另一平台曲目',
      artists: '歌手',
      album: '',
      picUrl: '',
      source: MusicSource.netease,
    );
    final a = _entries()[0];
    final b = _entries()[1];
    final entries = [
      (toplist: a.toplist, tracks: [shared, ...a.tracks, otherSource]),
      (toplist: b.toplist, tracks: [shared, ...b.tracks]),
    ];
    List<Track>? queue;
    Track? played;
    await _pumpPage(
      tester,
      entries: entries,
      onPlay: (track, tracks) {
        played = track;
        queue = tracks;
      },
    );
    await _tap(tester, _action('随机播放全部榜单'));
    final expected = {
      for (final entry in entries)
        for (final track in entry.tracks) track.key,
    };
    expect(queue!.map((track) => track.key).toSet(), expected);
    expect(queue!.length, expected.length);
    expect(played, queue!.first);
  });

  testWidgets('今天就听这些跳过各榜前三名、不重复，换一批可用', (tester) async {
    final entries = [
      for (final (i, name) in ['全球热门 50', '华语热门', '美国热门 50'].indexed)
        _entry(i, name, count: 12),
    ];
    List<Track>? queue;
    await _pumpPage(
      tester,
      entries: entries,
      onPlay: (_, tracks) => queue = tracks,
    );
    final shelf = find.byKey(const ValueKey('desktop-hot-tracks'));
    final card = find
        .descendant(
          of: shelf,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is MiuixPressable &&
                (widget.semanticLabel?.startsWith('播放 ') ?? false),
          ),
        )
        .first;
    await _tap(tester, card);
    final podium = {
      for (final entry in entries)
        for (final track in entry.tracks.take(3)) track.key,
    };
    expect(queue, isNotEmpty);
    expect(queue!.map((t) => t.key).toSet(), hasLength(queue!.length));
    expect(queue!.where((t) => podium.contains(t.key)), isEmpty);

    await _tap(tester, _action('换一批'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('票根：最近收听恢复历史队列，存根进播放记录', (tester) async {
    final history = _entries()[1].tracks;
    List<Track>? queue;
    var historyOpened = 0;
    await _pumpPage(
      tester,
      recent: history,
      onPlay: (_, tracks) => queue = tracks,
      onHistory: () => historyOpened++,
    );
    expect(find.text('最近收听'), findsOneWidget);
    expect(find.text('最近听过 ${history.length} 首'), findsOneWidget);
    expect(_action('打开播放器'), findsNothing);
    await _tap(tester, _action('继续播放'));
    expect(queue, history);
    await _tap(tester, _action('查看播放记录'));
    expect(historyOpened, 1);
  });

  testWidgets('正在播放时可暂停、打开播放器，点当前曲目不重建队列', (tester) async {
    final current = _entries().first.tracks.first;
    var toggled = 0;
    var opened = 0;
    var restarted = 0;
    await _pumpPage(
      tester,
      current: current,
      isPlaying: true,
      onToggle: () => toggled++,
      onPlayer: () => opened++,
      onPlay: (_, _) => restarted++,
    );
    expect(find.text('正在播放'), findsOneWidget);
    await _tap(tester, _action('暂停播放'));
    expect(toggled, 1);
    await _tap(tester, _action('打开播放器'));
    expect(opened, 1);

    final explorer = find.byKey(const ValueKey('desktop-chart-explorer'));
    await _tap(
      tester,
      find.descendant(
        of: explorer,
        matching: _action('暂停 ${current.name}，${current.artists}'),
      ),
    );
    expect(toggled, 2);
    expect(restarted, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('冷启动骨架、空态重试和缓存刷新都能正常展示', (tester) async {
    var retries = 0;
    await _pumpPage(tester, entries: [], loading: true);
    expect(find.text('正在加载榜单…'), findsOneWidget);
    expect(_action('随机播放全部榜单'), findsNothing);

    await _pumpPage(
      tester,
      entries: [],
      error: '测试网络错误',
      onRetry: () => retries++,
    );
    expect(find.text('测试网络错误'), findsOneWidget);
    await _tap(tester, _action('重新加载'));
    expect(retries, 1);

    // 有缓存时刷新中也直接展示内容，不被骨架盖住。
    await _pumpPage(tester, loading: true);
    expect(find.byKey(const ValueKey('desktop-charts-hero')), findsOneWidget);
    expect(find.text('正在加载榜单…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无曲目的榜单仍可查看，但不创建空播放队列', (tester) async {
    final toplist = _entries().first.toplist;
    var played = 0;
    Toplist? opened;
    await _pumpPage(
      tester,
      entries: [(toplist: toplist, tracks: const [])],
      onPlay: (_, _) => played++,
      onOpen: (chart) => opened = chart,
    );
    expect(_pressable(tester, '随机播放全部榜单').onPressed, isNull);
    expect(_pressable(tester, '播放${toplist.name}').onPressed, isNull);
    expect(find.text('暂无可播放曲目'), findsOneWidget);
    await _tap(tester, _action('查看${toplist.name}完整榜单'));
    expect(opened, toplist);
    expect(played, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('个性化分区按类型换版式，卡片点开交给首页分流', (tester) async {
    final sections = _sections();
    final openedItems = <String>[];
    List<Track>? queue;
    await _pumpPage(
      tester,
      sections: sections,
      onOpenItem: (item) => openedItems.add(item.name),
      onPlay: (_, tracks) => queue = tracks,
    );
    for (final section in sections) {
      expect(find.text(section.title), findsOneWidget);
    }
    await _tap(tester, _action('艺人 1'));
    await _tap(tester, _action('专辑 1'));
    await _tap(tester, _action('歌单 A 1'));
    expect(openedItems, ['艺人 1', '专辑 1', '歌单 A 1']);

    final songs = sections.first.tracks;
    await _tap(tester, _action('播放全部：${sections.first.title}'));
    expect(queue, songs);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一排放不下的分区可以翻页', (tester) async {
    final artists = _sections()[1];
    await _pumpPage(tester, sections: [artists]);
    expect(_action('艺人 1'), findsOneWidget);
    expect(_action('艺人 20'), findsNothing);
    expect(_pressable(tester, '上一页：${artists.title}').onPressed, isNull);

    for (var i = 0; i < 5; i++) {
      final next = _pressable(tester, '下一页：${artists.title}');
      if (next.onPressed == null) break;
      await _tap(tester, _action('下一页：${artists.title}'));
      await tester.pumpAndSettle();
    }
    expect(_action('艺人 20'), findsOneWidget);
    expect(_action('艺人 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首屏播放操作可用 Tab 和 Enter 触发', (tester) async {
    var played = 0;
    await _pumpPage(tester, onPlay: (_, _) => played++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(played, 1);
    expect(tester.takeException(), isNull);
  });

  for (final width in [2048.0, 1440.0, 1100.0, 840.0, 600.0, 480.0, 320.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('布局 ${width.toInt()}px / ${brightness.name} 无溢出', (
        tester,
      ) async {
        await _pumpPage(
          tester,
          width: width,
          brightness: brightness,
          sections: _sections(),
          recent: _entries()[2].tracks,
        );
        expect(tester.takeException(), isNull);
        // 不引入 Windows 上有崩溃历史的惰性横向列表。
        expect(find.byType(ListView), findsNothing);
        expect(find.byType(PageView), findsNothing);

        final hero = tester.getRect(
          find.byKey(const ValueKey('desktop-charts-hero')),
        );
        final ticket = tester.getRect(
          find.byKey(const ValueKey('desktop-listening-panel')),
        );
        final content = width - 48;
        if (content >= 1000) {
          expect(hero.top, ticket.top);
          expect(hero.height, ticket.height);
          expect(hero.right, lessThan(ticket.left));
        } else {
          expect(hero.bottom, lessThan(ticket.top));
        }
        // 宽屏左栏榜单与详情并排；窄屏榜单收成标签落在详情上方。
        final rail = tester.getRect(
          find.byKey(const ValueKey('desktop-chart-1')),
        );
        final detail = tester.getRect(
          find.byKey(const ValueKey('desktop-chart-detail-1')),
        );
        if (content >= 880) {
          expect(rail.right, lessThan(detail.left));
        } else {
          expect(rail.bottom, lessThan(detail.top));
        }
        // 排行榜在抽歌封面架之前。
        expect(
          detail.top,
          lessThan(
            tester
                .getRect(find.byKey(const ValueKey('desktop-hot-tracks')))
                .top,
          ),
        );
      });
    }
  }

  for (final width in [480.0, 600.0, 1100.0]) {
    testWidgets('大字体 ${width.toInt()}px 保持内容与操作完整', (tester) async {
      await _pumpPage(
        tester,
        width: width,
        textScale: 2,
        sections: _sections(),
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, _action('查看华语热门'));
      await tester.pumpAndSettle();
      expect(_action('播放华语热门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('超长榜名与空榜单在窄屏大字号下不溢出，播放禁用但详情可用', (tester) async {
    final longName = '超长榜单名称' * 12;
    final toplist = Toplist(
      id: 9,
      name: longName,
      coverImgUrl: '',
      description: 'Spotify $longName',
      tracks: const [],
      source: MusicSource.spotify,
    );
    Toplist? opened;
    var played = 0;
    await _pumpPage(
      tester,
      width: 480,
      textScale: 2,
      entries: [(toplist: toplist, tracks: const [])],
      onPlay: (_, _) => played++,
      onOpen: (chart) => opened = chart,
    );
    expect(tester.takeException(), isNull);
    expect(_pressable(tester, '播放$longName').onPressed, isNull);
    await _tap(tester, _action('查看$longName完整榜单'));
    expect(opened, toplist);
    expect(played, 0);
  });
}

Finder _action(String label) => find.byWidgetPredicate(
  (widget) => widget is MiuixPressable && widget.semanticLabel == label,
);

MiuixPressable _pressable(WidgetTester tester, String label) =>
    tester.widget<MiuixPressable>(_action(label));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<DesktopChartEntry>? entries,
  List<DesktopSpotifySection> sections = const [],
  void Function(Track, List<Track>)? onPlay,
  ValueChanged<Toplist>? onOpen,
  ValueChanged<SpotifyPlaylistPreview>? onOpenItem,
  VoidCallback? onToggle,
  VoidCallback? onPlayer,
  VoidCallback? onHistory,
  VoidCallback? onRetry,
  Track? current,
  bool isPlaying = false,
  List<Track> recent = const [],
  bool loading = false,
  String? error,
  double width = 1440,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    MiuixSystemTheme(
      child: Builder(
        builder: (context) => MaterialApp(
          theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: DesktopChartsHome(
                entries: entries ?? _entries(),
                sections: sections,
                currentTrack: current,
                isPlaying: isPlaying,
                recentTracks: recent,
                loading: loading,
                errorMessage: error,
                onPlay: onPlay ?? (_, _) {},
                onOpenChart: onOpen ?? (_) {},
                onOpenItem: onOpenItem ?? (_) {},
                onTogglePlayback: onToggle ?? () {},
                onOpenPlayer: onPlayer ?? () {},
                onOpenHistory: onHistory ?? () {},
                onRetry: onRetry ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DesktopChartEntry _entry(int index, String name, {int count = 5}) => (
  toplist: Toplist(
    id: index + 1,
    name: name,
    coverImgUrl: '',
    description: 'Spotify $name',
    tracks: const [],
    source: MusicSource.spotify,
  ),
  tracks: [
    for (var i = 0; i < count; i++)
      Track(
        id: '$index-$i',
        name: i == 0 ? '一首有很长很长名字的歌 · $name' : '歌曲 ${index + 1} - ${i + 1}',
        artists: '歌手 ${index + 1} / Artist',
        album: '专辑',
        picUrl: '',
        source: MusicSource.spotify,
        duration: Duration(seconds: 150 + i * 7),
      ),
  ],
);

List<DesktopChartEntry> _entries() => [
  for (final (index, name) in [
    '全球热门 50',
    '华语热门',
    '美国热门 50',
    '流行崛起',
    '说唱焦点',
  ].indexed)
    _entry(index, name),
];

SpotifyPlaylistPreview _preview(String name, SpotifyPersonalizedKind kind) => (
  id: name,
  name: name,
  description: '$name 的介绍',
  coverImgUrl: '',
  trackCount: 30,
  itemKind: kind,
);

DesktopSpotifySection _section(
  String id,
  SpotifyPersonalizedKind kind, {
  List<SpotifyPlaylistPreview> items = const [],
  List<Track> tracks = const [],
}) => (
  id: id,
  title: '分区 $id',
  description: '分区 $id 的说明',
  kind: kind,
  items: items,
  tracks: tracks,
);

List<DesktopSpotifySection> _sections() => [
  _section(
    'songs',
    SpotifyPersonalizedKind.track,
    tracks: _entry(7, '收藏', count: 14).tracks,
  ),
  _section(
    'artists',
    SpotifyPersonalizedKind.artist,
    items: [
      for (var i = 1; i <= 20; i++)
        _preview('艺人 $i', SpotifyPersonalizedKind.artist),
    ],
  ),
  _section(
    'albums',
    SpotifyPersonalizedKind.album,
    items: [
      for (var i = 1; i <= 8; i++)
        _preview('专辑 $i', SpotifyPersonalizedKind.album),
    ],
  ),
  // 四个歌单类分区依次走拼版 / 方卡 / 宽幅 / 列表。
  for (final letter in ['A', 'B', 'C', 'D'])
    _section(
      'mix$letter',
      SpotifyPersonalizedKind.mixed,
      items: [
        for (var i = 1; i <= 10; i++)
          _preview(
            '歌单 $letter $i',
            i.isEven
                ? SpotifyPersonalizedKind.album
                : SpotifyPersonalizedKind.playlist,
          ),
      ],
    ),
];
