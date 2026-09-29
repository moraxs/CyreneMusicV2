import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/discovery/discover_controller.dart';
import '../../application/home/home_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../application/playlists/playlist_library_controller.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/history.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/history_service.dart';
import '../../infrastructure/services/discovery_service.dart';
import '../../infrastructure/storage/spotify_charts_cache.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../history/history_page.dart';
import '../artist/artist_detail_page.dart';
import '../playlist/playlist_detail_loaders.dart';
import '../playlist/playlist_detail_page.dart';
import 'daily_recommend_page.dart';
import 'desktop_charts/desktop_charts_home.dart';
import 'for_you/for_you_palette.dart';
import 'recommend_card_artwork.dart';

/// 桌面端专属首页（宽屏布局，对应设计稿 Aurora Music 桌面版）。
///
/// **与移动端 [NowListeningPage] 完全隔离**：这是独立文件、独立子组件，
/// 只依赖 Material + Miuix，不引用移动端首页的任何私有部件。配色统一走
/// [MiuixTheme]（与移动端同源，故视觉一致，但代码互不影响）。挂载点见
/// `desktop_shell.dart` 的 `_pages()[0]`；它在外壳的 `_buildBody` 里被
/// Material + Material 默认 IconTheme 包裹，故不吃 fluent 的字号/图标色。
///
/// **桌面端的次级页面（歌单详情 / 每日推荐 / 播放历史）不走路由 push**：
/// 由 [body] 参数以「二级内容区」的形式渲染，外层 [DesktopShell] 负责
/// 覆盖区布局与「返回首页」的返回键/标题栏标题（见 `desktop_shell.dart`）。
/// 只有全屏播放器（[onOpenPlayer]）仍走全窗口路由，与移动端行为一致。
///
/// 推荐页保留个性化内容；榜单页由 [DesktopChartsHome] 组合精选海报、继续听、
/// 热门单曲与分类榜单，Spotify 个性化分区放在核心内容之后。数据全部复用
/// 外壳已持有的 controller，缓存和二级页导航仍在本页管理。
///
/// **坑：横向条一律不用惰性 [ListView]，改 SingleChildScrollView + Row。**
/// Windows 版 Flutter 的无障碍桥有一处已知缺陷（flutter#182444「ListView +
/// Tooltip」）：二者同时存在时语义树更新会畸形，引擎先刷
/// `Failed to update ui::AXTree, error: N will not be in the tree and is not
/// the new root`，随后在 flutter_windows.dll 里踩空指针，进程直接以
/// `0xc0000005`（访问违规）闪退——Dart 层拿不到任何异常，只看到
/// "Lost connection to device"。桌面外壳的侧栏收起态给每个图标都包了 Tooltip
/// （见 `desktop_shell.dart` 的 `_paneItem`），Tooltip 一侧无法避开，所以这边
/// 只能不用 ListView。代价是失去惰性构建，故每条横向条都必须自己限量。
class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({
    super.key,
    required this.account,
    required this.home,
    required this.discover,
    required this.playlists,
    required this.playback,
    required this.onOpenPlayer,
    required this.onOpenPlaylist,
    required this.onOpenPersonalPlaylist,
    this.onOpenDiscoverPlaylist,
    required this.onOpenSecondary,
    this.body,
  });

  final AccountSessionController account;
  final HomeController home;
  final DiscoverController discover;
  final PlaylistLibraryController playlists;
  final PlaybackController playback;

  /// 打开全屏播放器（复用移动端播放器页）。
  final VoidCallback onOpenPlayer;

  /// 打开首页歌单详情（id / 标题 / 封面）。
  final void Function(int id, String title, String coverUrl) onOpenPlaylist;

  /// 打开 Cyrene 账户中的个人歌单。个人歌单 ID 属于后端歌单库，不能交给
  /// 在线发现歌单接口加载。
  final ValueChanged<Playlist> onOpenPersonalPlaylist;

  /// 桌面端首页「推荐歌单」的入口已统一并入 [onOpenPlaylist]（走内容区
  /// 二级页），此参数在桌面端不再使用，保留仅防误用。
  final void Function(DiscoveryPlaylist playlist)? onOpenDiscoverPlaylist;

  /// 桌面端二级页打开回调：把内容区切换为 [page]，进入「首页 → 二级页」。
  /// 由外层 [DesktopShell] 提供（内部维护覆盖区状态与返回键）。
  final ValueChanged<Widget> onOpenSecondary;

  /// 桌面端二级页（歌单详情 / 每日推荐 / 播放历史）。非空时本页把整个
  /// 内容区让给它，进入「首页 → 二级页」状态；空则渲染首页本身。
  final Widget? body;

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with SingleTickerProviderStateMixin {
  var _tab = _HomeTab.recommend;

  /// Tab 滑块的位置：0 = 为你推荐，1 = 榜单。放在页面 state 而不是 Tab 栏里——
  /// 滚动视图按 Tab 换 key，切换时 Tab 栏会整个重建，自己持有的动画会丢。
  late final AnimationController _tabMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    value: _tab.index.toDouble(),
  );

  /// 切换 Tab。[animate] 为 false 用于加载完成后按绑定状态自动选中，不播动画。
  void _selectTab(_HomeTab tab, {bool animate = true}) {
    if (!animate) {
      _tabMotion.value = tab.index.toDouble();
    } else if (tab.index > _tabMotion.value) {
      _tabMotion.forward();
    } else {
      _tabMotion.reverse();
    }
    if (tab != _tab) setState(() => _tab = tab);
  }

  List<Toplist> _spotifyToplists = const [];
  bool _spotifyToplistsLoading = true;
  bool _spotifyToplistsFetching = false;
  bool _refreshing = false;
  String? _spotifyToplistsError;
  int _spotifyLoadGeneration = 0;
  String? _loadedToken;

  List<SpotifyPersonalizedSection> _spotifySections = const [];
  int _spotifyDiscoveryGeneration = 0;

  // 派生数据缓存：仅当控制器发布新 RecommendData 对象时才重新解析原始 JSON。
  RecommendData? _recommendCacheSource;
  List<Track> _daily = const [];
  List<Track> _fm = const [];
  List<Track> _newest = const [];
  _PlaylistRef? _relaxPlaylist;
  _PlaylistRef? _focusPlaylist;
  _PlaylistRef? _radarPlaylist;

  // 4 张推荐卡的动态视觉（随机曲目封面 + 该封面的主题色渐变）。解析是异步且
  // 逐卡落地的，故用 map 而非一次性替换，卡片各自就位、互不等待。
  final Map<_RecSlot, RecommendArtwork> _artwork = {};
  // 解析批次号：刷新会重抽封面，旧批次的迟到结果按此判定过期后丢弃。
  int _artworkBatch = 0;

  // 最近播放（HistoryService 为内存态、无 ChangeNotifier，故手动拉取）。
  List<HistoryEntry> _history = const [];
  String? _lastTrackKey;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_onAccountChanged);
    // 只监听切歌（结构性主通知），刷新最近播放；进度 tick 走独立通知，不在此。
    widget.playback.addListener(_onPlaybackChanged);
    _lastTrackKey = widget.playback.state.currentTrack?.key;
    _loadedToken = widget.account.token;
    _loadAll();
    _loadHistory();
    // 榜单使用 Spotify，首屏即加载，不等用户切换。
    _loadSpotifyToplists();
    _loadSpotifyDiscovery();
  }

  @override
  void dispose() {
    _spotifyLoadGeneration++;
    widget.account.removeListener(_onAccountChanged);
    widget.playback.removeListener(_onPlaybackChanged);
    _tabMotion.dispose();
    super.dispose();
  }

  Future<void> _loadSpotifyToplists() async {
    if (_spotifyToplistsFetching) return;
    _spotifyToplistsFetching = true;
    final generation = ++_spotifyLoadGeneration;
    try {
      // 已有内容不被加载态盖住；冷启动先读快照，再静默刷新。
      final cached = _spotifyToplists.isEmpty
          ? await SpotifyChartsCache.instance.read()
          : null;
      if (!mounted || generation != _spotifyLoadGeneration) return;
      setState(() {
        if (cached != null && cached.isNotEmpty) _spotifyToplists = cached;
        _spotifyToplistsLoading = _spotifyToplists.isEmpty;
        _spotifyToplistsError = null;
      });

      final toplists = await DiscoveryService.instance.getSpotifyToplists();
      if (!mounted || generation != _spotifyLoadGeneration) return;
      setState(() {
        if (toplists.isNotEmpty) {
          _spotifyToplists = toplists;
          SpotifyChartsCache.instance.write(toplists);
        } else if (_spotifyToplists.isEmpty) {
          _spotifyToplistsError = 'Spotify 榜单暂时不可用，请稍后刷新重试';
        }
      });
    } catch (error) {
      if (!mounted || generation != _spotifyLoadGeneration) return;
      debugPrint('[DHP] Spotify charts failed: $error');
      if (_spotifyToplists.isEmpty) {
        setState(() => _spotifyToplistsError = '榜单加载失败，请检查网络后重试');
      }
    } finally {
      _spotifyToplistsFetching = false;
      if (mounted && generation == _spotifyLoadGeneration) {
        setState(() => _spotifyToplistsLoading = false);
      }
    }
  }

  /// 拉取号池 Spotify 账号的个性化首页分区。
  ///
  /// 首屏拿不到就整段留白（各分区本就是「有才显示」），不弹错误——这块是锦上
  /// 添花，真正的主内容是下方的热门榜单。
  Future<void> _loadSpotifyDiscovery() async {
    final generation = ++_spotifyDiscoveryGeneration;
    final sections = await DiscoveryService.instance.getSpotifyHome(limit: 20);
    if (!mounted || generation != _spotifyDiscoveryGeneration) return;
    setState(() {
      if (sections.isNotEmpty) _spotifySections = sections;
    });
  }

  /// 打开专辑：立即进详情页，曲目由页面自己取（取的过程显示加载动画）。
  void _openSpotifyAlbum(SpotifyAlbumPreview album) {
    widget.onOpenSecondary(
      PlaylistDetailPage(
        playlistId: album.id,
        title: album.name,
        coverUrl: album.coverImgUrl,
        creator: album.artists,
        playback: widget.playback,
        token: widget.account.token,
        desktopLayout: true,
        source: MusicSource.spotify,
        loader: spotifyAlbumLoader(
          albumId: album.id,
          name: album.name,
          coverUrl: album.coverImgUrl,
          artists: album.artists,
        ),
      ),
    );
  }

  void _openSpotifyPlaylist(SpotifyPlaylistPreview preview) {
    widget.onOpenSecondary(
      PlaylistDetailPage(
        playlistId: preview.id,
        title: preview.name,
        coverUrl: preview.coverImgUrl,
        playback: widget.playback,
        token: widget.account.token,
        desktopLayout: true,
        source: MusicSource.spotify,
        reloadable: true,
        trackCount: preview.trackCount,
      ),
    );
  }

  /// 打开单曲电台：内容按需生成、没有可复用的歌单 id，交给 loader 在详情页
  /// 里现拉，页面立即打开。
  void _openSpotifyRadio(SpotifyPlaylistPreview preview) {
    widget.onOpenSecondary(
      PlaylistDetailPage(
        playlistId: preview.id,
        title: preview.name,
        coverUrl: preview.coverImgUrl,
        creator: 'Spotify',
        playback: widget.playback,
        token: widget.account.token,
        desktopLayout: true,
        source: MusicSource.spotify,
        loader: spotifyRadioLoader(
          seedId: preview.id,
          name: preview.name,
          coverUrl: preview.coverImgUrl,
          description: preview.description,
        ),
      ),
    );
  }

  /// 打开艺术家详情页。页面自己去拉数据，这里只把来源与专辑点击接管交给它。
  void _openSpotifyArtist(SpotifyPlaylistPreview preview) {
    widget.onOpenSecondary(
      ArtistDetailPage(
        playback: widget.playback,
        artistId: preview.id,
        artistName: preview.name,
        source: MusicSource.spotify,
        // Spotify 专辑 id 是 base62 字符串，内置的网易云 AlbumDetailPage 读不了，
        // 走本页既有的 Spotify 专辑路径。
        onOpenAlbum: (album) => _openSpotifyAlbum((
          id: album.id.toString(),
          name: album.name,
          artists: preview.name,
          coverImgUrl: album.picUrl ?? '',
        )),
      ),
    );
  }

  /// 个性化分区里的一张卡被点开：按**卡片自己**的类型分流。
  ///
  /// 不能按分区类型分——pathfinder 首页的「More like xxx」会把歌单和专辑混在一排。
  void _openPersonalizedItem(SpotifyPlaylistPreview preview) {
    switch (preview.itemKind) {
      case SpotifyPersonalizedKind.playlist:
        _openSpotifyPlaylist(preview);
      case SpotifyPersonalizedKind.radio:
        _openSpotifyRadio(preview);
      case SpotifyPersonalizedKind.artist:
        _openSpotifyArtist(preview);
      case SpotifyPersonalizedKind.album:
        _openSpotifyAlbum((
          id: preview.id,
          name: preview.name,
          artists: preview.description,
          coverImgUrl: preview.coverImgUrl,
        ));
      case SpotifyPersonalizedKind.track:
      case SpotifyPersonalizedKind.mixed:
        // track 由 _NewSongsSection 直接播放；mixed 只是分区级类型，
        // 落不到单张卡片上（见 DiscoveryService._parseCollectionItems）。
        break;
    }
  }

  void _onAccountChanged() {
    final token = widget.account.token;
    if (token == _loadedToken) return;
    _loadedToken = token;
    _loadAll();
  }

  void _onPlaybackChanged() {
    final key = widget.playback.state.currentTrack?.key;
    if (key == _lastTrackKey) return;
    _lastTrackKey = key;
    _loadHistory();
  }

  /// 刷新推荐与 Spotify 内容，而不只刷新网易云控制器。
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _artworkBatch++;
      _recommendCacheSource = null;
      _artwork.clear();
    });
    try {
      await Future.wait([
        widget.home.refresh(),
        _loadSpotifyToplists(),
        _loadSpotifyDiscovery(),
        _loadHistory(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _loadAll() {
    widget.home.load(token: _loadedToken).then((_) {
      if (!mounted) return;
      _selectTab(
        widget.home.state.isBound ? _HomeTab.recommend : _HomeTab.leaderboard,
        animate: false,
      );
    });
    widget.playlists.load(_loadedToken);
    widget.discover.load();
  }

  Future<void> _loadHistory() async {
    final entries = await HistoryService.instance.getHistory(limit: 12);
    if (!mounted) return;
    setState(() => _history = entries);
  }

  // ===== 派生数据 =====

  void _syncRecommendCache(RecommendData data) {
    if (identical(data, _recommendCacheSource)) return;
    _recommendCacheSource = data;
    _daily = widget.home.convertTracks(data.dailySongs);
    _fm = widget.home.convertTracks(data.fm);
    _newest = widget.home.convertTracks(data.personalizedNewsongs);
    _relaxPlaylist = _firstPlaylist(data.personalizedPlaylists);
    _focusPlaylist = _firstPlaylist(data.dailyPlaylists);
    _radarPlaylist = _firstPlaylist(data.radarPlaylists);
    _resolveArtwork();
  }

  /// 为 4 张推荐卡各解析一份「随机封面 + 主题色」。
  ///
  /// 在 build 期间被 [_syncRecommendCache] 调用，故只能启动异步任务、不能同步
  /// setState；每张卡各自 await、各自落地。
  void _resolveArtwork() {
    final batch = _artworkBatch;
    void resolve(_RecSlot slot, Future<RecommendArtwork?> future) {
      future
          .then((artwork) {
            if (!mounted || batch != _artworkBatch || artwork == null) return;
            setState(() => _artwork[slot] = artwork);
          })
          // 网络/解码异常不该冒泡成未捕获错误：卡片留在设计配色即可。
          .catchError((Object error) {
            debugPrint('[DHP] artwork $slot failed: $error');
          });
    }

    resolve(
      _RecSlot.daily,
      RecommendArtworkResolver.fromCovers([
        for (final track in _daily) track.picUrl,
      ]),
    );
    for (final (slot, ref) in [
      (_RecSlot.relax, _relaxPlaylist),
      (_RecSlot.focus, _focusPlaylist),
      (_RecSlot.radar, _radarPlaylist),
    ]) {
      if (ref == null) continue;
      resolve(slot, RecommendArtworkResolver.fromPlaylist(ref.id));
    }
  }

  _PlaylistRef? _firstPlaylist(List<dynamic> items) {
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, Object?>.from(raw);
      final id =
          (item['id'] as num?)?.toInt() ??
          int.tryParse(item['id']?.toString() ?? '') ??
          0;
      final name = item['name']?.toString() ?? '';
      if (id == 0 || name.isEmpty) continue;
      return _PlaylistRef(
        id: id,
        name: name,
        coverUrl: (item['picUrl'] ?? item['coverImgUrl'])?.toString() ?? '',
      );
    }
    return null;
  }

  // ===== 交互 =====

  void _openDailyDetail() {
    if (_daily.isEmpty) return;
    widget.onOpenSecondary(
      DailyRecommendPage(
        tracks: _daily,
        playback: widget.playback,
        token: widget.account.token,
        desktopLayout: true,
      ),
    );
  }

  void _playDaily() {
    if (_daily.isEmpty) return;
    widget.playback.playTrack(_daily.first, queue: _daily);
    CyreneToast.show('开始播放每日推荐');
  }

  // ===== 私人FM =====

  /// 当前播放的曲目是否来自 FM 列表（在播时 FM 卡实时跟随当前曲目）。
  bool _isFmCurrent(List<Track> fm) {
    final current = widget.playback.state.currentTrack;
    if (current == null) return false;
    return fm.any((track) => track.key == current.key);
  }

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

  /// 点击 FM 卡主体：未在播 FM 时先开播，再进全屏播放器。
  void _openFmInPlayer(List<Track> fm) {
    if (!_isFmCurrent(fm)) {
      widget.playback.playTrack(fm.first, queue: fm);
      CyreneToast.show('开始播放私人FM');
    }
    widget.onOpenPlayer();
  }

  void _openPlaylistRef(_PlaylistRef? ref) {
    if (ref == null) {
      CyreneToast.show('暂无内容，稍后刷新试试');
      return;
    }
    widget.onOpenPlaylist(ref.id, ref.name, ref.coverUrl);
  }

  void _playHistory(HistoryEntry entry) {
    final queue = _history.map(_historyToTrack).toList(growable: false);
    final track = _historyToTrack(entry);
    widget.playback.playTrack(track, queue: queue);
  }

  Track _historyToTrack(HistoryEntry entry) => Track(
    id: entry.id,
    name: entry.name,
    artists: entry.artists,
    album: entry.album,
    picUrl: entry.picUrl,
    source: MusicSource.fromWireName(entry.source),
  );

  void _openHistoryAll() {
    widget.onOpenSecondary(HistoryPage(playback: widget.playback));
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    if (body != null) {
      // 二级页模式：内容区整体让给 body（歌单详情 / 每日推荐 / 播放历史），
      // 返回首页与标题栏标题由 DesktopShell 接管，本页不再渲染首页。
      return body;
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.home,
        widget.account,
        widget.playlists,
        widget.discover,
      ]),
      builder: (context, _) {
        final state = widget.home.state;
        debugPrint(
          '[DHP] build tab=$_tab isLoading=${state.isLoading} '
          'hasContent=${state.hasContent} isBound=${state.isBound} '
          'toplists=${state.toplists.length}',
        );

        final showTabs = state.isBound;
        final tab = showTabs ? _tab : _HomeTab.leaderboard;
        if (tab == _HomeTab.recommend && state.isLoading && !state.hasContent) {
          return const Center(child: MiuixCircularProgressIndicator());
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // 超宽屏保留舒适的阅读宽度，小窗口则减小留白。
            final horizontal = math.max(
              constraints.maxWidth < 840 ? 24.0 : 36.0,
              (constraints.maxWidth - 1560) / 2,
            );
            // 榜单页与移动端同一套暖纸色底；推荐页保持原样。
            return _ChartsBackdrop(
              enabled: tab == _HomeTab.leaderboard,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: CustomScrollView(
                  key: PageStorageKey('desktop-home-${tab.name}-scroll'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        24,
                        horizontal,
                        48,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _GreetingHeader(
                            username: widget.account.state.user?.username,
                            refreshing: _refreshing || state.isRefreshing,
                            onRefresh: _refresh,
                          ),
                          const SizedBox(height: 22),
                          if (showTabs) ...[
                            _HomeTabSwitcher(
                              motion: _tabMotion,
                              selected: tab,
                              onSelected: _selectTab,
                            ),
                            const SizedBox(height: 20),
                          ],
                          // 整个滚动视图按 Tab 换 key，新内容挂载时从切换方向
                          // 淡入滑进来。
                          _TabReveal(
                            fromEnd: tab == _HomeTab.leaderboard,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: tab == _HomeTab.recommend
                                  ? _recommendSections(state)
                                  : _leaderboardSections(),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===== 为你推荐 =====

  List<Widget> _recommendSections(HomeState state) {
    final data = state.recommendations;
    if (data != null) _syncRecommendCache(data);

    final cards = <_RecCardData>[
      _RecCardData(
        tag: '每日推荐',
        title: '每日为你精选',
        subtitle: _daily.isEmpty ? '登录后每日更新' : '为你精选 ${_daily.length} 首',
        gradient: _kDailyGradient,
        artwork: _artwork[_RecSlot.daily],
        icon: Icons.album_rounded,
        onPlay: _daily.isEmpty ? null : _playDaily,
        onTap: _daily.isEmpty ? null : _openDailyDetail,
      ),
      _RecCardData(
        tag: '心情推荐',
        title: '放松时刻',
        subtitle: _relaxPlaylist?.name ?? '舒缓解压歌单',
        gradient: _kRelaxGradient,
        artwork: _artwork[_RecSlot.relax],
        icon: Icons.spa_rounded,
        onPlay: () => _openPlaylistRef(_relaxPlaylist),
        onTap: () => _openPlaylistRef(_relaxPlaylist),
      ),
      _RecCardData(
        tag: '场景推荐',
        title: '工作学习',
        subtitle: _focusPlaylist?.name ?? '专注当下歌单',
        gradient: _kFocusGradient,
        artwork: _artwork[_RecSlot.focus],
        icon: Icons.laptop_mac_rounded,
        onPlay: () => _openPlaylistRef(_focusPlaylist),
        onTap: () => _openPlaylistRef(_focusPlaylist),
      ),
      _RecCardData(
        tag: '专属推荐',
        title: '你的专属雷达',
        subtitle: _radarPlaylist?.name ?? '根据你的喜好生成',
        gradient: _kRadarGradient,
        artwork: _artwork[_RecSlot.radar],
        icon: Icons.radar_rounded,
        onPlay: () => _openPlaylistRef(_radarPlaylist),
        onTap: () => _openPlaylistRef(_radarPlaylist),
      ),
    ];

    return [
      _GradientCardRow(cards: cards),
      // 私人FM：正在播放的 FM 曲目实时跟随（结构性变更才走主通知，进度 tick
      // 走独立 ValueNotifier，故在此监听 playback 不会高频重建）。
      if (_fm.isNotEmpty) ...[
        const SizedBox(height: 28),
        ListenableBuilder(
          listenable: widget.playback,
          builder: (context, _) {
            final track = _fmDisplayTrack(_fm);
            if (track == null) return const SizedBox.shrink();
            return _PersonalFmSection(
              track: track,
              isPlaying: _isFmCurrent(_fm) && widget.playback.state.isPlaying,
              onToggle: () => _toggleFm(_fm),
              onSkip: () => _skipFm(_fm),
              onOpen: () => _openFmInPlayer(_fm),
            );
          },
        ),
      ],
      const SizedBox(height: 28),
      _RecentAndPlaylists(
        history: _history,
        playlists: widget.playlists.state.playlists,
        onPlayHistory: _playHistory,
        onOpenHistoryAll: _openHistoryAll,
        onOpenPlaylist: widget.onOpenPersonalPlaylist,
      ),
      const SizedBox(height: 28),
      _RecommendedPlaylists(
        playlists: widget.discover.state.playlists,
        // 桌面端统一并入 onOpenPlaylist（内容区二级页），与推荐卡一致。
        onOpen: (playlist) => widget.onOpenPlaylist(
          playlist.id,
          playlist.name,
          playlist.coverImgUrl,
        ),
      ),
      // 个性化新歌：把移动端才展示的第六路数据也铺到桌面。
      if (_newest.isNotEmpty) ...[
        const SizedBox(height: 28),
        _NewSongsSection(
          tracks: _newest,
          onPlay: (track, queue) =>
              widget.playback.playTrack(track, queue: queue),
        ),
      ],
    ];
  }

  // ===== 榜单 =====

  // 榜单页的派生数据缓存：播放状态每次结构性变化都会重建榜单页，
  // 只有源列表换了才重新转换曲目，DesktopChartsHome 也靠列表身份复用抽歌结果。
  List<Toplist>? _entriesSource;
  List<DesktopChartEntry> _entries = const [];
  List<SpotifyPersonalizedSection>? _sectionsSource;
  List<DesktopSpotifySection> _desktopSections = const [];
  List<HistoryEntry>? _recentSource;
  List<Track> _recent = const [];

  List<Widget> _leaderboardSections() {
    if (!identical(_entriesSource, _spotifyToplists)) {
      _entriesSource = _spotifyToplists;
      _entries = List.unmodifiable([
        for (final toplist in _spotifyToplists)
          (toplist: toplist, tracks: widget.home.tracksForToplist(toplist)),
      ]);
    }
    if (!identical(_sectionsSource, _spotifySections)) {
      _sectionsSource = _spotifySections;
      _desktopSections = List.unmodifiable([
        for (final section in _spotifySections)
          (
            id: section.id,
            title: section.title,
            description: section.description,
            kind: section.kind,
            items: section.collections,
            tracks: _toTracks(section.tracks),
          ),
      ]);
    }
    if (!identical(_recentSource, _history)) {
      _recentSource = _history;
      _recent = _history.map(_historyToTrack).toList(growable: false);
    }
    return [
      // 仅监听结构性播放状态，不订阅 position tick，封面和榜单不会每秒重建。
      ListenableBuilder(
        listenable: widget.playback,
        builder: (context, _) => DesktopChartsHome(
          entries: _entries,
          sections: _desktopSections,
          loading: _spotifyToplistsLoading,
          errorMessage: _spotifyToplistsError,
          onRetry: _loadSpotifyToplists,
          recentTracks: _recent,
          currentTrack: widget.playback.state.currentTrack,
          isPlaying: widget.playback.state.isPlaying,
          onPlay: (track, queue) =>
              widget.playback.playTrack(track, queue: queue),
          onTogglePlayback: widget.playback.togglePlay,
          onOpenPlayer: widget.onOpenPlayer,
          onOpenHistory: _openHistoryAll,
          onOpenChart: _openChart,
          onOpenItem: _openPersonalizedItem,
        ),
      ),
    ];
  }

  void _openChart(Toplist toplist) {
    if (toplist.source == MusicSource.spotify) {
      final tracks = toplist.tracks;
      widget.onOpenSecondary(
        PlaylistDetailPage(
          playlistId: toplist.externalId ?? toplist.id,
          title: toplist.name,
          coverUrl: toplist.coverImgUrl,
          playback: widget.playback,
          token: widget.account.token,
          desktopLayout: true,
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
      );
      return;
    }
    widget.onOpenPlaylist(toplist.id, toplist.name, toplist.coverImgUrl);
  }

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
}

enum _HomeTab { recommend, leaderboard }

/// 榜单页的暖纸色底。
///
/// 不用移动端的 ForYouAtmosphere：桌面内容区的 surface 是透明的（透出 Mica），
/// 它的渐变两端取 surface，会和透明黑插值出一片发灰的脏色。这里渐变两端用同一
/// 纸色、只变不透明度，顶部淡一些让 Mica 隐约透出，往下渐渐铺满。
class _ChartsBackdrop extends StatelessWidget {
  const _ChartsBackdrop({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final paper = palette.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 始终挂载、只切透明度：切到榜单时暖纸色渐渐铺开，而不是啪地出现。
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        paper.withValues(alpha: 0.55),
                        paper.withValues(alpha: 0.92),
                      ],
                      stops: const [0, 0.35],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 4 张推荐卡的位置标识，用于按卡索引已解析的动态视觉。
enum _RecSlot { daily, relax, focus, radar }

/// 桌面首页私有：时段问候语（移动端同名函数为库私有，此处自带一份）。
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
    < 18 => '愿音乐陪伴你度过美好的一天',
    _ => '夜色温柔，音乐更动听',
  };
  return (title, subtitle);
}

// 4 张推荐卡的渐变（贴近设计稿：蓝 / 粉紫 / 暖橙 / 绿）。
const _kDailyGradient = [Color(0xFF4E86E0), Color(0xFF6FA1EA)];
const _kRelaxGradient = [Color(0xFFB07CC9), Color(0xFFC792CE)];
const _kFocusGradient = [Color(0xFFD79A5B), Color(0xFFE1B279)];
const _kRadarGradient = [Color(0xFF5AA37C), Color(0xFF77B993)];

class _PlaylistRef {
  const _PlaylistRef({
    required this.id,
    required this.name,
    required this.coverUrl,
  });

  final int id;
  final String name;
  final String coverUrl;
}

class _RecCardData {
  const _RecCardData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.artwork,
    required this.icon,
    required this.onPlay,
    required this.onTap,
  });

  final String tag;
  final String title;
  final String subtitle;

  /// 设计稿配色，取色未就位（或失败）时的兜底。
  final List<Color> gradient;

  /// 随机曲目封面 + 其主题色渐变；null 表示还没解析出来。
  final RecommendArtwork? artwork;

  final IconData icon;
  final VoidCallback? onPlay;
  final VoidCallback? onTap;

  /// 实际渐变：优先用封面提取色，失败则回落设计配色。
  List<Color> get effectiveGradient => artwork?.gradient ?? gradient;
}

/// 问候头：图标 + 「下午好，用户名」+ 副标题，右侧刷新按钮。
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.username,
    required this.refreshing,
    required this.onRefresh,
  });

  final String? username;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final (greeting, subtitle) = _greetingOfNow();
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 18;
    final title = (username == null || username!.isEmpty)
        ? greeting
        : '$greeting，$username';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: const MiuixSquircleBorder(cornerRadius: 14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isNight
                  ? const [Color(0xFF5C6BC0), Color(0xFF7986CB)]
                  : const [Color(0xFFF6B44B), Color(0xFFF9C97A)],
            ),
          ),
          child: Icon(
            isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.title2.copyWith(
                  color: colors.onBackground,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        MiuixIconButton(
          enabled: !refreshing,
          onPressed: onRefresh,
          child: refreshing
              ? const MiuixInfiniteProgressIndicator(size: 18)
              : MiuixIcon(
                  icon: Icons.refresh_rounded,
                  size: 20,
                  tint: colors.onBackground,
                ),
        ),
      ],
    );
  }
}

/// 「为你推荐 / 榜单」分段切换。
///
/// 自绘的胶囊轨道 + 滑块：滑块由页面持有的 [motion]（0 → 1）驱动。移动时前沿
/// 走快曲线、后沿走慢曲线，滑块会先被拉长再收拢，像被拽过去一样；文字与图标
/// 颜色随滑块距离渐变。
class _HomeTabSwitcher extends StatelessWidget {
  const _HomeTabSwitcher({
    required this.motion,
    required this.selected,
    required this.onSelected,
  });

  final AnimationController motion;
  final _HomeTab selected;
  final ValueChanged<_HomeTab> onSelected;

  static const _pad = 4.0;
  static const _labels = ['为你推荐', '榜单'];
  static const _icons = [Icons.auto_awesome_rounded, Icons.leaderboard_rounded];

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final scaler = MediaQuery.textScalerOf(context);
    final segment = 124.0 * math.max(1.0, scaler.scale(14) / 14 * 0.9);
    final height = math.max(44.0, scaler.scale(14) * 1.4 + 24);
    const leading = Curves.easeOutCubic;
    const trailing = Curves.easeInOutCubic;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: segment * _labels.length + _pad * 2,
        height: height,
        decoration: BoxDecoration(
          color: colors.onBackground.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        // 描边放前景：写在 decoration 里会被 Container 当成内边距，吃掉 1.6px，
        // 两格按 segment 算的总宽就塞不下了，滑块位置也会和格子错开。
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: colors.onBackground.withValues(alpha: 0.06),
            width: 0.8,
          ),
        ),
        child: AnimatedBuilder(
          animation: motion,
          builder: (context, _) {
            final value = motion.value;
            // 往右走时右沿领先、左沿拖后；往左走时反过来。
            final double left;
            final double right;
            if (motion.status == AnimationStatus.reverse) {
              final q = 1 - value;
              left = 1 - leading.transform(q);
              right = 1 - trailing.transform(q);
            } else {
              left = trailing.transform(value);
              right = leading.transform(value);
            }
            return Stack(
              children: [
                Positioned(
                  left: _pad + left * segment,
                  width: segment + (right - left) * segment,
                  top: _pad,
                  bottom: _pad,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(height / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  left: _pad,
                  right: _pad,
                  child: Row(
                    children: [
                      for (var i = 0; i < _labels.length; i++)
                        SizedBox(
                          width: segment,
                          child: _HomeTabLabel(
                            label: _labels[i],
                            icon: _icons[i],
                            // 1 = 滑块正好停在这一格上。
                            emphasis: (1 - (value - i).abs()).clamp(0.0, 1.0),
                            selected: selected.index == i,
                            onPressed: () => onSelected(_HomeTab.values[i]),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeTabLabel extends StatelessWidget {
  const _HomeTabLabel({
    required this.label,
    required this.icon,
    required this.emphasis,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final double emphasis;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final text = Color.lerp(
      colors.onSurfaceVariantSummary,
      colors.onBackground,
      emphasis,
    )!;
    final glyph = Color.lerp(
      colors.onSurfaceVariantSummary,
      colors.primary,
      emphasis,
    )!;
    return Semantics(
      selected: selected,
      child: MiuixPressable(
        onPressed: onPressed,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(999),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.9 + 0.1 * emphasis,
                child: Icon(icon, size: 17, color: glyph),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    fontSize: 14,
                    // 字重不做插值（会抖动字宽），过半才加粗。
                    fontWeight: emphasis > 0.5
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab 内容挂载时的入场：淡入并从切换方向滑进来，只在挂载时播一次。
/// [child] 走 TweenAnimationBuilder 的 child 参数，动画期间不重建内容。
class _TabReveal extends StatelessWidget {
  const _TabReveal({required this.fromEnd, required this.child});

  final bool fromEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 460),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset((fromEnd ? 28 : -28) * (1 - t), 0),
        child: child,
      ),
    ),
  );
}

/// 4 张渐变推荐卡横向等宽排列。窄到放不下时横向滚动。
class _GradientCardRow extends StatelessWidget {
  const _GradientCardRow({required this.cards});

  final List<_RecCardData> cards;

  static const _cardHeight = 188.0;
  static const _minCardWidth = 232.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        debugPrint('[DHP] _GradientCardRow layout maxWidth=$total');
        final fitWidth = (total - _gap * (cards.length - 1)) / cards.length;
        // 等宽能满足最小宽度：一行铺满；否则横向滚动固定宽卡片。
        if (fitWidth >= _minCardWidth) {
          return SizedBox(
            height: _cardHeight,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Expanded(child: _GradientCard(data: cards[i])),
                ],
              ],
            ),
          );
        }
        // 刻意不用惰性 ListView：见本文件顶部关于 Windows 无障碍桥崩溃的说明。
        return SizedBox(
          height: _cardHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  SizedBox(
                    width: _minCardWidth,
                    child: _GradientCard(data: cards[i]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 推荐卡：左侧为封面提取的主题色，向右丝滑过渡到专辑封面本身。
///
/// 封面并非贴在右半边、而是整张铺满后由 [_FadedCover] 从左侧渐隐——单点硬切
/// 会在卡上留下一条可见竖边，长过渡带才「化」得开。取色未就位时退回设计配色，
/// 两者之间用 [AnimatedContainer] 补间，故首帧到落定不会有色块跳变。
class _GradientCard extends StatelessWidget {
  const _GradientCard({required this.data});

  final _RecCardData data;

  static const _colorFade = Duration(milliseconds: 620);
  static const _coverFade = Duration(milliseconds: 520);

  @override
  Widget build(BuildContext context) {
    final artwork = data.artwork;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return MiuixPressable(
      onPressed: data.onTap ?? () {},
      feedbackType: MiuixPressFeedbackType.sink,
      shape: const MiuixSquircleBorder(cornerRadius: 20),
      child: AnimatedContainer(
        duration: _colorFade,
        curve: Curves.easeOutCubic,
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          shape: const MiuixSquircleBorder(cornerRadius: 20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: data.effectiveGradient,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 右下角大号半透明装饰图标，营造场景氛围。位置在封面层之下，
            // 封面就位后自然被盖掉，只在无封面时露出来兜底。
            Positioned(
              right: -14,
              bottom: -14,
              child: Icon(
                data.icon,
                size: 104,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            // 封面层始终挂载（未就位时是一个空占位）：若改成 `if (artwork != null)`
            // 条件插入，AnimatedSwitcher 的首个 child 不会执行入场动画，封面会在
            // 底色还在补间时「啪」地出现。空 → 封面也当作一次切换，才是渐显。
            LayoutBuilder(
              builder: (context, constraints) {
                final width =
                    constraints.maxWidth.isFinite && constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : 240.0;
                return AnimatedSwitcher(
                  duration: _coverFade,
                  // 默认 layoutBuilder 的 Stack 只给松约束，BoxFit.cover 会缩成
                  // 原图尺寸；换封面时两张图需要同时铺满做交叉淡入。
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: artwork == null
                      ? const SizedBox.expand(key: ValueKey('no-artwork'))
                      : _FadedCover(
                          key: ValueKey(artwork.coverUrl),
                          url: artwork.coverUrl,
                          decodeWidth: coverDecodeWidth(width, dpr),
                        ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: ShapeDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      data.tag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CardPlayButton(onPressed: data.onPlay),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 铺满卡片的封面，左侧用长过渡带渐隐，让下层主题色「长」进封面里。
///
/// 用 [ShaderMask] 而不是叠一层同色渐变遮罩：叠色只能在纯色底上还原目标色，
/// 而这里底色是斜向渐变，叠出来会脏；直接擦掉封面的 alpha 才能露出真正的底。
class _FadedCover extends StatelessWidget {
  const _FadedCover({super.key, required this.url, required this.decodeWidth});

  final String url;
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        // 左 38% 全透明留给主题色，38%→86% 是过渡带，之后是完整封面。
        colors: [Color(0x00000000), Color(0x00000000), Color(0xFF000000)],
        stops: [0, 0.38, 0.86],
      ).createShader(bounds),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            httpHeaders: imageHeaders(url),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            memCacheWidth: decodeWidth,
            // 卡片已有底色，加载中/失败都不必再画占位，留空即可。
            placeholder: (_, _) => const SizedBox.expand(),
            errorWidget: (_, _, _) => const SizedBox.expand(),
          ),
          // 底部压暗，保证副标题与播放按钮在浅色封面（白底专辑）上仍可读；
          // 放在 mask 内部，跟封面一起被擦掉，否则会在左侧纯色区留一道暗影。
          // 只压底部，卡片右上角的封面得以保持原本的鲜艳。
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x66000000), Color(0x00000000)],
                stops: [0, 0.6],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPlayButton extends StatelessWidget {
  const _CardPlayButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.24),
          shape: const CircleBorder(),
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

/// 双栏：左「最近播放」横向卡列 + 右「你的歌单」竖列。窄屏则上下堆叠。
class _RecentAndPlaylists extends StatelessWidget {
  const _RecentAndPlaylists({
    required this.history,
    required this.playlists,
    required this.onPlayHistory,
    required this.onOpenHistoryAll,
    required this.onOpenPlaylist,
  });

  final List<HistoryEntry> history;
  final List<Playlist> playlists;
  final void Function(HistoryEntry entry) onPlayHistory;
  final VoidCallback onOpenHistoryAll;
  final void Function(Playlist playlist) onOpenPlaylist;

  static const _rightWidth = 340.0;
  static const _stackBreakpoint = 780.0;

  @override
  Widget build(BuildContext context) {
    final recent = _RecentlyPlayed(
      history: history,
      onPlay: onPlayHistory,
      onOpenAll: onOpenHistoryAll,
    );
    final yours = _YourPlaylists(playlists: playlists, onOpen: onOpenPlaylist);

    return LayoutBuilder(
      builder: (context, constraints) {
        debugPrint(
          '[DHP] _RecentAndPlaylists layout maxWidth=${constraints.maxWidth}',
        );
        if (constraints.maxWidth < _stackBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [recent, const SizedBox(height: 24), yours],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: recent),
            const SizedBox(width: 28),
            SizedBox(width: _rightWidth, child: yours),
          ],
        );
      },
    );
  }
}

class _RecentlyPlayed extends StatelessWidget {
  const _RecentlyPlayed({
    required this.history,
    required this.onPlay,
    required this.onOpenAll,
  });

  final List<HistoryEntry> history;
  final void Function(HistoryEntry entry) onPlay;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    debugPrint('[DHP2] _RecentlyPlayed.build history=${history.length}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: '最近播放', onViewAll: onOpenAll),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const _EmptyHint(
            icon: Icons.history_rounded,
            text: '还没有播放记录，去听点什么吧',
            compact: true,
          )
        else
          SizedBox(
            height: 178,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < history.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    _RecentCard(
                      entry: history[i],
                      onPlay: () => onPlay(history[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.entry, required this.onPlay});

  final HistoryEntry entry;
  final VoidCallback onPlay;

  static const _size = 128.0;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SizedBox(
      width: _size,
      child: MiuixPressable(
        onPressed: onPlay,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _Cover(url: entry.picUrl, size: _size, cornerRadius: 14),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: theme.colors.primary,
                      shape: const CircleBorder(),
                      shadows: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: theme.colors.onPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.onBackground,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.artists,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YourPlaylists extends StatelessWidget {
  const _YourPlaylists({required this.playlists, required this.onOpen});

  final List<Playlist> playlists;
  final void Function(Playlist playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    debugPrint('[DHP2] _YourPlaylists.build playlists=${playlists.length}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: '你的歌单',
          onViewAll: playlists.isEmpty
              ? null
              : () => CyreneToast.show('在「我的」查看全部歌单'),
        ),
        const SizedBox(height: 12),
        if (playlists.isEmpty)
          const _EmptyHint(
            icon: Icons.queue_music_rounded,
            text: '登录后同步你的歌单',
            compact: true,
          )
        else
          MiuixCard(
            cornerRadius: 18,
            insideMargin: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < playlists.length && i < 6; i++)
                  _PlaylistRow(
                    playlist: playlists[i],
                    accentIndex: i,
                    onTap: () => onOpen(playlists[i]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.accentIndex,
    required this.onTap,
  });

  final Playlist playlist;
  final int accentIndex;
  final VoidCallback onTap;

  // 无封面歌单的兜底彩色图标（心/叶/月……），循环取用。
  static const _fallbacks = [
    (Icons.favorite_rounded, [Color(0xFFEF6D8A), Color(0xFFF48FA5)]),
    (Icons.eco_rounded, [Color(0xFF5AA37C), Color(0xFF7BBE97)]),
    (Icons.nightlight_round, [Color(0xFF5C6BC0), Color(0xFF8189D6)]),
    (Icons.music_note_rounded, [Color(0xFF4E86E0), Color(0xFF74A3EA)]),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    debugPrint('[DHP2] _PlaylistRow.build "${playlist.name}"');
    final cover = playlist.coverUrl;
    final (icon, gradient) = _fallbacks[accentIndex % _fallbacks.length];

    return MiuixPressable(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (cover != null && cover.isNotEmpty)
              _Cover(url: cover, size: 46, cornerRadius: 12)
            else
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  shape: const MiuixSquircleBorder(cornerRadius: 12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.body2.copyWith(
                      color: theme.colors.onSurfaceContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.trackCount} 首歌曲',
                    style: theme.textStyles.footnote1.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            MiuixIcon(
              icon: Icons.more_horiz_rounded,
              size: 20,
              tint: theme.colors.onSurfaceVariantActions,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedPlaylists extends StatelessWidget {
  const _RecommendedPlaylists({required this.playlists, required this.onOpen});

  final List<DiscoveryPlaylist> playlists;
  final void Function(DiscoveryPlaylist playlist) onOpen;

  @override
  Widget build(BuildContext context) {
    debugPrint('[DHP2] _RecommendedPlaylists.build count=${playlists.length}');
    if (playlists.isEmpty) return const SizedBox.shrink();
    // 横向条改用非惰性的 SingleChildScrollView + Row（原因见类文档），故必须
    // 自己限量：发现页会给到 50 条，全量铺开等于一次创建 50 张卡与 50 个封面。
    final shown = playlists.take(18).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '推荐歌单'),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  _DiscoverPlaylistCard(
                    playlist: shown[i],
                    onTap: () => onOpen(shown[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoverPlaylistCard extends StatelessWidget {
  const _DiscoverPlaylistCard({required this.playlist, required this.onTap});

  final DiscoveryPlaylist playlist;
  final VoidCallback onTap;

  static const _size = 148.0;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SizedBox(
      width: _size,
      child: MiuixPressable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(url: playlist.coverImgUrl, size: _size, cornerRadius: 14),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.onBackground,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 私人FM区块（桌面）：显示当前 FM 曲目 + 播放/暂停 + 跳过，整卡可点进
/// 全屏播放器。只读 [playback] 的结构性变更（切歌/播放暂停），经父级
/// ListenableBuilder 订阅，进度 tick 走独立 ValueNotifier 不触发重建。
class _PersonalFmSection extends StatelessWidget {
  const _PersonalFmSection({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '私人FM'),
        const SizedBox(height: 12),
        MiuixCard(
          cornerRadius: 20,
          insideMargin: const EdgeInsets.all(16),
          onPressed: onOpen,
          feedbackType: MiuixPressFeedbackType.sink,
          child: Row(
            children: [
              _Cover(url: track.picUrl, size: 148, cornerRadius: 14),
              const SizedBox(width: 18),
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
                    const SizedBox(height: 4),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body2.copyWith(
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
        ),
      ],
    );
  }
}

/// 个性化新歌区块（桌面）：横向新歌卡片列。遵守本文件「横向条不用
/// ListView」（无障碍桥缺陷），故限量 + SingleChildScrollView + Row。
class _NewSongsSection extends StatelessWidget {
  const _NewSongsSection({required this.tracks, required this.onPlay});

  final List<Track> tracks;
  final void Function(Track track, List<Track> queue) onPlay;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final shown = tracks.take(18).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '个性化新歌'),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  _NewSongCard(
                    track: shown[i],
                    onTap: () => onPlay(shown[i], tracks),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 个性化新歌单卡：封面 + 歌名/歌手，点击即播放（整组作为队列）。
class _NewSongCard extends StatelessWidget {
  const _NewSongCard({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  static const _size = 148.0;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SizedBox(
      width: _size,
      child: MiuixPressable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(url: track.picUrl, size: _size, cornerRadius: 14),
            const SizedBox(height: 8),
            Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.onBackground,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artists,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 区块标题 + 可选「查看全部」。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onViewAll});

  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    debugPrint('[DHP2] _SectionHeader.build "$title"');
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textStyles.headline1.copyWith(
              color: theme.colors.onBackground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onViewAll != null)
          MiuixPressable(
            onPressed: onViewAll!,
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
                    icon: Icons.chevron_right_rounded,
                    size: 16,
                    tint: theme.colors.onSurfaceVariantActions,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.text,
    this.compact = false,
  });

  final IconData icon;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    debugPrint('[DHP2] _EmptyHint.build "$text"');
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: compact ? 32 : 56),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: theme.colors.onSurfaceVariantSummary),
          const SizedBox(height: 10),
          Text(
            text,
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }
}

/// squircle 圆角网络封面（自带一份，与移动端首页的私有封面组件无耦合）。
/// [size] 为空时填满父约束；按显示宽降采样解码，避免大图拖累滚动。
class _Cover extends StatelessWidget {
  const _Cover({required this.url, this.size, this.cornerRadius = 14});

  final String url;
  final double? size;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    debugPrint('[DHP2] _Cover.build size=$size urlLen=${url.length}');
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
      memCacheWidth: coverDecodeWidth(decodeWidth, dpr),
      errorWidget: (_, _, _) => fallback,
    );
    final Widget image = url.isEmpty
        ? fallback
        : (size != null
              ? buildImage(size!)
              : LayoutBuilder(
                  builder: (context, constraints) => buildImage(
                    constraints.maxWidth.isFinite && constraints.maxWidth > 0
                        ? constraints.maxWidth
                        : 160,
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
