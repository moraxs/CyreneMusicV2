import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _SearchHeader(onOpenSearch: _openSearch),
                const MiuixHorizontalDivider(),
                Expanded(
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
              ],
            ),
            // 迷你播放器与底部标签栏同层：它曾被提到 Navigator 之上（想让二级页
            // 也盖不住它），代价是连启动过渡页与引导页都会被它压住——那两个页面
            // 属于 AppGate，本就不该有播放器。所以放回外壳里，跟标签栏一起被
            // push 出来的路由整块盖掉，二者进退一致。
            //
            // 用集合 if 而不是让子组件返回 SizedBox.shrink()：Stack 里的非定位空
            // 子节点会参与尺寸计算，是踩过的坑。
            if (widget.playback.state.currentTrack != null)
              Positioned(
                left: 16,
                right: 16,
                // 标签栏之上。二级页没有标签栏，但迷你播放器也一起被盖住，
                // 不存在切页时上下跳的问题。
                bottom: 104,
                child: MiniPlayer(
                  playback: widget.playback,
                  audioSources: widget.audioSources,
                  account: widget.account,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar.bottom(
                tabs: const [
                  GlassTab(
                    icon: Icon(CupertinoIcons.house),
                    activeIcon: Icon(CupertinoIcons.house_fill),
                    label: '首页',
                    semanticLabel: '首页',
                  ),
                  GlassTab(
                    icon: Icon(CupertinoIcons.compass),
                    activeIcon: Icon(CupertinoIcons.compass_fill),
                    label: '发现',
                    semanticLabel: '发现',
                  ),
                  GlassTab(
                    icon: Icon(CupertinoIcons.person),
                    activeIcon: Icon(CupertinoIcons.person_fill),
                    label: '我的',
                    semanticLabel: '我的',
                  ),
                  GlassTab(
                    icon: Icon(CupertinoIcons.ellipsis),
                    activeIcon: Icon(CupertinoIcons.ellipsis_circle_fill),
                    label: '更多',
                    semanticLabel: '更多',
                  ),
                ],
                selectedIndex: _selectedIndex,
                onTabSelected: _onTabSelected,
              ),
            ),
          ],
        ),
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

  void _onTabSelected(int index) {
    if (index == 3) {
      MoreMenuDrawer.show(
        context,
        account: widget.account,
        audioSources: widget.audioSources,
        playback: widget.playback,
      );
      return;
    }
    setState(() => _selectedIndex = index);
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
      CupertinoPageRoute<void>(
        builder: (_) => MobilePlayerPage(
          playback: widget.playback,
          audioSources: widget.audioSources,
          account: widget.account,
        ),
      ),
    );
  }
}

/// 顶部搜索栏：Miuix 专用搜索框的折叠态，仅作入口（对应组件库 example 的
/// 移动端范式）——屏蔽内部指针避免抢焦点弹键盘，点击整条直接进搜索页。
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpenSearch,
        child: IgnorePointer(
          child: MiuixSearchBar(
            expanded: false,
            onExpandedChange: (_) {},
            insideMargin: const EdgeInsets.symmetric(horizontal: 16),
            inputField: MiuixInputField(
              query: '',
              onQueryChange: (_) {},
              onSearch: (_) {},
              expanded: false,
              onExpandedChange: (_) {},
              label: '搜索歌曲、歌手或专辑',
            ),
            content: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
