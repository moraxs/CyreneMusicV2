import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/discovery.dart';
import '../../../domain/models/track.dart';
import '../../../infrastructure/services/discovery_service.dart';
import 'for_you_artwork.dart';
import 'for_you_palette.dart';
import 'for_you_widgets.dart';

/// 移动端首页「榜单」页签（Spotify 源）的版式组件。
///
/// 原来整页只有两种形态：方形唱片架和一段段五行歌曲列表，二十来个分区连着
/// 刷下来非常单调。这里按内容类型换版式——艺人是圆形头像、专辑是露出半张
/// 黑胶的唱片、歌单在拼版 / 方卡 / 宽幅 / 列表之间轮换，歌曲则做成三首一页
/// 的横滑卡组；榜单收成一排横滑的榜单卡。
///
/// 文案一律中文，不用全大写的英文装饰字。

double _line(BuildContext context, double fontSize, [double height = 1.35]) =>
    MediaQuery.textScalerOf(context).scale(fontSize) * height;

/// 卡片类型的中文短名，用在封面角标上。
String spotifyKindLabel(SpotifyPersonalizedKind kind) => switch (kind) {
  SpotifyPersonalizedKind.playlist => '歌单',
  SpotifyPersonalizedKind.album => '专辑',
  SpotifyPersonalizedKind.radio => '电台',
  SpotifyPersonalizedKind.artist => '艺人',
  SpotifyPersonalizedKind.track => '单曲',
  SpotifyPersonalizedKind.mixed => '精选',
};

// ===== 顶部：随心畅听 =====

/// 榜单页顶部的随机播放横幅：左边文案，右边一叠扇形展开的封面。
///
/// 封面取自各榜单的榜首，数字是真实的榜单数 / 曲目数，不写空泛的口号。
class SpotifyMixHero extends StatelessWidget {
  const SpotifyMixHero({
    super.key,
    required this.covers,
    required this.chartCount,
    required this.trackCount,
    required this.onShuffle,
    this.leadTrack,
  });

  final List<String> covers;
  final int chartCount;
  final int trackCount;
  final Track? leadTrack;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final height = math.max(
      176.0,
      36 +
          _line(context, 12.5) +
          8 +
          _line(context, 23, 1.2) +
          6 +
          _line(context, 12) * 2 +
          14 +
          44,
    );
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.peach, palette.paper, palette.rose],
          stops: const [0, 0.62, 1],
        ),
        shape: MiuixSquircleBorder(
          cornerRadius: 26,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            top: 0,
            bottom: 0,
            width: 158,
            child: _FannedCovers(covers: covers),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 150, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shuffle_rounded,
                      size: 15,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '随机模式',
                      style: theme.textStyles.body2.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '随心畅听',
                  style: theme.textStyles.title1.copyWith(
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  leadTrack == null
                      ? '$chartCount 张榜单 · $trackCount 首热歌'
                      : '$chartCount 张榜单 · $trackCount 首热歌\n'
                            '此刻最热：${leadTrack!.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote1.copyWith(
                    fontSize: 12,
                    height: 1.35,
                    color: palette.muted,
                  ),
                ),
                const Spacer(),
                ForYouPlayAction(
                  label: '开始播放',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onShuffle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FannedCovers extends StatelessWidget {
  const _FannedCovers({required this.covers});

  final List<String> covers;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    String cover(int index) =>
        covers.isEmpty ? '' : covers[index % covers.length];
    Widget print(int index, double size) => Container(
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: palette.paper,
        shape: const MiuixSquircleBorder(cornerRadius: 16),
        shadows: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ForYouArtwork(url: cover(index), size: size, cornerRadius: 13),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: 4,
                  top: h * 0.08,
                  child: Transform.rotate(angle: 0.2, child: print(2, 78)),
                ),
                Positioned(
                  left: 4,
                  top: h * 0.12,
                  child: Transform.rotate(angle: -0.16, child: print(1, 78)),
                ),
                Positioned(
                  left: 26,
                  bottom: h * 0.08,
                  child: Transform.rotate(angle: 0.04, child: print(0, 92)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ===== 小按钮 =====

/// 分区标题右侧的轻量文字按钮（换一批 / 打开歌单 / 全部）。
class SpotifyPillAction extends StatelessWidget {
  const SpotifyPillAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.chevron_right_rounded,
    this.leadingIcon = false,
  });

  final String label;
  final IconData icon;
  final bool leadingIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final glyph = Icon(icon, size: 14, color: palette.accent);
    return MiuixPressable(
      onPressed: onPressed,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(14),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.outline, width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon) ...[glyph, const SizedBox(width: 3)],
            Text(
              label,
              style: theme.textStyles.footnote2.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
            if (!leadingIcon) ...[const SizedBox(width: 3), glyph],
          ],
        ),
      ),
    );
  }
}

// ===== 横向分页 =====

/// 横向翻页的「竖排 N 行」容器：歌曲卡组与歌单列表共用。
///
/// 每页宽度约 88%，右侧露出下一页的边，提示还能往左滑。
class _PagedRows extends StatefulWidget {
  const _PagedRows({
    required this.storageKey,
    required this.itemCount,
    required this.rowsPerPage,
    required this.rowHeight,
    required this.itemBuilder,
    this.surface = true,
  });

  final String storageKey;
  final int itemCount;
  final int rowsPerPage;
  final double rowHeight;
  final IndexedWidgetBuilder itemBuilder;

  /// 每页是否垫一张纸张底卡。
  final bool surface;

  @override
  State<_PagedRows> createState() => _PagedRowsState();
}

class _PagedRowsState extends State<_PagedRows> {
  late final _controller = PageController(viewportFraction: 0.88);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final pages = (widget.itemCount / widget.rowsPerPage).ceil();
    const vertical = 8.0;
    // 纸张底卡的描边（ShapeDecoration.side）也会算进 Container 的内边距，
    // 上下各让出 1。
    final height =
        widget.rowHeight * widget.rowsPerPage +
        vertical * 2 +
        (widget.surface ? 2 : 0);
    return SizedBox(
      height: height,
      child: PageView.builder(
        key: PageStorageKey(widget.storageKey),
        controller: _controller,
        padEnds: false,
        itemCount: pages,
        itemBuilder: (context, page) {
          final start = page * widget.rowsPerPage;
          final end = math.min(start + widget.rowsPerPage, widget.itemCount);
          final rows = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = start; i < end; i++)
                SizedBox(
                  height: widget.rowHeight,
                  child: widget.itemBuilder(context, i),
                ),
            ],
          );
          return Padding(
            padding: const EdgeInsetsDirectional.only(start: 20),
            child: widget.surface
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: vertical),
                    alignment: Alignment.topCenter,
                    decoration: ShapeDecoration(
                      color: palette.paper.withValues(alpha: 0.86),
                      shape: MiuixSquircleBorder(
                        cornerRadius: 22,
                        side: BorderSide(color: palette.outline, width: 0.7),
                      ),
                    ),
                    child: rows,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: vertical),
                    child: Align(alignment: Alignment.topCenter, child: rows),
                  ),
          );
        },
      ),
    );
  }
}

// ===== 歌曲卡组 =====

/// 三首一页的横滑歌曲卡组。点哪首就以整组为队列从哪首开播。
class SpotifySongPager extends StatelessWidget {
  const SpotifySongPager({
    super.key,
    required this.tracks,
    required this.playback,
    required this.storageKey,
  });

  final List<Track> tracks;
  final PlaybackController playback;
  final String storageKey;

  static double rowHeightFor(BuildContext context) =>
      math.max(62.0, _line(context, 14) + _line(context, 11.5) + 26);

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: _PagedRows(
      storageKey: storageKey,
      itemCount: tracks.length,
      rowsPerPage: 3,
      rowHeight: rowHeightFor(context),
      itemBuilder: (context, index) => _PagerSongRow(
        track: tracks[index],
        playback: playback,
        onPlay: () => playback.playTrack(tracks[index], queue: tracks),
      ),
    ),
  );
}

/// 卡组里的一行歌。只在「是否为当前曲目」翻转时重建，播放进度不打扰它
/// （与 HomeSongRow 同一做法）。
class _PagerSongRow extends StatefulWidget {
  const _PagerSongRow({
    required this.track,
    required this.playback,
    required this.onPlay,
  });

  final Track track;
  final PlaybackController playback;
  final VoidCallback onPlay;

  @override
  State<_PagerSongRow> createState() => _PagerSongRowState();
}

class _PagerSongRowState extends State<_PagerSongRow> {
  late bool _active = _isActive();

  bool _isActive() =>
      widget.playback.state.currentTrack?.key == widget.track.key;

  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_onPlayback);
  }

  @override
  void didUpdateWidget(_PagerSongRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playback, widget.playback)) {
      oldWidget.playback.removeListener(_onPlayback);
      widget.playback.addListener(_onPlayback);
    }
    _active = _isActive();
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlayback);
    super.dispose();
  }

  void _onPlayback() {
    final active = _isActive();
    if (active != _active) setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final track = widget.track;
    return MiuixPressable(
      onPressed: widget.onPlay,
      semanticLabel: '${track.name} ${track.artists}',
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            ForYouArtwork(url: track.picUrl, size: 48, cornerRadius: 12),
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
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: _active ? palette.accent : palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote2.copyWith(
                      fontSize: 11.5,
                      height: 1.35,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _active ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
              size: 20,
              color: _active ? palette.accent : palette.muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 排行榜 =====

/// 一排横滑的榜单卡，每张只露前三名。点卡头进榜单详情，点某一行直接播。
class SpotifyChartCarousel extends StatelessWidget {
  const SpotifyChartCarousel({
    super.key,
    required this.toplists,
    required this.tracksFor,
    required this.onOpen,
    required this.playback,
  });

  final List<Toplist> toplists;
  final List<Track> Function(Toplist toplist) tracksFor;
  final ValueChanged<Toplist> onOpen;
  final PlaybackController playback;

  static const _rows = 3;

  double _rowHeight(BuildContext context) =>
      math.max(34.0, _line(context, 13.5) + 12);

  double _heightFor(BuildContext context) =>
      16 +
      math.max(58.0, _line(context, 17, 1.3) + 4 + _line(context, 11.5)) +
      10 +
      _rowHeight(context) * _rows +
      12;

  @override
  Widget build(BuildContext context) {
    final charts = [
      for (final toplist in toplists)
        if (tracksFor(toplist).isNotEmpty) toplist,
    ];
    if (charts.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth * 0.8).clamp(260.0, 340.0);
          return SizedBox(
            height: _heightFor(context),
            child: ListView.separated(
              key: const PageStorageKey('home-spotify-charts'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: charts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: width,
                child: _ChartCard(
                  toplist: charts[index],
                  tracks: tracksFor(charts[index]),
                  tone: index,
                  rowHeight: _rowHeight(context),
                  onOpen: () => onOpen(charts[index]),
                  playback: playback,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.toplist,
    required this.tracks,
    required this.tone,
    required this.rowHeight,
    required this.onOpen,
    required this.playback,
  });

  final Toplist toplist;
  final List<Track> tracks;
  final int tone;
  final double rowHeight;
  final VoidCallback onOpen;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    // 四种纸色轮换，相邻两张榜单卡不同色；鼠尾草底配深绿名次，其余用陶土色。
    final (tint, rankColor) = switch (tone % 4) {
      0 => (palette.peach, palette.accent),
      1 => (palette.sage, palette.sageAccent),
      2 => (palette.rose, palette.accent),
      _ => (palette.paper, palette.accent),
    };
    final description = toplist.description.trim();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, palette.paper],
          stops: const [0, 0.85],
        ),
        shape: MiuixSquircleBorder(
          cornerRadius: 24,
          side: BorderSide(color: palette.outline, width: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuixPressable(
            onPressed: onOpen,
            semanticLabel: toplist.name,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                toplist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textStyles.headline1.copyWith(
                                  fontSize: 17,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: palette.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description.isNotEmpty ? description : '热门曲目实时更新',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.footnote2.copyWith(
                            fontSize: 11.5,
                            height: 1.35,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ForYouArtwork(
                    url: toplist.coverImgUrl.isNotEmpty
                        ? toplist.coverImgUrl
                        : tracks.first.picUrl,
                    size: 58,
                    cornerRadius: 14,
                  ),
                ],
              ),
            ),
          ),
          for (
            var i = 0;
            i < math.min(SpotifyChartCarousel._rows, tracks.length);
            i++
          )
            SizedBox(
              height: rowHeight,
              child: MiuixPressable(
                onPressed: () => playback.playTrack(tracks[i], queue: tracks),
                semanticLabel: '第 ${i + 1} 名 ${tracks[i].name}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${i + 1}',
                          style: theme.textStyles.body1.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontStyle: FontStyle.italic,
                            color: rankColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: tracks[i].name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: palette.ink,
                                ),
                              ),
                              TextSpan(
                                text: '  ${tracks[i].artists}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.muted,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.body2.copyWith(
                            fontSize: 13.5,
                            height: 1.3,
                          ),
                        ),
                      ),
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

// ===== 个性化分区：艺人 =====

/// 圆形头像一排，像通讯录里的常用联系人。
class SpotifyArtistRow extends StatelessWidget {
  const SpotifyArtistRow({
    super.key,
    required this.items,
    required this.onOpen,
    required this.storageKey,
  });

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    const avatar = 76.0;
    return SizedBox(
      height: avatar + 10 + _line(context, 12.5) + 4,
      child: ListView.separated(
        key: PageStorageKey(storageKey),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          return MiuixPressable(
            onPressed: () => onOpen(item),
            semanticLabel: item.name,
            feedbackType: MiuixPressFeedbackType.sink,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: avatar + 8,
              child: Column(
                children: [
                  Container(
                    width: avatar,
                    height: avatar,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: palette.accent.withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                    ),
                    child: ClipOval(
                      child: ForYouArtwork(
                        url: item.coverImgUrl,
                        cornerRadius: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textStyles.footnote1.copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===== 个性化分区：专辑 =====

/// 唱片架：封面右侧露出半张黑胶，一眼就知道是专辑而不是歌单。
class SpotifyAlbumShelf extends StatelessWidget {
  const SpotifyAlbumShelf({
    super.key,
    required this.items,
    required this.onOpen,
    required this.storageKey,
  });

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    const cover = 112.0;
    const width = cover + 26;
    return SizedBox(
      height: cover + 12 + _line(context, 13.5) * 2 + 2 + _line(context, 11.5),
      child: ListView.separated(
        key: PageStorageKey(storageKey),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          return MiuixPressable(
            onPressed: () => onOpen(item),
            semanticLabel: item.name,
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.97,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: width,
                    height: cover,
                    child: Stack(
                      children: [
                        Positioned(
                          right: 0,
                          top: 6,
                          child: ForYouRecord(
                            coverUrl: item.coverImgUrl,
                            size: cover - 12,
                          ),
                        ),
                        Container(
                          decoration: ShapeDecoration(
                            shape: const MiuixSquircleBorder(cornerRadius: 14),
                            shadows: [
                              BoxShadow(
                                color: palette.shadow,
                                blurRadius: 12,
                                offset: const Offset(4, 5),
                              ),
                            ],
                          ),
                          child: ForYouArtwork(
                            url: item.coverImgUrl,
                            size: cover,
                            cornerRadius: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.body2.copyWith(
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.footnote2.copyWith(
                      fontSize: 11.5,
                      height: 1.35,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===== 个性化分区：歌单 / 混排的四种版式 =====

/// 歌单与混排分区轮换使用的版式。
enum SpotifyCollectionLayout {
  /// 一大两小的拼版，余下的收进下方小卡横排。
  mosaic,

  /// 方形封面横排。
  shelf,

  /// 宽幅封面横排。
  wide,

  /// 三行一页的列表横滑。
  list,
}

class SpotifyCollectionSection extends StatelessWidget {
  const SpotifyCollectionSection({
    super.key,
    required this.items,
    required this.layout,
    required this.onOpen,
    required this.storageKey,
  });

  final List<SpotifyPlaylistPreview> items;
  final SpotifyCollectionLayout layout;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    final effective =
        layout == SpotifyCollectionLayout.mosaic && items.length < 3
        ? SpotifyCollectionLayout.shelf
        : layout;
    return RepaintBoundary(
      child: switch (effective) {
        SpotifyCollectionLayout.mosaic => _Mosaic(
          items: items,
          onOpen: onOpen,
          storageKey: storageKey,
        ),
        SpotifyCollectionLayout.shelf => _SquareShelf(
          items: items,
          onOpen: onOpen,
          storageKey: storageKey,
          fraction: 0.4,
        ),
        SpotifyCollectionLayout.wide => _WideShelf(
          items: items,
          onOpen: onOpen,
          storageKey: storageKey,
        ),
        SpotifyCollectionLayout.list => _ListPager(
          items: items,
          onOpen: onOpen,
          storageKey: storageKey,
        ),
      },
    );
  }
}

/// 封面上叠渐变与文字的卡片，拼版的大小格共用。
class _OverlayTile extends StatelessWidget {
  const _OverlayTile({
    required this.item,
    required this.onOpen,
    this.large = false,
  });

  final SpotifyPlaylistPreview item;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    const radius = 20.0;
    return MiuixPressable(
      onPressed: () => onOpen(item),
      semanticLabel: item.name,
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.97,
      shape: const MiuixSquircleBorder(cornerRadius: radius),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: const ShapeDecoration(
          shape: MiuixSquircleBorder(cornerRadius: radius),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ForYouArtwork(url: item.coverImgUrl, cornerRadius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x10000000),
                    Color(0xC8141216),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 10,
              child: _KindTag(label: spotifyKindLabel(item.itemKind)),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: large ? 14 : 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyles.body1.copyWith(
                      fontSize: large ? 17 : 13.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (large && item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.footnote2.copyWith(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTag extends StatelessWidget {
  const _KindTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x66000000),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x30FFFFFF), width: 0.6),
    ),
    child: Text(
      label,
      style: MiuixTheme.of(
        context,
      ).textStyles.footnote2.copyWith(fontSize: 10, color: Colors.white),
    ),
  );
}

class _Mosaic extends StatelessWidget {
  const _Mosaic({
    required this.items,
    required this.onOpen,
    required this.storageKey,
  });

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    final rest = items.skip(3).toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final big = ((constraints.maxWidth - gap) * 0.56).floorToDouble();
              return SizedBox(
                height: big,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: big,
                      child: _OverlayTile(
                        item: items[0],
                        onOpen: onOpen,
                        large: true,
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _OverlayTile(item: items[1], onOpen: onOpen),
                          ),
                          const SizedBox(height: gap),
                          Expanded(
                            child: _OverlayTile(item: items[2], onOpen: onOpen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SquareShelf(
            items: rest,
            onOpen: onOpen,
            storageKey: '$storageKey-rest',
            fraction: 0.28,
            showCaption: false,
          ),
        ],
      ],
    );
  }
}

class _SquareShelf extends StatelessWidget {
  const _SquareShelf({
    required this.items,
    required this.onOpen,
    required this.storageKey,
    required this.fraction,
    this.showCaption = true,
  });

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;
  final double fraction;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * fraction).clamp(100.0, 180.0);
        final height =
            width +
            10 +
            _line(context, 13.5) * 2 +
            (showCaption ? 3 + _line(context, 11.5) : 0);
        return SizedBox(
          height: height,
          child: ListView.separated(
            key: PageStorageKey(storageKey),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final artist = item.itemKind == SpotifyPersonalizedKind.artist;
              return MiuixPressable(
                onPressed: () => onOpen(item),
                semanticLabel: item.name,
                feedbackType: MiuixPressFeedbackType.sink,
                sinkAmount: 0.97,
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.square(
                        dimension: width,
                        child: artist
                            ? ClipOval(
                                child: ForYouArtwork(
                                  url: item.coverImgUrl,
                                  cornerRadius: 0,
                                ),
                              )
                            : ForYouArtwork(
                                url: item.coverImgUrl,
                                cornerRadius: 18,
                              ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.body2.copyWith(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      if (showCaption) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.description.isNotEmpty
                              ? item.description
                              : spotifyKindLabel(item.itemKind),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textStyles.footnote2.copyWith(
                            fontSize: 11.5,
                            height: 1.35,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WideShelf extends StatelessWidget {
  const _WideShelf({
    required this.items,
    required this.onOpen,
    required this.storageKey,
  });

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth * 0.7).clamp(232.0, 300.0);
      return SizedBox(
        height: ForYouSpotlightPlaylist.heightFor(context, compact: true),
        child: ListView.separated(
          key: PageStorageKey(storageKey),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = items[index];
            return SizedBox(
              width: width,
              child: ForYouSpotlightPlaylist(
                // 卡片不读 id，跳转所需的 id 由闭包里的 item 带着。
                data: ForYouPlaylistData(
                  id: 0,
                  name: item.name,
                  coverUrl: item.coverImgUrl,
                  description: item.description,
                  trackCount: item.trackCount,
                ),
                compact: true,
                label: spotifyKindLabel(item.itemKind),
                onTap: (_) => onOpen(item),
              ),
            );
          },
        ),
      );
    },
  );
}

class _ListPager extends StatelessWidget {
  const _ListPager({
    required this.items,
    required this.onOpen,
    required this.storageKey,
  });

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return _PagedRows(
      storageKey: storageKey,
      itemCount: items.length,
      rowsPerPage: 3,
      surface: false,
      rowHeight: math.max(72.0, _line(context, 14) + _line(context, 11.5) + 30),
      itemBuilder: (context, index) {
        final item = items[index];
        final artist = item.itemKind == SpotifyPersonalizedKind.artist;
        final caption = [
          spotifyKindLabel(item.itemKind),
          if (item.trackCount > 0) '${item.trackCount} 首',
          if (item.description.isNotEmpty) item.description,
        ].join(' · ');
        return MiuixPressable(
          onPressed: () => onOpen(item),
          semanticLabel: item.name,
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.98,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 60,
                  child: artist
                      ? ClipOval(
                          child: ForYouArtwork(
                            url: item.coverImgUrl,
                            cornerRadius: 0,
                          ),
                        )
                      : ForYouArtwork(url: item.coverImgUrl, cornerRadius: 15),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.body2.copyWith(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.footnote2.copyWith(
                          fontSize: 11.5,
                          height: 1.35,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
