import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../domain/models/payment_order.dart';
import '../../domain/models/user.dart';
import '../../infrastructure/services/membership_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import 'membership_orders_page.dart';
import 'premium_membership_section.dart';

/// 会员中心：显示当前账号的 Cyrene Premium 身份，并给出「我的订单」入口。
///
/// 会员卡片本身复用 [PremiumMembershipSection]——「播放与音源」页里那张
/// 状态/购买/重新下发卡是同一段代码，购买链路（下单 → 支付 → 轮询 → 下发）
/// 不在这里重写一遍。
///
/// 状态优先级说明：卡片的权威结论来自后端 `/card/status`（含存量赞助者补授
/// Premium 的闸门），本机快照只是缓存；两者不一致时以 `/card/status` 为准并
/// 回写快照（见 [_onCardStatus]），这样个人中心/「我的」页的徽章无需重登即更新。
///
/// 桌面端沿用设置页的二级栈范式：[onOpenSecondary] 非空时子页推右侧内容区，
/// [body] 非空表示当前就是栈顶页；移动端走 CupertinoPageRoute。
class MembershipCenterPage extends StatefulWidget {
  const MembershipCenterPage({
    super.key,
    required this.account,
    required this.audioSources,
    this.onOpenSecondary,
    this.body,
  });

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final ValueChanged<Widget>? onOpenSecondary;
  final Widget? body;

  @override
  State<MembershipCenterPage> createState() => _MembershipCenterPageState();
}

/// 内容区宽度达到这个值才用左右分栏的宽屏布局。
const _kWideBreakpoint = 760.0;

const _kPremiumPurple = Color(0xFF8A64FF);

class _MembershipCenterPageState extends State<MembershipCenterPage> {
  static const _iconBlue = Color(0xFF3482FF);
  static const _iconPurple = _kPremiumPurple;

  MembershipOrders? _orders;
  var _loadingOrders = true;

  /// 每手动刷新一次就 +1：用作会员卡片的 key，强制它重建并重新走 `/card/status`。
  /// 卡片自己是 StatefulWidget，不给它换一个 key 就没法从外面触发重拉。
  int _sectionRevision = 0;

  /// 会员状态与开通时间：初值取本机快照，随后被 /card/status 的权威结论覆盖。
  var _hasPremium = false;
  String? _premiumSince;

  String? get _token => widget.account.token;

  @override
  void initState() {
    super.initState();
    final user = widget.account.state.user;
    _hasPremium = user?.hasListeningCard ?? false;
    _premiumSince = user?.listeningCardSince;
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _loadingOrders = false);
      return;
    }
    final orders = await MembershipService.instance.getOrders(token);
    if (!mounted) return;
    setState(() {
      _loadingOrders = false;
      if (orders != null) _orders = orders;
    });
  }

  /// 卡片把 `/card/status` 的结论（或本地支付成功的即时结果）报上来时同步本页。
  void _onCardStatus({required bool hasCard, String? grantedAt}) {
    final changed = hasCard != _hasPremium;
    if (mounted) {
      setState(() {
        _hasPremium = hasCard;
        if (grantedAt != null && grantedAt.isNotEmpty) {
          _premiumSince = grantedAt;
        }
      });
    }
    // 服务端说已开通而本机快照还不知道（在别的设备买的 / 快照过期）：回写快照。
    final user = widget.account.state.user;
    if (hasCard && user != null && !user.hasListeningCard) {
      unawaited(
        widget.account.patchUser(
          (u) => u.copyWith(
            hasListeningCard: true,
            listeningCardSince: u.listeningCardSince ?? grantedAt,
          ),
        ),
      );
    }
    // 刚支付成功时订单表才多出已支付记录，顺手刷新汇总（首次加载不重复请求）。
    if (changed && hasCard) unawaited(_loadOrders());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    // 会员卡会回写会话快照（patchUser）、退登也会 notify：整页跟着重绘，
    // 会员状态行、入口可用性与未登录空态才不会停在旧快照上。
    animation: widget.account,
    builder: (context, _) => _page(),
  );

  Widget _page() {
    final secondaryBody = widget.body;
    if (secondaryBody != null) return secondaryBody;

    final token = _token;
    if (token == null || token.isEmpty) {
      return CyrenePage(
        title: '会员中心',
        body: const CyreneEmptyState(
          vector: null,
          icon: Icons.person_outline_rounded,
          title: '登录后查看会员中心',
          description: '登录 Cyrene Music 账号后可以查看 Premium 身份与支付订单。',
        ),
      );
    }

    // 会员卡 + 购买/重新下发入口（与「播放与音源」页同一实现），两种布局共用。
    final section = PremiumMembershipSection(
      key: ValueKey('premium-card-$_sectionRevision'),
      controller: widget.audioSources,
      account: widget.account,
      sources: widget.audioSources.state.sources,
      token: token,
      onStatusChanged: _onCardStatus,
    );

    return CyrenePage(
      title: '会员中心',
      actions: [
        CyreneBarButton(
          onPressed: _loadingOrders ? null : _refresh,
          tooltip: '刷新',
          child: MiuixIcon(vector: MiuixIcons.os4.refresh, size: 24),
        ),
      ],
      // 按内容区实际宽度切换，而不是按窗口：桌面设置的二级页也可能被压窄。
      bodyBuilder: (context, topPadding) => LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= _kWideBreakpoint
            ? _wideBody(context, topPadding, section)
            : _narrowBody(context, topPadding, section),
      ),
    );
  }

  /// 移动端 / 窄内容区：会员卡铺满宽度，下面依次是身份、订单与说明。
  Widget _narrowBody(
    BuildContext context,
    EdgeInsets topPadding,
    Widget section,
  ) => ListView(
    physics: const BouncingScrollPhysics(),
    padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
    children: [
      section,
      const SizedBox(height: 12),
      CyreneMenuGroup(children: _statusRows(widget.account.state.user)),
      const SizedBox(height: 12),
      const MiuixSmallTitle(
        '订单',
        insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
      ),
      CyreneMenuGroup(children: [_ordersRow(context)]),
      const SizedBox(height: 12),
      _ordersNotice(),
    ],
  );

  /// 桌面宽屏：会员卡收在左侧定宽一栏（原来 1.585 比例的卡面按整宽铺开，能占满
  /// 一屏），右侧是身份概览与数据卡；下面是权益网格与订单。
  Widget _wideBody(
    BuildContext context,
    EdgeInsets topPadding,
    Widget section,
  ) {
    final user = widget.account.state.user;
    final isSponsor = user?.isSponsor ?? false;
    final since = _formatDate(_premiumSince);
    final orders = _orders;
    return ListView(
      padding: topPadding + const EdgeInsets.fromLTRB(28, 12, 28, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 360, child: section),
                    const SizedBox(width: 32),
                    Expanded(
                      child: _MembershipOverview(
                        hasPremium: _hasPremium,
                        isSponsor: isSponsor,
                        since: since,
                        stats: [
                          _Stat(
                            icon: Icons.workspace_premium_rounded,
                            label: '会员状态',
                            value: _hasPremium
                                ? 'Premium'
                                : (isSponsor ? 'Sponsor' : '普通用户'),
                          ),
                          _Stat(
                            icon: Icons.verified_outlined,
                            label: '套餐',
                            value: _hasPremium ? '永久买断' : '未开通',
                          ),
                          _Stat(
                            icon: Icons.schedule_rounded,
                            label: '开通时间',
                            value: _hasPremium && since.isNotEmpty
                                ? since
                                : '—',
                          ),
                          _Stat(
                            icon: Icons.receipt_long_rounded,
                            label: '累计支付',
                            value: _loadingOrders
                                ? '…'
                                : (orders == null || orders.paidCount == 0)
                                ? '—'
                                : '¥${orders.totalPaid.toStringAsFixed(2)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                const _WideSectionTitle('会员权益'),
                _BenefitGrid(active: _hasPremium),
                const SizedBox(height: 36),
                const _WideSectionTitle('订单'),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final ordersGroup = CyreneMenuGroup(
                      children: [_ordersRow(context)],
                    );
                    if (constraints.maxWidth < 860) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ordersGroup,
                          const SizedBox(height: 12),
                          _ordersNotice(),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: ordersGroup),
                        const SizedBox(width: 16),
                        Expanded(child: _ordersNotice()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ordersRow(BuildContext context) => CyreneMenuRow(
    key: const Key('open-membership-orders'),
    vector: MiuixIcons.extended.byName('bankCards')!,
    iconBackground: _iconBlue,
    title: '我的订单',
    subtitle: _ordersSubtitle,
    value: _ordersValue,
    onTap: () =>
        _openPage(context, MembershipOrdersPage(account: widget.account)),
  );

  Widget _ordersNotice() => CyreneInlineAlert(
    vector: MiuixIcons.extended.byName('info')!,
    title: '关于订单',
    description:
        '订单含 Premium 买断与赞助记录。「已扣款但状态没变」通常是支付平台'
        '回调丢失，到我的订单里对该笔点「查询支付结果」即可补上权益。',
  );

  /// 会员身份行。套餐/开通时间只在已开通时出现，未开通时留一行说明门槛，
  /// 避免整组内容变成一排空值。
  List<Widget> _statusRows(User? user) {
    final since = _formatDate(_premiumSince);
    return [
      CyreneMenuRow(
        icon: Icons.workspace_premium_rounded,
        iconBackground: _hasPremium ? _iconPurple : null,
        title: '会员状态',
        value: _hasPremium
            ? 'Cyrene Premium'
            : ((user?.isSponsor ?? false) ? 'Sponsor' : '普通用户'),
        trailing: const SizedBox.shrink(),
      ),
      if (_hasPremium) ...[
        CyreneMenuRow(
          icon: Icons.verified_outlined,
          title: '套餐',
          value: '永久买断',
          trailing: const SizedBox.shrink(),
        ),
        CyreneMenuRow(
          icon: Icons.schedule_rounded,
          title: '开通时间',
          value: since.isEmpty ? '—' : since,
          trailing: const SizedBox.shrink(),
        ),
      ] else
        CyreneMenuRow(
          icon: Icons.info_outline_rounded,
          title: 'Premium 权益',
          subtitle: '一次付费永久生效，官方 OmniParse 音源自动下发到本机',
          trailing: const SizedBox.shrink(),
        ),
    ];
  }

  String get _ordersSubtitle {
    if (_loadingOrders) return '正在读取支付流水…';
    final orders = _orders;
    if (orders == null) return '查看全部支付订单';
    if (orders.isEmpty) return '还没有支付记录';
    return '${orders.orderCount} 笔订单'
        '${orders.pendingCount > 0 ? ' · ${orders.pendingCount} 笔待支付' : ''}';
  }

  String? get _ordersValue {
    final orders = _orders;
    if (orders == null || orders.paidCount == 0) return null;
    return '累计 ¥${orders.totalPaid.toStringAsFixed(2)}';
  }

  /// 手动刷新：同时重拉订单与会员状态（后者靠给卡片换 key 重建触发）。
  Future<void> _refresh() async {
    setState(() {
      _loadingOrders = true;
      _sectionRevision++;
    });
    await _loadOrders();
  }

  void _openPage(BuildContext context, Widget page) {
    final openSecondary = widget.onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(page);
      return;
    }
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  }
}

/// ISO 时间串 → `yyyy.MM.dd`；解析失败回落到原值，空值给空串。
String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}.${two(dt.month)}.${two(dt.day)}';
}

// ===== 宽屏布局部件 =====

class _Stat {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;
}

/// 宽屏右侧的身份概览：状态徽标 + 大标题 + 一句说明 + 四张数据卡。
class _MembershipOverview extends StatelessWidget {
  const _MembershipOverview({
    required this.hasPremium,
    required this.isSponsor,
    required this.since,
    required this.stats,
  });

  final bool hasPremium;
  final bool isSponsor;
  final String since;
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final badgeColor = hasPremium
        ? _kPremiumPurple
        : colors.onSurfaceVariantSummary;
    final title = hasPremium ? '你已是 Cyrene Premium 会员' : '升级到 Cyrene Premium';
    final description = hasPremium
        ? '${since.isEmpty ? '' : '开通于 $since，'}永久有效。官方 OmniParse 音源已随账号下发到本机。'
        : '一次付费，永久生效。开通后官方 OmniParse 音源自动下发到本机'
              '${isSponsor ? '，感谢你一直以来的赞助' : ''}。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasPremium
                    ? Icons.verified_rounded
                    : Icons.lock_outline_rounded,
                size: 15,
                color: badgeColor,
              ),
              const SizedBox(width: 5),
              Text(
                hasPremium ? '已开通' : '未开通',
                style: theme.textStyles.footnote1.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: theme.textStyles.title2.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: theme.textStyles.body2.copyWith(
            color: colors.onSurfaceVariantSummary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final columns = constraints.maxWidth >= 560 ? 4 : 2;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final stat in stats)
                  SizedBox(
                    width: width,
                    child: _StatTile(stat: stat, accent: hasPremium),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, required this.accent});

  final _Stat stat;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            stat.icon,
            size: 18,
            color: accent ? _kPremiumPurple : colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 10),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.footnote1.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyles.body1.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _WideSectionTitle extends StatelessWidget {
  const _WideSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Text(
        title,
        style: theme.textStyles.title4.copyWith(
          color: theme.colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(this.icon, this.color, this.title, this.description);

  final IconData icon;
  final Color color;
  final String title;
  final String description;
}

/// 权益网格。文案只写真实存在的能力（音源下发 / 买断 / 重新下发 / 订单补单）。
class _BenefitGrid extends StatelessWidget {
  const _BenefitGrid({required this.active});

  /// 已开通时每张卡右上角标「已生效」。
  final bool active;

  static const _benefits = [
    _Benefit(
      Icons.cloud_download_rounded,
      Color(0xFF3482FF),
      '官方音源自动下发',
      '开通后官方 OmniParse 音源配置自动下发到本机，不用手动填写地址与密钥。',
    ),
    _Benefit(
      Icons.all_inclusive_rounded,
      _kPremiumPurple,
      '永久买断',
      '一次付费永久生效，没有续费，也没有到期时间。',
    ),
    _Benefit(
      Icons.sync_rounded,
      Color(0xFF3CC756),
      '密钥更新一键同步',
      '服务端更换密钥后，点「重新下发配置」即可同步到本机。',
    ),
    _Benefit(
      Icons.receipt_long_rounded,
      Color(0xFFFF9500),
      '订单可查可补',
      '支付流水随时可查；支付回调丢失时可在订单里查询结果，补上权益。',
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 14.0;
      final columns = constraints.maxWidth >= 900 ? 4 : 2;
      final rows = <Widget>[];
      for (var start = 0; start < _benefits.length; start += columns) {
        final slice = _benefits.skip(start).take(columns).toList();
        if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
        // 同一行的卡片等高：文案长短不一，不拉齐会参差不齐。
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: i < slice.length
                        ? _BenefitTile(benefit: slice[i], active: active)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    },
  );
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.benefit, required this.active});

  final _Benefit benefit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: benefit.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(benefit.icon, size: 21, color: benefit.color),
              ),
              const Spacer(),
              if (active)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Color(0xFF3CC756),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '已生效',
                      style: theme.textStyles.footnote2.copyWith(
                        color: const Color(0xFF3CC756),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            benefit.title,
            style: theme.textStyles.body1.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            benefit.description,
            style: theme.textStyles.footnote1.copyWith(
              color: colors.onSurfaceVariantSummary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
