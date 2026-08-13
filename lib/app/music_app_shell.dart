import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../application/audio_sources/audio_source_preferences_controller.dart';
import '../application/auth/account_session_controller.dart';
import '../application/discovery/discover_controller.dart';
import '../application/home/home_controller.dart';
import '../application/playback/playback_controller.dart';
import '../application/playlists/playlist_library_controller.dart';
import '../application/search/search_controller.dart';
import '../application/updates/update_controller.dart';
import '../domain/models/discovery.dart';
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
    // 启动后静默检查一次更新。放在外壳而不是 main：弹窗需要导航树里的
    // context，main 的 initState 拿不到。首帧后再延迟几秒，避开启动期的
    // 网络与布局高峰。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateOnce());
  }

  /// 整个应用生命周期内只自动检查一次——外壳不会被重建，无需额外的重入保护。
  Future<void> _checkUpdateOnce() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    final update = UpdateController.instance;
    final info = await update.check();
    if (!mounted || info == null) return;
    if (!await update.shouldPrompt(info)) return;
    if (!mounted) return;

    await showUpdateDialog(context, info);
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
            if (widget.playback.state.currentTrack != null)
              Positioned(
                left: 16,
                right: 16,
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
        builder: (_) =>
            SearchPage(search: widget.search, playback: widget.playback),
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

  void _openHomePlaylist(int id, String title, String coverUrl) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          playlistId: id,
          title: title,
          coverUrl: coverUrl,
          playback: widget.playback,
          token: widget.account.token,
        ),
      ),
    );
  }

  void _openDiscoverPlaylist(DiscoveryPlaylist playlist) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          playlistId: playlist.id,
          title: playlist.name,
          coverUrl: playlist.coverImgUrl,
          playback: widget.playback,
          token: widget.account.token,
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
        context,
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
