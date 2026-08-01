import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/album.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/album_service.dart';
import '../../infrastructure/services/discovery_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../player/cyrene_track_tile.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.albumId,
    required this.playback,
  });

  final Object albumId;
  final PlaybackController playback;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  AlbumDetailInfo? _detail;
  String? _errorMessage;
  bool _isLoading = true;
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
      final detail = await AlbumService.instance.fetchAlbumDetail(
        widget.albumId,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
        if (detail == null) _errorMessage = '未找到该专辑的信息。';
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '专辑加载失败，请稍后重试。';
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CyrenePage(
        title: '专辑详情',
        bodyBuilder: (context, topPadding) => _buildBody(topPadding),
      );

  Widget _buildBody(EdgeInsets topPadding) {
    if (_isLoading && _detail == null) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_errorMessage != null && _detail == null) {
      return CyreneEmptyState(
        icon: Icons.album,
        title: '无法加载专辑',
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

    final detail = _detail!;
    final tracks = detail.songs
        .map((song) => _convertSong(song, detail.album))
        .toList(growable: false);
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
              child: _AlbumHeader(
                album: detail.album,
                songCount: tracks.length,
                onPlayAll: tracks.isEmpty
                    ? null
                    : () => _play(tracks.first, tracks),
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: CyreneEmptyState(
                icon: Icons.music_note,
                title: '这张专辑暂无歌曲',
                description: '稍后再来看看吧。',
              ),
            )
          else ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
              sliver: SliverToBoxAdapter(
                child: CyreneSectionTitle(title: '歌曲'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
        ],
      ),
    );
  }

  Track _convertSong(Map<String, Object?> song, Map<String, Object?> album) {
    try {
      final converted = DiscoveryService.instance.convertToTrack(song);
      return Track(
        id: converted.id,
        name: converted.name,
        artists: converted.artists,
        album: converted.album.isEmpty
            ? album['name']?.toString() ?? ''
            : converted.album,
        picUrl: converted.picUrl.isEmpty
            ? album['picUrl']?.toString() ?? ''
            : converted.picUrl,
        source: converted.source,
        duration: converted.duration,
        alternatives: converted.alternatives,
      );
    } catch (_) {
      return Track(
        id: song['id']?.toString() ?? '',
        name: song['name']?.toString() ?? '',
        artists: _names(song['artists'] ?? song['ar']),
        album: album['name']?.toString() ?? '',
        picUrl: song['picUrl']?.toString() ?? album['picUrl']?.toString() ?? '',
        source: MusicSource.netease,
      );
    }
  }

  static String _names(Object? value) {
    if (value is List) {
      return value
          .map((item) => item is Map ? item['name']?.toString() ?? '' : '$item')
          .where((name) => name.isNotEmpty)
          .join(' / ');
    }
    return value?.toString() ?? '';
  }

  void _play(Track track, List<Track> queue) {
    widget.playback.playTrack(track, queue: queue);
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.songCount,
    required this.onPlayAll,
  });

  final Map<String, Object?> album;
  final int songCount;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final coverUrl = album['picUrl']?.toString() ?? '';
    final artistRaw = album['artist'];
    final artist = artistRaw is Map
        ? artistRaw['name']?.toString() ?? ''
        : artistRaw?.toString() ?? '';
    final title = album['name']?.toString() ?? '未知专辑';
    final description = album['description']?.toString().trim() ?? '';
    final company = album['company']?.toString() ?? '';
    final publishTime = (album['publishTime'] as num?)?.toInt();
    final year = publishTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(publishTime).year;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.18,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _AlbumCover(url: coverUrl),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .08),
                      colors.background.withValues(alpha: .55),
                      colors.background,
                    ],
                    stops: const [0, .58, 1],
                  ),
                ),
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -26),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textStyles.title3.copyWith(
                    color: colors.onBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    artist,
                    textAlign: TextAlign.center,
                    style: theme.textStyles.body2.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Text(
                  [
                    '$songCount 首歌曲',
                    if (year != null) '$year',
                    if (company.isNotEmpty) company,
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: theme.textStyles.body2.copyWith(
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
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
        ),
      ],
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Center(
        child: MiuixIcon(
          vector: MiuixIcons.extended.byName('album')!,
          size: 72,
          tint: colors.onSurfaceVariantSummary,
        ),
      ),
    );
    return url.isEmpty
        ? fallback
        : LayoutBuilder(
            builder: (context, constraints) => CachedNetworkImage(
              imageUrl: url,
              httpHeaders: imageHeaders(url),
              fit: BoxFit.cover,
              // 按实际显示宽降采样解码(见 coverDecodeWidth)。
              memCacheWidth: coverDecodeWidth(
                constraints.maxWidth.isFinite && constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : 400,
                MediaQuery.devicePixelRatioOf(context),
              ),
              errorWidget: (_, _, _) => fallback,
            ),
          );
  }
}
