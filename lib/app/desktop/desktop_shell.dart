import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as m;
// 侧栏与标题栏走 fluent,这里只借 Miuix 的配色给外壳其余部分。底部迷你播放器
// 由独立的 [DesktopMiniPlayer] 自绘(零 fluent_ui,取 Miuix 配色)。仍用 show
// 限定,避免与 fluent_ui 的同名导出撞车。
import 'package:flutter_miuix/miuix.dart' show MiuixTheme, MiuixColors;

import '../debug_probe.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/discovery/discover_controller.dart';
import '../../application/home/home_controller.dart';
import '../../application/playback/playback_controller.dart';
import '../../application/playlists/playlist_library_controller.dart';
import '../../application/search/search_controller.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/playlist.dart';
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
  final void Function(int id, String title, String coverUrl)?
  onOpenHomePlaylist;

  /// 打开发现页歌单详情。桌面端为 null 时同上,走内容区二级页。
  final void Function(DiscoveryPlaylist playlist)? onOpenDiscoverPlaylist;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

/// 单条导航项的静态描述:导航项文案 [label]、Segoe Fluent 图标 [icon]、顶部
/// 标题栏区块标题 [title]。用 record 替代平行数组,消除索引错位风险。
typedef _NavEntry = ({String label, IconData icon, String title});

class _DesktopShellState extends State<DesktopShell> {
  /// 侧栏选中项(0..7),驱动 IndexedStack 页面切换。
  int _index = 0;

  /// 首页二级页导航栈(歌单详情/每日推荐/播放历史)。栈非空时内容区整个
  /// 覆盖为栈顶:窗口外壳(侧栏/标题栏/迷你播放器)保持原样,只有内容区
  /// 切换,不再整窗 push 路由。上一级/下一级按钮驱动后退/前进,栈空即首页。
  final _homeStack = DesktopHomeStack();

  /// 发现页自己的内容区二级页栈，避免歌单详情通过路由覆盖整个桌面窗口。
  final _discoverStack = DesktopHomeStack();

  /// “我的”页菜单与个人歌单使用的内容区二级页栈。
  final _profileStack = DesktopHomeStack();

  /// 设置页各分类页面使用的内容区二级页栈。
  final _settingsStack = DesktopHomeStack();

  DesktopHomeStack get _activeSecondaryStack => switch (_index) {
    1 => _discoverStack,
    2 => _profileStack,
    6 => _settingsStack,
    _ => _homeStack,
  };

  /// 打开首页歌单详情(内容区二级页);「放松时刻/工作学习」等推荐卡、榜单
  /// 卡片、你的歌单、推荐歌单都走这里,压入 `_homeStack` 而非整窗 push 路由。
  void _openHomePlaylist(int id, String title, String coverUrl) {
    setState(() {
      _homeStack.push(
        PlaylistDetailPage(
          playlistId: id,
          title: title,
          coverUrl: coverUrl,
          playback: widget.playback,
          token: widget.account.token,
          onOpenPlaylist: _openHomePlaylist,
          desktopLayout: true,
        ),
      );
    });
  }

  void _openDiscoverPlaylist(DiscoveryPlaylist playlist) {
    setState(() {
      _discoverStack.push(
        PlaylistDetailPage(
          playlistId: playlist.id,
          title: playlist.name,
          coverUrl: playlist.coverImgUrl,
          playback: widget.playback,
          token: widget.account.token,
          desktopLayout: true,
        ),
      );
    });
  }

  /// 打开首页「你的歌单」中的个人歌单。此处必须使用 personal 构造，令曲目
  /// 从 Cyrene 后端 `/playlists/:id/tracks` 加载，而不是误走在线发现歌单接口。
  void _openPersonalPlaylist(Playlist playlist) {
    final token = widget.account.token;
    if (token == null || token.isEmpty) return;
    setState(() {
      _homeStack.push(
        PlaylistDetailPage.personal(
          playlistId: playlist.id,
          title: playlist.name,
          coverUrl: playlist.coverUrl ?? '',
          playback: widget.playback,
          token: token,
          trackCount: playlist.trackCount,
          desktopLayout: true,
        ),
      );
    });
  }

  /// 侧栏是否展开(展开 320 宽带文字,收起 50 宽仅图标)。由标题栏左侧那枚
  /// 汉堡按钮驱动:显示模式固定 expanded,fluent 自带的 togglePane() 在这个
  /// 模式下是空实现,收展只能自己管。
  bool _paneOpen = false;

  /// 标题栏搜索框最近一次提交的关键词与序号。序号驱动 [SearchPage] 重建:
  /// 换 key 触发它 `initState` 里的 `search(initialQuery)`,同词也能重搜。
  /// 从侧栏正常进入「搜索」时序号不变,该页保留原有状态。
  String _searchKeyword = '';
  int _searchSeq = 0;

  /// 标题栏搜索框提交:切到「搜索」导航项,并让搜索页以该关键词重建搜索。
  void _onTitleBarSearch(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    setState(() {
      _index = 3; // 「搜索」在 _entries 里的下标(见 _mainEntries)。
      _homeStack.clear(); // 离开首页,清二级页栈。
      _discoverStack.clear();
      _profileStack.clear();
      _settingsStack.clear();
      _searchKeyword = k;
      _searchSeq++;
    });
  }

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
    // 外壳顶层不走不透明底色,让 flutter_acrylic 的 Win11 Mica 效果透出。
    // NavigationView 的侧栏面板自带 fluent 的 Mica/Acrylic 背景;内容区
    // 使用半透明 surface 色,让系统 Mica 透过内容区,同时保持可读性;
    // 底栏迷你播放器由 DesktopMiniPlayer 自绘,不依赖此外壳底色。
    return m.Material(
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
                    title: _entries[_index].title,
                    paneOpen: _paneOpen,
                    onTogglePane: () => setState(() => _paneOpen = !_paneOpen),
                    // 首页二级页导航栈驱动后退/前进;按钮常驻显示,栈状态只
                    // 决定可点态。
                    canGoBack: _activeSecondaryStack.canGoBack,
                    canGoForward: _activeSecondaryStack.canGoForward,
                    onBack: () =>
                        setState(() => _activeSecondaryStack.back()),
                    onForward: () =>
                        setState(() => _activeSecondaryStack.forward()),
                    // 正中搜索框提交 → 切到搜索页展示结果。
                    onSubmitSearch: _onTitleBarSearch,
                  ),
                  pane: NavigationPane(
                    selected: _index,
                    onChanged: (index) => setState(() {
                      _index = index;
                      // 切走首页时清空二级页栈,避免回来后还是歌单详情。
                      if (_index != 0) _homeStack.clear();
                      // 发现页采用相同语义：切走后回到发现主页。
                      if (_index != 1) _discoverStack.clear();
                      // “我的”页切走后同样回到其主页面。
                      if (_index != 2) _profileStack.clear();
                      // 设置页切走后回到设置主页。
                      if (_index != 6) _settingsStack.clear();
                    }), // 固定 expanded,收展改由 size.openWidth 承担(理由见类文档)。
                    displayMode: PaneDisplayMode.expanded,
                    size: NavigationPaneSize(
                      openWidth: _paneOpen
                          ? kOpenNavigationPaneWidth
                          : kCompactNavigationPaneWidth,
                    ),
                    items: [
                      for (final entry in _mainEntries.take(4))
                        _paneItem(entry),
                      PaneItemSeparator(),
                      for (final entry in _mainEntries.skip(4))
                        _paneItem(entry),
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
              build: () =>
                  Tooltip(message: entry.label, child: Icon(entry.icon)),
            ),
          ),
    title: Text(entry.label),
    body: const SizedBox.shrink(),
  );

  /// 内容区:全部页面用 [IndexedStack] 保活(切换不丢状态、不重拉)。
  ///
  /// [background] 为半透明 surface 色,让系统 Mica 透过内容区,增强桌面端
  /// 沉浸感;内容区的卡片/列表等组件自带背景色,故可读性不受影响。
  ///
  /// 子树统一包裹 [MiuixTheme] 将 `colors.surface` 覆盖为透明,使所有
  /// [CyrenePage] → [MiuixScaffold] 的默认背景色也变为透明,防止其不透明
  /// surface 底色遮盖系统 Mica。
  ///
  /// [FluentTheme] 会往子树注入自己的 DefaultTextStyle 与 IconTheme,而这些
  /// 页面是和移动端共用的 Miuix/Material 页,吃到 fluent 的默认字号(14 号
  /// body)与图标色就会和移动端不一致。[m.Material] 本身会把 DefaultTextStyle
  /// 重置回 `textTheme.bodyMedium`,IconTheme 得显式补一层。
  Widget _buildBody(Color background) => ColoredBox(
    color: background.withOpacity(0.55),
    child: Builder(
      builder: (context) => MiuixTheme(
        data: MiuixTheme.of(context).copyWith(
          colors: MiuixTheme.of(context).colors.copy(surface: m.Colors.transparent),
        ),
        child: m.IconTheme(
          data: m.Theme.of(context).iconTheme,
          child: m.Material(
            type: m.MaterialType.transparency,
            child: probeNoIndexedStack
                ? _pages()[_index]
                : IndexedStack(index: _index, children: _pages()),
          ),
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
      onOpenPersonalPlaylist: _openPersonalPlaylist,
      // 首页二级页覆盖:见 [DesktopHomePage] 类文档「桌面端次级页面不走路由」。
      onOpenSecondary: (page) => setState(() => _homeStack.push(page)),
      body: _compactSecondary(_homeStack.current),
    ),
    DiscoverPage(
      discover: widget.discover,
      onOpenPlaylist:
          widget.onOpenDiscoverPlaylist ?? _openDiscoverPlaylist,
      body: _compactSecondary(_discoverStack.current),
    ),
    ProfilePage(
      accountSessionController: widget.account,
      playback: widget.playback,
      playlists: widget.playlists,
      desktopLayout: true,
      onOpenSecondary: (page) => setState(() => _profileStack.push(page)),
      body: _compactSecondary(_profileStack.current),
    ),
    SearchPage(
      // key 随标题栏提交序号变化 → 该页重建,initState 里以 initialQuery
      // 自动搜索并回填输入框;侧栏正常进入时 key 不变,保留原有状态。
      key: ValueKey('search-$_searchSeq'),
      search: widget.search,
      playback: widget.playback,
      initialQuery: _searchKeyword,
    ),
    HistoryPage(playback: widget.playback),
    LocalMusicPage(playback: widget.playback),
    SettingsPage(
      account: widget.account,
      audioSources: widget.audioSources,
      onOpenSecondary: (page) => setState(() => _settingsStack.push(page)),
      body: _compactSecondary(_settingsStack.current),
    ),
    SupportPage(account: widget.account),
  ];

  Widget? _compactSecondary(Widget? page) => page == null
      ? null
      : _DesktopCompactSecondary(child: page);
}

/// 桌面二级内容的统一紧凑层。只调整二级页，不改变一级页面和移动端视觉。
class _DesktopCompactSecondary extends StatelessWidget {
  const _DesktopCompactSecondary({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final material = m.Theme.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: const m.TextScaler.linear(0.9)),
      child: m.Theme(
        data: material.copyWith(
          visualDensity: const m.VisualDensity(horizontal: -2, vertical: -2),
          iconTheme: material.iconTheme.copyWith(size: 20),
        ),
        child: child,
      ),
    );
  }
}

/// 首页二级页导航栈:后退/前进都按「栈模型」语义——后退把当前页弹回上一页
/// (弹到首页即栈空),前进把刚弹出的页再放回。进栈即断掉前进分支,与浏览器
/// 行为一致(见 [push] 注释)。逐页渲染靠 [current] 取栈顶,页面保活由
/// [IndexedStack] 承担,故本类只存 Widget 不掺状态。
class DesktopHomeStack {
  final List<Widget> _back = [];
  final List<Widget> _forward = [];

  /// 有可后退的上级页面。栈非空即可后退:栈顶就是当前二级页,后退把它弹回
  /// (弹到栈空即回首页)。首页本体不在栈里,栈空时无法后退。
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  Widget? get current => _back.isEmpty ? null : _back.last;

  /// 压入新页。回退后又前进到新位置时,旧的前进分支作废(与浏览器一致)。
  void push(Widget page) {
    _back.add(page);
    _forward.clear();
  }

  void back() {
    if (!canGoBack) return;
    final current = _back.removeLast();
    _forward.add(current);
  }

  void forward() {
    if (!canGoForward) return;
    _back.add(_forward.removeLast());
  }

  void clear() {
    _back.clear();
    _forward.clear();
  }
}
