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
import '../../presentation/cyrene/cyrene_toast.dart';
import '../history/history_page.dart';
import '../playlist/playlist_detail_page.dart';
import 'daily_recommend_page.dart';
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
/// 六段式（自上而下）：问候头 → 「为你推荐 / 榜单」切换 → 4 张渐变推荐卡 →
/// 「最近播放 + 你的歌单」双栏 → 推荐歌单。数据全部复用外壳已持有的
/// controller（[home]/[discover]/[playlists]/[account]/[playback]）。
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

class _DesktopHomePageState extends State<DesktopHomePage> {
  var _tab = _HomeTab.recommend;
  var _leaderboardSource = _LeaderboardSource.netease;
  List<Toplist> _spotifyToplists = const [];
  bool _spotifyToplistsLoading = false;
  String? _spotifyToplistsError;
  int _spotifyLoadGeneration = 0;
  String? _loadedToken;

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
  }

  @override
  void dispose() {
    _spotifyLoadGeneration++;
    widget.account.removeListener(_onAccountChanged);
    widget.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  Future<void> _selectLeaderboardSource(_LeaderboardSource source) async {
    if (_leaderboardSource == source) return;
    setState(() => _leaderboardSource = source);
    if (source == _LeaderboardSource.spotify && _spotifyToplists.isEmpty) {
      await _loadSpotifyToplists();
    }
  }

  Future<void> _loadSpotifyToplists() async {
    if (_spotifyToplistsLoading) return;
    final generation = ++_spotifyLoadGeneration;
    setState(() {
      _spotifyToplistsLoading = true;
      _spotifyToplistsError = null;
    });
    final toplists = await DiscoveryService.instance.getSpotifyToplists();
    if (!mounted || generation != _spotifyLoadGeneration) return;
    setState(() {
      _spotifyToplists = toplists;
      _spotifyToplistsLoading = false;
      if (toplists.isEmpty) {
        _spotifyToplistsError = 'Spotify 榜单暂时不可用，请确认后端与 spotify-streamer 已启动';
      }
    });
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

  /// 刷新：除了重拉数据，还要重抽推荐卡封面（同一份推荐数据换一张封面）。
  Future<void> _refresh() {
    _artworkBatch++;
    _recommendCacheSource = null;
    _artwork.clear();
    return widget.home.refresh();
  }

  void _loadAll() {
    widget.home.load(token: _loadedToken).then((_) {
      if (!mounted) return;
      setState(() {
        _tab = widget.home.state.isBound
            ? _HomeTab.recommend
            : _HomeTab.leaderboard;
      });
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
      DailyRecommendPage(tracks: _daily, playback: widget.playback),
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

        if (state.isLoading && !state.hasContent) {
          return const Center(child: MiuixCircularProgressIndicator());
        }

        final showTabs = state.isBound;
        final tab = showTabs ? _tab : _HomeTab.leaderboard;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: CustomScrollView(
            key: const PageStorageKey('desktop-home-scroll'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _GreetingHeader(
                      username: widget.account.state.user?.username,
                      refreshing: state.isRefreshing,
                      onRefresh: _refresh,
                    ),
                    const SizedBox(height: 22),
                    _TabBar(
                      showTabs: showTabs,
                      selected: tab,
                      onSelected: (value) => setState(() => _tab = value),
                    ),
                    const SizedBox(height: 20),
                    if (tab == _HomeTab.recommend)
                      ..._recommendSections(state)
                    else
                      ..._leaderboardSections(state),
                  ]),
                ),
              ),
            ],
          ),
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

  List<Widget> _leaderboardSections(HomeState state) {
    final isSpotify = _leaderboardSource == _LeaderboardSource.spotify;
    final toplists = isSpotify ? _spotifyToplists : state.toplists;
    debugPrint('[DHP] _leaderboardSections toplists=${toplists.length}');
    return [
      _LeaderboardDashboard(
        source: _leaderboardSource,
        loading: isSpotify && _spotifyToplistsLoading,
        errorMessage: isSpotify ? _spotifyToplistsError : null,
        onRetry: isSpotify ? _loadSpotifyToplists : null,
        onSourceChanged: _selectLeaderboardSource,
        entries: [
          for (final toplist in toplists)
            (toplist: toplist, tracks: widget.home.tracksForToplist(toplist)),
        ],
        onPlay: (track, queue) =>
            widget.playback.playTrack(track, queue: queue),
        onOpen: (toplist) {
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
        },
      ),
    ];
  }
}

enum _HomeTab { recommend, leaderboard }

enum _LeaderboardSource { netease, spotify }

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

/// 「为你推荐 / 榜单」切换 + 右侧「自定义推荐」按钮。
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.showTabs,
    required this.selected,
    required this.onSelected,
  });

  final bool showTabs;
  final _HomeTab selected;
  final ValueChanged<_HomeTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    debugPrint('[DHP] _TabBar.build showTabs=$showTabs');
    return Row(
      children: [
        if (showTabs)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: MiuixTabRowWithContour(
                tabs: const ['为你推荐', '榜单'],
                selectedTabIndex: selected == _HomeTab.recommend ? 0 : 1,
                contentAlignment: AlignmentDirectional.centerStart,
                onTabSelected: (index) => onSelected(
                  index == 0 ? _HomeTab.recommend : _HomeTab.leaderboard,
                ),
              ),
            ),
          )
        else
          const Spacer(),
        MiuixPressable(
          onPressed: () => CyreneToast.show('自定义推荐即将上线'),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: ShapeDecoration(
              color: theme.colors.secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiuixIcon(
                  icon: Icons.tune_rounded,
                  size: 16,
                  tint: theme.colors.onSurfaceContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  '自定义推荐',
                  style: theme.textStyles.footnote1.copyWith(
                    color: theme.colors.onSurfaceContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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

/// 榜单区块（桌面）：标题 + 「查看全部」+ 前 5 首歌曲行。
typedef _LeaderboardEntry = ({Toplist toplist, List<Track> tracks});

class _LeaderboardDashboard extends StatelessWidget {
  const _LeaderboardDashboard({
    required this.entries,
    required this.onPlay,
    required this.onOpen,
    required this.source,
    required this.onSourceChanged,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
  });

  final List<_LeaderboardEntry> entries;
  final void Function(Track track, List<Track> queue) onPlay;
  final ValueChanged<Toplist> onOpen;
  final _LeaderboardSource source;
  final ValueChanged<_LeaderboardSource> onSourceChanged;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '热门榜单',
                    style: theme.textStyles.headline1.copyWith(
                      color: theme.colors.onBackground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    source == _LeaderboardSource.spotify
                        ? '探索 Spotify 全球与地区热门音乐'
                        : '实时发现正在流行的音乐与高热度作品',
                    style: theme.textStyles.body2.copyWith(
                      color: theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 158,
              child: MiuixWindowDropdownMenu(
                title: source == _LeaderboardSource.spotify
                    ? 'Spotify'
                    : '网易云音乐',
                insideMargin: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                entry: MiuixDropdownEntry(
                  items: [
                    MiuixDropdownItem(
                      text: '网易云音乐',
                      selected: source == _LeaderboardSource.netease,
                      onClick: () =>
                          onSourceChanged(_LeaderboardSource.netease),
                    ),
                    MiuixDropdownItem(
                      text: 'Spotify',
                      selected: source == _LeaderboardSource.spotify,
                      onClick: () =>
                          onSourceChanged(_LeaderboardSource.spotify),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (loading)
          const SizedBox(
            height: 220,
            child: Center(child: MiuixCircularProgressIndicator()),
          )
        else if (entries.isEmpty)
          Column(
            children: [
              _EmptyHint(
                icon: Icons.emoji_events_outlined,
                text: errorMessage ?? '暂无榜单内容，稍后刷新再试',
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                MiuixButton(onPressed: onRetry, child: const MiuixText('重新加载')),
              ],
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 18.0;
              final columns = constraints.maxWidth >= 980 ? 2 : 1;
              final cardWidth = columns == 2
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final entry in entries)
                    SizedBox(
                      width: cardWidth,
                      child: _LeaderboardCard(
                        entry: entry,
                        onPlay: onPlay,
                        onOpen: () => onOpen(entry.toplist),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({
    required this.entry,
    required this.onPlay,
    required this.onOpen,
  });

  final _LeaderboardEntry entry;
  final void Function(Track track, List<Track> queue) onPlay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final toplist = entry.toplist;
    final tracks = entry.tracks;
    final visibleTracks = tracks.take(4).toList(growable: false);
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(url: toplist.coverImgUrl, size: 104, cornerRadius: 16),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 104,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        toplist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.title4.copyWith(
                          color: colors.onSurfaceContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        toplist.description.trim().isEmpty
                            ? '精选当下热门歌曲'
                            : toplist.description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.footnote1.copyWith(
                          color: colors.onSurfaceVariantSummary,
                          height: 1.35,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          _LeaderboardAction(
                            icon: Icons.play_arrow_rounded,
                            label: '播放',
                            primary: true,
                            onPressed: tracks.isEmpty
                                ? null
                                : () => onPlay(tracks.first, tracks),
                          ),
                          const SizedBox(width: 8),
                          _LeaderboardAction(
                            icon: Icons.open_in_new_rounded,
                            label: '查看',
                            onPressed: onOpen,
                          ),
                          const Spacer(),
                          Text(
                            '${tracks.length} 首',
                            style: theme.textStyles.footnote1.copyWith(
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (index, track) in visibleTracks.indexed)
            _LeaderboardTrackRow(
              rank: index + 1,
              track: track,
              onPressed: () => onPlay(track, tracks),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardAction extends StatelessWidget {
  const _LeaderboardAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixButton(
      onPressed: onPressed,
      minWidth: 0,
      minHeight: 30,
      cornerRadius: 10,
      insideMargin: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      colors: primary ? MiuixButtonDefaults.buttonColorsPrimary(context) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiuixIcon(icon: icon, size: 15),
          const SizedBox(width: 5),
          MiuixText(
            label,
            style: theme.textStyles.footnote1.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTrackRow extends StatelessWidget {
  const _LeaderboardTrackRow({
    required this.rank,
    required this.track,
    required this.onPressed,
  });

  final int rank;
  final Track track;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixPressable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                rank.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: theme.textStyles.footnote1.copyWith(
                  color: rank <= 3
                      ? colors.primary
                      : colors.onSurfaceVariantSummary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _Cover(url: track.picUrl, size: 38, cornerRadius: 9),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.body2.copyWith(
                      color: colors.onSurfaceContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote1.copyWith(
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.footnote1.copyWith(
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MiuixIcon(
              icon: Icons.play_arrow_rounded,
              size: 18,
              tint: colors.onSurfaceVariantActions,
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
