import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as m;
// 侧栏与标题栏走 fluent,这里只借 Miuix 的配色给外壳其余部分。底部迷你播放器
// 由独立的 [DesktopMiniPlayer] 自绘(零 fluent_ui,取 Miuix 配色)。仍用 show
// 限定,避免与 fluent_ui 的同名导出撞车。
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;

import '../debug_probe.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/discovery/discover_controller.dart';
import '../../application/home/home_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../application/playlists/playlist_library_controller.dart';
import '../../application/search/search_controller.dart';
import '../../domain/models/discovery.dart';
import '../../features/discover/discover_page.dart';
import '../../features/history/history_page.dart';
import '../../features/home/desktop_home_page.dart';
import '../../features/local/local_music_page.dart';
import '../../features/player/desktop_mini_player.dart';
import '../../features/playlist/playlist_detail_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/search/search_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/support/support_page.dart';
import 'desktop_fluent_theme.dart';
import 'desktop_title_bar.dart';

/// 桌面端外壳:fluent [NavigationView](Win11 风格)+ 顶部融合标题栏,内容区
/// 下方常驻迷你播放器横条。仅当 `isDesktopLayout` 为真时挂载;桌面选中项由
/// 本组件自持,不与移动端 tab 共享。
///
/// 侧栏是 fluent 原生导航面板,默认收起成 50 宽的图标栏,点标题栏左侧的汉堡
/// 按钮展开为 320 宽的带文字面板,选中态由 `StickyNavigationIndicator` 强调条
/// 拉伸过渡。
///
/// **收展为什么不走 fluent 的 compact↔expanded 切换**:那两个模式是两套不同的
/// 面板部件在互换(`_CompactNavigationPane` / `_OpenNavigationPane`),而 open
/// 那套顶部多了一个高度为 0 但带 6px 下边距的 header 容器,外层 Mica 又套了
/// 1px 的纵向 margin——互换的瞬间所有导航项会整体上下跳 7px,宽度却是动画的,
/// 观感就是抖动。这里改为**始终停在 expanded 模式**,只把
/// [NavigationPaneSize.openWidth] 在 50 / 320 之间切,部件树从头到尾不换,
/// 宽度由 fluent 自己的 `AnimatedContainer` 平滑过渡。
///
/// 收起到 50 宽时的行内宽度恰好是 `12(iconPadding) + 14(图标) + 12` = 38,
/// 与 fluent 原生 compact 面板逐像素一致,不会溢出。
///
/// 顶部为融合标题栏 [DesktopTitleBar](塞进 `NavigationView.titleBar` 槽):
/// Win32 原生标题栏已在 main 的 `_initDesktopWindow` 中隐藏,由应用自绘拖拽区
/// 与 caption 按钮。
///
/// 三条约束都与「不影响移动端那套 Miuix 视觉」直接相关:
/// 1. [FluentTheme] 只罩住 [NavigationView],底部迷你播放器留在它外面——那是
///    自绘的 [DesktopMiniPlayer],取 Miuix 主题与 Material,不依赖 fluent。
/// 2. 内容页(NowListeningPage 等)同样与移动端共用,故在 [_buildBody] 里把
///    DefaultTextStyle / IconTheme 拉回 Material 的默认值。
/// 3. 页面切换用 [IndexedStack] 保活;fluent 默认的 `PaneItem.body` 每次切换
///    都重建(会重新拉数据),故内容统一由 `paneBodyBuilder` 接管,代价是没有
///    fluent 的入场转场动画。
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.account,
    required this.audioSources,
    required this.discover,
    required this.home,
    required this.playback,
    required this.playlists,
    required this.search,
    required this.onOpenPlayer,
    required this.onOpenHomePlaylist,
    required this.onOpenDiscoverPlaylist,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final DiscoverController discover;
  final HomeController home;
  final PlaybackController playback;
  final PlaylistLibraryController playlists;
  final SearchController search;

  /// 打开全屏播放器(复用移动端播放器页,行为与移动端一致)。
  final VoidCallback onOpenPlayer;

  /// 打开首页歌单详情(id / 标题 / 封面)。桌面端为 null 时改为内容区
  /// 二级页,由本组件自持(见 [_DesktopShellState._homeBody]);非 null
  /// 为兼容层预留(目前移动端走自己的路由,不会进这里)。
  final void Function(int id, String title, String coverUrl)? onOpenHomePlaylist;

  /// 打开发现页歌单详情。桌面端为 null 时同上,走内容区二级页。
  final void Function(DiscoveryPlaylist playlist)? onOpenDiscoverPlaylist;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

/// 单条导航项的静态描述:导航项文案 [label]、Segoe Fluent 图标 [icon]、顶部
/// 标题栏区块标题 [title]。用 record 替代平行数组,消除索引错位风险。
typedef _NavEntry = ({String label, IconData icon, String title});

class _DesktopShellState extends State<DesktopShell> {
  /// 侧栏选中项(0..7),驱动 IndexedStack 与标题栏区块标题。
  int _index = 0;

  /// 首页当前的二级页(歌单详情/每日推荐/播放历史)。非 null 时内容区整个
  /// 覆盖为该页:窗口外壳(侧栏/标题栏/迷你播放器)保持原样,只有内容区
  /// 切换,不再整窗 push 路由。从二级页返回首页:置回 null。
  Widget? _homeBody;

  /// 首页当前覆盖的二级页;非 null 时标题栏标题回退为「正在听」。
  bool get _homeCovered => _homeBody != null;

  /// 打开首页歌单详情(内容区二级页);「放松时刻/工作学习」等推荐卡、榜单
  /// 卡片、你的歌单、推荐歌单都走这里,覆盖 `_homeBody` 而非整窗 push 路由。
  void _openHomePlaylist(int id, String title, String coverUrl) {
    setState(() {
      _homeBody = PlaylistDetailPage(
        playlistId: id,
        title: title,
        coverUrl: coverUrl,
        playback: widget.playback,
        token: widget.account.token,
      );
    });
  }

  /// 侧栏是否展开(展开 320 宽带文字,收起 50 宽仅图标)。由标题栏左侧那枚
  /// 汉堡按钮驱动:显示模式固定 expanded,fluent 自带的 togglePane() 在这个
  /// 模式下是空实现,收展只能自己管。
  bool _paneOpen = false;

  /// 主导航项。前 4 项与移动端 tab 语义对应(首页/发现/我的/搜索);后 2 项
  /// 原属「更多」子菜单,现在直接作为独立导航项,点击即切 IndexedStack。
  static const _mainEntries = <_NavEntry>[
    (label: '首页', icon: WindowsIcons.home, title: '正在听'),
    (label: '发现', icon: WindowsIcons.globe, title: '发现'),
    (label: '我的', icon: WindowsIcons.contact, title: '我的'),
    (label: '搜索', icon: WindowsIcons.search, title: '搜索'),
    (label: '播放历史', icon: WindowsIcons.history, title: '播放历史'),
    (label: '本地音乐', icon: WindowsIcons.folder, title: '本地音乐'),
  ];

  /// 面板底部的项(WinUI 惯例:设置固定沉底)。
  static const _footerEntries = <_NavEntry>[
    (label: '设置', icon: WindowsIcons.settings, title: '设置'),
    (label: '帮助与支持', icon: WindowsIcons.help, title: '帮助与支持'),
  ];

  /// 选中下标查的是这份合并表:fluent 的 `NavigationPane.selected` 索引的是
  /// `items + footerItems` 拼接后的可导航项,顺序必须与 [_pages] 一一对应。
  /// 分隔符不是 `PaneItem`,不占下标。
  static const _entries = <_NavEntry>[..._mainEntries, ..._footerEntries];

  @override
  Widget build(BuildContext context) {
    final miuix = MiuixTheme.of(context);
    // 外壳自己铺底色:迷你播放器横条那一带不归 NavigationView 画,不铺会露出
    // 窗口的黑色清屏色。注意不能靠 Material 的 color--MaterialType.transparency
    // 不画任何东西(color 被忽略),故用 ColoredBox 铺色、Material 只用来给下游
    // Miuix 组件提供 Material 祖先。
    return ColoredBox(
      color: miuix.colors.surface,
      child: m.Material(
        type: m.MaterialType.transparency,
        child: Column(
          children: [
            Expanded(
              child: FluentTheme(
                // 与挂在根 Overlay 之上那层同一份主题(见
                // DesktopRootFluentTheme):浮层与外壳本体的配色才不会两套。
                data: desktopFluentTheme(context),
                child: NavigationView(
                  titleBar: DesktopTitleBar(
                    title: _homeCovered
                        ? '正在听'
                        : _entries[_index].title,
                    paneOpen: _paneOpen,
                    onTogglePane: () => setState(() => _paneOpen = !_paneOpen),
                    // 首页二级页覆盖时:标题栏最左侧出现返回按钮,点击回首页。
                    onBack: _homeCovered
                        ? () => setState(() => _homeBody = null)
                        : null,
                  ),
                  pane: NavigationPane(
                    selected: _index,
                    onChanged: (index) => setState(() {
                      _index = index;
                      // 切走首页时清理二级页覆盖,避免回来后还是歌单详情。
                      if (_index != 0) _homeBody = null;
                    }),                    // 固定 expanded,收展改由 size.openWidth 承担(理由见类文档)。
                    displayMode: PaneDisplayMode.expanded,
                    size: NavigationPaneSize(
                      openWidth: _paneOpen
                          ? kOpenNavigationPaneWidth
                          : kCompactNavigationPaneWidth,
                    ),
                    items: [
                      for (final entry in _mainEntries.take(4)) _paneItem(entry),
                      PaneItemSeparator(),
                      for (final entry in _mainEntries.skip(4)) _paneItem(entry),
                    ],
                    footerItems: [
                      for (final entry in _footerEntries) _paneItem(entry),
                    ],
                  ),
                  // 内容统一由这里给出,不走各 PaneItem 的 body(见类文档第 3 条)。
                  paneBodyBuilder: (item, body) =>
                      _buildBody(miuix.colors.surface),
                ),
              ),
            ),
            // 底部常驻迷你播放器：有当前曲目时才挂。自绘、零 fluent_ui（见
            // DesktopMiniPlayer），故放在 FluentTheme 外面无妨——它取 Miuix
            // 主题与 Material，不依赖 fluent。
            if (widget.playback.state.currentTrack != null)
              DesktopMiniPlayer(
                playback: widget.playback,
                audioSources: widget.audioSources,
                account: widget.account,
              ),
          ],
        ),
      ),
    );
  }

  /// 一条导航项。[PaneItem.body] 必须非 null——fluent 会把 body 为空的项从
  /// `effectiveItems` 里剔除,那样 `selected` 下标就和页面对不上了;真正的
  /// 内容由 `paneBodyBuilder` 提供,所以这里给个空盒占位。
  ///
  /// 收起态要自己补文字提示:fluent 只在 compact *显示模式*下自动给 PaneItem
  /// 加提示,而这里全程停在 expanded(见类文档)。提示挂在图标上,并把它撑到
  /// 整行高以便悬停;**宽度不能撑**——收起到 50 宽时行内只有 38 的余量,
  /// `iconPadding(12) + 图标 + iconPadding(12)` 已经占满,撑宽必溢出。
  PaneItem _paneItem(_NavEntry entry) => PaneItem(
    icon: _paneOpen
        ? Icon(entry.icon)
        : SizedBox(
            height: kPaneItemMinHeight,
            child: probeTooltip(
              child: Icon(entry.icon),
              build: () => Tooltip(
                message: entry.label,
                child: Icon(entry.icon),
              ),
            ),
          ),
    title: Text(entry.label),
    body: const SizedBox.shrink(),
  );

  /// 内容区:全部页面用 [IndexedStack] 保活(切换不丢状态、不重拉)。
  ///
  /// [FluentTheme] 会往子树注入自己的 DefaultTextStyle 与 IconTheme,而这些
  /// 页面是和移动端共用的 Miuix/Material 页,吃到 fluent 的默认字号(14 号
  /// body)与图标色就会和移动端不一致。[m.Material] 本身会把 DefaultTextStyle
  /// 重置回 `textTheme.bodyMedium`,IconTheme 得显式补一层。
  Widget _buildBody(Color background) => ColoredBox(
    color: background,
    child: Builder(
      builder: (context) => m.IconTheme(
        data: m.Theme.of(context).iconTheme,
        child: m.Material(
          type: m.MaterialType.transparency,
          child: probeNoIndexedStack
              ? _pages()[_index]
              : IndexedStack(index: _index, children: _pages()),
        ),
      ),
    ),
  );

  List<Widget> _pages() => [
    DesktopHomePage(
      account: widget.account,
      home: widget.home,
      discover: widget.discover,
      playlists: widget.playlists,
      playback: widget.playback,
      onOpenPlayer: widget.onOpenPlayer,
      onOpenPlaylist: widget.onOpenHomePlaylist ?? _openHomePlaylist,
      // 首页二级页覆盖:见 [DesktopHomePage] 类文档「桌面端次级页面不走路由」。
      onOpenSecondary: (page) => setState(() => _homeBody = page),
      body: _homeBody,
    ),
    DiscoverPage(
      discover: widget.discover,
      // 发现页保持整窗 push(桌面端既有行为);首页的歌单入口才走内容区
      // 二级页(见 _openHomePlaylist)。两种入口行为不同:首页→二级菜单,
      // 发现页→独立页面。
      onOpenPlaylist: (playlist) => Navigator.of(context).push(
        m.MaterialPageRoute<void>(
          builder: (_) => PlaylistDetailPage(
            playlistId: playlist.id,
            title: playlist.name,
            coverUrl: playlist.coverImgUrl,
            playback: widget.playback,
            token: widget.account.token,
          ),
        ),
      ),
    ),
    ProfilePage(
      accountSessionController: widget.account,
      playback: widget.playback,
      playlists: widget.playlists,
    ),
    SearchPage(search: widget.search, playback: widget.playback),
    HistoryPage(playback: widget.playback),
    LocalMusicPage(playback: widget.playback),
    SettingsPage(account: widget.account, audioSources: widget.audioSources),
    SupportPage(account: widget.account),
  ];
}
