import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../application/search/search_controller.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/search.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/search_suggestion_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../artist/artist_detail_page.dart';
import '../player/cyrene_track_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.search,
    required this.playback,
    this.initialQuery = '',
  });

  final SearchController search;
  final PlaybackController playback;
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchFocusNode = FocusNode();
  final _suggestionService = SearchSuggestionService.instance;
  late String _query = widget.initialQuery;

  /// 空关键词进入（首页搜索入口跳来）时立即聚焦弹键盘。
  late bool _expanded = widget.initialQuery.trim().isEmpty;
  _SearchTab _tab = _SearchTab.aggregate;

  /// 输入防抖 300ms（与 Next.js useDebounce 一致）；seq 丢弃过期响应。
  Timer? _suggestDebounce;
  int _suggestSeq = 0;
  List<String> _suggestions = const [];
  List<String> _hotSearches = const [];
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().isNotEmpty) {
      widget.search.search(widget.initialQuery);
    }
    // MiuixInputField 只在获得焦点时上报 expanded=true，失焦这里自己收：
    // 否则空关键词失焦后占位标签不会恢复显示。
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _loadDiscoverData();
  }

  Future<void> _loadDiscoverData() async {
    final history = await _suggestionService.loadHistory();
    if (mounted) setState(() => _history = history);
    final hots = await _suggestionService.fetchHotSearches();
    if (mounted) setState(() => _hotSearches = hots);
  }

  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus && _expanded) {
      setState(() => _expanded = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _suggestDebounce?.cancel();
    final keywords = value.trim();
    if (keywords.isEmpty) {
      _suggestSeq++;
      setState(() => _suggestions = const []);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 300), () async {
      final seq = ++_suggestSeq;
      final results = await _suggestionService.fetchSuggestions(keywords);
      if (!mounted || seq != _suggestSeq || _query.trim() != keywords) return;
      setState(() => _suggestions = results);
    });
  }

  /// 用给定关键词直接搜索（建议 / 热搜 / 历史点击）。
  void _searchWith(String term) {
    setState(() => _query = term);
    _submit();
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '搜索',
    body: AnimatedBuilder(
      animation: widget.search,
      builder: (context, _) {
        final state = widget.search.state;
        final typed = _query.trim();
        // 输入中且与已提交关键词不同 → 展示搜索建议（与 Web 弹层条件一致）。
        final showSuggestions =
            typed.isNotEmpty &&
            typed != state.keyword &&
            _suggestions.isNotEmpty;
        final showDiscover = typed.isEmpty && state.keyword.isEmpty;
        return Column(
          children: [
            // Miuix 专用搜索框：键盘搜索键提交，自带搜索图标与清除按钮。
            Padding(
              padding: const EdgeInsets.all(16),
              child: MiuixInputField(
                query: _query,
                onQueryChange: _onQueryChanged,
                onSearch: (_) => _submit(),
                expanded: _expanded,
                onExpandedChange: (value) => setState(() => _expanded = value),
                focusNode: _searchFocusNode,
                label: '搜索歌曲、歌手或专辑',
              ),
            ),
            if (state.keyword.isNotEmpty && !showSuggestions && !showDiscover)
              _PlatformTabs(
                selected: _tab,
                result: state.result,
                onSelected: (tab) => setState(() => _tab = tab),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: showSuggestions
                  ? _buildSuggestions()
                  : showDiscover
                  ? _buildDiscover()
                  : _buildContent(state),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildContent(dynamic state) {
    if (state.isLoading) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return CyreneEmptyState(
        icon: Icons.cloud_off,
        title: '搜索失败',
        description: state.errorMessage!,
        action: MiuixButton(
          onPressed: _submit,
          child: MiuixText(
            '重试',
            style: MiuixTheme.of(context).textStyles.button,
          ),
        ),
      );
    }
    if (state.keyword.isEmpty) {
      return const CyreneEmptyState(
        icon: Icons.auto_awesome,
        title: '发现正流向你耳边的声音',
        description: '输入关键词，即可从已配置的音源搜索歌曲和歌手。',
      );
    }

    final result = state.result as SearchResult;
    if (_tab == _SearchTab.artist) {
      return _artistResults(result.artistResults, result.artistError);
    }
    return _trackResults(_tracksFor(result, _tab), _errorFor(result, _tab));
  }

  Widget _trackResults(List<Track> tracks, String? error) {
    if (error != null && tracks.isEmpty) {
      return CyreneEmptyState(
        icon: Icons.warning_amber_rounded,
        title: _tab.failureTitle,
        description: error,
        action: MiuixButton(
          onPressed: _submit,
          child: MiuixText(
            '重试',
            style: MiuixTheme.of(context).textStyles.button,
          ),
        ),
      );
    }
    if (tracks.isEmpty) {
      return CyreneEmptyState(
        icon: Icons.music_note,
        title: _tab.emptyTitle,
        description: '换个关键词再试试。',
      );
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: tracks.length + (error == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0 && error != null) {
          return CyreneInlineAlert(
            icon: Icons.warning_amber_rounded,
            title: '部分结果不可用',
            description: error,
            destructive: true,
          );
        }
        final trackIndex = index - (error == null ? 0 : 1);
        final track = tracks[trackIndex];
        return CyreneTrackTile(
          track: track,
          onPlay: () => widget.playback.playTrack(track, queue: [track]),
          onAddToQueue: () {
            widget.playback.addToQueue(track);
            CyreneToast.show('已加入播放队列：${track.name}');
          },
        );
      },
    );
  }

  Widget _artistResults(List<NeteaseArtistBrief> artists, String? error) {
    if (error != null && artists.isEmpty) {
      return CyreneEmptyState(
        icon: Icons.person_off,
        title: '歌手搜索失败',
        description: error,
        action: MiuixButton(
          onPressed: _submit,
          child: MiuixText(
            '重试',
            style: MiuixTheme.of(context).textStyles.button,
          ),
        ),
      );
    }
    if (artists.isEmpty) {
      return const CyreneEmptyState(
        icon: Icons.person_search,
        title: '暂无歌手结果',
        description: '换个歌手名称再试试。',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: .85,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return _ArtistCard(
          artist: artist,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => ArtistDetailPage(
                playback: widget.playback,
                artistId: artist.id,
                artistName: artist.name,
              ),
            ),
          ),
        );
      },
    );
  }

  List<Track> _tracksFor(SearchResult result, _SearchTab tab) => switch (tab) {
    _SearchTab.aggregate => result.aggregatedTracks,
    _SearchTab.spotify => result.spotifyResults,
    _SearchTab.artist => const [],
  };

  String? _errorFor(SearchResult result, _SearchTab tab) => switch (tab) {
    _SearchTab.aggregate => result.aggregatedError,
    _SearchTab.spotify => result.spotifyError,
    _SearchTab.artist => result.artistError,
  };

  Future<void> _submit() async {
    final keyword = _query.trim();
    if (keyword.isEmpty) return;
    widget.search.search(keyword);
    _searchFocusNode.unfocus();
    // 与 Web 端 handleSearch 一致：提交即写入搜索历史（去重置顶）。
    final history = await _suggestionService.saveHistory(keyword);
    if (mounted) setState(() => _history = history);
  }

  // ===== 搜索建议 / 热搜榜 / 搜索历史 =====

  Widget _buildSuggestions() {
    final theme = MiuixTheme.of(context);
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final keyword = _suggestions[index];
        return MiuixCard(
          colors: MiuixCardColors(
            color: Colors.transparent,
            contentColor: theme.colors.onSurfaceContainer,
          ),
          insideMargin: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          onPressed: () => _searchWith(keyword),
          feedbackType: MiuixPressFeedbackType.sink,
          child: Row(
            children: [
              MiuixIcon(
                vector: MiuixIcons.basic.search,
                size: 16,
                tint: theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceContainer,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiscover() {
    if (_hotSearches.isEmpty && _history.isEmpty) {
      return const CyreneEmptyState(
        icon: Icons.auto_awesome,
        title: '发现正流向你耳边的声音',
        description: '输入关键词，即可从已配置的音源搜索歌曲和歌手。',
      );
    }
    final theme = MiuixTheme.of(context);
    final headerStyle = theme.textStyles.footnote1.copyWith(
      color: theme.colors.onSurfaceVariantSummary,
      fontWeight: FontWeight.w600,
    );
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        if (_hotSearches.isNotEmpty) ...[
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                size: 15,
                color: Color(0xFFFF6D00),
              ),
              const SizedBox(width: 5),
              Text('热搜榜', style: headerStyle),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 与 Web 端一致：仅取前 10，前三名序号高亮。
              for (final (index, name) in _hotSearches.take(10).indexed)
                _SearchChip(
                  leading: Text(
                    '${index + 1}',
                    style: theme.textStyles.footnote1.copyWith(
                      fontWeight: FontWeight.w600,
                      color: index < 3
                          ? const Color(0xFFFF6D00)
                          : theme.colors.onSurfaceVariantSummary,
                    ),
                  ),
                  label: name,
                  onTap: () => _searchWith(name),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.history,
                size: 15,
                color: theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 5),
              Text('搜索历史', style: headerStyle),
              const Spacer(),
              MiuixIconButton(
                minWidth: 30,
                minHeight: 30,
                onPressed: _clearHistory,
                child: MiuixIcon(
                  vector: MiuixIcons.extended.byName('delete')!,
                  size: 15,
                  tint: theme.colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in _history)
                _SearchChip(
                  label: term,
                  onTap: () => _searchWith(term),
                  onRemove: () => _removeHistory(term),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _removeHistory(String term) async {
    final history = await _suggestionService.removeHistory(term);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _clearHistory() async {
    await _suggestionService.clearHistory();
    if (mounted) setState(() => _history = const []);
  }
}

/// 圆角胶囊标签（热搜 / 历史），可带前缀序号与移除按钮。
class _SearchChip extends StatelessWidget {
  const _SearchChip({
    required this.label,
    required this.onTap,
    this.leading,
    this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? leading;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.footnote1.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _SearchTab {
  aggregate('聚合搜索'),
  spotify('Spotify'),
  artist('歌手');

  const _SearchTab(this.label);
  final String label;

  /// 失败空态标题（避免 '聚合搜索搜索失败' 这类读感）。
  String get failureTitle => switch (this) {
    _SearchTab.aggregate => '搜索失败',
    _SearchTab.spotify => 'Spotify 搜索失败',
    _SearchTab.artist => '歌手搜索失败',
  };

  /// 无结果空态标题。
  String get emptyTitle => switch (this) {
    _SearchTab.aggregate => '暂无结果',
    _SearchTab.spotify => 'Spotify 暂无结果',
    _SearchTab.artist => '暂无歌手结果',
  };
}

class _PlatformTabs extends StatelessWidget {
  const _PlatformTabs({
    required this.selected,
    required this.result,
    required this.onSelected,
  });

  final _SearchTab selected;
  final SearchResult result;
  final ValueChanged<_SearchTab> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: _SearchTab.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final theme = MiuixTheme.of(context);
        final tab = _SearchTab.values[index];
        final label = '${tab.label} ${_count(tab)}';
        // insideMargin 收窄以适配 42 高的横向标签条（默认竖向 13 会溢出）。
        const tabMargin = EdgeInsets.symmetric(horizontal: 16, vertical: 9);
        return tab == selected
            ? MiuixButton(
                onPressed: () => onSelected(tab),
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                insideMargin: tabMargin,
                child: MiuixText(label, style: theme.textStyles.button),
              )
            : MiuixButton(
                onPressed: () => onSelected(tab),
                insideMargin: tabMargin,
                child: MiuixText(label, style: theme.textStyles.button),
              );
      },
    ),
  );

  int _count(_SearchTab tab) => switch (tab) {
    _SearchTab.aggregate => result.aggregatedTracks.length,
    _SearchTab.spotify => result.spotifyResults.length,
    _SearchTab.artist => result.artistResults.length,
  };
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist, required this.onTap});

  final NeteaseArtistBrief artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.person,
        size: 42,
        color: colors.onSurfaceVariantSummary,
      ),
    );
    return MiuixCard(
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      insideMargin: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: ClipOval(
              child: AspectRatio(
                aspectRatio: 1,
                child: artist.picUrl.isEmpty
                    ? fallback
                    : LayoutBuilder(
                        builder: (context, constraints) => CachedNetworkImage(
                          imageUrl: artist.picUrl,
                          httpHeaders: imageHeaders(artist.picUrl),
                          fit: BoxFit.cover,
                          // 按 cell 实际宽降采样解码,避免全尺寸头像拖累滚动。
                          memCacheWidth: coverDecodeWidth(
                            constraints.maxWidth.isFinite &&
                                    constraints.maxWidth > 0
                                ? constraints.maxWidth
                                : 160,
                            MediaQuery.devicePixelRatioOf(context),
                          ),
                          errorWidget: (_, _, _) => fallback,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (artist.alias?.isNotEmpty == true) ...[
            const SizedBox(height: 3),
            Text(
              artist.alias!.join(' / '),
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
