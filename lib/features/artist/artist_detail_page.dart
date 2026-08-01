import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/artist.dart';
import '../../domain/models/media_url.dart';
import '../../infrastructure/services/artist_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../album/album_detail_page.dart';
import '../player/cyrene_track_tile.dart';

class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.playback,
    this.artistId,
    this.artistName,
  });

  final PlaybackController playback;
  final Object? artistId;
  final String? artistName;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  ArtistDetailInfo? _detail;
  var _loading = true;
  var _requestId = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Object? id = widget.artistId;
      if (id == null && widget.artistName?.trim().isNotEmpty == true) {
        id = await ArtistService.instance.resolveArtistIdByName(
          widget.artistName!.trim(),
        );
      }
      final detail = id == null
          ? null
          : await ArtistService.instance.fetchArtistDetail(id);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _detail = detail;
        _loading = false;
        if (detail == null) _error = '未找到该歌手的信息。';
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '歌手详情加载失败，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      CyrenePage(
        title: '歌手详情',
        bodyBuilder: (context, topPadding) => _buildBody(topPadding),
      );

  Widget _buildBody(EdgeInsets topPadding) {
    if (_loading) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_detail == null) {
      return CyreneEmptyState(
        icon: Icons.person_off,
        title: '无法加载歌手',
        description: _error ?? '歌手信息暂时不可用。',
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
    return CyrenePullToRefresh(
      onRefresh: _load,
      contentPadding: EdgeInsets.only(top: topPadding.top),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: topPadding + const EdgeInsets.fromLTRB(16, 20, 16, 36),
        children: [
          _ArtistHeader(artist: detail.artist),
          if (detail.songs.isNotEmpty) ...[
            const SizedBox(height: 24),
            CyreneSectionTitle(
              title: '热门歌曲',
              trailing: MiuixTextButton(
                '播放全部',
                onPressed: () => widget.playback.playTrack(
                  detail.songs.first,
                  queue: detail.songs,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...detail.songs.map(
              (track) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CyreneTrackTile(
                  track: track,
                  onPlay: () =>
                      widget.playback.playTrack(track, queue: detail.songs),
                  onAddToQueue: () => widget.playback.addToQueue(track),
                ),
              ),
            ),
          ],
          if (detail.albums.isNotEmpty) ...[
            const SizedBox(height: 18),
            const CyreneSectionTitle(title: '专辑'),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: .78,
              ),
              itemCount: detail.albums.length,
              itemBuilder: (context, index) {
                final album = detail.albums[index];
                return _AlbumCard(
                  album: album,
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => AlbumDetailPage(
                        albumId: album.id,
                        playback: widget.playback,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.artist});

  final ArtistInfo artist;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final url = artist.picUrl ?? artist.img1v1Url ?? '';
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.person,
        size: 54,
        color: colors.onSurfaceVariantSummary,
      ),
    );
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Column(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 120,
              child: url.isEmpty
                  ? fallback
                  : CachedNetworkImage(
                      imageUrl: url,
                      httpHeaders: imageHeaders(url),
                      fit: BoxFit.cover,
                      // 120px 显示,按显示尺寸降采样解码(见 coverDecodeWidth)。
                      memCacheWidth: coverDecodeWidth(
                        120,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      errorWidget: (_, _, _) => fallback,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            artist.name,
            style: theme.textStyles.title3.copyWith(
              color: colors.onSurfaceContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (artist.alias?.isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Text(
              artist.alias!.join(' / '),
              style: theme.textStyles.body2.copyWith(
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '${artist.musicSize ?? 0} 首歌曲 · ${artist.albumSize ?? 0} 张专辑 · ${artist.mvSize ?? 0} 个 MV',
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (artist.briefDesc?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Text(
              artist.briefDesc!.trim(),
              style: theme.textStyles.body2.copyWith(
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final ArtistAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Center(
        child: MiuixIcon(
          vector: MiuixIcons.extended.byName('album')!,
          size: 40,
          tint: colors.onSurfaceVariantSummary,
        ),
      ),
    );
    return MiuixCard(
      // 透明卡片：保留原网格卡片的无底色外观，仅借用 Miuix 的按压反馈。
      colors: MiuixCardColors(
        color: Colors.transparent,
        contentColor: colors.onBackground,
      ),
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.expand(
                child: album.picUrl?.isNotEmpty == true
                    ? LayoutBuilder(
                        builder: (context, constraints) => CachedNetworkImage(
                          imageUrl: album.picUrl!,
                          httpHeaders: imageHeaders(album.picUrl!),
                          fit: BoxFit.cover,
                          // 按 cell 实际宽降采样解码(见 coverDecodeWidth)。
                          memCacheWidth: coverDecodeWidth(
                            constraints.maxWidth.isFinite &&
                                    constraints.maxWidth > 0
                                ? constraints.maxWidth
                                : 200,
                            MediaQuery.devicePixelRatioOf(context),
                          ),
                          errorWidget: (_, _, _) => fallback,
                        ),
                      )
                    : fallback,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.body2.copyWith(
              color: colors.onBackground,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (album.company?.isNotEmpty == true) ...[
            const SizedBox(height: 3),
            Text(
              album.company!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.body2.copyWith(
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
