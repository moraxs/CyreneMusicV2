import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/home/home_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/artist.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/discovery_service.dart';
import '../../infrastructure/storage/spotify_charts_cache.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_page_routes.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../artist/artist_detail_page.dart';
import '../playlist/playlist_detail_loaders.dart';
import '../playlist/playlist_detail_page.dart';
import '../settings/login_page.dart';
import 'daily_recommend_page.dart';
import 'for_you/for_you_palette.dart';
import 'for_you/for_you_widgets.dart';
import 'for_you/spotify_home_widgets.dart';
import 'home_song_row.dart';

/// 移动端首页：为你推荐与榜单两个页签共用暖色纸张手帐风格（ForYouPalette），
/// 数据和导航仍复用首页控制器。
/// 推荐页：问候 → 每日唱片拼贴 → 私人电台 → 唱片架 / 专属精选 / 雷达 → 新歌来信；
/// 榜单页：榜单源切换 → 随心畅听 → 榜单抽歌卡组 → 个性化分区（按类型换版式），
/// 中间穿插横滑排行榜与歌单摘歌。未登录时展示登录引导 + 榜单。
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
  final void Function(
    int id,
    String title,
    String coverUrl, {
    String? heroTag,
    Alignment? originAlignment,
  })
  onOpenPlaylist;

  @override
  State<NowListeningPage> createState() => _NowListeningPageState();
}

class _NowListeningPageState extends State<NowListeningPage>
    with AutomaticKeepAliveClientMixin {
  var _tab = _HomeTab.leaderboard;
  var _leaderboardSource = _LeaderboardSource.spotify; // 默认 Spotify，网易云可选
  List<Toplist> _spotifyToplists = const [];
  bool _spotifyToplistsLoading = false;
  String? _spotifyToplistsError;
  int _spotifyLoadGeneration = 0;
  List<SpotifyPersonalizedSection> _spotifySections = const [];
  int _spotifySectionsGeneration = 0;

  /// 「今天就听这些」从各榜单轮流抽歌；「换一批」只是换个随机种子。
  int _pickSeed = 0;
  List<Toplist>? _picksSource;
  int _picksSeed = -1;
  List<Track> _picks = const [];

  /// 从某张个性化歌单里摘出来的几首歌（首页分区只有歌单封面，没有曲目）。
  ({SpotifyPlaylistPreview preview, List<Track> tracks})? _playlistPick;
  String? _loadedToken;

  // 派生数据缓存：仅当控制器发布新数据对象时才重新转换原始 JSON，
  // 避免每次重建都全量解析。
  RecommendData? _recommendCacheSource;
  List<Track> _daily = const [];
  List<Track> _fm = const [];
  List<Track> _newest = const [];
  List<ForYouPlaylistData> _dailyPlaylists = const [];
  List<ForYouPlaylistData> _personalizedPlaylists = const [];
  List<ForYouPlaylistData> _radarPlaylists = const [];
  List<Toplist>? _toplistCacheSource;
  final _toplistTracks = <Toplist, List<Track>>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_onAccountChanged);
    _load();
    // 榜单默认源是 Spotify（网易云可选），首屏即需加载，不等用户切换。
    _loadSpotifyToplists();
    _loadSpotifyPersonalized();
  }

  @override
  void dispose() {
    _spotifyLoadGeneration++;
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

  Future<void> _selectLeaderboardSource(_LeaderboardSource source) async {
    if (_leaderboardSource == source) return;
    setState(() => _leaderboardSource = source);
    if (source == _LeaderboardSource.spotify && _spotifyToplists.isEmpty) {
      await _loadSpotifyToplists();
    }
  }

  /// Spotify 榜单两阶段加载：先读本地快照秒开（loading=false 静默刷新），
  /// 后台请求后端刷新并回写；失败有缓存则保留不闪错误，无缓存则设错误+重试。
  /// 与桌面首页 _loadSpotifyToplists 同款，复用 SpotifyChartsCache + getSpotifyToplists。
  Future<void> _loadSpotifyToplists() async {
    if (_spotifyToplistsLoading) return;
    final generation = ++_spotifyLoadGeneration;

    final cached = await SpotifyChartsCache.instance.read();
    if (!mounted || generation != _spotifyLoadGeneration) return;

    final hasCache = cached != null && cached.isNotEmpty;
    setState(() {
      if (hasCache) {
        _spotifyToplists = cached;
        _spotifyToplistsError = null;
        _spotifyToplistsLoading = false;
      } else {
        _spotifyToplistsLoading = true;
        _spotifyToplistsError = null;
      }
    });

    final toplists = await DiscoveryService.instance.getSpotifyToplists();
    if (!mounted || generation != _spotifyLoadGeneration) return;

    setState(() {
      if (toplists.isNotEmpty) {
        _spotifyToplists = toplists;
        _spotifyToplistsError = null;
        SpotifyChartsCache.instance.write(toplists);
      } else if (!hasCache) {
        _spotifyToplistsError = 'Spotify 榜单暂时不可用，请确认后端与 spotify-streamer 已启动';
      }
      _spotifyToplistsLoading = false;
    });
  }

  /// 拉取号池 Spotify 账号的官方同款首页分区。
  ///
  /// 纯增量内容：拿不到就整段不渲染，不影响下方榜单，也不弹错误。
  Future<void> _loadSpotifyPersonalized() async {
    final generation = ++_spotifySectionsGeneration;
    final sections = await DiscoveryService.instance.getSpotifyHome(limit: 20);
    if (!mounted ||
        generation != _spotifySectionsGeneration ||
        sections.isEmpty) {
      return;
    }
    setState(() => _spotifySections = sections);
    _loadPlaylistPick(sections, generation);
  }

  /// 挑一张个性化歌单（Daily Mix 之类）拉曲目，随机摘几首做成歌曲卡组。
  ///
  /// 只试前几张：拉不到或曲目太少就换下一张，都不行就不出这一段。
  Future<void> _loadPlaylistPick(
    List<SpotifyPersonalizedSection> sections,
    int generation,
  ) async {
    final candidates = [
      for (final section in sections)
        for (final item in section.collections)
          if (item.itemKind == SpotifyPersonalizedKind.playlist) item,
    ];
    for (final preview in candidates.take(3)) {
      final detail = await DiscoveryService.instance.getPlaylistDetail(
        preview.id,
        source: 'spotify',
        limit: 40,
      );
      if (!mounted || generation != _spotifySectionsGeneration) return;
      final tracks = _toTracks(detail?.tracks ?? const []);
      if (tracks.length < 3) continue;
      final picked = [...tracks]..shuffle(Random(preview.id.hashCode));
      setState(() {
        _playlistPick = (
          preview: preview,
          tracks: picked.take(9).toList(growable: false),
        );
      });
      return;
    }
  }

  /// 把 Spotify 曲目结构转成可播放的 [Track]。
  List<Track> _toTracks(List<ToplistTrack> items) => items
      .map(
        (item) => Track(
          id: item.id,
          name: item.name,
          artists: item.artists,
          album: item.album,
          picUrl: item.picUrl,
          source: item.source ?? MusicSource.spotify,
          duration: item.duration == null
              ? null
              : Duration(milliseconds: item.duration!),
        ),
      )
      .where((track) => track.id.isNotEmpty)
      .toList(growable: false);

  /// 个性化分区里的一张卡被点开：按**卡片自己**的类型分流到对应的详情页。
  ///
  /// 不能按分区类型分——pathfinder 首页的「More like xxx」会把歌单和专辑混在一排。
  /// 一律立即跳转：歌单有稳定 id，由详情页自己重拉；电台与专辑没有可复用的
  /// 歌单 id，交给 loader 在详情页里现拉（电台每次生成都不同）。
  Future<void> _openPersonalizedItem(SpotifyPlaylistPreview preview) async {
    switch (preview.itemKind) {
      case SpotifyPersonalizedKind.artist:
        await _openSpotifyArtist(preview);
      case SpotifyPersonalizedKind.radio:
        _pushSpotifyDetail(
          preview,
          loader: spotifyRadioLoader(
            seedId: preview.id,
            name: preview.name,
            coverUrl: preview.coverImgUrl,
            description: preview.description,
          ),
        );
      case SpotifyPersonalizedKind.album:
        _pushSpotifyDetail(
          preview,
          loader: spotifyAlbumLoader(
            albumId: preview.id,
            name: preview.name,
            coverUrl: preview.coverImgUrl,
            artists: preview.description,
          ),
        );
      case SpotifyPersonalizedKind.playlist:
      case SpotifyPersonalizedKind.track:
      case SpotifyPersonalizedKind.mixed:
        _pushSpotifyDetail(preview);
    }
  }

  /// 打开艺术家详情页。页面自己去拉数据，这里只把来源与专辑点击接管交给它。
  Future<void> _openSpotifyArtist(SpotifyPlaylistPreview preview) async {
    await Navigator.of(context).push(
      CyreneHeroExpandPageRoute<void>(
        builder: (_) => ArtistDetailPage(
          playback: widget.playback,
          artistId: preview.id,
          artistName: preview.name,
          source: MusicSource.spotify,
          // Spotify 专辑 id 是 base62 字符串，内置的网易云 AlbumDetailPage 读不了，
          // 改走本页的 Spotify 专辑详情。
          onOpenAlbum: _openSpotifyAlbumFromArtist,
        ),
      ),
    );
  }

  /// 艺术家页里点开一张专辑：立即进详情页，曲目由 loader 在页内现拉。
  void _openSpotifyAlbumFromArtist(ArtistAlbum album) {
    final albumId = album.id.toString();
    _pushSpotifyDetail(
      (
        id: albumId,
        name: album.name,
        description: '',
        coverImgUrl: album.picUrl ?? '',
        trackCount: 0,
        itemKind: SpotifyPersonalizedKind.album,
      ),
      loader: spotifyAlbumLoader(
        albumId: albumId,
        name: album.name,
        coverUrl: album.picUrl ?? '',
      ),
    );
  }

  /// [loader] 为空时详情页按歌单 id 自己拉取。
  void _pushSpotifyDetail(
    SpotifyPlaylistPreview preview, {
    Future<PlaylistDetail?> Function()? loader,
  }) {
    Navigator.of(context).push(
      CyreneHeroExpandPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          playlistId: preview.id,
          title: preview.name,
          coverUrl: preview.coverImgUrl,
          playback: widget.playback,
          token: widget.account.token,
          desktopLayout: false,
          source: MusicSource.spotify,
          trackCount: preview.trackCount,
          loader: loader,
        ),
      ),
    );
  }

  /// 打开榜单详情：Spotify 榜单直接 push 详情页（source=spotify、曲目预填、
  /// 无重载闪烁）；网易云走 widget.onOpenPlaylist（默认 netease 源）。
  void _openToplist(Toplist toplist) {
    if (toplist.source == MusicSource.spotify) {
      final tracks = toplist.tracks;
      Navigator.of(context).push(
        CyreneHeroExpandPageRoute<void>(
          builder: (_) => PlaylistDetailPage(
            playlistId: toplist.externalId ?? toplist.id,
            title: toplist.name,
            coverUrl: toplist.coverImgUrl,
            playback: widget.playback,
            token: widget.account.token,
            desktopLayout: false,
            source: MusicSource.spotify,
            reloadable: toplist.externalId != null,
            initialPlaylist: PlaylistDetail(
              id: toplist.id,
              name: toplist.name,
              coverImgUrl: toplist.coverImgUrl,
              description: toplist.description,
              source: MusicSource.spotify,
              tracks: tracks,
              playCount: 0,
              creator: 'Spotify',
              trackCount: tracks.length,
              createTime: 0,
              updateTime: 0,
              tags: const ['Spotify'],
            ),
          ),
        ),
      );
      return;
    }
    widget.onOpenPlaylist(toplist.id, toplist.name, toplist.coverImgUrl);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 播放状态仍由 FM 和歌曲行局部监听，进度更新不重建整页。
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
        final forYou = tab == _HomeTab.recommend;
        final palette = ForYouPalette.of(context);
        final (greeting, greetingSubtitle) = _greetingOfNow();
        return LayoutBuilder(
          builder: (context, constraints) => ForYouAtmosphere(
            enabled: true,
            child: MiuixPullToRefresh(
              isRefreshing: state.isRefreshing,
              onRefresh: widget.home.refresh,
              refreshTexts: const ['下拉刷新', '释放立即刷新', '正在刷新...', '刷新成功'],
              // 保留钳制滚动和 OverscrollNotification，iOS 下拉刷新也正常工作。
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: CustomScrollView(
                  // 两个页签分别记住位置，横向唱片架也持有各自的 PageStorageKey。
                  key: PageStorageKey(
                    forYou ? 'home-recommend-scroll' : 'home-scroll',
                  ),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: [
                    // CustomScrollView 不会自动消费 MediaQuery.padding（只有
                    // ListView 等 BoxScrollView 会）。外壳已把「状态栏 + 玻璃
                    // 顶栏」高度注入 padding.top（桌面端为 0），这里显式让出，
                    // 静止时内容停在顶栏下方，上滑时滚入模糊带。
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).top,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: ForYouGreeting(
                        title: greeting,
                        subtitle: greetingSubtitle,
                        refreshing: state.isRefreshing,
                        onRefresh: widget.home.refresh,
                      ),
                    ),
                    if (showTabs)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: MiuixTabRowWithContour(
                            tabs: const ['为你推荐', '榜单'],
                            selectedTabIndex: forYou ? 0 : 1,
                            cornerRadius: 16,
                            minWidth: 92,
                            maxWidth: 116,
                            contentAlignment: AlignmentDirectional.centerStart,
                            colors: MiuixTabRowColors(
                              backgroundColor: Colors.transparent,
                              contentColor: palette.muted,
                              selectedBackgroundColor: palette.paper,
                              selectedContentColor: palette.accent,
                            ),
                            onTabSelected: (index) => setState(() {
                              _tab = index == 0
                                  ? _HomeTab.recommend
                                  : _HomeTab.leaderboard;
                            }),
                          ),
                        ),
                      ),
                    if (forYou)
                      ..._recommendSlivers(state, constraints.maxWidth)
                    else
                      ..._leaderboardSlivers(state),
                    const SliverToBoxAdapter(child: SizedBox(height: 180)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ===== 为你推荐 =====

  List<Widget> _recommendSlivers(HomeState state, double availableWidth) {
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(
              child: ForYouDailyCard(
                tracks: daily,
                onOpen: () => _openDailyDetail(daily),
                onPlay: () => _playRecommendationQueue(daily),
              ),
            ),
          ),
        ),
      if (fm.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(
              child: ListenableBuilder(
                listenable: widget.playback,
                builder: (context, _) => ForYouRadioCard(
                  track: _fmDisplayTrack(fm)!,
                  isPlaying:
                      _isFmCurrent(fm) && widget.playback.state.isPlaying,
                  onToggle: () => _toggleFm(fm),
                  onSkip: () => _skipFm(fm),
                  onOpen: () => _openFmInPlayer(fm),
                ),
              ),
            ),
          ),
        ),
      if (dailyPlaylists.isNotEmpty) ...[
        _forYouSection(title: '今日歌单', subtitle: '给每个平凡时刻，选一点喜欢'),
        _playlistShelf(dailyPlaylists, storageKey: 'daily'),
      ],
      if (personalized.isNotEmpty) ...[
        _forYouSection(title: '懂你的音乐角落', subtitle: '专属歌单，刚好合你的心意'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(
              child: ForYouSpotlightPlaylist(
                data: personalized.first,
                label: '专属精选',
                onTap: (cardContext) =>
                    _openRecommendedPlaylist(personalized.first, cardContext),
              ),
            ),
          ),
        ),
        if (personalized.length > 1) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
          _playlistGrid(
            personalized.skip(1).toList(growable: false),
            availableWidth: availableWidth,
          ),
        ],
      ],
      if (radar.isNotEmpty) ...[
        _forYouSection(title: '和下一首好歌相遇', subtitle: '雷达歌单，发现新的心动'),
        _playlistShelf(radar, storageKey: 'radar', wide: true),
      ],
      if (newest.isNotEmpty) ...[
        _forYouSection(
          title: '新歌来信',
          subtitle: '一些新鲜旋律，等你拆开',
          trailing: ForYouPlayAction(
            label: '播放全部',
            subtle: true,
            onPressed: () => _playRecommendationQueue(newest),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: newest.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = newest[index];
              return ForYouSongSurface(
                child: HomeSongRow(
                  track: track,
                  playback: widget.playback,
                  onPlay: () => widget.playback.playTrack(track, queue: newest),
                  onAddToQueue: () => widget.playback.addToQueue(track),
                ),
              );
            },
          ),
        ),
      ],
      const SliverToBoxAdapter(child: ForYouEndNote()),
    ];
  }

  // ===== 榜单 =====

  List<Widget> _leaderboardSlivers(HomeState state) {
    final palette = ForYouPalette.of(context);
    // 网易云榜单入口暂时下线：历史选中的网易云源一律回退到 Spotify，
    // 相关代码保留以便恢复。
    if (_leaderboardSource != _LeaderboardSource.spotify) {
      _leaderboardSource = _LeaderboardSource.spotify;
    }
    final isSpotify = _leaderboardSource == _LeaderboardSource.spotify;
    final toplists = isSpotify ? _spotifyToplists : state.toplists;
    final loading = isSpotify && _spotifyToplistsLoading;
    final error = isSpotify ? _spotifyToplistsError : null;
    final loggedIn = widget.account.state.isLoggedIn;
    return [
      // 榜单源切换（始终显示：榜单 tab 对登录/未绑定用户都展示，两源均不依赖登录态）。
      // 与桌面首页一致，改用下拉选择框而非 Tab 栏，省横向空间且语义更清晰。
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        sliver: SliverToBoxAdapter(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              decoration: ShapeDecoration(
                color: palette.paper.withValues(alpha: 0.6),
                shape: MiuixSquircleBorder(
                  cornerRadius: 16,
                  side: BorderSide(color: palette.outline, width: 0.7),
                ),
              ),
              child: MiuixWindowDropdownMenu(
                title: isSpotify ? 'Spotify' : '网易云音乐',
                summary: isSpotify ? '全球热门榜单' : '网易云音乐榜单',
                insideMargin: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                entry: MiuixDropdownEntry(
                  items: [
                    MiuixDropdownItem(
                      text: 'Spotify',
                      selected: isSpotify,
                      onClick: () =>
                          _selectLeaderboardSource(_LeaderboardSource.spotify),
                    ),
                    // 网易云榜单入口暂时下线，保留代码以便恢复。
                    // MiuixDropdownItem(
                    //   text: '网易云音乐',
                    //   selected: !isSpotify,
                    //   onClick: () =>
                    //       _selectLeaderboardSource(_LeaderboardSource.netease),
                    // ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (!loggedIn)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _LoginPromptCard(onLogin: _openLogin),
          ),
        ),
      ..._chartsBody(toplists, loading: loading, error: error),
    ];
  }

  /// 榜单页签正文：随心畅听 → 今天就听这些 → 个性化分区，中间穿插排行榜与
  /// 歌单摘歌，避免一种版式连着出现。
  ///
  /// 个性化分区与榜单走两条后端链路，谁先回来先铺谁，一边挂了不连累另一边。
  List<Widget> _chartsBody(
    List<Toplist> toplists, {
    required bool loading,
    required String? error,
  }) {
    final sections = _leaderboardSource == _LeaderboardSource.spotify
        ? _spotifySections
        : const <SpotifyPersonalizedSection>[];
    final charts = [
      for (final toplist in toplists)
        if (_tracksFor(toplist).isNotEmpty) toplist,
    ];
    if (charts.isEmpty && sections.isEmpty) {
      if (loading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: MiuixCircularProgressIndicator()),
          ),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: error != null
              ? CyreneEmptyState(
                  icon: Icons.cloud_off,
                  title: 'Spotify 榜单加载失败',
                  description: error,
                  action: MiuixButton(
                    onPressed: _loadSpotifyToplists,
                    child: MiuixText(
                      '重试',
                      style: MiuixTheme.of(context).textStyles.button,
                    ),
                  ),
                )
              : const CyreneEmptyState(
                  icon: Icons.emoji_events,
                  title: '暂无榜单内容',
                  description: '稍后下拉刷新再试。',
                ),
        ),
      ];
    }

    final slivers = <Widget>[];
    if (charts.isNotEmpty) {
      final all = {
        for (final chart in charts)
          for (final track in _tracksFor(chart)) track.key,
      };
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(
              child: SpotifyMixHero(
                covers: [
                  for (final chart in charts.take(3))
                    _tracksFor(chart).first.picUrl,
                ],
                chartCount: charts.length,
                trackCount: all.length,
                leadTrack: _tracksFor(charts.first).first,
                onShuffle: _playShuffledToplists,
              ),
            ),
          ),
        ),
      );
      final picks = _chartPicks(charts);
      if (picks.isNotEmpty) {
        slivers.addAll([
          _forYouSection(
            title: '今天就听这些',
            subtitle: '从各个榜单里挑出来的歌',
            trailing: SpotifyPillAction(
              label: '换一批',
              icon: Icons.refresh_rounded,
              leadingIcon: true,
              onPressed: () => setState(() => _pickSeed++),
            ),
          ),
          SliverToBoxAdapter(
            child: SpotifySongPager(
              tracks: picks,
              playback: widget.playback,
              // 换一批后回到第一页，不恢复上一批的翻页位置。
              storageKey: 'home-spotify-picks-$_pickSeed',
            ),
          ),
        ]);
      }
    }

    // 排行榜插在第 2 个分区后、歌单摘歌插在第 5 个分区后；分区不够就顺延到末尾。
    var chartsPlaced = false;
    var pickPlaced = false;
    var collectionIndex = 0;
    for (var i = 0; i < sections.length; i++) {
      if (i == 2) {
        slivers.addAll(_chartCarousel(charts, loading: loading, error: error));
        chartsPlaced = true;
      }
      if (i == 5) {
        slivers.addAll(_playlistPickSlivers());
        pickPlaced = true;
      }
      final section = sections[i];
      slivers.addAll(_personalizedSection(section, collectionIndex));
      if (_usesRotatingLayout(section)) collectionIndex++;
    }
    if (!chartsPlaced) {
      slivers.addAll(_chartCarousel(charts, loading: loading, error: error));
    }
    if (!pickPlaced) slivers.addAll(_playlistPickSlivers());
    slivers.add(const SliverToBoxAdapter(child: ForYouEndNote()));
    return slivers;
  }

  /// 从各榜单轮流抽歌：每张榜单跳过前三名（排行榜卡里已经露出），打乱后
  /// 一张抽一首，去重，凑满 12 首（四页）。
  List<Track> _chartPicks(List<Toplist> charts) {
    if (_picksSeed == _pickSeed &&
        _picksSource != null &&
        _sameCharts(_picksSource!, charts)) {
      return _picks;
    }
    final random = Random(_pickSeed * 7919 + charts.length);
    final pools = [
      for (final chart in charts)
        (_tracksFor(chart).skip(3).toList()..shuffle(random)),
    ];
    final seen = <String>{};
    final picks = <Track>[];
    for (var round = 0; picks.length < 12; round++) {
      if (pools.every((pool) => round >= pool.length)) break;
      for (final pool in pools) {
        if (round < pool.length && seen.add(pool[round].key)) {
          picks.add(pool[round]);
          if (picks.length == 12) break;
        }
      }
    }
    _picksSource = charts;
    _picksSeed = _pickSeed;
    return _picks = List.unmodifiable(picks);
  }

  /// [charts] 每次 build 都是新列表，按元素比对才能让缓存生效。
  static bool _sameCharts(List<Toplist> a, List<Toplist> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  List<Widget> _chartCarousel(
    List<Toplist> charts, {
    required bool loading,
    required String? error,
  }) {
    if (charts.isNotEmpty) {
      return [
        _forYouSection(title: '排行榜', subtitle: '全球与各地区的播放热度'),
        SliverToBoxAdapter(
          child: SpotifyChartCarousel(
            toplists: charts,
            tracksFor: _tracksFor,
            onOpen: _openToplist,
            playback: widget.playback,
          ),
        ),
      ];
    }
    if (loading) {
      return [
        _forYouSection(title: '排行榜', subtitle: '全球与各地区的播放热度'),
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: Center(child: MiuixCircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (error == null) return const [];
    // 个性化分区还在，榜单挂了就只在它自己的位置给一句提示和重试。
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return [
      _forYouSection(title: '排行榜', subtitle: '暂时没有取到'),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(
          child: ForYouSongSurface(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '榜单服务暂时不可用',
                      style: theme.textStyles.body2.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ),
                  MiuixTextButton('重试', onPressed: _loadSpotifyToplists),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _playlistPickSlivers() {
    final pick = _playlistPick;
    if (pick == null) return const [];
    return [
      _forYouSection(
        title: '摘自「${pick.preview.name}」',
        subtitle: '从歌单里挑了几首，先听听看',
        trailing: SpotifyPillAction(
          label: '打开歌单',
          onPressed: () => _openPersonalizedItem(pick.preview),
        ),
      ),
      SliverToBoxAdapter(
        child: SpotifySongPager(
          tracks: pick.tracks,
          playback: widget.playback,
          storageKey: 'home-spotify-playlist-pick',
        ),
      ),
    ];
  }

  /// 艺人与专辑分区有专属版式，其余（歌单 / 电台 / 混排）才参与轮换。
  bool _usesRotatingLayout(SpotifyPersonalizedSection section) =>
      section.kind != SpotifyPersonalizedKind.track &&
      section.kind != SpotifyPersonalizedKind.artist &&
      section.kind != SpotifyPersonalizedKind.album &&
      section.collections.isNotEmpty;

  static const _rotatingLayouts = [
    SpotifyCollectionLayout.mosaic,
    SpotifyCollectionLayout.shelf,
    SpotifyCollectionLayout.list,
    SpotifyCollectionLayout.wide,
  ];

  /// 号池 Spotify 账号的一个个性化分区。
  ///
  /// 分区种类与数量都由后端按「哪几路数据真的取到了」决定，本地不硬编码——
  /// 原来桌面端写死的六个 Web API 分类在后端 404 后只剩六个永远转圈的占位。
  /// 版式按分区类型选；歌单类分区按出现顺序在四种版式间轮换。
  List<Widget> _personalizedSection(
    SpotifyPersonalizedSection section,
    int collectionIndex,
  ) {
    final storageKey = 'home-spotify-${section.id}';
    if (section.kind == SpotifyPersonalizedKind.track) {
      final tracks = _toTracks(section.tracks);
      if (tracks.isEmpty) return const [];
      return [
        _forYouSection(
          title: section.title,
          subtitle: section.description,
          trailing: ForYouPlayAction(
            label: '播放全部',
            subtle: true,
            onPressed: () =>
                widget.playback.playTrack(tracks.first, queue: tracks),
          ),
        ),
        SliverToBoxAdapter(
          child: SpotifySongPager(
            tracks: tracks,
            playback: widget.playback,
            storageKey: '$storageKey-songs',
          ),
        ),
      ];
    }
    final items = section.collections;
    if (items.isEmpty) return const [];
    final Widget body = switch (section.kind) {
      SpotifyPersonalizedKind.artist => SpotifyArtistRow(
        items: items,
        onOpen: _openPersonalizedItem,
        storageKey: '$storageKey-artists',
      ),
      SpotifyPersonalizedKind.album => SpotifyAlbumShelf(
        items: items,
        onOpen: _openPersonalizedItem,
        storageKey: '$storageKey-albums',
      ),
      _ => SpotifyCollectionSection(
        items: items,
        layout: _rotatingLayouts[collectionIndex % _rotatingLayouts.length],
        onOpen: _openPersonalizedItem,
        storageKey: '$storageKey-shelf',
      ),
    };
    return [
      _forYouSection(title: section.title, subtitle: section.description),
      SliverToBoxAdapter(child: body),
    ];
  }

  void _playShuffledToplists() {
    final isSpotify = _leaderboardSource == _LeaderboardSource.spotify;
    final toplists = isSpotify ? _spotifyToplists : widget.home.state.toplists;
    final all = toplists.expand(_tracksFor).toList();
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
    _dailyPlaylists = _playlistCards(data.dailyPlaylists, 'daily');
    _personalizedPlaylists = _playlistCards(
      data.personalizedPlaylists,
      'personalized',
    );
    _radarPlaylists = _playlistCards(data.radarPlaylists, 'radar');
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
    final isSpotify = _leaderboardSource == _LeaderboardSource.spotify;
    final source = isSpotify ? _spotifyToplists : widget.home.state.toplists;
    if (!identical(_toplistCacheSource, source)) {
      _toplistCacheSource = source;
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

  void _playRecommendationQueue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    widget.playback.playTrack(tracks.first, queue: tracks);
    widget.onOpenPlayer();
  }

  void _openDailyDetail(List<Track> daily) {
    Navigator.of(context).push(
      CyreneHeroExpandPageRoute<void>(
        builder: (_) => DailyRecommendPage(
          tracks: daily,
          playback: widget.playback,
          token: widget.account.token,
        ),
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

  Widget _forYouSection({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) => SliverToBoxAdapter(
    child: ForYouSectionHeading(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
    ),
  );

  Widget _playlistShelf(
    List<ForYouPlaylistData> playlists, {
    required String storageKey,
    bool wide = false,
  }) => SliverToBoxAdapter(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = wide
            ? (constraints.maxWidth * 0.67).clamp(224.0, 300.0)
            : (constraints.maxWidth * 0.42).clamp(140.0, 184.0);
        final height = wide
            ? ForYouSpotlightPlaylist.heightFor(context, compact: true)
            : ForYouPlaylistCard.heightFor(context, cardWidth);
        return SizedBox(
          height: height,
          child: ListView.separated(
            key: PageStorageKey('home-$storageKey-shelf'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return SizedBox(
                width: cardWidth,
                child: wide
                    ? ForYouSpotlightPlaylist(
                        data: playlist,
                        compact: true,
                        label: '音乐雷达',
                        onTap: (cardContext) =>
                            _openRecommendedPlaylist(playlist, cardContext),
                      )
                    : ForYouPlaylistCard(
                        data: playlist,
                        onTap: (cardContext) =>
                            _openRecommendedPlaylist(playlist, cardContext),
                      ),
              );
            },
          ),
        );
      },
    ),
  );

  Widget _playlistGrid(
    List<ForYouPlaylistData> playlists, {
    required double availableWidth,
  }) {
    // 宽度来自页面级 Box LayoutBuilder；不用会随 scrollOffset 每帧重建的
    // SliverLayoutBuilder，卡片高度仍会响应窗口宽度与系统字号。
    final contentWidth = availableWidth - 40;
    final columns = contentWidth >= 600 ? 3 : 2;
    const spacing = 14.0;
    final width = (contentWidth - spacing * (columns - 1)) / columns;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 18,
          crossAxisSpacing: spacing,
          mainAxisExtent: ForYouPlaylistCard.heightFor(context, width),
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final playlist = playlists[index];
          return ForYouPlaylistCard(
            data: playlist,
            onTap: (cardContext) =>
                _openRecommendedPlaylist(playlist, cardContext),
          );
        }, childCount: playlists.length),
      ),
    );
  }

  void _openRecommendedPlaylist(
    ForYouPlaylistData playlist,
    BuildContext cardContext,
  ) {
    final box = cardContext.findRenderObject() as RenderBox?;
    Alignment? alignment;
    if (box != null && box.hasSize) {
      final size = MediaQuery.sizeOf(cardContext);
      final center = box.localToGlobal(box.size.center(Offset.zero));
      alignment = Alignment(
        ((center.dx / size.width) * 2.0 - 1.0).clamp(-1.0, 1.0),
        ((center.dy / size.height) * 2.0 - 1.0).clamp(-1.0, 1.0),
      );
    }
    widget.onOpenPlaylist(
      playlist.id,
      playlist.name,
      playlist.coverUrl,
      heroTag: playlist.heroTag,
      originAlignment: alignment,
    );
  }

  List<ForYouPlaylistData> _playlistCards(
    Iterable<dynamic> items,
    String tagPrefix,
  ) {
    int readCount(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

    return items
        .whereType<Map>()
        .map((item) {
          final id = readCount(item['id']);
          return ForYouPlaylistData(
            id: id,
            name: item['name']?.toString() ?? '',
            coverUrl: (item['picUrl'] ?? item['coverImgUrl'])?.toString() ?? '',
            heroTag: 'home-playlist-$tagPrefix-$id',
            description:
                (item['copywriter'] ?? item['description'])?.toString() ?? '',
            trackCount: readCount(item['trackCount']),
            playCount: readCount(item['playCount'] ?? item['playcount']),
          );
        })
        .where((item) => item.id != 0 && item.name.isNotEmpty)
        .toList(growable: false);
  }
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
    < 6 => '把音量放轻，和今天温柔道别',
    < 9 => '给新的一天，留一点明亮的旋律',
    < 12 => '喜欢的歌，陪你慢慢走过今天',
    < 14 => '忙里偷闲，让耳朵也歇一会儿',
    < 18 => '收集一点旋律，也收集一点好心情',
    _ => '夜色很温柔，音乐也是',
  };
  return (title, subtitle);
}

enum _HomeTab { recommend, leaderboard }

// 网易云榜单入口暂时下线：netease 枚举值暂未被引用，保留以便恢复。
// ignore: unused_field
enum _LeaderboardSource { netease, spotify }

/// 未登录引导卡（对应原版 ForYouLoginPrompt），与每日推荐卡同族的渐变纸张卡。
class _LoginPromptCard extends StatelessWidget {
  const _LoginPromptCard({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.peach, palette.paper, palette.rose],
          stops: const [0, 0.7, 1],
        ),
        shape: MiuixSquircleBorder(
          cornerRadius: 26,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              shape: const CircleBorder(),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.rose, palette.paper],
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 40,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '登录后查看更多内容',
            style: theme.textStyles.title3.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '登录即可获取每日推荐、私人FM、专属歌单等个性化内容',
            textAlign: TextAlign.center,
            style: theme.textStyles.body2.copyWith(
              color: palette.muted,
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
    final palette = ForYouPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.paper.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textStyles.footnote1.copyWith(color: palette.accent),
          ),
        ],
      ),
    );
  }
}
