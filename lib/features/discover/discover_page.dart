import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/discovery/discover_controller.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/media_url.dart';
import '../../presentation/cyrene/cyrene_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.discover,
    required this.onOpenPlaylist,
  });

  final DiscoverController discover;
  final ValueChanged<DiscoveryPlaylist> onOpenPlaylist;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.discover.load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: widget.discover,
      builder: (context, _) {
        final state = widget.discover.state;
        if (state.isInitialLoading && state.playlists.isEmpty) {
          return const Center(child: MiuixCircularProgressIndicator());
        }
        if (state.errorMessage != null && state.playlists.isEmpty) {
          return CyreneEmptyState(
            icon: Icons.cloud_off,
            title: '发现内容暂时不可用',
            description: state.errorMessage!,
            action: MiuixButton(
              onPressed: widget.discover.refresh,
              child: MiuixText(
                '重试',
                style: MiuixTheme.of(context).textStyles.button,
              ),
            ),
          );
        }

        return CyrenePullToRefresh(
          onRefresh: widget.discover.refresh,
          child: CustomScrollView(
            key: const PageStorageKey('discover-scroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 22, 16, 14),
                sliver: SliverToBoxAdapter(
                  child: CyreneSectionTitle(
                    title: '发现',
                    description: '探索热门分类与高品质歌单',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _CategorySelector(
                  tags: state.tags,
                  selectedCategory: state.selectedCategory,
                  onSelected: widget.discover.selectCategory,
                ),
              ),
              if (state.isRefreshing)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: MiuixLinearProgressIndicator(height: 2),
                  ),
                ),
              if (state.errorMessage != null && state.playlists.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _InlineError(
                      message: state.errorMessage!,
                      onRetry: widget.discover.refresh,
                    ),
                  ),
                ),
              if (state.playlists.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: CyreneEmptyState(
                    icon: Icons.library_music,
                    title: '这个分类还没有歌单',
                    description: '换个分类看看，或稍后下拉刷新。',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 180),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 12,
                          childAspectRatio: .72,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final playlist = state.playlists[index];
                      return _DiscoverPlaylistCard(
                        playlist: playlist,
                        onTap: () => widget.onOpenPlaylist(playlist),
                      );
                    }, childCount: state.playlists.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.tags,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<DiscoveryTag> tags;
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final categories = <String>['全部歌单', ...tags.map((tag) => tag.name)];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        key: const PageStorageKey('discover-categories'),
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category == selectedCategory;
          return MiuixButton(
            onPressed: () => onSelected(category),
            colors: selected
                ? MiuixButtonDefaults.buttonColorsPrimary(context)
                : null,
            insideMargin: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: MiuixText(
              category,
              style: MiuixTheme.of(context).textStyles.button,
            ),
          );
        },
      ),
    );
  }
}

class _DiscoverPlaylistCard extends StatelessWidget {
  const _DiscoverPlaylistCard({required this.playlist, required this.onTap});

  final DiscoveryPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final fallback = ColoredBox(
      color: theme.colors.secondaryContainer,
      child: Icon(
        Icons.library_music,
        size: 40,
        color: theme.colors.onSurfaceVariantSummary,
      ),
    );
    return MiuixCard(
      colors: MiuixCardColors(
        color: Colors.transparent,
        contentColor: theme.colors.onBackground,
      ),
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MiuixCard(
              child: ClipPath.shape(
                shape: const MiuixSquircleBorder(cornerRadius: 16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (playlist.coverImgUrl.isEmpty)
                      fallback
                    else
                      CachedNetworkImage(
                        imageUrl: playlist.coverImgUrl,
                        httpHeaders: imageHeaders(playlist.coverImgUrl),
                        fit: BoxFit.cover,
                        // 网格 cell 宽 ≤ maxCrossAxisExtent(220),按此降采样解码,
                        // 避免全尺寸封面拖累滚动(见 coverDecodeWidth)。
                        memCacheWidth: coverDecodeWidth(
                          220,
                          MediaQuery.devicePixelRatioOf(context),
                        ),
                        errorWidget: (_, _, _) => fallback,
                      ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _CoverGlassChip(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const MiuixIcon(
                                icon: Icons.headphones,
                                size: 12,
                                tint: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              MiuixText(
                                _formatPlayCount(playlist.playCount),
                                style: theme.textStyles.footnote2.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _CoverGlassChip(
                        child: MiuixIconButton(
                          onPressed: onTap,
                          child: MiuixIcon(
                            vector: MiuixIcons.extended.byName(
                              'chevronForward',
                            )!,
                            size: 18,
                            tint: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            playlist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onBackground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            playlist.creatorNickname.isEmpty
                ? '${playlist.trackCount} 首歌曲'
                : playlist.creatorNickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlayCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(0)}万';
    return count.toString();
  }
}

/// 封面上的玻璃挂件：胶囊裁剪 + 毛玻璃取样 + 深色半透明底，
/// 边缘用 Miuix 玻璃高光（bloom stroke）照亮，内容恒为白色。
class _CoverGlassChip extends StatelessWidget {
  const _CoverGlassChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath.shape(
      shape: const StadiumBorder(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        // 深色玻璃配 SmallDark 预设（小挂件、深底的高光强度），
        // shape 缺省即胶囊，与外层裁剪一致。
        child: MiuixHighlight(
          highlight: Highlight.glassStrokeSmallDark,
          child: ColoredBox(color: const Color(0x40000000), child: child),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Row(
        children: [
          const MiuixIcon(icon: Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceContainer,
              ),
            ),
          ),
          MiuixTextButton('重试', onPressed: onRetry),
        ],
      ),
    );
  }
}
