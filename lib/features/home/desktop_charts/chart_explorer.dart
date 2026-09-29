part of 'desktop_charts_home.dart';

/// 排行榜：左栏竖排全部榜单，右栏是选中榜单的封面 + Top 10。
/// 窄屏时左栏收成一排可换行的榜单标签，详情落到下方。
class _ChartExplorer extends StatefulWidget {
  const _ChartExplorer({
    required this.entries,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlay,
    required this.onPlayAll,
    required this.onOpen,
  });

  final List<DesktopChartEntry> entries;
  final Track? currentTrack;
  final bool isPlaying;
  final _PlayTracks onPlay;
  final ValueChanged<DesktopChartEntry> onPlayAll;
  final ValueChanged<Toplist> onOpen;

  static const _topCount = 10;

  @override
  State<_ChartExplorer> createState() => _ChartExplorerState();
}

class _ChartExplorerState extends State<_ChartExplorer> {
  /// 按榜单 id 记住选中项：刷新后榜单顺序变了也不会跳到别的榜。
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    var index = entries.indexWhere((entry) => entry.toplist.id == _selectedId);
    if (index < 0) index = 0;
    final selected = entries[index];

    void select(DesktopChartEntry entry) =>
        setState(() => _selectedId = entry.toplist.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860 && _textScale(context) <= 1.4;
        final detail = AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: _ChartDetail(
            key: ValueKey('desktop-chart-detail-${selected.toplist.id}'),
            entry: selected,
            index: index,
            currentTrack: widget.currentTrack,
            isPlaying: widget.isPlaying,
            onPlay: widget.onPlay,
            onPlayAll: () => widget.onPlayAll(selected),
            onOpen: () => widget.onOpen(selected.toplist),
          ),
        );
        return _PaperSurface(
          key: const ValueKey('desktop-chart-explorer'),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          for (final (i, entry) in entries.indexed)
                            _RailItem(
                              entry: entry,
                              index: i,
                              selected: i == index,
                              onPressed: () => select(entry),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: detail),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (i, entry) in entries.indexed)
                            _ChartChip(
                              entry: entry,
                              selected: i == index,
                              onPressed: () => select(entry),
                            ),
                        ],
                      ),
                    ),
                    detail,
                  ],
                ),
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.entry,
    required this.index,
    required this.selected,
    required this.onPressed,
  });

  final DesktopChartEntry entry;
  final int index;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final (tint, accent) = _tone(palette, index);
    final lead = entry.tracks.firstOrNull;
    return Semantics(
      selected: selected,
      child: MiuixPressable(
        onPressed: onPressed,
        semanticLabel: '查看${entry.toplist.name}',
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          key: ValueKey('desktop-chart-${entry.toplist.id}'),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? tint : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              ForYouArtwork(
                url: lead?.picUrl ?? entry.toplist.coverImgUrl,
                size: 46,
                cornerRadius: 13,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.toplist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body2.copyWith(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lead == null ? '暂无曲目' : '榜首 · ${lead.name}',
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
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: selected ? 1 : 0,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartChip extends StatelessWidget {
  const _ChartChip({
    required this.entry,
    required this.selected,
    required this.onPressed,
  });

  final DesktopChartEntry entry;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    return Semantics(
      selected: selected,
      child: MiuixPressable(
        onPressed: onPressed,
        semanticLabel: '查看${entry.toplist.name}',
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          key: ValueKey('desktop-chart-${entry.toplist.id}'),
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            color: selected ? palette.accent : palette.paper,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? palette.accent : palette.outline,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: ForYouArtwork(
                  url:
                      entry.tracks.firstOrNull?.picUrl ??
                      entry.toplist.coverImgUrl,
                  size: 26,
                  cornerRadius: 0,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  entry.toplist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote1.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? palette.onAccent : palette.ink,
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

class _ChartDetail extends StatelessWidget {
  const _ChartDetail({
    super.key,
    required this.entry,
    required this.index,
    required this.currentTrack,
    required this.isPlaying,
    required this.onPlay,
    required this.onPlayAll,
    required this.onOpen,
  });

  final DesktopChartEntry entry;
  final int index;
  final Track? currentTrack;
  final bool isPlaying;
  final _PlayTracks onPlay;
  final VoidCallback onPlayAll;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final palette = ForYouPalette.of(context);
    final (tint, accent) = _tone(palette, index);
    final toplist = entry.toplist;
    final tracks = entry.tracks;
    final top = tracks.take(_ChartExplorer._topCount).toList(growable: false);
    final description = toplist.description.trim();
    final coverUrl = tracks.firstOrNull?.picUrl ?? toplist.coverImgUrl;

    final header = _Hover(
      builder: (context, hovered) => LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 560 || _textScale(context) > 1.4;
          final coverSize = compact ? 96.0 : 150.0;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '第 ${index + 1} 张榜单 · ${tracks.length} 首 · 实时更新',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.footnote1.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                toplist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.title1.copyWith(
                  fontSize: compact ? 22 : 28,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: palette.ink,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    fontSize: 13,
                    height: 1.45,
                    color: palette.muted,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AccentButton(
                    label: '播放全部',
                    icon: Icons.play_arrow_rounded,
                    semanticLabel: '播放${toplist.name}',
                    onPressed: tracks.isEmpty ? null : onPlayAll,
                  ),
                  _GhostButton(
                    label: '完整榜单',
                    trailingIcon: Icons.arrow_forward_rounded,
                    semanticLabel: '查看${toplist.name}完整榜单',
                    onPressed: onOpen,
                  ),
                ],
              ),
            ],
          );
          return Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint, tint.withValues(alpha: 0)],
                stops: const [0, 0.9],
              ),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CoverWithRecord(
                        url: coverUrl,
                        size: coverSize,
                        out: hovered,
                      ),
                      const SizedBox(height: 16),
                      info,
                    ],
                  )
                : Row(
                    children: [
                      _CoverWithRecord(
                        url: coverUrl,
                        size: coverSize,
                        out: hovered,
                      ),
                      const SizedBox(width: 26),
                      Expanded(child: info),
                    ],
                  ),
          );
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 8),
        if (top.isEmpty)
          SizedBox(
            height: 180,
            child: Center(
              child: Text(
                '暂无可播放曲目',
                style: theme.textStyles.body2.copyWith(color: palette.muted),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 700 && _textScale(context) <= 1.4
                  ? 2
                  : 1;
              final perColumn = (top.length / columns).ceil();
              Widget row(int i) => _SongRow(
                track: top[i],
                rank: i + 1,
                rankColor: accent,
                active: top[i].key == currentTrack?.key,
                isPlaying: isPlaying,
                showDuration: columns == 1,
                onPressed: () => onPlay(top[i], tracks),
              );
              // 名次按列排：左列 1–5，右列 6–10，读起来是一张榜。
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
                            i < math.min((c + 1) * perColumn, top.length);
                            i++
                          )
                            row(i),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        if (tracks.length > top.length)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: MiuixPressable(
                onPressed: onOpen,
                semanticLabel: '查看${toplist.name}其余曲目',
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '还有 ${tracks.length - top.length} 首',
                        style: theme.textStyles.footnote1.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.muted,
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
              ),
            ),
          ),
      ],
    );
  }
}

/// 专辑封面后面藏一张黑胶，悬停时滑出来一截。
class _CoverWithRecord extends StatelessWidget {
  const _CoverWithRecord({
    required this.url,
    required this.size,
    required this.out,
  });

  final String url;
  final double size;
  final bool out;

  @override
  Widget build(BuildContext context) {
    final palette = ForYouPalette.of(context);
    final record = size * 0.9;
    return ExcludeSemantics(
      child: SizedBox(
        width: size * 1.36,
        height: size,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              left: out ? size * 0.46 : size * 0.3,
              top: (size - record) / 2,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                turns: out ? 0.16 : 0,
                child: ForYouRecord(coverUrl: url, size: record),
              ),
            ),
            Container(
              decoration: ShapeDecoration(
                shape: const MiuixSquircleBorder(cornerRadius: 22),
                shadows: [
                  BoxShadow(
                    color: palette.shadow.withValues(
                      alpha: palette.shadow.a * 1.8,
                    ),
                    blurRadius: 18,
                    offset: const Offset(5, 8),
                  ),
                ],
              ),
              child: ForYouArtwork(url: url, size: size, cornerRadius: 22),
            ),
          ],
        ),
      ),
    );
  }
}
