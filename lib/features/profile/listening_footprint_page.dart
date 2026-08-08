import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../domain/models/listening_stats.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/listening_stats_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';

/// 听歌足迹页（对应 Next.js demo/app/footprint/page.tsx）。
///
/// 四块：累计统计（聆听时长 + 播放次数）、本周唱片墙、听歌语言占比、播放排行。
class ListeningFootprintPage extends StatefulWidget {
  const ListeningFootprintPage({
    super.key,
    required this.account,
    this.playback,
    this.desktopLayout = false,
  });

  final AccountSessionController account;
  final PlaybackController? playback;
  final bool desktopLayout;

  @override
  State<ListeningFootprintPage> createState() => _ListeningFootprintPageState();
}

class _ListeningFootprintPageState extends State<ListeningFootprintPage> {
  var _loading = false;
  var _requestId = 0;
  String? _error;
  String? _loadedToken;
  ListeningStatsData? _stats;
  List<WeeklyPlayItem>? _weekly;
  LanguageStatsData? _languages;

  @override
  void initState() {
    super.initState();
    widget.account.addListener(_onAccountChanged);
    _load();
  }

  @override
  void dispose() {
    widget.account.removeListener(_onAccountChanged);
    _requestId++;
    super.dispose();
  }

  /// 会话异步恢复完成（或重新登录）后补拉数据：进页时 token 可能尚未就绪。
  void _onAccountChanged() {
    if (widget.account.token != _loadedToken) _load();
  }

  Future<void> _load() async {
    final token = widget.account.token;
    _loadedToken = token;
    if (token == null) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ListeningStatsService.instance.fetchStats(token),
        ListeningStatsService.instance.fetchWeeklyPlays(token),
        ListeningStatsService.instance.fetchLanguageStats(token),
      ]);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _stats = results[0] as ListeningStatsData?;
        _weekly = results[1] as List<WeeklyPlayItem>?;
        _languages = results[2] as LanguageStatsData?;
        _loading = false;
        if (results.every((value) => value == null)) {
          _error = '暂时无法获取听歌统计。';
        }
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = '听歌足迹加载失败，请稍后重试。';
      });
    }
  }

  void _playTop(TopPlayItem item) {
    final playback = widget.playback;
    if (playback == null) return;
    final track = Track(
      id: item.trackId,
      name: item.trackName,
      artists: item.artists,
      album: item.album,
      picUrl: item.picUrl,
      source: MusicSource.fromWireName(item.source),
    );
    playback.playTrack(track, queue: [track]);
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '听歌足迹',
    bodyBuilder: (context, topPadding) => AnimatedBuilder(
      animation: widget.account,
      builder: (context, _) {
        if (widget.account.token == null) {
          return const CyreneEmptyState(
            icon: Icons.login_rounded,
            title: '登录后查看听歌足迹',
            description: '登录后可以查看累计时长、周播放与语言偏好。',
          );
        }
        if (_loading) {
          return const Center(child: MiuixCircularProgressIndicator());
        }
        if (_error != null) {
          return CyreneEmptyState(
            icon: Icons.cloud_off_rounded,
            title: '足迹暂时不可用',
            description: _error!,
            action: MiuixTextButton('重试', onPressed: _load),
          );
        }
        return CyrenePullToRefresh(
          onRefresh: _load,
          contentPadding: EdgeInsets.only(top: topPadding.top),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: topPadding + const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              const CyreneSectionTitle(
                title: '你的音乐旅程',
                description: '回顾最近留下的声音印记',
              ),
              const SizedBox(height: 16),
              _StatsRow(stats: _stats),
              const SizedBox(height: 24),
              // 新增字段在 Flutter 热重载保留的旧 Widget 实例上可能暂时为
              // null；显式比较可保证条件表达式始终返回 bool。
              if (widget.desktopLayout == true)
                SizedBox(
                  height: 300,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _WeeklyAlbumWall(weeklyPlays: _weekly),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _LanguageStatsSection(
                          languageStats: _languages,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _WeeklyAlbumWall(weeklyPlays: _weekly),
                const SizedBox(height: 24),
                _LanguageStatsSection(languageStats: _languages),
              ],
              const SizedBox(height: 24),
              _TopRankingSection(
                topPlays: _stats?.playCounts.take(10).toList() ?? const [],
                onPlay: widget.playback == null ? null : _playTop,
              ),
            ],
          ),
        );
      },
    ),
  );

  static String formatListeningTime(int seconds) {
    if (seconds <= 0) return '0 分钟';
    if (seconds < 60) return '$seconds 秒';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    return mins == 0 ? '$hours 小时' : '$hours 小时 $mins 分';
  }
}

/// 累计统计：聆听时长 + 播放次数（对应 ProfileStats）。
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final ListeningStatsData? stats;

  @override
  // IntrinsicHeight：ListView 给子项的高度约束无限，裸 stretch 会被强制
  // 拉到无限高直接抛 performLayout 异常（整页空白），需以内容高为基准等高。
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.headphones_rounded,
            label: '聆听时长',
            value: _ListeningFootprintPageState.formatListeningTime(
              stats?.totalListeningTime ?? 0,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.play_arrow_rounded,
            label: '播放次数',
            value: '${stats?.totalPlayCount ?? 0} 次',
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CyreneIconBox(icon: icon, size: 34),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: theme.textStyles.title3.copyWith(
                color: colors.onSurfaceContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本周唱片墙（对应 WeeklyAlbumWall）：封面网格背景 + 渐变遮罩 + 收听首数。
class _WeeklyAlbumWall extends StatelessWidget {
  const _WeeklyAlbumWall({required this.weeklyPlays});

  final List<WeeklyPlayItem>? weeklyPlays;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final plays = weeklyPlays ?? const [];
    if (plays.isEmpty) {
      return const _SectionEmpty(
        icon: Icons.album_rounded,
        title: '暂无本周播放记录',
        description: '多听几首歌后再来看看吧。',
      );
    }

    final covers = plays
        .map((p) => p.picUrl)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1.32,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.colors.secondaryContainer),
            if (covers.isNotEmpty) _CoverGrid(covers: covers),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Color(0x66000000),
                    Color(0xE6000000),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: Text(
                '本周唱片墙',
                style: theme.textStyles.title4.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${plays.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 6, bottom: 8),
                    child: Text(
                      '首',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '本周收听歌曲',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
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

/// 封面网格背景：循环填充铺满，无封面时留底色。
class _CoverGrid extends StatefulWidget {
  const _CoverGrid({required this.covers});

  final List<String> covers;

  @override
  State<_CoverGrid> createState() => _CoverGridState();
}

class _CoverGridState extends State<_CoverGrid> {
  final _scrollController = ScrollController();
  int _scrollGeneration = 0;
  double _cycleDistance = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
  }

  @override
  void didUpdateWidget(covariant _CoverGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.covers != widget.covers) {
      _scrollGeneration++;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
    }
  }

  @override
  void dispose() {
    _scrollGeneration++;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startAutoScroll() async {
    final generation = ++_scrollGeneration;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    while (mounted && generation == _scrollGeneration) {
      if (!_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }

      final position = _scrollController.position;
      // 32 个单元由两份相同的 4×4 封面墙组成；滚过前半段后无缝复位。
      final cycleDistance = _cycleDistance.clamp(
        0.0,
        position.maxScrollExtent,
      ).toDouble();
      if (cycleDistance <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      await _scrollController.animateTo(
        cycleDistance,
        duration: Duration(milliseconds: (cycleDistance * 32).round()),
        curve: Curves.linear,
      );
      if (!mounted || generation != _scrollGeneration) return;
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, gridConstraints) {
      // 4×4 正方形网格的高度等于网格宽度，即一份封面墙的循环距离。
      _cycleDistance = gridConstraints.maxWidth;
      return GridView.builder(
        controller: _scrollController,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
        ),
        itemCount: 32,
        itemBuilder: (context, index) {
          final url = widget.covers[index % widget.covers.length];
          return LayoutBuilder(
            builder: (context, constraints) => CachedNetworkImage(
              imageUrl: url,
              httpHeaders: imageHeaders(url),
              fit: BoxFit.cover,
              // 4 列网格,按 cell 实际宽降采样解码(见 coverDecodeWidth)。
              memCacheWidth: coverDecodeWidth(
                constraints.maxWidth.isFinite && constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : 110,
                MediaQuery.devicePixelRatioOf(context),
              ),
              errorWidget: (_, _, _) => ColoredBox(
                color: MiuixTheme.of(context).colors.secondaryContainer,
              ),
            ),
          );
        },
      );
    },
  );
}

/// 听歌语言占比（对应 LanguageStatsSection）：横向柱状，按播放次数倒序。
class _LanguageStatsSection extends StatefulWidget {
  const _LanguageStatsSection({required this.languageStats});

  final LanguageStatsData? languageStats;

  @override
  State<_LanguageStatsSection> createState() =>
      _LanguageStatsSectionState();
}

class _LanguageStatsSectionState extends State<_LanguageStatsSection> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final data = widget.languageStats;
    final items = data?.languages ?? const [];
    if (items.isEmpty) {
      return const _SectionEmpty(
        icon: Icons.language_rounded,
        title: '暂无语言数据',
        description: '播放更多歌曲后再来看看吧。',
      );
    }

    final totalPlayCount = data!.totalPlayCount;
    final sorted = [...items]
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本周听歌语言',
            style: theme.textStyles.title4.copyWith(
              color: colors.onSurfaceContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 150,
                  child: Listener(
                    onPointerSignal: _handlePointerSignal,
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: ListView.separated(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 10),
                        itemCount: sorted.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 20),
                        itemBuilder: (context, index) {
                          final item = sorted[index];
                          final ratio = totalPlayCount > 0
                              ? item.playCount / totalPlayCount
                              : 0.0;
                          final barHeight = 12 + ratio * 80;
                          final percent = (ratio * 100).round();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$percent%',
                                style: theme.textStyles.title3.copyWith(
                                  color: colors.onSurfaceContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.language,
                                style: theme.textStyles.body2.copyWith(
                                  color: colors.onSurfaceContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: 56,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      colors.primary,
                                      colors.primary.withValues(alpha: 0.6),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '共计 ${data.totalSongCount} 首，播放 ${data.totalPlayCount} 次 · 仅统计已识别语种',
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放排行（对应 TopRankingSection）：序号 + 封面 + 标题/歌手 + 次数，可点击播放。
class _TopRankingSection extends StatelessWidget {
  const _TopRankingSection({required this.topPlays, this.onPlay});

  final List<TopPlayItem> topPlays;
  final ValueChanged<TopPlayItem>? onPlay;

  @override
  Widget build(BuildContext context) {
    if (topPlays.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CyreneSectionTitle(title: '播放排行'),
          SizedBox(height: 12),
          _SectionEmpty(
            icon: Icons.emoji_events_rounded,
            title: '暂无播放记录',
            description: '多听几首歌后再来看看吧。',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CyreneSectionTitle(title: '播放排行'),
        const SizedBox(height: 8),
        for (final (index, item) in topPlays.indexed)
          _TopRankingTile(rank: index + 1, item: item, onPlay: onPlay),
      ],
    );
  }
}

class _TopRankingTile extends StatelessWidget {
  const _TopRankingTile({
    required this.rank,
    required this.item,
    required this.onPlay,
  });

  final int rank;
  final TopPlayItem item;
  final ValueChanged<TopPlayItem>? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.music_note_rounded,
        size: 22,
        color: colors.onSurfaceVariantSummary,
      ),
    );
    // 透明背景的可点击卡片：列表行按压反馈，不引入卡片底色。
    return MiuixCard(
      colors: MiuixCardColors(
        color: Colors.transparent,
        contentColor: colors.onBackground,
      ),
      insideMargin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      onPressed: onPlay == null ? null : () => onPlay!(item),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: theme.textStyles.body2.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: 48,
              child: item.picUrl.isEmpty
                  ? fallback
                  : CachedNetworkImage(
                      imageUrl: item.picUrl,
                      httpHeaders: imageHeaders(item.picUrl),
                      fit: BoxFit.cover,
                      // 48px 显示,按显示尺寸降采样解码(见 coverDecodeWidth)。
                      memCacheWidth: coverDecodeWidth(
                        48,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      errorWidget: (_, _, _) => fallback,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onBackground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.playCount} 次',
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区内嵌空状态卡片。
class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              CyreneIconBox(icon: icon, size: 44),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
