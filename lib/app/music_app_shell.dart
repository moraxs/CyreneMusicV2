import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../application/announcements/announcement_controller.dart';
import '../application/audio_sources/audio_source_preferences_controller.dart';
import '../application/auth/account_session_controller.dart';
import '../application/discovery/discover_controller.dart';
import '../application/home/home_controller.dart';
import '../application/playback/playback_controller.dart';
import '../application/playlists/playlist_library_controller.dart';
import '../application/search/search_controller.dart';
import '../application/updates/update_controller.dart';
import '../domain/models/discovery.dart';
import '../features/announcements/announcement_dialog.dart';
import '../features/discover/discover_page.dart';
import '../features/home/now_listening_page.dart';
import '../features/more/more_menu_drawer.dart';
import '../features/player/mini_player.dart';
import '../features/player/mini_player_expand_route.dart';
import '../features/player/mobile/mobile_player_page.dart';
import '../features/player/mobile/mobile_fullscreen_player_host.dart';
import '../features/player/desktop_fullscreen_player_host.dart';
import '../features/player/desktop_fullscreen_player_route.dart';
import '../features/playlist/playlist_detail_page.dart';
import '../features/profile/profile_page.dart';
import '../features/search/search_page.dart';
import '../features/updates/update_dialogs.dart';
import '../presentation/cyrene/breakpoints.dart';
import '../presentation/cyrene/cyrene_page_routes.dart';
import 'desktop/desktop_shell.dart';

class MusicAppShell extends StatefulWidget {
  const MusicAppShell({
    super.key,
    required this.account,
    required this.audioSources,
    required this.discover,
    required this.home,
    required this.playback,
    required this.playlists,
    required this.search,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final DiscoverController discover;
  final HomeController home;
  final PlaybackController playback;
  final PlaylistLibraryController playlists;
  final SearchController search;

  @override
  State<MusicAppShell> createState() => _MusicAppShellState();
}

class _MusicAppShellState extends State<MusicAppShell> {
  var _selectedIndex = 0;

  /// 迷你播放器面板的锚点：首页那张「正在播放」卡片进全屏播放器时，起点动画
  /// 也从底部这块面板长出来，跟直接点迷你播放器完全一致。
  final _miniPlayerKey = GlobalKey();

  final _navigationBackdrop = MiuixLayerBackdrop();
  bool _moreMenuOpen = false;
  final _moreTabKey = GlobalKey();
  Rect _moreMenuAnchor = Rect.zero;
  bool _moreMenuClosing = false;
  MoreMenuItem? _pendingMoreItem;

  /// 内容区是否滚离顶部：驱动顶部玻璃模糊条淡入。由 IndexedStack 内各页
  /// 滚动冒泡的 ScrollNotification 维护。
  bool _contentScrolled = false;

  @override
  void initState() {
    super.initState();
    // 启动后静默跑一遍更新检查与公告。放在外壳而不是 main：弹窗需要导航树里的
    // context，main 的 initState 拿不到。首帧后再延迟几秒，避开启动期的
    // 网络与布局高峰。
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupChecks());
  }

  /// 整个应用生命周期内只跑一次——外壳不会被重建，无需额外的重入保护。
  ///
  /// 顺序是先更新后公告，且串行 await：两者都是命令式弹窗，并行会互相叠在
  /// 一起，后弹的还可能被先弹那个的退场动画顺手 pop 掉（见 showUpdateDialog
  /// 里的注释）。强制更新/维护公告的弹窗不可关闭，公告自然就轮不上——这也是
  /// 想要的效果。
  Future<void> _runStartupChecks() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    await _checkUpdateOnce();
    if (!mounted) return;
    await _showAnnouncementOnce();
  }

  Future<void> _checkUpdateOnce() async {
    final update = UpdateController.instance;
    final info = await update.check();
    if (!mounted || info == null) return;
    if (!await update.shouldPrompt(info)) return;
    if (!mounted) return;

    await showUpdateDialog(context, info);
  }

  /// 启动公告：后端开了公告、且编号比用户勾「不再提示」时记下的更大才弹。
  Future<void> _showAnnouncementOnce() async {
    final announcements = AnnouncementController.instance;
    final announcement = await announcements.fetch();
    if (!mounted || announcement == null) return;
    if (!await announcements.shouldPrompt(announcement)) return;
    if (!mounted) return;

    await showAnnouncementDialog(
      context,
      announcement,
      showDismissOption: true,
      controller: announcements,
    );
  }

  @override
  void dispose() {
    _navigationBackdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.playback,
    builder: (context, _) => isDesktopLayout(context)
        ? _buildDesktop(context)
        : _buildMobile(context),
  );

  /// 移动端布局:底部 GlassTabBar + Positioned MiniPlayer + 顶部搜索栏。
  /// 原样保留,断点 < 900 时使用。
  Widget _buildMobile(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Scaffold(
      // HyperOS 灰底白卡：页面底用 surface 灰，卡片才浮得出来。
      backgroundColor: theme.colors.surface,
      // 内容边到边：不给外层 SafeArea，让列表一直滚进状态栏区域，顶部玻璃
      // 顶栏的 BackdropFilter 才有内容可糊（HyperOS 4 原生形态）。各页滚动
      // 内容的顶部留白靠下方注入的 MediaQuery.padding.top 承担；底部导航栏
      // 内部自带 SafeArea，不受影响。
      body: Stack(
        children: [
          Stack(
            children: [
              MiuixLayerBackdropCapture(
                backdrop: _navigationBackdrop,
                pixelRatio: 1,
                child: ColoredBox(
                  color: theme.colors.surface,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      // 各页纵向滚动的通知会冒泡到这里；内容离开顶部即让顶部
                      // 玻璃条浮现，回到顶部即收回。
                      if (notification.metrics.axis != Axis.vertical) {
                        return false;
                      }
                      final scrolled = notification.metrics.pixels > 0;
                      if (scrolled != _contentScrolled) {
                        setState(() => _contentScrolled = scrolled);
                      }
                      return false;
                    },
                    child: Column(
                      children: [
                        Expanded(
                          // 各页 CustomScrollView 未显式传 padding 时默认取
                          // MediaQuery.padding：这里把「状态栏 + 玻璃顶栏」高度
                          // 注入为内容上内边距，静止时内容停在栏下，上滑时滚入
                          // 模糊区。显式传 padding 的页（如我的）需自行加回。
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              padding: MediaQuery.of(context).padding.copyWith(
                                top:
                                    MediaQuery.of(context).padding.top +
                                    MiuixTopAppBarDefaults.collapsedHeight,
                              ),
                            ),
                            child: IndexedStack(
                              index: _selectedIndex,
                              children: [
                                NowListeningPage(
                                  account: widget.account,
                                  home: widget.home,
                                  playback: widget.playback,
                                  onOpenPlayer: _openPlayer,
                                  onOpenPlaylist: _openHomePlaylist,
                                ),
                                DiscoverPage(
                                  discover: widget.discover,
                                  onOpenPlaylist: _openDiscoverPlaylist,
                                ),
                                ProfilePage(
                                  accountSessionController: widget.account,
                                  playback: widget.playback,
                                  playlists: widget.playlists,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 迷你播放器与底部标签栏同层：它曾被提到 Navigator 之上（想让二级页
              // 也盖不住它），代价是连启动过渡页与引导页都会被它压住——那两个页面
              // 属于 AppGate，本就不该有播放器。所以放回外壳里，跟标签栏一起被
              // push 出来的路由整块盖掉，二者进退一致。
              //
              // 用集合 if 而不是让子组件返回 SizedBox.shrink()：Stack 里的非定位空
              // 子节点会参与尺寸计算，是踩过的坑。
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 标签栏之上。二级页没有标签栏，但迷你播放器也一起被盖住，
                        // 不存在切页时上下跳的问题。
                        if (widget.playback.state.currentTrack != null) ...[
                          MiniPlayer(
                            playback: widget.playback,
                            audioSources: widget.audioSources,
                            account: widget.account,
                            anchorKey: _miniPlayerKey,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: MiuixGlassNavigationBar(
                                      key: const Key('mobile-navigation-bar'),
                                      backdrop: _navigationBackdrop,
                                      // 发现页入口下线后导航项少一项：页下标 0/2 映射为可见下标 0/1。
                                      selectedIndex: _selectedIndex <= 0
                                          ? 0
                                          : _selectedIndex - 1,
                                      onSelect: _onTabSelected,
                                      items: [
                                        MiuixGlassNavigationItem(
                                          icon: MiuixIcon(
                                            vector: MiuixIcons.extended.byName(
                                              'home',
                                            )!,
                                            size: 28,
                                          ),
                                          label: '首页',
                                          contentDescription: '首页',
                                        ),
                                        // 发现页入口暂时下线，保留代码以便恢复。
                                        // MiuixGlassNavigationItem(
                                        //   icon: MiuixIcon(
                                        //     vector: MiuixIcons.os4.gridView,
                                        //     size: 28,
                                        //   ),
                                        //   label: '发现',
                                        //   contentDescription: '发现',
                                        // ),
                                        MiuixGlassNavigationItem(
                                          icon: MiuixIcon(
                                            vector:
                                                MiuixIcons.os4.contactsCircle,
                                            size: 28,
                                          ),
                                          label: '我的',
                                          contentDescription: '我的',
                                        ),
                                        MiuixGlassNavigationItem(
                                          icon: KeyedSubtree(
                                            key: _moreTabKey,
                                            child: MiuixIcon(
                                              vector: MiuixIcons.os4.more,
                                              size: 28,
                                            ),
                                          ),
                                          label: '更多',
                                          contentDescription: '更多',
                                          isAction: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // iOS 26 风格的独立圆形搜索按钮：与导航栏共用
                                  // 同一层液态玻璃背景，点击直接进搜索页。
                                  MiuixGlassIconButton(
                                    backdrop: _navigationBackdrop,
                                    size: 54,
                                    shadow: MiuixGlassShadows.floating,
                                    semanticLabel: '搜索',
                                    onPressed: _openSearch,
                                    child: MiuixIcon(
                                      vector: MiuixIcons.basic.search,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
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
          // HyperOS 4 玻璃顶栏：无标题无按钮，压在最外层 Stack 顶部，band 连
          // 状态栏区域一起覆盖（内部 SafeArea 撑出状态栏高度）。只在内容滚离
          // 顶部时浮现渐隐高斯模糊遮罩，回到顶部收回。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MiuixGlassTopAppBar(
              title: '',
              backdrop: _navigationBackdrop,
              isContentScrolled: _contentScrolled,
              bandOverhang: 40,
            ),
          ),
          Positioned(top: 0, left: 0, child: _buildMoreMenu(context)),
        ],
      ),
    );
  }

  /// 桌面横屏布局:委托 [DesktopShell](fluent NavigationView 侧栏 + 融合标题栏)。
  /// 断点 >= 900 时使用,移动端布局不动。
  ///
  /// 桌面端的歌单详情 / 每日推荐 / 播放历史改为**内容区二级页**,由
  /// [DesktopShell] 自持覆盖状态,不再整窗 push——故这里传 null,外壳检测到
  /// null 即走自己的二级页逻辑;移动端 `_openHomePlaylist` 等不受影响。
  Widget _buildDesktop(BuildContext context) => DesktopShell(
    account: widget.account,
    audioSources: widget.audioSources,
    discover: widget.discover,
    home: widget.home,
    playback: widget.playback,
    playlists: widget.playlists,
    search: widget.search,
    onOpenPlayer: _openPlayer,
    onOpenHomePlaylist: null,
    onOpenDiscoverPlaylist: null,
  );

  void _openSearch() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => SearchPage(
          search: widget.search,
          playback: widget.playback,
          token: widget.account.token,
        ),
      ),
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    final items = moreMenuItems(
      account: widget.account,
      audioSources: widget.audioSources,
      playback: widget.playback,
    );
    return MiuixWindowListPopup(
      show: _moreMenuOpen,
      anchorBounds: Rect.fromLTWH(
        _moreMenuAnchor.right + 8,
        _moreMenuAnchor.top,
        0,
        _moreMenuAnchor.height,
      ),
      alignment: MiuixPopupAlign.start,
      onDismissRequest: _dismissMoreMenu,
      onDismissFinished: _finishMoreMenuDismissal,
      content: MiuixListPopupColumn(
        children: [
          MiuixDropdownEntriesPopupContent(
            entries: [
              MiuixDropdownEntry(
                items: [
                  for (final item in items) MiuixDropdownItem(text: item.title),
                ],
              ),
            ],
            dropdownColors: MiuixDropdownDefaults.dropdownColors(context),
            onItemClick: (_, index) {
              if (!_moreMenuOpen) return;
              HapticFeedback.selectionClick();
              _pendingMoreItem = items[index];
              _dismissMoreMenu();
            },
          ),
        ],
      ),
    );
  }

  void _dismissMoreMenu() {
    if (!mounted || !_moreMenuOpen) return;
    setState(() {
      _moreMenuOpen = false;
      _moreMenuClosing = true;
    });
  }

  void _finishMoreMenuDismissal() {
    if (!mounted) return;
    final item = _pendingMoreItem;
    _pendingMoreItem = null;
    _moreMenuClosing = false;
    if (item == null) return;
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (context) => item.pageBuilder(context)),
    );
  }

  void _onTabSelected(int index) {
    if (_moreMenuOpen || _moreMenuClosing) return;
    // 发现页入口暂时下线：导航项为 [首页, 我的, 更多]；「更多」仍是最后一项，
    // 其余下标 +1 跳过保留在 IndexedStack 里的发现页（index 1），便于恢复。
    if (index == 2) {
      final box = _moreTabKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      setState(() {
        _moreMenuAnchor = box.localToGlobal(Offset.zero) & box.size;
        _pendingMoreItem = null;
        _moreMenuOpen = true;
      });
      return;
    }
    final pageIndex = index >= 1 ? index + 1 : index;
    if (pageIndex == _selectedIndex) return;
    // 切页后顶部模糊条回到未滚动态，由新页面自己的滚动通知再更新。
    setState(() {
      _selectedIndex = pageIndex;
      _contentScrolled = false;
    });
  }

  void _openHomePlaylist(
    int id,
    String title,
    String coverUrl, {
    String? heroTag,
    Alignment? originAlignment,
  }) {
    Navigator.of(context).push(
      CyreneHeroExpandPageRoute<void>(
        originAlignment: originAlignment ?? Alignment.center,
        builder: (_) => PlaylistDetailPage(
          playlistId: id,
          title: title,
          coverUrl: coverUrl,
          playback: widget.playback,
          token: widget.account.token,
          heroTag: heroTag,
        ),
      ),
    );
  }

  void _openDiscoverPlaylist(
    DiscoveryPlaylist playlist, {
    String? heroTag,
    Alignment? originAlignment,
  }) {
    Navigator.of(context).push(
      CyreneHeroExpandPageRoute<void>(
        originAlignment: originAlignment ?? Alignment.center,
        builder: (_) => PlaylistDetailPage(
          playlistId: playlist.id,
          title: playlist.name,
          coverUrl: playlist.coverImgUrl,
          creator: playlist.creatorNickname,
          trackCount: playlist.trackCount,
          playback: widget.playback,
          token: widget.account.token,
          heroTag: heroTag,
        ),
      ),
    );
  }

  void _openPlayer() {
    if (isDesktopLayout(context)) {
      Navigator.of(context).push(
        DesktopFullscreenPlayerRoute(
          builder: (_) => DesktopFullscreenPlayerHost(
            playback: widget.playback,
            audioSources: widget.audioSources,
            account: widget.account,
          ),
        ),
      );
      return;
    }
    // 移动端：外观设置选了 SuperCyrene 时进横屏 SuperCyrene 播放器。
    if (shouldOpenMobileSuperCyrene()) {
      pushMobileSuperCyrenePlayer(
        Navigator.of(context),
        playback: widget.playback,
        audioSources: widget.audioSources,
        account: widget.account,
      );
      return;
    }
    Navigator.of(context).push(
      MiniPlayerExpandRoute<void>(
        originRect: () => globalRectOfKey(_miniPlayerKey),
        builder: (_) => MobilePlayerPage(
          playback: widget.playback,
          audioSources: widget.audioSources,
          account: widget.account,
        ),
      ),
    );
  }
}
