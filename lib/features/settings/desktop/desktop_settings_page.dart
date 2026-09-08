import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../app/app_version.dart';
import '../../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../../application/auth/account_session_controller.dart';
import '../../../domain/models/media_url.dart';
import '../../../domain/models/user.dart';
import '../../../infrastructure/services/developer_mode_service.dart';
import '../../../presentation/cyrene/cyrene_page.dart';
import '../../../presentation/cyrene/cyrene_toast.dart';
import '../about_page.dart';
import '../ai_settings_page.dart';
import '../appearance_settings_page.dart';
import '../audio_source_settings_page.dart';
import '../cache_settings_page.dart';
import '../developer_options_page.dart';
import '../equalizer_page.dart';
import '../login_page.dart';
import '../personal_center_page.dart';
import '../settings_actions.dart';
import '../together_settings_page.dart';

/// 桌面端设置页：所有设置项合并成一条长滚动，顶部一排锚点 tab。
///
/// 移动端的 `SettingsPage` 是「一屏入口 + 逐层下钻」，在 1400px 宽的窗口里
/// 就是一列孤零零的箭头。这里换成网易云桌面版那套：**内容全在一页**，tab 只
/// 是书签——滚动时高亮跟着走，点 tab 则滚到对应段落。
///
/// 各段落的正文不是在这里重写的，全是各设置页抽出来的 `XxxBody`
/// （见 `settings_body.dart`）。这一点必须守住：这里再抄一份开关逻辑，
/// 就等于给每个设置项开了两套实现。
class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({
    super.key,
    required this.account,
    required this.audioSources,
    this.onOpenSecondary,
    this.body,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;

  /// 二级页在右侧栏打开（与 `SettingsPage` 同一套约定）。
  final ValueChanged<Widget>? onOpenSecondary;

  /// 二级栈栈顶。非空时整页让位给它，与 `SettingsPage` 行为一致。
  final Widget? body;

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

/// 段落顶端滚过这个距离就算「进入」该段。
///
/// 取 0 会让相邻两段在边界上反复横跳（顶端正好压线时浮点抖动就能翻转），
/// 留一点余量，高亮切换才是干脆的一次。
const double _kAnchorThresholdPx = 28;

/// 内容区最大宽度。再宽下去每行要扫的距离就超出舒适范围了，
/// 与音源页桌面布局的 1040 同源。
const double _kContentMaxWidth = 1040;

const Duration _kAnchorScrollDuration = Duration(milliseconds: 420);

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  late final List<GlobalKey> _sectionKeys;

  /// 当前高亮的段落。
  ///
  /// **刻意不做成 State 字段**：滚动时它一秒能变好几次，走 setState 就会把整页
  /// 八段正文（含音源那张 shrinkWrap 的可拖排序列表、均衡器十条推子）全部重建，
  /// 那正是滑动发卡的原因。做成 ValueNotifier 后只有顶部 tab 条会重建。
  final ValueNotifier<int> _activeIndex = ValueNotifier<int>(0);

  /// 段落只构建一次。
  ///
  /// 同理：bodyBuilder 每重跑一次就重新 new 一遍八段正文，整棵元素树都要比对，
  /// 白付一次 diff。只有控制器换了才需要重来（见 didUpdateWidget）。
  List<_SettingsSection>? _sections;

  /// 点 tab 触发的滚动期间不要回读滚动位置。
  ///
  /// 否则动画一路扫过中间那几段，高亮会跟着闪一串，看着像点错了。
  bool _programmaticScroll = false;

  @override
  void initState() {
    super.initState();
    _sectionKeys = List.generate(_kSectionCount, (_) => GlobalKey());
    _controller.addListener(_syncActiveSection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncActiveSection());
  }

  @override
  void didUpdateWidget(covariant DesktopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.account != oldWidget.account ||
        widget.audioSources != oldWidget.audioSources ||
        widget.onOpenSecondary != oldWidget.onOpenSecondary) {
      _sections = null;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncActiveSection)
      ..dispose();
    _activeIndex.dispose();
    super.dispose();
  }

  /// 段落数量。与 [_buildSections] 必须对齐——多一个少一个都会错位。
  static const int _kSectionCount = 8;

  void _syncActiveSection() {
    if (_programmaticScroll || !mounted) return;

    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;

    var next = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final sectionContext = _sectionKeys[i].currentContext;
      if (sectionContext == null) continue;
      final box = sectionContext.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero, ancestor: viewport).dy <=
          _kAnchorThresholdPx) {
        next = i;
      }
    }

    // 最后一段通常没长到能顶到视口顶端，光看位置永远轮不到它高亮。
    // 滚到底就直接判给它——这也是用户此刻真正在看的东西。
    final position = _controller.position;
    if (position.hasContentDimensions &&
        position.pixels >= position.maxScrollExtent - 4) {
      next = _sectionKeys.length - 1;
    }

    _activeIndex.value = next;
  }

  Future<void> _scrollToSection(int index) async {
    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext == null) return;

    _activeIndex.value = index;
    _programmaticScroll = true;
    await Scrollable.ensureVisible(
      sectionContext,
      duration: _kAnchorScrollDuration,
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
    if (!mounted) return;
    _programmaticScroll = false;
    _syncActiveSection();
  }

  @override
  Widget build(BuildContext context) {
    final secondaryBody = widget.body;
    if (secondaryBody != null) return secondaryBody;

    return CyrenePage(
      title: '设置',
      // 小标题栏：锚点 tab 条要常驻在顶栏正下方，大标题折叠时那条会跟着上下
      // 位移，读起来像在抖。
      largeTitle: false,
      bodyBuilder: (context, topPadding) {
        final sections = _sections ??= _buildSections();
        return Padding(
          padding: topPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RepaintBoundary(
                child: _AnchorTabBar(
                  labels: [for (final section in sections) section.label],
                  activeIndex: _activeIndex,
                  onSelected: _scrollToSection,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: _viewportKey,
                  controller: _controller,
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kContentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < sections.length; i++)
                            // 每段自成一层：SingleChildScrollView 不像 ListView
                            // 那样自动给孩子加重绘边界，少了这层，滚动的每一帧
                            // 都要把整条八段长文重画一遍。
                            RepaintBoundary(
                              child: _SectionBlock(
                                key: _sectionKeys[i],
                                title: sections[i].label,
                                description: sections[i].description,
                                child: sections[i].child,
                              ),
                            ),
                          // 末段也要能滚到顶端，否则它永远拿不到高亮。
                          // 留一屏的余量，最后一个 tab 才点得动。
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * .6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_SettingsSection> _buildSections() => [
    _SettingsSection(
      label: '账号',
      description: '登录状态与个人资料',
      child: AnimatedBuilder(
        animation: widget.account,
        builder: (context, _) => _AccountSection(
          account: widget.account,
          onOpenSecondary: widget.onOpenSecondary,
          onOpen: _openPage,
        ),
      ),
    ),
    _SettingsSection(
      label: '播放与音源',
      description: '解析服务的顺序、启用状态与默认音质',
      child: AnimatedBuilder(
        animation: widget.account,
        builder: (context, _) => AudioSourceSettingsBody(
          controller: widget.audioSources,
          account: widget.account,
          topPadding: EdgeInsets.zero,
          token: widget.account.state.isLoggedIn ? widget.account.token : null,
          desktopLayout: true,
          embedded: true,
        ),
      ),
    ),
    const _SettingsSection(
      label: '音效',
      description: '均衡器与 DSP 滤镜',
      child: EqualizerBody(embedded: true),
    ),
    const _SettingsSection(
      label: 'AI 助手',
      description: '接自己的模型服务，生成赏析、总结与推荐',
      child: AiSettingsBody(embedded: true),
    ),
    _SettingsSection(
      label: '一起听',
      description: '和朋友同步听歌、发弹幕',
      child: TogetherSettingsBody(
        embedded: true,
        onOpenSecondary: widget.onOpenSecondary,
      ),
    ),
    _SettingsSection(
      label: '缓存',
      description: '加密缓存已播放的歌曲，离线也能听',
      child: CacheSettingsBody(
        embedded: true,
        onOpenSecondary: widget.onOpenSecondary,
      ),
    ),
    _SettingsSection(
      label: '外观',
      description: '主题、播放器样式与背景',
      child: AppearanceSettingsBody(account: widget.account, embedded: true),
    ),
    _SettingsSection(
      label: '关于',
      description: '公告、更新与版本信息',
      child: _AboutSection(onOpen: _openPage),
    ),
  ];

  void _openPage(BuildContext context, Widget page) {
    final openSecondary = widget.onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(page);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _SettingsSection {
  const _SettingsSection({
    required this.label,
    required this.description,
    required this.child,
  });

  final String label;
  final String description;
  final Widget child;
}

/// 一个段落：标题 + 说明 + 正文。key 挂在最外层，锚点定位量的就是它的顶端。
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: MiuixText(
              title,
              style: theme.textStyles.title3.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: MiuixText(
              description,
              style: theme.textStyles.footnote1,
              color: theme.colors.onBackgroundVariant,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 顶部锚点 tab 条。横向可滚，窄窗口下也不会挤成一团。
///
/// 高亮走 [activeIndex] 这个 listenable 而不是构造参数：滚动时高亮变得很勤，
/// 让上层 setState 把它传下来就等于每次都重建整页正文。
class _AnchorTabBar extends StatefulWidget {
  const _AnchorTabBar({
    required this.labels,
    required this.activeIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final ValueListenable<int> activeIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_AnchorTabBar> createState() => _AnchorTabBarState();
}

class _AnchorTabBarState extends State<_AnchorTabBar> {
  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _chipKeys = [];

  @override
  void initState() {
    super.initState();
    widget.activeIndex.addListener(_onActiveChanged);
  }

  @override
  void didUpdateWidget(covariant _AnchorTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != oldWidget.activeIndex) {
      oldWidget.activeIndex.removeListener(_onActiveChanged);
      widget.activeIndex.addListener(_onActiveChanged);
    }
  }

  @override
  void dispose() {
    widget.activeIndex.removeListener(_onActiveChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 高亮换了就把它带进可视区：滚动到靠后的段落时，对应的 tab 可能已经被
  /// 挤出了这条横向滚动。
  void _onActiveChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  void _revealActive() {
    if (!mounted) return;
    final index = widget.activeIndex.value;
    if (index >= _chipKeys.length) return;
    final chipContext = _chipKeys[index].currentContext;
    if (chipContext == null) return;
    Scrollable.ensureVisible(
      chipContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: .5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    while (_chipKeys.length < widget.labels.length) {
      _chipKeys.add(GlobalKey());
    }

    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colors.dividerLine, width: .8),
        ),
      ),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (var i = 0; i < widget.labels.length; i++)
              Padding(
                key: _chipKeys[i],
                padding: const EdgeInsets.only(right: 6),
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.activeIndex,
                  builder: (context, active, _) => _AnchorTab(
                    key: settingsTabKey(widget.labels[i]),
                    label: widget.labels[i],
                    selected: i == active,
                    onTap: () => widget.onSelected(i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 锚点 tab 的稳定 key。
///
/// 段落标题跟 tab 是同一串文案，按文字找会撞上；测试要断言「哪个 tab 亮着」
/// 就得有个不会歧义的抓手。
Key settingsTabKey(String label) => Key('settings-tab-$label');

class _AnchorTab extends StatefulWidget {
  const _AnchorTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AnchorTab> createState() => _AnchorTabState();
}

class _AnchorTabState extends State<_AnchorTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final selected = widget.selected;

    return Semantics(
      // 这是一排「哪一段是当前段」的书签，不是普通按钮：选中态要报出去，
      // 读屏才说得清用户滚到哪儿了。测试也靠这个断言高亮跟没跟上滚动。
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected
                  ? theme.colors.primary.withValues(alpha: .14)
                  : (_hovered
                        ? theme.colors.onBackground.withValues(alpha: .06)
                        : Colors.transparent),
            ),
            child: MiuixText(
              widget.label,
              style: theme.textStyles.body2.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              color: selected
                  ? theme.colors.primary
                  : theme.colors.onBackgroundVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 账号段落：未登录给登录入口，已登录给个人中心入口。
class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.account,
    required this.onOpenSecondary,
    required this.onOpen,
  });

  final AccountSessionController account;
  final ValueChanged<Widget>? onOpenSecondary;
  final void Function(BuildContext context, Widget page) onOpen;

  @override
  Widget build(BuildContext context) {
    final state = account.state;

    if (state.status == AccountSessionStatus.restoring) {
      return const CyreneMenuGroup(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                MiuixCircularProgressIndicator(size: 18, strokeWidth: 2),
                SizedBox(width: 12),
                Text('正在恢复账号信息…'),
              ],
            ),
          ),
        ],
      );
    }

    final user = state.user;
    return CyreneMenuGroup(
      children: [
        if (user == null)
          CyreneMenuRow(
            key: const Key('open-login-button'),
            vector: MiuixIcons.extended.byName('contactsCircle')!,
            iconBackground: const Color(0xFF3482FF),
            title: '登录账号',
            subtitle: 'Cyrene Music 账号',
            onTap: () => _openLogin(context),
          )
        else
          CyreneMenuRow(
            key: const Key('open-personal-center'),
            leading: _AccountAvatar(user: user),
            title: user.username,
            subtitle: user.email,
            onTap: () => onOpen(
              context,
              PersonalCenterPage(
                account: account,
                onOpenSecondary: onOpenSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openLogin(BuildContext context) async {
    account.clearError();
    final openSecondary = onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(LoginPage(account: account));
      return;
    }
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginPage(account: account)),
    );
    if (loggedIn == true && context.mounted) {
      CyreneToast.show('登录成功，账号信息已安全保存在本机。');
    }
  }
}

/// 关于段落：公告 / 检查更新 / 关于页 / 开发者选项。
///
/// 这几项本身就是「点开另一个东西」，没有可以摊平到长页里的内容，
/// 所以保留成入口行。
class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.onOpen});

  final void Function(BuildContext context, Widget page) onOpen;

  @override
  Widget build(BuildContext context) => CyreneMenuGroup(
    children: [
      CyreneMenuRow(
        vector: MiuixIcons.extended.byName('promotions')!,
        iconBackground: const Color(0xFF3482FF),
        title: '公告',
        subtitle: '查看最新通知',
        onTap: () => openAnnouncement(context),
      ),
      CyreneMenuRow(
        vector: MiuixIcons.extended.byName('update')!,
        iconBackground: const Color(0xFF3CC756),
        title: '检查更新',
        value: 'v$appVersion',
        onTap: () => checkUpdateInteractively(context),
      ),
      CyreneMenuRow(
        vector: MiuixIcons.extended.byName('info')!,
        iconBackground: const Color(0xFFFF9F0A),
        title: '关于 Cyrene Music',
        onTap: () => onOpen(context, const AboutPage()),
      ),
      // 连点关于页版本号 5 次开启后才出现（对应原版开发者模式）。
      ListenableBuilder(
        listenable: DeveloperModeService.instance,
        builder: (context, _) => DeveloperModeService.instance.isDeveloperMode
            ? CyreneMenuRow(
                vector: MiuixIcons.extended.byName('notes')!,
                iconBackground: const Color(0xFF5F6368),
                title: '开发者选项',
                subtitle: '性能叠加层与运行日志',
                onTap: () => onOpen(context, const DeveloperOptionsPage()),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

/// 账号行的圆形头像：真实头像 + 首字母回退。
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final initial = user.username.trim().isEmpty
        ? '?'
        : user.username.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: 18,
      foregroundImage: user.avatarUrl?.isNotEmpty == true
          ? CachedNetworkImageProvider(
              user.avatarUrl!,
              headers: imageHeaders(user.avatarUrl!),
            )
          : null,
      // 加载失败时静默回退到文字头像，避免未处理的异步图片异常。
      onForegroundImageError: user.avatarUrl?.isNotEmpty == true
          ? (_, _) {}
          : null,
      backgroundColor: colors.primary,
      child: Text(
        initial,
        style: TextStyle(color: colors.onPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}
