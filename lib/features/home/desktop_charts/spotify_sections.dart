part of 'desktop_charts_home.dart';

/// 个性化分区的桌面版式。与移动端同一思路——按内容类型换版式，避免二十来个
/// 分区一个模样：艺人是圆形头像、专辑露出半张黑胶、歌曲是分栏列表，歌单类
/// 分区在拼版 / 方卡 / 宽幅 / 列表之间轮换。
///
/// 一排放不下的内容用翻页箭头换页，而不是横向滚动（见 [DesktopChartsHome]）。
class _SpotifySectionView extends StatelessWidget {
  const _SpotifySectionView({
    super.key,
    required this.section,
    required this.rotation,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlay,
    required this.onPlayAll,
    required this.onOpen,
  });

  final DesktopSpotifySection section;
  final int rotation;
  final Track? currentTrack;
  final bool isPlaying;

  /// 点某一首：当前曲目则暂停 / 继续。
  final _PlayTracks onPlay;

  /// 「播放全部」：总是从头开播。
  final _PlayTracks onPlayAll;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = section.items;
    switch (section.kind) {
      case SpotifyPersonalizedKind.track:
        final tracks = section.tracks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(
              title: section.title,
              subtitle: section.description,
              trailing: _GhostButton(
                label: '播放全部',
                icon: Icons.play_arrow_rounded,
                semanticLabel: '播放全部：${section.title}',
                onPressed: tracks.isEmpty
                    ? null
                    : () => onPlayAll(tracks.first, tracks),
              ),
            ),
            _SongColumns(
              tracks: tracks,
              currentTrack: currentTrack,
              isPlaying: isPlaying,
              onPlay: onPlay,
            ),
          ],
        );
      case SpotifyPersonalizedKind.artist:
        return _PagedStrip(
          title: section.title,
          subtitle: section.description,
          itemCount: items.length,
          target: 138,
          itemBuilder: (context, index, width) =>
              _ArtistTile(item: items[index], width: width, onOpen: onOpen),
        );
      case SpotifyPersonalizedKind.album:
        return _PagedStrip(
          title: section.title,
          subtitle: section.description,
          itemCount: items.length,
          target: 204,
          itemBuilder: (context, index, width) =>
              _VinylTile(item: items[index], width: width, onOpen: onOpen),
        );
      case SpotifyPersonalizedKind.playlist:
      case SpotifyPersonalizedKind.radio:
      case SpotifyPersonalizedKind.mixed:
        final shelf = _PagedStrip(
          title: section.title,
          subtitle: section.description,
          itemCount: items.length,
          target: 184,
          itemBuilder: (context, index, width) =>
              _CoverTile(item: items[index], onOpen: onOpen),
        );
        return switch (rotation % 4) {
          0 => _Bento(section: section, onOpen: onOpen, fallback: shelf),
          1 => shelf,
          2 => _PagedStrip(
            title: section.title,
            subtitle: section.description,
            itemCount: items.length,
            target: 340,
            itemBuilder: (context, index, width) => SizedBox(
              height: (width * 0.56).clamp(180.0, 240.0),
              child: _OverlayTile(item: items[index], onOpen: onOpen),
            ),
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(title: section.title, subtitle: section.description),
              _ListColumns(items: items, onOpen: onOpen),
            ],
          ),
        };
    }
  }
}

/// 一排定宽卡片 + 标题栏右侧的翻页箭头。列数随宽度变化，翻页带淡入滑动。
class _PagedStrip extends StatefulWidget {
  const _PagedStrip({
    required this.title,
    required this.subtitle,
    required this.itemCount,
    required this.target,
    required this.itemBuilder,
  });

  final String title;
  final String subtitle;
  final int itemCount;

  /// 期望的卡片宽度，实际宽度会拉伸到刚好铺满一排。
  final double target;
  final Widget Function(BuildContext context, int index, double width)
  itemBuilder;

  @override
  State<_PagedStrip> createState() => _PagedStripState();
}

class _PagedStripState extends State<_PagedStrip> {
  var _page = 0;
  var _forward = true;

  static const _gap = 18.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final target = widget.target * math.max(1.0, _textScale(context) * 0.85);
      final columns = ((constraints.maxWidth + _gap) / (target + _gap))
          .floor()
          .clamp(2, 10);
      final width = (constraints.maxWidth - _gap * (columns - 1)) / columns;
      final pages = math.max(1, (widget.itemCount / columns).ceil());
      final page = _page.clamp(0, pages - 1);
      final start = page * columns;
      final end = math.min(start + columns, widget.itemCount);

      void go(int delta) => setState(() {
        _forward = delta > 0;
        _page = (page + delta).clamp(0, pages - 1);
      });

      final pageKey = ValueKey(page);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: pages > 1
                ? _PagerArrows(
                    title: widget.title,
                    page: page,
                    pages: pages,
                    onPrevious: page > 0 ? () => go(-1) : null,
                    onNext: page < pages - 1 ? () => go(1) : null,
                  )
                : null,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.topStart,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) {
              // 新页从翻页方向滑入，旧页朝反方向退出。
              final incoming = child.key == pageKey;
              final dx = (_forward == incoming ? 1 : -1) * 0.05;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(dx, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Row(
              key: pageKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = start; i < end; i++) ...[
                  if (i > start) const SizedBox(width: _gap),
                  SizedBox(
                    width: width,
                    child: widget.itemBuilder(context, i, width),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _PagerArrows extends StatelessWidget {
  const _PagerArrows({
    required this.title,
    required this.page,
    required this.pages,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final int page;
  final int pages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${page + 1} / $pages',
          style: theme.textStyles.footnote1.copyWith(
            fontSize: 12,
            color: palette.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        _RoundButton(
          label: '上一页：$title',
          icon: Icons.chevron_left_rounded,
          onPressed: onPrevious,
          size: 34,
        ),
        const SizedBox(width: 6),
        _RoundButton(
          label: '下一页：$title',
          icon: Icons.chevron_right_rounded,
          onPressed: onNext,
          size: 34,
        ),
      ],
    );
  }
}

String _caption(SpotifyPlaylistPreview item) => [
  spotifyKindLabel(item.itemKind),
  if (item.trackCount > 0) '${item.trackCount} 首',
  if (item.description.isNotEmpty) item.description,
].join(' · ');

/// 圆形头像，悬停时微微放大。
class _ArtistTile extends StatelessWidget {
  const _ArtistTile({
    required this.item,
    required this.width,
    required this.onOpen,
  });

  final SpotifyPlaylistPreview item;
  final double width;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final avatar = width - 12;
    return _Hover(
      builder: (context, hovered) => MiuixPressable(
        onPressed: () => onOpen(item),
        semanticLabel: item.name,
        feedbackType: MiuixPressFeedbackType.sink,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            AnimatedScale(
              duration: _kHoverDuration,
              curve: Curves.easeOutCubic,
              scale: hovered ? 1.04 : 1,
              child: Container(
                width: avatar,
                height: avatar,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.accent.withValues(
                      alpha: hovered ? 0.55 : 0.25,
                    ),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: hovered ? 20 : 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: ForYouArtwork(url: item.coverImgUrl, cornerRadius: 0),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textStyles.body2.copyWith(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '艺人',
              style: theme.textStyles.footnote2.copyWith(
                fontSize: 11.5,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 专辑：封面右侧露出半张黑胶，悬停时黑胶滑出并转一点。
class _VinylTile extends StatelessWidget {
  const _VinylTile({
    required this.item,
    required this.width,
    required this.onOpen,
  });

  final SpotifyPlaylistPreview item;
  final double width;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final cover = width * 0.74;
    final record = cover * 0.92;
    return _Hover(
      builder: (context, hovered) => MiuixPressable(
        onPressed: () => onOpen(item),
        semanticLabel: item.name,
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.97,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: cover,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    left: hovered ? width - record : cover * 0.26,
                    top: (cover - record) / 2,
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      turns: hovered ? 0.2 : 0,
                      child: ForYouRecord(
                        coverUrl: item.coverImgUrl,
                        size: record,
                      ),
                    ),
                  ),
                  Container(
                    decoration: ShapeDecoration(
                      shape: const MiuixSquircleBorder(cornerRadius: 16),
                      shadows: [
                        BoxShadow(
                          color: palette.shadow.withValues(
                            alpha: palette.shadow.a * 1.8,
                          ),
                          blurRadius: 14,
                          offset: const Offset(4, 6),
                        ),
                      ],
                    ),
                    child: ForYouArtwork(
                      url: item.coverImgUrl,
                      size: cover,
                      cornerRadius: 16,
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
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.description.isNotEmpty ? item.description : '专辑',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote2.copyWith(
                fontSize: 12,
                height: 1.35,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方形封面卡：左上角类型角标，悬停抬起并浮出箭头。
class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.item, required this.onOpen});

  final SpotifyPlaylistPreview item;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final artist = item.itemKind == SpotifyPersonalizedKind.artist;
    return _Hover(
      builder: (context, hovered) => MiuixPressable(
        onPressed: () => onOpen(item),
        semanticLabel: item.name,
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.97,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LiftedArtwork(
              hovered: hovered,
              radius: artist ? 999 : 20,
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (artist)
                      ClipOval(
                        child: ForYouArtwork(
                          url: item.coverImgUrl,
                          cornerRadius: 0,
                        ),
                      )
                    else
                      ForYouArtwork(url: item.coverImgUrl, cornerRadius: 20),
                    if (!artist)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: _KindTag(label: spotifyKindLabel(item.itemKind)),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: AnimatedOpacity(
                        duration: _kHoverDuration,
                        opacity: hovered ? 1 : 0,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: palette.paper,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_outward_rounded,
                            size: 18,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              item.name,
              maxLines: 2,
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
              item.description.isNotEmpty
                  ? item.description
                  : spotifyKindLabel(item.itemKind),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyles.footnote2.copyWith(
                fontSize: 12,
                height: 1.35,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面铺满、文字压在底部渐变上的卡片。拼版的大小格与宽幅卡共用；
/// 悬停时封面在卡内缓慢放大。
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
    final palette = ForYouPalette.of(context);
    const radius = 22.0;
    return _Hover(
      builder: (context, hovered) => MiuixPressable(
        onPressed: () => onOpen(item),
        semanticLabel: item.name,
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        shape: const MiuixSquircleBorder(cornerRadius: radius),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: const ShapeDecoration(
            shape: MiuixSquircleBorder(cornerRadius: radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                scale: hovered ? 1.06 : 1,
                child: ForYouArtwork(url: item.coverImgUrl, cornerRadius: 0),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x14000000),
                      Color(0xCC141216),
                    ],
                    stops: [0, 0.42, 1],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 12,
                child: _KindTag(label: spotifyKindLabel(item.itemKind)),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: AnimatedOpacity(
                  duration: _kHoverDuration,
                  opacity: hovered ? 1 : 0,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.paper,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_outward_rounded,
                      size: 17,
                      color: palette.ink,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: large ? 18 : 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body1.copyWith(
                        fontSize: large ? 22 : 15,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        maxLines: large ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.footnote2.copyWith(
                          fontSize: large ? 13 : 11.5,
                          height: 1.4,
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
      ),
    );
  }
}

/// 拼版：左边一张 2×2 的大卡，右边两排小卡。太窄或数量不够时退回方卡横排。
class _Bento extends StatelessWidget {
  const _Bento({
    required this.section,
    required this.onOpen,
    required this.fallback,
  });

  final DesktopSpotifySection section;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;
  final Widget fallback;

  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final items = section.items;
      final width = constraints.maxWidth;
      final wanted = width >= 1180
          ? 4
          : width >= 900
          ? 3
          : 2;
      final smallColumns = math.min(wanted, (items.length - 1) ~/ 2);
      if (width < 720 || smallColumns < 2 || _textScale(context) > 1.4) {
        return fallback;
      }
      final total = 2 + smallColumns;
      final cell = (width - _gap * (total - 1)) / total;
      final big = cell * 2 + _gap;
      Widget small(int index) => SizedBox.square(
        dimension: cell,
        child: _OverlayTile(item: items[index], onOpen: onOpen),
      );
      Widget row(int from) => Row(
        children: [
          for (var i = 0; i < smallColumns; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            small(from + i),
          ],
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(title: section.title, subtitle: section.description),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: big,
                child: _OverlayTile(
                  item: items[0],
                  onOpen: onOpen,
                  large: true,
                ),
              ),
              const SizedBox(width: _gap),
              Column(
                children: [
                  row(1),
                  const SizedBox(height: _gap),
                  row(1 + smallColumns),
                ],
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// 三行一栏的列表，按列排满后换下一栏。
class _ListColumns extends StatelessWidget {
  const _ListColumns({required this.items, required this.onOpen});

  final List<SpotifyPlaylistPreview> items;
  final ValueChanged<SpotifyPlaylistPreview> onOpen;

  static const _rows = 3;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return _PaperSurface(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / math.max(1, _textScale(context));
          final columns = width >= 1000
              ? 3
              : width >= 640
              ? 2
              : 1;
          final shown = items.take(columns * _rows).toList(growable: false);
          final perColumn = (shown.length / columns).ceil();
          Widget tile(SpotifyPlaylistPreview item) {
            final artist = item.itemKind == SpotifyPersonalizedKind.artist;
            return MiuixPressable(
              onPressed: () => onOpen(item),
              semanticLabel: item.name,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(8),
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
                          : ForYouArtwork(
                              url: item.coverImgUrl,
                              cornerRadius: 15,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
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
                            _caption(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.footnote2.copyWith(
                              fontSize: 12,
                              height: 1.35,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: palette.muted,
                    ),
                  ],
                ),
              ),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      for (
                        var i = c * perColumn;
                        i < math.min((c + 1) * perColumn, shown.length);
                        i++
                      )
                        tile(shown[i]),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 歌曲分区：纸张底卡上的分栏歌曲列表，每栏四首。
class _SongColumns extends StatelessWidget {
  const _SongColumns({
    required this.tracks,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlay,
  });

  final List<Track> tracks;
  final Track? currentTrack;
  final bool isPlaying;
  final _PlayTracks onPlay;

  static const _rows = 4;

  @override
  Widget build(BuildContext context) => _PaperSurface(
    padding: const EdgeInsets.all(8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / math.max(1, _textScale(context));
        final columns = width >= 1100
            ? 3
            : width >= 700
            ? 2
            : 1;
        final shown = tracks.take(columns * _rows).toList(growable: false);
        final perColumn = (shown.length / columns).ceil();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    for (
                      var i = c * perColumn;
                      i < math.min((c + 1) * perColumn, shown.length);
                      i++
                    )
                      _SongRow(
                        track: shown[i],
                        active: shown[i].key == currentTrack?.key,
                        isPlaying: isPlaying,
                        onPressed: () => onPlay(shown[i], tracks),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
