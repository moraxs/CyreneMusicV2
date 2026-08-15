import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/discovery_service.dart';
import '../../infrastructure/services/playlist_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../player/cyrene_track_tile.dart';
import '../player/mobile/compat/color_extraction_service.dart';
import '../player/track_action_menu.dart';
import '../player/track_artwork.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.title,
    required this.coverUrl,
    required this.playback,
    this.token,
    this.onOpenPlaylist,
    this.desktopLayout = false,
    this.source = MusicSource.netease,
    this.creator,
    this.trackCount = 0,
    this.initialPlaylist,
    this.reloadable = true,
  }) : isPersonal = false;

  /// 个人歌单模式：曲目走 Cyrene 后端 `/playlists/:id/tracks`（需 [token]）。
  const PlaylistDetailPage.personal({
    super.key,
    required this.playlistId,
    required this.title,
    required this.coverUrl,
    required this.playback,
    required String this.token,
    this.trackCount = 0,
    this.creator,
    this.onOpenPlaylist,
    this.desktopLayout = false,
    this.source = MusicSource.netease,
    this.initialPlaylist,
    this.reloadable = true,
  }) : isPersonal = true;

  final Object playlistId;
  final String title;
  final String coverUrl;
  final String? creator;
  final PlaybackController playback;
  final String? token;
  final bool isPersonal;
  final int trackCount;
  final MusicSource source;
  final PlaylistDetail? initialPlaylist;
  final bool reloadable;

  /// 桌面端使用居中限宽与紧凑顶栏；默认关闭以完整保留移动端布局。
  final bool desktopLayout;

  /// 详情页内再打开歌单（如个人歌单里关联的在线歌单）时的跳转回调。桌面端
  /// 由外壳提供并压入首页二级页导航栈（见 `desktop_shell.dart`），支持逐级
  /// 向下钻取；null（移动端）则回退为整窗 push 路由。
  final void Function(int id, String title, String coverUrl)? onOpenPlaylist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

/// 歌单曲目排序方式。`default` 反转歌单原始顺序（最后一首在前）。
enum PlaylistSortMode {
  defaultOrder('默认排序'),
  titleAsc('歌名 A-Z'),
  titleDesc('歌名 Z-A');

  const PlaylistSortMode(this.label);
  final String label;
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  PlaylistDetail? _playlist;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isSyncing = false;
  int _loadGeneration = 0;
  List<Track> _tracks = const [];
  Color? _extractedThemeColor;

  /// 是否展开歌单内搜索框；关闭时清空关键词与输入控制器。
  bool _searching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  /// 当前排序方式；默认保持歌单原始顺序。
  PlaylistSortMode _sortMode = PlaylistSortMode.defaultOrder;

  @override
  void initState() {
    super.initState();
    _playlist = widget.initialPlaylist ??
        PlaylistDetail(
          id: widget.playlistId is int
              ? widget.playlistId as int
              : (int.tryParse(widget.playlistId.toString()) ?? 0),
          name: widget.title,
          coverImgUrl: widget.coverUrl,
          description: '',
          tracks: const [],
          source: widget.source,
          playCount: 0,
          creator: widget.creator ?? '',
          trackCount: widget.trackCount,
          createTime: 0,
          updateTime: 0,
          tags: const [],
        );
    _tracks = _mapTracks(widget.initialPlaylist);
    _isLoading = widget.initialPlaylist == null;
    _triggerColorExtraction();
    if (widget.initialPlaylist == null) _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 按当前搜索关键词过滤后的歌曲列表（歌名/歌手/专辑不区分大小写包含匹配）。
  /// 关键词为空时直接返回全部歌曲，避免无谓的拷贝。
  List<Track> get _filteredTracks {
    final query = _searchQuery.trim();
    if (query.isEmpty) return _tracks;
    final lower = query.toLowerCase();
    return _tracks
        .where(
          (t) =>
              t.name.toLowerCase().contains(lower) ||
              t.artists.toLowerCase().contains(lower) ||
              t.album.toLowerCase().contains(lower),
        )
        .toList(growable: false);
  }

  /// 过滤后再按当前排序方式排序后的最终列表，供列表渲染与「播放全部」使用。
  /// 默认排序时反转歌单原始顺序（最后一首在前），其余按歌名升/降序。
  List<Track> get _sortedTracks {
    final filtered = _filteredTracks;
    if (filtered.isEmpty) return filtered;
    if (_sortMode == PlaylistSortMode.defaultOrder) {
      return filtered.reversed.toList(growable: false);
    }
    if (filtered.length == 1) return filtered;
    final sorted = [...filtered];
    sorted.sort((a, b) {
      // 按歌名排序，不区分大小写；歌名相同则退回原始相对顺序（sort 稳定）。
      final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sortMode == PlaylistSortMode.titleAsc ? cmp : -cmp;
    });
    return sorted;
  }

  void _toggleSearch() {
    if (_searching) {
      _closeSearch();
    } else {
      setState(() => _searching = true);
      // 展开后自动聚焦输入框，省一次点击。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _searching = false;
      _searchQuery = '';
    });
  }

  /// 弹出排序方式选择抽屉。选中后立即应用并刷新列表。
  Future<void> _openSortSheet(BuildContext context) async {
    final selected = await showCyreneSheet<PlaylistSortMode>(
      context: context,
      title: '排序方式',
      builder: (sheetContext, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in PlaylistSortMode.values)
            MiuixRadioButtonPreference(
              title: mode.label,
              selected: mode == _sortMode,
              onClick: () => dismiss(mode),
            ),
        ],
      ),
    );
    if (selected != null && selected != _sortMode && mounted) {
      setState(() => _sortMode = selected);
    }
  }

  Future<void> _load() async {
    if (!widget.reloadable && widget.initialPlaylist != null) {
      setState(() {
        _playlist = widget.initialPlaylist;
        _tracks = _mapTracks(widget.initialPlaylist);
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fetched = widget.isPersonal
          ? await _loadPersonal()
          : await DiscoveryService.instance.getPlaylistDetail(
              widget.playlistId,
              token: widget.token,
              source: widget.source.wireName,
            );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (fetched != null) {
          final mergedName = (fetched.name.isNotEmpty && fetched.name != '酷狗歌单')
              ? fetched.name
              : (widget.title.isNotEmpty ? widget.title : fetched.name);
          final mergedCover = fetched.coverImgUrl.isNotEmpty
              ? fetched.coverImgUrl
              : widget.coverUrl;
          final mergedCreator = (fetched.creator.isNotEmpty && fetched.creator != '酷狗音乐')
              ? fetched.creator
              : (widget.creator?.isNotEmpty == true ? widget.creator! : fetched.creator);
          final mergedTrackCount = fetched.trackCount > 0
              ? fetched.trackCount
              : (widget.trackCount > 0
                  ? widget.trackCount
                  : fetched.tracks.length);

          _playlist = PlaylistDetail(
            id: fetched.id != 0
                ? fetched.id
                : (widget.playlistId is int
                    ? widget.playlistId as int
                    : (int.tryParse(widget.playlistId.toString()) ?? 0)),
            name: mergedName,
            coverImgUrl: mergedCover,
            description: fetched.description,
            tracks: fetched.tracks,
            source: fetched.source ?? widget.source,
            playCount: fetched.playCount,
            creator: mergedCreator,
            trackCount: mergedTrackCount,
            createTime: fetched.createTime,
            updateTime: fetched.updateTime,
            tags: fetched.tags,
          );
          _triggerColorExtraction();
        }
        _tracks = _mapTracks(_playlist);
        _isLoading = false;
        if (fetched == null && _tracks.isEmpty) {
          _errorMessage = '未能获取这个歌单，请稍后重试。';
        }
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        if (_tracks.isEmpty) {
          _errorMessage = '歌单加载失败，请检查网络后重试。';
        }
      });
    }
  }

  void _triggerColorExtraction() {
    final cover = _playlist?.coverImgUrl.isNotEmpty == true
        ? _playlist!.coverImgUrl
        : widget.coverUrl;
    if (cover.isEmpty) return;

    final cached = ColorExtractionService().getCachedColors(cover);
    if (cached?.themeColor != null) {
      _extractedThemeColor = cached!.themeColor;
      return;
    }

    final gen = _loadGeneration;
    ColorExtractionService()
        .extractColorsFromUrl(cover, sampleSize: 32)
        .then((result) {
      if (!mounted || gen != _loadGeneration) return;
      if (result?.themeColor != null &&
          result!.themeColor != _extractedThemeColor) {
        setState(() {
          _extractedThemeColor = result.themeColor;
        });
      }
    });
  }

  /// 加载个人歌单曲目并组装为 [PlaylistDetail]（元信息来自跳转参数）。
  Future<PlaylistDetail> _loadPersonal() async {
    final tracks = await PlaylistService.instance.getPlaylistTracks(
      widget.token!,
      widget.playlistId as int,
    );
    return PlaylistDetail(
      id: widget.playlistId as int,
      name: widget.title,
      coverImgUrl: widget.coverUrl,
      description: '',
      creator: '',
      playCount: 0,
      trackCount: tracks.length,
      createTime: 0,
      updateTime: 0,
      tags: const [],
      tracks: tracks.map(_playlistTrackToToplist).toList(growable: false),
    );
  }

  ToplistTrack _playlistTrackToToplist(PlaylistTrack t) => ToplistTrack(
    id: t.trackId,
    name: t.name,
    artists: t.artists,
    album: t.album,
    picUrl: t.picUrl,
    source: t.source,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.desktopLayout) {
      return CyrenePage(
        title: '',
        largeTitle: false,
        actions: [
          MiuixIconButton(
            key: const Key('playlist-search-button'),
            onPressed: _toggleSearch,
            child: MiuixIcon(
              vector:
                  MiuixIcons.extended.byName(_searching ? 'close' : 'search')!,
              size: 20,
            ),
          ),
        ],
        bodyBuilder: (context, topPadding) => _buildBody(topPadding),
      );
    }

    return MiuixScaffold(
      containerColor: Colors.transparent,
      content: (_) => Material(
        type: MaterialType.transparency,
        child: _buildBody(EdgeInsets.zero),
      ),
    );
  }

  Future<void> _syncToAccount(BuildContext context) async {
    final token = widget.token;
    if (token == null || token.isEmpty) return;
    List<Playlist> playlists;
    try {
      playlists = await PlaylistService.instance.getPlaylists(token);
    } catch (_) {
      CyreneToast.show('获取歌单列表失败，请稍后重试');
      return;
    }
    if (!context.mounted) return;
    if (playlists.isEmpty) {
      CyreneToast.show('还没有可同步的歌单，请先在「我的」中创建');
      return;
    }
    final target = await showCyreneSheet<Playlist>(
      context: context,
      title: '同步到哪个歌单？',
      builder: (context, dismiss) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final playlist in playlists)
              CyreneMenuRow(
                icon: playlist.isDefault
                    ? Icons.favorite_rounded
                    : Icons.queue_music_rounded,
                title: playlist.name,
                subtitle: '${playlist.trackCount} 首',
                onTap: () => dismiss(playlist),
              ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    setState(() => _isSyncing = true);
    try {
      final bound = await PlaylistService.instance.bindImportConfig(
        token,
        target.id,
        source: widget.source.wireName,
        sourcePlaylistId: widget.playlistId.toString(),
      );
      if (!bound) {
        CyreneToast.show('绑定来源失败，请稍后重试');
        return;
      }
      final result = await PlaylistService.instance.syncPlaylist(
        token,
        target.id,
      );
      if (result == null) {
        CyreneToast.show('同步失败，请稍后重试');
        return;
      }
      CyreneToast.show(
        result.insertedCount > 0
            ? '已同步到「${target.name}」，新增 ${result.insertedCount} 首'
            : '已同步到「${target.name}」，暂无新增歌曲',
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildBody(EdgeInsets topPadding) {
    final theme = MiuixTheme.of(context);
    final isDesktop = widget.desktopLayout;
    final canPop = Navigator.of(context).canPop();

    if (_errorMessage != null && _tracks.isEmpty) {
      final emptyState = CyreneEmptyState(
        icon: Icons.cloud_off,
        title: '歌单暂时不可用',
        description: _errorMessage!,
        action: MiuixButton(
          onPressed: _load,
          child: MiuixText(
            '重试',
            style: theme.textStyles.button,
          ),
        ),
      );
      if (isDesktop) return emptyState;
      return SafeArea(
        child: Column(
          children: [
            if (canPop)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CyreneBackButton(
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
              ),
            Expanded(child: emptyState),
          ],
        ),
      );
    }

    final playlist = _playlist!;
    final allTracks = _tracks;
    final tracks = _sortedTracks;
    final isFiltering = _searchQuery.trim().isNotEmpty;
    final cover = playlist.coverImgUrl.isNotEmpty
        ? playlist.coverImgUrl
        : widget.coverUrl;

    if (isDesktop) {
      final scrollView = CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: topPadding,
            sliver: SliverToBoxAdapter(
              child: _DesktopPlaylistHeader(
                playlist: playlist,
                fallbackCoverUrl: widget.coverUrl,
                onPlayAll: tracks.isEmpty
                    ? null
                    : () => _play(tracks.first, tracks),
                onSync:
                    !widget.isPersonal &&
                        widget.token?.isNotEmpty == true &&
                        !_isSyncing
                    ? () => _syncToAccount(context)
                    : null,
                isSyncing: _isSyncing,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _PlaylistSortBar(
              mode: _sortMode,
              trackCount: isFiltering ? tracks.length : playlist.trackCount,
              onTap: () => _openSortSheet(context),
              desktopLayout: true,
            ),
          ),
          if (_searching)
            SliverToBoxAdapter(
              child: _PlaylistSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (value) => setState(() => _searchQuery = value),
                onClear: _closeSearch,
                resultCount: isFiltering ? tracks.length : null,
                desktopLayout: true,
              ),
            ),
          if (_isLoading && allTracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: MiuixCircularProgressIndicator()),
            )
          else if (allTracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: CyreneEmptyState(
                icon: Icons.music_note,
                title: '歌单里还没有歌曲',
                description: '稍后再来看看吧。',
              ),
            )
          else if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: CyreneEmptyState(
                icon: Icons.search_off,
                title: '没有匹配的歌曲',
                description: '换个关键词试试，或清空搜索查看全部。',
                action: MiuixButton(
                  onPressed: _closeSearch,
                  child: MiuixText('清空搜索', style: theme.textStyles.button),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
              sliver: _DesktopTrackTable(
                tracks: tracks,
                playback: widget.playback,
                onPlay: (track) => _play(track, tracks),
                onShowMenu: (track) => showTrackActionMenu(
                  context,
                  track: track,
                  playback: widget.playback,
                  token: widget.token,
                ),
              ),
            ),
        ],
      );

      return CyrenePullToRefresh(
        onRefresh: _load,
        contentPadding: EdgeInsets.only(top: topPadding.top),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: scrollView,
          ),
        ),
      );
    }

    // 移动端：全宽顶部固定封面 + 向上滑动的详情与歌曲内容 + 悬浮操作栏
    final screenWidth = MediaQuery.sizeOf(context).width;
    final heroHeight = (screenWidth * 0.95).clamp(330.0, 420.0);
    final topSafeInset = MediaQuery.paddingOf(context).top;

    final mobileScrollView = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      slivers: [
        // 移动端顶部透明留白与歌单元数据（滚动时向上推入）
        SliverToBoxAdapter(
          child: _MobilePlaylistContentHeader(
            playlist: playlist,
            heroHeight: heroHeight,
            extractedColor: _extractedThemeColor,
            onPlayAll:
                tracks.isEmpty ? null : () => _play(tracks.first, tracks),
            onOpenPlaylist: widget.onOpenPlaylist,
          ),
        ),

        // 常驻排序工具条：左侧歌曲数量，右侧排序方式切换
        SliverToBoxAdapter(
          child: _PlaylistSortBar(
            mode: _sortMode,
            trackCount: isFiltering ? tracks.length : playlist.trackCount,
            onTap: () => _openSortSheet(context),
            desktopLayout: false,
          ),
        ),

        if (_searching)
          SliverToBoxAdapter(
            child: _PlaylistSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _searchQuery = value),
              onClear: _closeSearch,
              resultCount: isFiltering ? tracks.length : null,
              desktopLayout: false,
            ),
          ),

        if (_isLoading && allTracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: MiuixCircularProgressIndicator()),
          )
        else if (allTracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: CyreneEmptyState(
              icon: Icons.music_note,
              title: '歌单里还没有歌曲',
              description: '稍后再来看看吧。',
            ),
          )
        else if (tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: CyreneEmptyState(
              icon: Icons.search_off,
              title: '没有匹配的歌曲',
              description: '换个关键词试试，或清空搜索查看全部。',
              action: MiuixButton(
                onPressed: _closeSearch,
                child: MiuixText('清空搜索', style: theme.textStyles.button),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            sliver: SliverList.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return AnimatedBuilder(
                  animation: widget.playback,
                  builder: (context, _) => CyreneTrackTile(
                    track: track,
                    isGlass: true,
                    isActive:
                        widget.playback.state.currentTrack?.key == track.key,
                    onPlay: () => _play(track, tracks),
                    onShowMenu: () => showTrackActionMenu(
                      context,
                      track: track,
                      playback: widget.playback,
                      token: widget.token,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 0. 全屏主题色环境渐变背景（从封面提取色全屏自然铺满，自上而下沉浸式过渡）
        Positioned.fill(
          child: _FullScreenThemeBackground(
            extractedColor: _extractedThemeColor,
          ),
        ),

        // 1. 3D 视差分速滚动的 100% 宽度顶部专辑封面：
        // 下拉刷新时保持不动（offset <= 0 偏移锁定为 0），向上滑动时以 0.45x 较慢速度向上滑移并配合 3D 缩放，
        // 与下方 1.0x 正常速度滚动的主内容形成分层的 3D 视差景深感。
        AnimatedBuilder(
          animation: _scrollController,
          builder: (context, _) {
            final offset = _scrollController.hasClients
                ? _scrollController.offset
                : 0.0;
            // 向上滑动时取 0.45x 视差上移，下拉刷新（offset < 0）时锁定为 0 保持绝对不动
            final parallaxOffset = offset > 0 ? offset * 0.45 : 0.0;
            final progress = (offset / heroHeight).clamp(0.0, 1.0);
            final scale = 1.0 - progress * 0.05;

            return Positioned(
              top: -parallaxOffset,
              left: 0,
              right: 0,
              height: heroHeight,
              child: RepaintBoundary(
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: _FixedMobileHeroCover(
                    coverUrl: cover,
                    topPadding: topSafeInset,
                    heroHeight: heroHeight,
                    extractedColor: _extractedThemeColor,
                  ),
                ),
              ),
            );
          },
        ),

        // 2. 页面滚动区域与下拉刷新（内容在封面上方平滑滚动，下拉刷新不移动封面）
        Positioned.fill(
          child: CyrenePullToRefresh(
            onRefresh: _load,
            contentPadding: EdgeInsets.only(top: topSafeInset + 48),
            child: mobileScrollView,
          ),
        ),

        // 3. 固定在顶部的悬浮操作栏（返回 / 同步 / 搜索）
        Positioned(
          top: topSafeInset + 6,
          left: 16,
          right: 16,
          child: _FloatingTopBar(
            canPop: canPop,
            onSync: !widget.isPersonal &&
                    widget.token?.isNotEmpty == true &&
                    !_isSyncing
                ? () => _syncToAccount(context)
                : null,
            isSyncing: _isSyncing,
            searching: _searching,
            onToggleSearch: _toggleSearch,
          ),
        ),
      ],
    );
  }

  Track _toTrack(ToplistTrack item) => Track(
    id: item.id,
    name: item.name,
    artists: item.artists,
    album: item.album,
    picUrl: item.picUrl,
    source: item.source ?? MusicSource.netease,
    duration: _normalizeTrackDuration(item.duration),
  );

  List<Track> _mapTracks(PlaylistDetail? playlist) =>
      playlist?.tracks.map(_toTrack).toList(growable: false) ?? const [];

  /// 歌单接口存在毫秒和秒两种历史单位；正常歌曲不会达到 10000 秒，
  /// 因此较大的原始值按毫秒解释，其余按秒解释。
  Duration? _normalizeTrackDuration(int? rawDuration) {
    if (rawDuration == null || rawDuration <= 0) return null;
    return rawDuration >= 10000
        ? Duration(milliseconds: rawDuration)
        : Duration(seconds: rawDuration);
  }

  void _play(Track track, List<Track> queue) {
    widget.playback.playTrack(track, queue: queue);
  }
}

/// 桌面端专用的歌单头部：参考桌面音乐客户端的横向信息层级，大封面在左，
/// 标题、简介、创建者、统计与操作集中在右侧。移动端使用 [_MobilePlaylistHeroHeader]。
class _DesktopPlaylistHeader extends StatelessWidget {
  const _DesktopPlaylistHeader({
    required this.playlist,
    required this.fallbackCoverUrl,
    required this.onPlayAll,
    required this.onSync,
    required this.isSyncing,
  });

  final PlaylistDetail playlist;
  final String fallbackCoverUrl;
  final VoidCallback? onPlayAll;
  final VoidCallback? onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final cover = playlist.coverImgUrl.isNotEmpty
        ? playlist.coverImgUrl
        : fallbackCoverUrl;
    final description = playlist.description.trim();
    final createdAt = _formatCreateDate(playlist.createTime);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverImage(
            url: cover,
            size: 176,
            icon: MiuixIcons.extended.byName('playlist')!,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.title1.copyWith(
                    color: colors.onBackground,
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.body2.copyWith(
                      color: colors.onSurfaceVariantSummary,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (playlist.creator.isNotEmpty)
                      Text(
                        playlist.creator,
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (createdAt != null)
                      Text(
                        '$createdAt 创建',
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    Text(
                      '${playlist.trackCount} 首歌曲 · '
                      '${_formatPlayCount(playlist.playCount)} 次播放',
                      style: theme.textStyles.body2.copyWith(
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                ),
                if (playlist.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final tag in playlist.tags)
                        MiuixBadge(
                          containerColor: colors.secondaryContainer,
                          contentColor: colors.onSecondaryContainer,
                          child: MiuixText(
                            tag,
                            style: theme.textStyles.footnote2,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    MiuixButton(
                      onPressed: onPlayAll,
                      minHeight: 32,
                      cornerRadius: 12,
                      insideMargin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MiuixIcon(
                            vector: MiuixIcons.extended.byName('play')!,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          MiuixText(
                            '播放全部',
                            style: theme.textStyles.footnote1.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onSync != null || isSyncing) ...[
                      const SizedBox(width: 12),
                      MiuixButton(
                        onPressed: onSync,
                        minHeight: 32,
                        cornerRadius: 12,
                        insideMargin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSyncing)
                              const MiuixCircularProgressIndicator(
                                size: 17,
                                strokeWidth: 2,
                              )
                            else
                              const MiuixIcon(
                                icon: Icons.sync_rounded,
                                size: 16,
                              ),
                            const SizedBox(width: 8),
                            MiuixText(
                              isSyncing ? '正在同步' : '同步到歌单',
                              style: theme.textStyles.footnote1.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _formatCreateDate(int timestamp) {
    if (timestamp <= 0) return null;
    final milliseconds = timestamp < 1000000000000
        ? timestamp * 1000
        : timestamp;
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }
}

/// 桌面端表格式歌曲列表。列宽在较窄的桌面窗口中会逐步隐藏专辑和时长，
/// 保证标题与操作始终可用，而不是把移动端卡片横向拉伸。
class _DesktopTrackTable extends StatelessWidget {
  const _DesktopTrackTable({
    required this.tracks,
    required this.playback,
    required this.onPlay,
    required this.onShowMenu,
  });

  final List<Track> tracks;
  final PlaybackController playback;
  final ValueChanged<Track> onPlay;
  final ValueChanged<Track> onShowMenu;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final showAlbum = constraints.crossAxisExtent >= 760;
        final showDuration = constraints.crossAxisExtent >= 620;
        final headingStyle = theme.textStyles.footnote1.copyWith(
          color: colors.onSurfaceVariantSummary,
          fontWeight: FontWeight.w500,
        );
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == 0) {
              return Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          '#',
                          textAlign: TextAlign.center,
                          style: headingStyle,
                        ),
                      ),
                      Expanded(flex: 5, child: Text('标题', style: headingStyle)),
                      if (showAlbum)
                        Expanded(
                          flex: 3,
                          child: Text('专辑', style: headingStyle),
                        ),
                      if (showDuration)
                        SizedBox(
                          width: 72,
                          child: Text('时长', style: headingStyle),
                        ),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(height: 1, color: colors.dividerLine),
                ],
              );
            }

            final trackIndex = index - 1;
            final track = tracks[trackIndex];
            return AnimatedBuilder(
              key: ValueKey('desktop-track-${track.key}'),
              animation: playback,
              builder: (context, _) => _DesktopTrackRow(
                index: trackIndex,
                track: track,
                active: playback.state.currentTrack?.key == track.key,
                showAlbum: showAlbum,
                showDuration: showDuration,
                onPlay: () => onPlay(track),
                onShowMenu: () => onShowMenu(track),
              ),
            );
          }, childCount: tracks.length + 1),
        );
      },
    );
  }
}

class _DesktopTrackRow extends StatelessWidget {
  const _DesktopTrackRow({
    required this.index,
    required this.track,
    required this.active,
    required this.showAlbum,
    required this.showDuration,
    required this.onPlay,
    required this.onShowMenu,
  });

  final int index;
  final Track track;
  final bool active;
  final bool showAlbum;
  final bool showDuration;
  final VoidCallback onPlay;
  final VoidCallback onShowMenu;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final primaryText = active ? colors.primary : colors.onSurfaceContainer;
    final secondaryStyle = theme.textStyles.footnote1.copyWith(
      color: colors.onSurfaceVariantSummary,
    );
    return Semantics(
      button: true,
      selected: active,
      label: '${track.name}，${track.artists}',
      child: MiuixPressable(
        onPressed: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: secondaryStyle,
                ),
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    TrackArtwork(track: track, size: 38, borderRadius: 8),
                    const SizedBox(width: 12),
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
                              color: primaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondaryStyle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
              if (showAlbum)
                Expanded(
                  flex: 3,
                  child: Text(
                    track.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                ),
              if (showDuration)
                SizedBox(
                  width: 72,
                  child: Text(
                    _formatDuration(track.duration),
                    style: secondaryStyle,
                  ),
                ),
              SizedBox(
                width: 44,
                child: MiuixIconButton(
                  key: ValueKey('desktop-menu-${track.key}'),
                  onPressed: onShowMenu,
                  child: MiuixIcon(
                    vector: MiuixIcons.extended.byName('more')!,
                    size: 18,
                    tint: colors.onSurfaceVariantActions,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 移动端：全屏沉浸式主题色背景渐变层（从封面提取的主题色自顶向下自然铺展至底色）。
class _FullScreenThemeBackground extends StatelessWidget {
  const _FullScreenThemeBackground({
    this.extractedColor,
  });

  final Color? extractedColor;

  static List<Color> _buildFullScreenGradient(
    Color seedColor,
    Color surfaceColor,
  ) {
    final hsl = HSLColor.fromColor(seedColor);
    final isDark = surfaceColor.computeLuminance() < 0.5;

    // 调和全屏背景色：保持浓郁的主题色氛围感，并根据深浅主题平滑延展
    final saturation = hsl.saturation < 0.12
        ? hsl.saturation
        : hsl.saturation.clamp(0.40, 0.85);
    final topLightness = isDark
        ? hsl.lightness.clamp(0.20, 0.38)
        : hsl.lightness.clamp(0.70, 0.86);
    final midLightness = isDark
        ? hsl.lightness.clamp(0.10, 0.20)
        : hsl.lightness.clamp(0.85, 0.94);

    final topColor = hsl
        .withSaturation(saturation)
        .withLightness(topLightness)
        .toColor();
    final midColor = hsl
        .withSaturation(saturation * 0.75)
        .withLightness(midLightness)
        .toColor();

    return [
      topColor,
      midColor,
      Color.lerp(midColor, surfaceColor, 0.70)!,
      surfaceColor,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final themeSeed = extractedColor ?? colors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _buildFullScreenGradient(themeSeed, colors.surface),
          stops: const [0.0, 0.38, 0.72, 1.0],
        ),
      ),
    );
  }
}

/// 移动端：固定在顶部的 100% 宽度专辑封面背景（不随滚动与下拉刷新移位，平滑融入全屏背景）。
class _FixedMobileHeroCover extends StatelessWidget {
  const _FixedMobileHeroCover({
    required this.coverUrl,
    required this.topPadding,
    required this.heroHeight,
    this.extractedColor,
  });

  final String coverUrl;
  final double topPadding;
  final double heroHeight;
  final Color? extractedColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 封面图片：通过 ShaderMask 将底部平滑 Alpha 渐隐至完全透明（0），
          // 从而无缝自然透出底层的全屏主题色环境渐变，彻底根除任何硬切边和分割线。
          if (coverUrl.isNotEmpty)
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Color(0xB3FFFFFF), // 70%
                    Color(0x33FFFFFF), // 20%
                    Colors.transparent, // 0% 完全透明
                  ],
                  stops: [0.0, 0.35, 0.65, 0.88, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                httpHeaders: imageHeaders(coverUrl),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const _FallbackCoverBackground(),
              ),
            )
          else
            const _FallbackCoverBackground(),

          // 顶部暗色渐变遮罩（保证返回、搜索按钮与状态栏清晰）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 68,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8C000000), // ~55% 黑色
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 移动端：固定在顶部的悬浮操作栏（返回 / 同步 / 搜索）。
class _FloatingTopBar extends StatelessWidget {
  const _FloatingTopBar({
    required this.canPop,
    required this.onSync,
    required this.isSyncing,
    required this.searching,
    required this.onToggleSearch,
  });

  final bool canPop;
  final VoidCallback? onSync;
  final bool isSyncing;
  final bool searching;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (canPop)
          _FrostedCircleButton(
            onPressed: () => Navigator.maybePop(context),
            icon: MiuixIcons.extended.byName('back')!,
          ),
        const Spacer(),
        if (onSync != null || isSyncing) ...[
          _FrostedCircleButton(
            onPressed: onSync ?? () {},
            iconData: Icons.sync_rounded,
            isLoading: isSyncing,
          ),
          const SizedBox(width: 10),
        ],
        _FrostedCircleButton(
          onPressed: onToggleSearch,
          icon: MiuixIcons.extended.byName(
            searching ? 'close' : 'search',
          )!,
        ),
      ],
    );
  }
}

class _PlaylistHeaderPalette {
  const _PlaylistHeaderPalette({
    required this.titleColor,
    required this.creatorColor,
    required this.descColor,
    required this.subtitleColor,
    required this.tagContainerColor,
    required this.tagContentColor,
    required this.toggleColor,
    required this.accentIconColor,
  });

  final Color titleColor;
  final Color creatorColor;
  final Color descColor;
  final Color subtitleColor;
  final Color tagContainerColor;
  final Color tagContentColor;
  final Color toggleColor;
  final Color accentIconColor;
}

/// 移动端：跟随列表滚动的歌单信息头部（透明留白露底 + 详情与操作）。
class _MobilePlaylistContentHeader extends StatelessWidget {
  const _MobilePlaylistContentHeader({
    required this.playlist,
    required this.heroHeight,
    required this.onPlayAll,
    this.onOpenPlaylist,
    this.extractedColor,
  });

  final PlaylistDetail playlist;
  final double heroHeight;
  final VoidCallback? onPlayAll;

  /// 详情页内再打开歌单（个人歌单子项）的跳转回调。null 则不渲染入口。
  final void Function(int id, String title, String coverUrl)? onOpenPlaylist;
  final Color? extractedColor;

  static _PlaylistHeaderPalette _deriveHeaderPalette({
    required Color seedColor,
    required Color surfaceColor,
    required bool isSystemDark,
  }) {
    final hsl = HSLColor.fromColor(seedColor);
    final isSurfaceDark = surfaceColor.computeLuminance() < 0.5;
    // 背景在顶部呈现的主题亮度
    final topBgLightness = isSurfaceDark
        ? hsl.lightness.clamp(0.20, 0.38)
        : hsl.lightness.clamp(0.70, 0.86);
    final isDarkBg = isSurfaceDark || topBgLightness < 0.5;

    if (isDarkBg) {
      // 深色背景：文字从提取色中保留相同色相，大幅提亮至浅调（0.74 ~ 0.92），保证与背景对比度 > 7:1
      final titleColor = hsl
          .withSaturation((hsl.saturation * 0.7).clamp(0.20, 0.65))
          .withLightness(0.92)
          .toColor();
      final creatorColor = hsl
          .withSaturation((hsl.saturation * 0.9).clamp(0.40, 0.85))
          .withLightness(0.84)
          .toColor();
      final descColor = hsl
          .withSaturation((hsl.saturation * 0.45).clamp(0.12, 0.40))
          .withLightness(0.82)
          .toColor();
      final subtitleColor = hsl
          .withSaturation((hsl.saturation * 0.35).clamp(0.10, 0.35))
          .withLightness(0.74)
          .toColor();
      final tagContentColor = hsl
          .withSaturation((hsl.saturation * 0.9).clamp(0.50, 0.90))
          .withLightness(0.88)
          .toColor();
      final tagContainerColor = tagContentColor.withValues(alpha: 0.20);
      final toggleColor = tagContentColor;

      return _PlaylistHeaderPalette(
        titleColor: titleColor,
        creatorColor: creatorColor,
        descColor: descColor,
        subtitleColor: subtitleColor,
        tagContainerColor: tagContainerColor,
        tagContentColor: tagContentColor,
        toggleColor: toggleColor,
        accentIconColor: tagContentColor,
      );
    } else {
      // 浅色背景：文字从提取色中保留相同色相，大幅加深至深调（0.12 ~ 0.42），保证与背景对比度 > 8:1
      final titleColor = hsl
          .withSaturation((hsl.saturation * 0.9).clamp(0.50, 0.90))
          .withLightness(0.12)
          .toColor();
      final creatorColor = hsl
          .withSaturation((hsl.saturation * 0.85).clamp(0.45, 0.85))
          .withLightness(0.22)
          .toColor();
      final descColor = hsl
          .withSaturation((hsl.saturation * 0.5).clamp(0.20, 0.50))
          .withLightness(0.28)
          .toColor();
      final subtitleColor = hsl
          .withSaturation((hsl.saturation * 0.35).clamp(0.15, 0.40))
          .withLightness(0.42)
          .toColor();
      final tagContentColor = hsl
          .withSaturation((hsl.saturation * 0.95).clamp(0.60, 0.95))
          .withLightness(0.30)
          .toColor();
      final tagContainerColor = tagContentColor.withValues(alpha: 0.12);
      final toggleColor = tagContentColor;

      return _PlaylistHeaderPalette(
        titleColor: titleColor,
        creatorColor: creatorColor,
        descColor: descColor,
        subtitleColor: subtitleColor,
        tagContainerColor: tagContainerColor,
        tagContentColor: tagContentColor,
        toggleColor: toggleColor,
        accentIconColor: tagContentColor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final description = playlist.description.trim();
    final createdAt = _formatCreateDate(playlist.createTime);
    final themeSeed = extractedColor ?? colors.primary;

    final palette = _deriveHeaderPalette(
      seedColor: themeSeed,
      surfaceColor: colors.surface,
      isSystemDark: theme.brightness == Brightness.dark,
    );

    // 顶部透明留白高度：让封面在初始状态下充分展现，随后无缝过渡到信息
    final topSpacerHeight = (heroHeight * 0.48).clamp(160.0, 240.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部透明留白区（透出下方固定的专辑封面大图）
        SizedBox(height: topSpacerHeight),

        // 歌单详情元信息排版（位于渐变过渡区域）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 歌单标签
              if (playlist.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in playlist.tags)
                      MiuixBadge(
                        containerColor: palette.tagContainerColor,
                        contentColor: palette.tagContentColor,
                        child: MiuixText(
                          tag,
                          style: theme.textStyles.footnote2.copyWith(
                            fontWeight: FontWeight.w600,
                            color: palette.tagContentColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // 歌单名称
              Text(
                playlist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.title1.copyWith(
                  color: palette.titleColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),

              // 创建者 & 播放统计
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (playlist.creator.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MiuixIcon(
                          icon: Icons.person_rounded,
                          size: 15,
                          tint: palette.accentIconColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          playlist.creator,
                          style: theme.textStyles.body2.copyWith(
                            color: palette.creatorColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  if (createdAt != null)
                    Text(
                      '$createdAt 创建',
                      style: theme.textStyles.body2.copyWith(
                        color: palette.subtitleColor,
                        fontSize: 13,
                      ),
                    ),
                  Text(
                    '${playlist.trackCount} 首歌曲 · ${_formatPlayCount(playlist.playCount)} 次播放',
                    style: theme.textStyles.body2.copyWith(
                      color: palette.subtitleColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),

              // 歌单描述
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ExpandableDescription(
                  text: description,
                  textColor: palette.descColor,
                  toggleColor: palette.toggleColor,
                ),
              ],

              // 关联子歌单
              if (onOpenPlaylist != null &&
                  _LinkedPlaylistRow.childrenOf(playlist).isNotEmpty) ...[
                const SizedBox(height: 14),
                Column(
                  children: [
                    for (final child
                        in _LinkedPlaylistRow.childrenOf(playlist))
                      _LinkedPlaylistRow(
                        playlist: child,
                        onTap: () => onOpenPlaylist!(
                          child.id,
                          child.name,
                          child.coverImgUrl,
                        ),
                      ),
                  ],
                ),
              ],

              // 播放全部主按钮（高光玻璃胶囊效果）
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: MiuixHighlight(
                    highlight: Highlight.glassStrokeSmallDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Material(
                      color: const Color(0x40000000),
                      child: InkWell(
                        onTap: onPlayAll,
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              MiuixIcon(
                                vector: MiuixIcons.extended.byName('play')!,
                                size: 18,
                                tint: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                playlist.trackCount > 0
                                    ? '播放全部 (${playlist.trackCount})'
                                    : '播放全部',
                                style: theme.textStyles.button.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({
    required this.onPressed,
    this.icon,
    this.iconData,
    this.isLoading = false,
  });

  final VoidCallback onPressed;
  final MiuixVectorIcon? icon;
  final IconData? iconData;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: MiuixHighlight(
          highlight: Highlight.glassStrokeSmallDark,
          shape: const CircleBorder(),
          child: Material(
            color: const Color(0x40000000),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: isLoading ? null : onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : (icon != null
                          ? MiuixIcon(
                              vector: icon!,
                              size: 20,
                              tint: Colors.white,
                            )
                          : Icon(iconData, size: 20, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FallbackCoverBackground extends StatelessWidget {
  const _FallbackCoverBackground();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.3),
            colors.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: MiuixIcon(
          vector: MiuixIcons.extended.byName('playlist')!,
          size: 64,
          tint: colors.onSurfaceVariantSummary,
        ),
      ),
    );
  }
}

/// 个人歌单里的「关联在线歌单」行：封面 + 名称 + 跳转提示，点击继续向下
/// 钻取（桌面端由外壳压入首页二级页导航栈，见 `desktop_shell.dart`）。
class _LinkedPlaylistRow extends StatelessWidget {
  const _LinkedPlaylistRow({required this.playlist, required this.onTap});

  final DiscoveryPlaylist playlist;
  final VoidCallback onTap;

  /// 个人歌单的子项（关联的在线歌单，表现为 playlist 结构的 entry）。
  /// 原始 JSON 里这些子项的 id/名称/封面等字段与歌曲不同，当前个人歌单
  /// 模式只装歌曲，没有子歌单概念，故恒为空；将来后端返回子歌单时在此
  /// 展开即可（桌面端可继续向下钻取，配合标题栏上一级/下一级）。
  static List<DiscoveryPlaylist> childrenOf(PlaylistDetail detail) => const [];

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixPressable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: colors.secondaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          children: [
            _CoverImage(
              url: playlist.coverImgUrl,
              size: 40,
              icon: MiuixIcons.extended.byName('playlist')!,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            MiuixIcon(
              icon: Icons.chevron_right_rounded,
              size: 18,
              tint: colors.onSurfaceVariantActions,
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌单介绍：超过 [_collapsedLines] 行时折叠为省略号，点按「展开/收起」
/// 切换完整内容，尺寸变化经 [AnimatedSize] 平滑过渡。
class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({
    required this.text,
    this.textColor,
    this.toggleColor,
  });

  final String text;
  final Color? textColor;
  final Color? toggleColor;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  static const _collapsedLines = 3;

  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final style = theme.textStyles.body2.copyWith(
      color: widget.textColor ?? colors.onSurfaceVariantSummary,
      fontSize: 13,
      height: 1.45,
    );
    final effectiveToggleColor = widget.toggleColor ?? colors.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final needsToggle = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text(
                widget.text,
                style: style,
                maxLines: _expanded ? null : _collapsedLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
            if (needsToggle) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: _expanded ? '收起歌单介绍' : '展开歌单介绍',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded ? '收起' : '展开',
                            style: theme.textStyles.body2.copyWith(
                              color: effectiveToggleColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 2),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            child: MiuixIcon(
                              vector: MiuixIcons.extended.byName('expandMore')!,
                              size: 16,
                              tint: effectiveToggleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 歌单详情页内的搜索过滤框：随列表一起滚动，输入即过滤；右侧清除按钮
/// 一键清空并关闭搜索。带搜索结果计数提示（仅过滤中显示）。
class _PlaylistSearchField extends StatelessWidget {
  const _PlaylistSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.resultCount,
    required this.desktopLayout,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// 过滤中的结果数；null 表示尚未过滤（关键词为空），不渲染计数。
  final int? resultCount;
  final bool desktopLayout;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktopLayout ? 20 : 16,
        0,
        desktopLayout ? 20 : 16,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuixTextField(
            controller: controller,
            focusNode: focusNode,
            label: '搜索歌单内歌曲',
            useLabelAsPlaceholder: true,
            singleLine: true,
            leadingIcon: MiuixIcon(
              vector: MiuixIcons.extended.byName('search')!,
              size: 18,
              tint: colors.onSurfaceVariantSummary,
            ),
            trailingIcon: MiuixIconButton(
              onPressed: onClear,
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName('close')!,
                size: 16,
                tint: colors.onSurfaceVariantSummary,
              ),
            ),
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
          ),
          if (resultCount != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '匹配到 $resultCount 首歌曲',
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceVariantSummary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 常驻排序工具条：左侧曲目数量提示，右侧排序方式切换。
class _PlaylistSortBar extends StatelessWidget {
  const _PlaylistSortBar({
    required this.mode,
    required this.onTap,
    required this.desktopLayout,
    this.trackCount,
  });

  final PlaylistSortMode mode;
  final VoidCallback onTap;
  final bool desktopLayout;
  final int? trackCount;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktopLayout ? 20 : 18,
        4,
        desktopLayout ? 20 : 16,
        4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (trackCount != null && trackCount! > 0)
            Text(
              '歌曲列表 ($trackCount)',
              style: theme.textStyles.title3.copyWith(
                color: colors.onSurfaceContainer,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            const SizedBox.shrink(),
          MiuixPressable(
            onPressed: onTap,
            borderRadius: BorderRadius.circular(20),
            feedbackType: MiuixPressFeedbackType.sink,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('sort')!,
                    size: 16,
                    tint: colors.onSurfaceVariantSummary,
                  ),
                  const SizedBox(width: 6),
                  MiuixText(
                    mode.label,
                    style: theme.textStyles.body2.copyWith(
                      color: colors.onSurfaceVariantSummary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.url,
    required this.size,
    required this.icon,
  });

  final String url;
  final double size;
  final MiuixVectorIcon icon;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Center(
        child: MiuixIcon(
          vector: icon,
          size: size * .34,
          tint: colors.onSurfaceVariantSummary,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                httpHeaders: imageHeaders(url),
                fit: BoxFit.cover,
                // 按显示尺寸降采样解码,避免歌曲列表滚动时全尺寸封面拖累帧率。
                memCacheWidth: coverDecodeWidth(
                  size,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

String? _formatCreateDate(int timestamp) {
  if (timestamp <= 0) return null;
  final milliseconds =
      timestamp < 1000000000000 ? timestamp * 1000 : timestamp;
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

String _formatPlayCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
  return count.toString();
}
