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

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.title,
    required this.coverUrl,
    required this.playback,
    this.token,
    this.onOpenPlaylist,
  }) : isPersonal = false,
       trackCount = 0;

  /// 个人歌单模式：曲目走 Cyrene 后端 `/playlists/:id/tracks`（需 [token]）。
  const PlaylistDetailPage.personal({
    super.key,
    required this.playlistId,
    required this.title,
    required this.coverUrl,
    required this.playback,
    required String this.token,
    this.trackCount = 0,
    this.onOpenPlaylist,
  }) : isPersonal = true;

  final int playlistId;
  final String title;
  final String coverUrl;
  final PlaybackController playback;
  final String? token;
  final bool isPersonal;
  final int trackCount;

  /// 详情页内再打开歌单（如个人歌单里关联的在线歌单）时的跳转回调。桌面端
  /// 由外壳提供并压入首页二级页导航栈（见 `desktop_shell.dart`），支持逐级
  /// 向下钻取；null（移动端）则回退为整窗 push 路由。
  final void Function(int id, String title, String coverUrl)? onOpenPlaylist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  PlaylistDetail? _playlist;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isSyncing = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final playlist = widget.isPersonal
          ? await _loadPersonal()
          : await DiscoveryService.instance.getPlaylistDetail(
              widget.playlistId,
              token: widget.token,
            );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _playlist = playlist;
        _isLoading = false;
        if (playlist == null) _errorMessage = '未能获取这个歌单，请稍后重试。';
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '歌单加载失败，请检查网络后重试。';
      });
    }
  }

  /// 加载个人歌单曲目并组装为 [PlaylistDetail]（元信息来自跳转参数）。
  Future<PlaylistDetail> _loadPersonal() async {
    final tracks = await PlaylistService.instance.getPlaylistTracks(
      widget.token!,
      widget.playlistId,
    );
    return PlaylistDetail(
      id: widget.playlistId,
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
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: _playlist?.name.isNotEmpty == true ? _playlist!.name : widget.title,
    actions: [
      // 在线歌单：同步收藏到自己的歌单（绑定来源 + 增量同步，对应原版发现页功能）。
      if (!widget.isPersonal && widget.token?.isNotEmpty == true) ...[
        MiuixIconButton(
          key: const Key('sync-playlist-button'),
          enabled: !_isSyncing,
          onPressed: () => _syncToAccount(context),
          child: _isSyncing
              ? const MiuixCircularProgressIndicator(size: 18, strokeWidth: 2)
              : const MiuixIcon(icon: Icons.sync_rounded, size: 20),
        ),
        const SizedBox(width: 8),
      ],
    ],
    bodyBuilder: (context, topPadding) => _buildBody(topPadding),
  );

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
        source: 'netease',
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
    if (_isLoading && _playlist == null) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_errorMessage != null && _playlist == null) {
      return CyreneEmptyState(
        icon: Icons.cloud_off,
        title: '歌单暂时不可用',
        description: _errorMessage!,
        action: MiuixButton(
          onPressed: _load,
          child: MiuixText(
            '重试',
            style: MiuixTheme.of(context).textStyles.button,
          ),
        ),
      );
    }

    final playlist = _playlist!;
    final tracks = playlist.tracks.map(_toTrack).toList(growable: false);
    return CyrenePullToRefresh(
      onRefresh: _load,
      contentPadding: EdgeInsets.only(top: topPadding.top),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: topPadding,
            sliver: SliverToBoxAdapter(
              child: _PlaylistHeader(
                playlist: playlist,
                fallbackCoverUrl: widget.coverUrl,
                onPlayAll: tracks.isEmpty
                    ? null
                    : () => _play(tracks.first, tracks),
                onOpenPlaylist: widget.onOpenPlaylist,
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: CyreneEmptyState(
                icon: Icons.music_note,
                title: '歌单里还没有歌曲',
                description: '稍后再来看看吧。',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList.separated(
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return AnimatedBuilder(
                    animation: widget.playback,
                    builder: (context, _) => CyreneTrackTile(
                      track: track,
                      isActive:
                          widget.playback.state.currentTrack?.key == track.key,
                      onPlay: () => _play(track, tracks),
                      onAddToQueue: () => widget.playback.addToQueue(track),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Track _toTrack(ToplistTrack item) => Track(
    id: item.id,
    name: item.name,
    artists: item.artists,
    album: item.album,
    picUrl: item.picUrl,
    source: item.source ?? MusicSource.netease,
    duration: item.duration == null ? null : Duration(seconds: item.duration!),
  );

  void _play(Track track, List<Track> queue) {
    widget.playback.playTrack(track, queue: queue);
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.fallbackCoverUrl,
    required this.onPlayAll,
    this.onOpenPlaylist,
  });

  final PlaylistDetail playlist;
  final String fallbackCoverUrl;
  final VoidCallback? onPlayAll;

  /// 详情页内再打开歌单（个人歌单子项）的跳转回调。null 则不渲染入口。
  final void Function(int id, String title, String coverUrl)? onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final cover = playlist.coverImgUrl.isNotEmpty
        ? playlist.coverImgUrl
        : fallbackCoverUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      child: MiuixCard(
        insideMargin: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverImage(
                  url: cover,
                  size: 116,
                  icon: MiuixIcons.extended.byName('playlist')!,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: theme.textStyles.title3.copyWith(
                          color: colors.onSurfaceContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (playlist.creator.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          playlist.creator,
                          style: theme.textStyles.body2.copyWith(
                            color: colors.onSurfaceContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        '${playlist.trackCount} 首 · ${_formatPlayCount(playlist.playCount)} 次播放',
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                      if (playlist.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: playlist.tags
                              .map(
                                (tag) => MiuixBadge(
                                  containerColor: colors.secondaryContainer,
                                  contentColor: colors.onSecondaryContainer,
                                  child: MiuixText(
                                    tag,
                                    style: theme.textStyles.footnote2,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (playlist.description.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              _ExpandableDescription(text: playlist.description.trim()),
            ],
            // 个人歌单：把关联的在线歌单项再打开时继续向下钻取（桌面端压
            // 二级栈，支持逐级后退/前进；移动端不传回调，此处不渲染）。
            if (onOpenPlaylist != null &&
                _LinkedPlaylistRow.childrenOf(playlist).isNotEmpty) ...[
              const SizedBox(height: 16),
              Column(
                children: [
                  for (final child in _LinkedPlaylistRow.childrenOf(playlist))
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: MiuixButton(
                onPressed: onPlayAll,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MiuixIcon(
                      vector: MiuixIcons.extended.byName('play')!,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    MiuixText('播放全部', style: theme.textStyles.button),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPlayCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    return count.toString();
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
  static List<DiscoveryPlaylist> childrenOf(PlaylistDetail detail) =>
      const [];

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
  const _ExpandableDescription({required this.text});

  final String text;

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
      color: colors.onSurfaceVariantSummary,
    );
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
                              color: colors.primary,
                              fontWeight: FontWeight.w500,
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
                              tint: colors.primary,
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
