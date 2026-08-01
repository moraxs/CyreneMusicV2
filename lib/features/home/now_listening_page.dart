import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/home/home_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/track.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../settings/login_page.dart';
import 'daily_recommend_page.dart';
import 'home_song_row.dart';

/// 首页（对应原版 HomePage 的移动端布局）：
/// 问候头 → 「为你推荐 / 榜单」切换 → 每日推荐 hero 卡 → 私人FM →
/// 每日推荐歌单 / 专属歌单 / 雷达歌单（双列网格）→ 个性化新歌（分组列表）。
/// 未登录时展示登录引导 + 榜单。
class NowListeningPage extends StatefulWidget {
  const NowListeningPage({
    super.key,
    required this.account,
    required this.home,
    required this.playback,
    required this.onOpenPlayer,
    required this.onOpenPlaylist,
  });

  final AccountSessionController account;
  final HomeController home;
  final PlaybackController playback;
  final VoidCallback onOpenPlayer;
  final void Function(int id, String title, String coverUrl) onOpenPlaylist;

  @override
  State<NowListeningPage> createState() => _NowListeningPageState();
}

class _NowListeningPageState extends State<NowListeningPage>
    with AutomaticKeepAliveClientMixin {
  var _tab = _HomeTab.leaderboard;
  String? _loadedToken;

  // 派生数据缓存：仅当控制器发布新数据对象时才重新转换原始 JSON，
  // 避免每次重建都全量解析。
  RecommendData? _recommendCacheSource;
  List<Track> _daily = const [];
  List<Track> _fm = const [];
  List<Track> _newest = const [];
  List<_HomePlaylistCardData> _dailyPlaylists = const [];
  List<_HomePlaylistCardData> _personalizedPlaylists = const [];
  List<_HomePlaylistCardData> _radarPlaylists = const [];
  List<Toplist>? _toplistCacheSource;
  final _toplistTracks = <Toplist, List<Track>>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_onAccountChanged);
    _load();
  }

  @override
  void dispose() {
    widget.account.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    final token = widget.account.token;
    if (token == _loadedToken) return;
    _load();
  }

  void _load() {
    _loadedToken = widget.account.token;
    widget.home.load(token: _loadedToken).then((_) {
      if (!mounted) return;
      setState(() {
        _tab = widget.home.state.isBound
            ? _HomeTab.recommend
            : _HomeTab.leaderboard;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 播放状态只影响私人FM卡与歌曲行，由它们各自监听 playback，
    // 避免播放进度 tick 触发整页重建。
    return ListenableBuilder(
      listenable: Listenable.merge([widget.home, widget.account]),
      builder: (context, _) {
        final theme = MiuixTheme.of(context);
        final state = widget.home.state;
        if (state.isLoading && !state.hasContent) {
          return const Center(child: MiuixCircularProgressIndicator());
        }
        if (state.errorMessage != null && !state.hasContent) {
          return CyreneEmptyState(
            icon: Icons.cloud_off,
            title: '内容加载失败',
            description: state.errorMessage!,
            action: MiuixButton(
              onPressed: widget.home.refresh,
              child: MiuixText('重试', style: theme.textStyles.button),
            ),
          );
        }

        final showTabs = state.isBound;
        final tab = showTabs ? _tab : _HomeTab.leaderboard;
        final (greeting, greetingSubtitle) = _greetingOfNow();

        return MiuixPullToRefresh(
          isRefreshing: state.isRefreshing,
          onRefresh: widget.home.refresh,
          refreshTexts: const ['下拉刷新', '释放立即刷新', '正在刷新...', '刷新成功'],
          // MiuixPullToRefresh 依赖顶部 OverscrollNotification：必须钳制物理
          // （iOS 默认 bouncing 不会发出该通知），并关掉安卓拉伸指示器以免
          // 与下拉头叠加动画。
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(overscroll: false),
            child: CustomScrollView(
              key: const PageStorageKey('home-scroll'),
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _HomeHeader(
                    title: greeting,
                    subtitle: greetingSubtitle,
                    refreshing: state.isRefreshing,
                    onRefresh: widget.home.refresh,
                  ),
                ),
                if (showTabs)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                    sliver: SliverToBoxAdapter(
                      child: MiuixTabRowWithContour(
                        tabs: const ['为你推荐', '榜单'],
                        selectedTabIndex: tab == _HomeTab.recommend ? 0 : 1,
                        contentAlignment: AlignmentDirectional.centerStart,
                        onTabSelected: (index) => setState(() {
                          _tab = index == 0
                              ? _HomeTab.recommend
                              : _HomeTab.leaderboard;
                        }),
                      ),
                    ),
                  ),
                if (tab == _HomeTab.recommend)
                  ..._recommendSlivers(state)
                else
                  ..._leaderboardSlivers(state),
                const SliverToBoxAdapter(child: SizedBox(height: 180)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== 为你推荐 =====

  List<Widget> _recommendSlivers(HomeState state) {
    final data = state.recommendations;
    if (data == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CyreneEmptyState(
            icon: Icons.music_note,
            title: '暂无推荐内容',
            description: '下拉刷新试试。',
          ),
        ),
      ];
    }

    _syncRecommendCache(data);
    final daily = _daily;
    final fm = _fm;
    final newest = _newest;
    final dailyPlaylists = _dailyPlaylists;
    final personalized = _personalizedPlaylists;
    final radar = _radarPlaylists;

    if (daily.isEmpty &&
        fm.isEmpty &&
        newest.isEmpty &&
        dailyPlaylists.isEmpty &&
        personalized.isEmpty &&
        radar.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CyreneEmptyState(
            icon: Icons.music_note,
            title: '暂无推荐内容',
            description: '下拉刷新试试。',
          ),
        ),
      ];
    }

    return [
      if (daily.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
          sliver: SliverToBoxAdapter(
            child: _DailyRecommendCard(
              tracks: daily,
              onTap: () => _openDailyDetail(daily),
            ),
          ),
        ),
      if (fm.isNotEmpty) ...[
        _sectionTitle('私人FM'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: widget.playback,
              builder: (context, _) => _PersonalFmCard(
                track: _fmDisplayTrack(fm)!,
                isPlaying: _isFmCurrent(fm) && widget.playback.state.isPlaying,
                onToggle: () => _toggleFm(fm),
                onSkip: () => _skipFm(fm),
                onOpen: () => _openFmInPlayer(fm),
              ),
            ),
          ),
        ),
      ],
      if (dailyPlaylists.isNotEmpty) ...[
        _sectionTitle('每日推荐歌单'),
        _playlistGrid(dailyPlaylists),
      ],
      if (personalized.isNotEmpty) ...[
        _sectionTitle('专属歌单'),
        _playlistGrid(personalized),
      ],
      if (radar.isNotEmpty) ...[_sectionTitle('雷达歌单'), _playlistGrid(radar)],
      if (newest.isNotEmpty) ...[
        _sectionTitle('个性化新歌'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverToBoxAdapter(
            child: CyreneMenuGroup(
              children: [
                for (final track in newest)
                  HomeSongRow(
                    track: track,
                    playback: widget.playback,
                    onPlay: () =>
                        widget.playback.playTrack(track, queue: newest),
                    onAddToQueue: () => widget.playback.addToQueue(track),
                  ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  // ===== 榜单 =====

  List<Widget> _leaderboardSlivers(HomeState state) {
    final toplists = state.toplists;
    final loggedIn = widget.account.state.isLoggedIn;
    return [
      if (!loggedIn)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
          sliver: SliverToBoxAdapter(
            child: _LoginPromptCard(onLogin: _openLogin),
          ),
        ),
      if (toplists.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: CyreneEmptyState(
            icon: Icons.emoji_events,
            title: '暂无榜单内容',
            description: '稍后下拉刷新再试。',
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
          sliver: SliverToBoxAdapter(
            child: _ShuffleHeroCard(
              coverUrl: toplists.first.coverImgUrl,
              onShuffle: _playShuffledToplists,
            ),
          ),
        ),
        for (final toplist in toplists) ..._toplistSection(toplist),
      ],
    ];
  }

  List<Widget> _toplistSection(Toplist toplist) {
    final tracks = _tracksFor(toplist);
    if (tracks.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _ToplistHeader(
          name: toplist.name,
          onOpen: () => widget.onOpenPlaylist(
            toplist.id,
            toplist.name,
            toplist.coverImgUrl,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverToBoxAdapter(
          child: CyreneMenuGroup(
            children: [
              for (var i = 0; i < min(5, tracks.length); i++)
                HomeSongRow(
                  track: tracks[i],
                  rank: i + 1,
                  playback: widget.playback,
                  onPlay: () =>
                      widget.playback.playTrack(tracks[i], queue: tracks),
                  onAddToQueue: () => widget.playback.addToQueue(tracks[i]),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  void _playShuffledToplists() {
    final all = widget.home.state.toplists.expand(_tracksFor).toList();
    if (all.isEmpty) return;
    all.shuffle(Random());
    widget.playback.playTrack(all.first, queue: all);
    CyreneToast.show('已开启随心畅听');
  }

  // ===== 派生数据缓存 =====

  void _syncRecommendCache(RecommendData data) {
    if (identical(data, _recommendCacheSource)) return;
    _recommendCacheSource = data;
    _daily = widget.home.convertTracks(data.dailySongs);
    _fm = widget.home.convertTracks(data.fm);
    _newest = widget.home.convertTracks(data.personalizedNewsongs);
    _dailyPlaylists = _playlistCards(data.dailyPlaylists);
    _personalizedPlaylists = _playlistCards(data.personalizedPlaylists);
    _radarPlaylists = _playlistCards(data.radarPlaylists);
    if (kDebugMode) {
      debugPrint(
        '[ForYou] 封面抽样 daily=${_daily.firstOrNull?.picUrl} '
        'fm=${_fm.firstOrNull?.picUrl} newest=${_newest.firstOrNull?.picUrl} '
        'dailyPl=${_dailyPlaylists.firstOrNull?.coverUrl} '
        'radar=${_radarPlaylists.firstOrNull?.coverUrl}',
      );
    }
  }

  List<Track> _tracksFor(Toplist toplist) {
    final toplists = widget.home.state.toplists;
    if (!identical(_toplistCacheSource, toplists)) {
      _toplistCacheSource = toplists;
      _toplistTracks.clear();
    }
    return _toplistTracks.putIfAbsent(
      toplist,
      () => widget.home.tracksForToplist(toplist),
    );
  }

  // ===== 私人FM =====

  bool _isFmCurrent(List<Track> fm) {
    final current = widget.playback.state.currentTrack;
    if (current == null) return false;
    return fm.any((track) => track.key == current.key);
  }

  /// 正在播放 FM 中的歌曲时卡片实时跟随当前曲目（对应原版 AnimatedBuilder 行为）。
  Track? _fmDisplayTrack(List<Track> fm) {
    final current = widget.playback.state.currentTrack;
    if (current != null && fm.any((track) => track.key == current.key)) {
      return current;
    }
    return fm.firstOrNull;
  }

  void _toggleFm(List<Track> fm) {
    if (_isFmCurrent(fm)) {
      widget.playback.togglePlay();
      return;
    }
    widget.playback.playTrack(fm.first, queue: fm);
    CyreneToast.show('开始播放私人FM');
  }

  void _skipFm(List<Track> fm) {
    if (_isFmCurrent(fm)) {
      widget.playback.playNext();
      return;
    }
    widget.playback.playTrack(fm.length > 1 ? fm[1] : fm.first, queue: fm);
  }

  /// 点击 FM 卡片主体：未在播 FM 时先开播，再进全屏播放器（对应原版整卡可点）。
  void _openFmInPlayer(List<Track> fm) {
    if (!_isFmCurrent(fm)) {
      widget.playback.playTrack(fm.first, queue: fm);
      CyreneToast.show('开始播放私人FM');
    }
    widget.onOpenPlayer();
  }

  void _openDailyDetail(List<Track> daily) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) =>
            DailyRecommendPage(tracks: daily, playback: widget.playback),
      ),
    );
  }

  // ===== 登录 =====

  Future<void> _openLogin() async {
    widget.account.clearError();
    final loggedIn = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => LoginPage(account: widget.account)),
    );
    if (loggedIn == true && mounted) {
      CyreneToast.show('登录成功，正在为你准备推荐内容');
    }
  }

  // ===== 通用 =====

  Widget _sectionTitle(String text) => SliverToBoxAdapter(
    child: MiuixSmallTitle(
      text,
      insideMargin: const EdgeInsets.fromLTRB(28, 20, 28, 8),
    ),
  );

  Widget _playlistGrid(List<_HomePlaylistCardData> playlists) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.76,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final playlist = playlists[index];
        return _PlaylistCard(
          data: playlist,
          onTap: () => widget.onOpenPlaylist(
            playlist.id,
            playlist.name,
            playlist.coverUrl,
          ),
        );
      }, childCount: playlists.length),
    ),
  );

  List<_HomePlaylistCardData> _playlistCards(Iterable<dynamic> items) => items
      .whereType<Map>()
      .map((raw) => Map<String, Object?>.from(raw))
      .map(
        (item) => _HomePlaylistCardData(
          id:
              (item['id'] as num?)?.toInt() ??
              int.tryParse(item['id']?.toString() ?? '') ??
              0,
          name: item['name']?.toString() ?? '',
          coverUrl: (item['picUrl'] ?? item['coverImgUrl'])?.toString() ?? '',
        ),
      )
      .where((item) => item.id != 0 && item.name.isNotEmpty)
      .toList(growable: false);
}

(String, String) _greetingOfNow() {
  final hour = DateTime.now().hour;
  final title = switch (hour) {
    < 6 => '夜深了',
    < 9 => '早上好',
    < 12 => '上午好',
    < 14 => '中午好',
    < 18 => '下午好',
    _ => '晚上好',
  };
  final subtitle = switch (hour) {
    < 6 => '注意休息，音乐轻声一点',
    < 9 => '新的一天，从此开始好心情',
    < 12 => '愿音乐伴你高效工作',
    < 14 => '午后小憩，来点轻松的旋律',
    < 18 => '忙碌之余，听听喜欢的歌',
    _ => '夜色温柔，音乐更动听',
  };
  return (title, subtitle);
}

enum _HomeTab { recommend, leaderboard }

/// 问候头：大字问候语 + 副标题 + 右侧刷新按钮（对应原版 GreetingHeader + 顶栏动作）。
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.title,
    required this.subtitle,
    required this.refreshing,
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textStyles.title2.copyWith(
                    color: theme.colors.onBackground,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MiuixIconButton(
            enabled: !refreshing,
            onPressed: onRefresh,
            child: refreshing
                ? const MiuixInfiniteProgressIndicator(size: 18)
                : MiuixIcon(
                    vector: MiuixIcons.extended.byName('refresh')!,
                    size: 20,
                    tint: theme.colors.onBackground,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 每日推荐 hero 卡：左侧文案，右侧三张倾斜堆叠封面（对应原版 MobileDailyRecommendCard）。
class _DailyRecommendCard extends StatelessWidget {
  const _DailyRecommendCard({required this.tracks, required this.onTap});

  final List<Track> tracks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final covers = tracks
        .map((track) => track.picUrl)
        .where((url) => url.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return MiuixPressable(
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      shape: const MiuixSquircleBorder(cornerRadius: 20),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          shape: const MiuixSquircleBorder(cornerRadius: 20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.surfaceContainerHigh, colors.surfaceContainer],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 22, 16, 22),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '每日推荐',
                    style: theme.textStyles.title2.copyWith(
                      color: colors.onSurfaceContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: colors.primary),
                      const SizedBox(width: 5),
                      Text(
                        '为您精选 ${tracks.length} 首',
                        style: theme.textStyles.footnote1.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '每日凌晨更新，遇见你的心头好',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote1.copyWith(
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              height: 120,
              child: _TiltedCoverStack(covers: covers),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三张封面的倾斜堆叠（沿用原版层级参数：缩放/旋转/位移/透明度）。
class _TiltedCoverStack extends StatelessWidget {
  const _TiltedCoverStack({required this.covers});

  final List<String> covers;

  static const _base = 80.0;

  // 自后向前：(缩放, 旋转弧度, 位移, 不透明度)
  static const _layers = <(double, double, Offset, double)>[
    (0.85, -0.2, Offset(-20, -10), 0.5),
    (0.92, 0.15, Offset(15, 0), 0.8),
    (1.0, 0.0, Offset.zero, 1.0),
  ];

  @override
  Widget build(BuildContext context) {
    if (covers.isEmpty) {
      return const Center(
        child: _HomeCover(url: '', size: _base),
      );
    }
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < _layers.length; i++)
          _buildLayer(_layers[i], layerFromFront: _layers.length - 1 - i),
      ],
    );
  }

  Widget _buildLayer(
    (double, double, Offset, double) layer, {
    required int layerFromFront,
  }) {
    final (scale, angle, offset, opacity) = layer;
    final url = covers[min(layerFromFront, covers.length - 1)];
    final isFront = layerFromFront == 0;
    Widget cover = _HomeCover(url: url, size: _base * scale, cornerRadius: 12);
    if (isFront) {
      cover = Container(
        decoration: const ShapeDecoration(
          shape: MiuixSquircleBorder(cornerRadius: 12),
          shadows: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 15,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: cover,
      );
    }
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Opacity(opacity: opacity, child: cover),
      ),
    );
  }
}

/// 私人FM 卡：大封面 + 曲名/歌手 + 切歌与播放按钮（对应原版 MobilePersonalFm）。
class _PersonalFmCard extends StatelessWidget {
  const _PersonalFmCard({
    required this.track,
    required this.isPlaying,
    required this.onToggle,
    required this.onSkip,
    required this.onOpen,
  });

  final Track track;
  final bool isPlaying;
  final VoidCallback onToggle;
  final VoidCallback onSkip;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.all(16),
      onPressed: onOpen,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Row(
        children: [
          _HomeCover(url: track.picUrl, size: 120, cornerRadius: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.headline1.copyWith(
                    color: colors.onSurfaceContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MiuixIconButton(
                      onPressed: onSkip,
                      backgroundColor: colors.secondaryContainer,
                      cornerRadius: 14,
                      child: MiuixIcon(
                        icon: Icons.skip_next_rounded,
                        size: 22,
                        tint: colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    MiuixIconButton(
                      onPressed: onToggle,
                      backgroundColor: colors.primary,
                      cornerRadius: 16,
                      minWidth: 48,
                      minHeight: 48,
                      child: MiuixIcon(
                        icon: isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                        tint: colors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌单网格卡：封面 + 两行歌单名（对应原版 MobileHoverPlaylistCard 的触屏形态）。
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.data, required this.onTap});

  final _HomePlaylistCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      cornerRadius: 20,
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: _HomeCover(url: data.coverUrl),
            ),
          ),
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  data.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceContainer,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 榜单区块标题：小标题 + 「查看全部」。
class _ToplistHeader extends StatelessWidget {
  const _ToplistHeader({required this.name, required this.onOpen});

  final String name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: MiuixSmallTitle(
            name,
            insideMargin: const EdgeInsets.fromLTRB(28, 20, 8, 8),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 20, bottom: 4),
          child: MiuixPressable(
            onPressed: onOpen,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '查看全部',
                    style: theme.textStyles.footnote1.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('chevronForward')!,
                    size: 13,
                    tint: theme.colors.onSurfaceVariantActions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 榜单页顶部的随机播放卡。
class _ShuffleHeroCard extends StatelessWidget {
  const _ShuffleHeroCard({required this.coverUrl, required this.onShuffle});

  final String coverUrl;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.all(16),
      child: Row(
        children: [
          _HomeCover(url: coverUrl, size: 64, cornerRadius: 14),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '随心畅听',
                  style: theme.textStyles.headline1.copyWith(
                    color: colors.onSurfaceContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '从全部榜单中随机播放热门歌曲',
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MiuixIconButton(
            onPressed: onShuffle,
            backgroundColor: colors.primary,
            cornerRadius: 16,
            minWidth: 48,
            minHeight: 48,
            child: MiuixIcon(
              icon: Icons.shuffle_rounded,
              size: 22,
              tint: colors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 未登录引导卡（对应原版 ForYouLoginPrompt）。
class _LoginPromptCard extends StatelessWidget {
  const _LoginPromptCard({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              shape: const CircleBorder(),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary.withValues(alpha: 0.18),
                  colors.primary.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 42,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '登录后查看更多内容',
            style: theme.textStyles.title3.copyWith(
              color: colors.onSurfaceContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '登录即可获取每日推荐、私人FM、专属歌单等个性化内容',
            textAlign: TextAlign.center,
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _FeatureChip(label: '每日推荐', icon: Icons.calendar_month_rounded),
              _FeatureChip(label: '私人FM', icon: Icons.radio_rounded),
              _FeatureChip(label: '专属歌单', icon: Icons.library_music_rounded),
              _FeatureChip(label: '新歌推荐', icon: Icons.new_releases_rounded),
            ],
          ),
          const SizedBox(height: 22),
          MiuixButton(
            onPressed: onLogin,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            insideMargin: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiuixIcon(icon: Icons.login_rounded, size: 18),
                const SizedBox(width: 8),
                MiuixText('立即登录', style: theme.textStyles.button),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        color: colors.secondaryContainer,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textStyles.footnote1.copyWith(
              color: colors.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// squircle 圆角网络封面；[size] 为空时填满父约束。
class _HomeCover extends StatelessWidget {
  const _HomeCover({required this.url, this.size, this.cornerRadius = 16});

  final String url;
  final double? size;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final fallback = Center(
      child: Icon(
        Icons.music_note_rounded,
        color: colors.onSurfaceVariantSummary,
      ),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget buildImage(double decodeWidth) => CachedNetworkImage(
      imageUrl: url,
      httpHeaders: imageHeaders(url),
      fit: BoxFit.cover,
      // 按显示宽降采样解码,避免网格里全尺寸封面拖累滚动(见 coverDecodeWidth)。
      memCacheWidth: coverDecodeWidth(decodeWidth, dpr),
      errorWidget: (_, _, error) {
        debugPrint('[HomeCover] 加载失败 $url -> $error');
        return fallback;
      },
    );
    // size 为空时填满父约束(网格卡),用 LayoutBuilder 拿到实际宽度做降采样。
    final Widget image = url.isEmpty
        ? fallback
        : (size != null
              ? buildImage(size!)
              : LayoutBuilder(
                  builder: (context, constraints) => buildImage(
                    constraints.maxWidth.isFinite && constraints.maxWidth > 0
                        ? constraints.maxWidth
                        : 220,
                  ),
                ));
    Widget cover = Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: colors.secondaryContainer,
        shape: MiuixSquircleBorder(cornerRadius: cornerRadius),
      ),
      child: image,
    );
    if (size != null) {
      cover = SizedBox.square(dimension: size, child: cover);
    }
    return cover;
  }
}

class _HomePlaylistCardData {
  const _HomePlaylistCardData({
    required this.id,
    required this.name,
    required this.coverUrl,
  });

  final int id;
  final String name;
  final String coverUrl;
}
