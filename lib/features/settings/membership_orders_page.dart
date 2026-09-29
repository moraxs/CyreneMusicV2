import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../domain/models/payment_order.dart';
import '../../infrastructure/services/membership_service.dart';
import '../../infrastructure/services/sponsor_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 我的订单：当前账号的全部支付流水（金额、状态、支付时间、订单号）。
///
/// 数据来自后端 `/member/orders`（按登录用户取 donations，含未支付单）。未支付
/// 单必须出现在列表里：换了设备或杀掉进程后，这里是唯一还能看到「这笔没付成功」
/// 的地方，也是补权益的入口——行内的「查询支付结果」会打 `/pay/query`，后端在
/// 查到已付款时会顺手把权益补发（见 routes/pay.ts 的 grantEntitlement 幂等重试）。
class MembershipOrdersPage extends StatefulWidget {
  const MembershipOrdersPage({super.key, required this.account});

  final AccountSessionController account;

  @override
  State<MembershipOrdersPage> createState() => _MembershipOrdersPageState();
}

class _MembershipOrdersPageState extends State<MembershipOrdersPage> {
  MembershipOrders? _result;
  var _loading = true;
  String? _error;

  /// 正在向网关补查的订单号，用来把那一行的按钮变成转圈并挡住重复点击。
  String? _syncingOutTradeNo;

  String? get _token => widget.account.token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = '登录后即可查看支付订单';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await MembershipService.instance.getOrders(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null) {
        _error = '加载失败，请检查网络后重试';
        return;
      }
      _result = result;
    });
  }

  /// 向网关补查单笔支付结果：付过了就把权益和本机快照补上。
  Future<void> _syncOrder(PaymentOrder order) async {
    final outTradeNo = order.outTradeNo;
    if (outTradeNo.isEmpty || _syncingOutTradeNo != null) return;
    setState(() => _syncingOutTradeNo = outTradeNo);
    try {
      final data = await SponsorService.instance.queryPayStatus(outTradeNo);
      final status = data['status'];
      final paid = status == 1 || status == '1';
      if (!mounted) return;
      if (paid) {
        // /pay/query 已经在服务端把订单置为已支付并授予权益；本机会话快照同步跟上，
        // 否则个人中心徽章要等下次登录才变。
        if (order.paymentType == 'card') {
          final grantedAt = DateTime.now().toIso8601String();
          await widget.account.patchUser(
            (u) => u.copyWith(
              hasListeningCard: true,
              listeningCardSince: u.listeningCardSince ?? grantedAt,
            ),
          );
        }
        CyreneToast.show('该订单已支付，权益已补齐');
        await _load();
      } else {
        CyreneToast.show('这笔订单还没收到支付结果');
      }
    } catch (_) {
      if (mounted) CyreneToast.show('查询失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _syncingOutTradeNo = null);
    }
  }

  Future<void> _copy(String text, String label) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) CyreneToast.show('$label已复制');
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '我的订单',
    actions: [
      CyreneBarButton(
        onPressed: _loading ? null : _load,
        tooltip: '刷新',
        child: MiuixIcon(vector: MiuixIcons.os4.refresh, size: 24),
      ),
    ],
    bodyBuilder: (context, topPadding) {
      if (_loading) {
        return const Center(
          child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2),
        );
      }
      final result = _result;
      if (_error != null || result == null) {
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: topPadding + const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            CyreneInlineAlert(
              vector: MiuixIcons.extended.byName('info')!,
              title: '暂时打不开',
              description: _error ?? '加载失败，请稍后重试',
              destructive: true,
            ),
            const SizedBox(height: 12),
            MiuixButton(
              onPressed: _load,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(
                '重试',
                style: MiuixTheme.of(context).textStyles.button,
              ),
            ),
          ],
        );
      }
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          _SummaryCard(result: result),
          const SizedBox(height: 12),
          if (result.isEmpty)
            const CyreneEmptyState(
              icon: Icons.receipt_long_rounded,
              title: '还没有订单',
              description: '购买 Cyrene Premium 或赞助后，支付记录会出现在这里。',
            )
          else ...[
            const MiuixSmallTitle(
              '支付流水',
              insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
            ),
            CyreneMenuGroup(
              children: [
                for (var i = 0; i < result.orders.length; i++) ...[
                  if (i > 0) const _OrderDivider(),
                  _OrderRow(
                    order: result.orders[i],
                    syncing: _syncingOutTradeNo == result.orders[i].outTradeNo,
                    syncBusy: _syncingOutTradeNo != null,
                    onCopy: _copy,
                    onSync: () => _syncOrder(result.orders[i]),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    },
  );
}

/// 顶部汇总：累计支付 / 已支付笔数 / 待支付笔数。
///
/// 三个数都取自后端 stats 字段（同一份列表算出来的），不在客户端重算，
/// 免得「累计」和明细对不上。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result});

  final MembershipOrders result;

  @override
  Widget build(BuildContext context) {
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _cell(
              context,
              '¥${result.totalPaid.toStringAsFixed(2)}',
              '累计支付',
            ),
          ),
          Expanded(child: _cell(context, '${result.paidCount}', '已支付')),
          Expanded(
            child: _cell(
              context,
              '${result.pendingCount}',
              '待支付',
              emphasize: result.pendingCount > 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String value,
    String label, {
    bool emphasize = false,
  }) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      children: [
        Text(
          value,
          style: theme.textStyles.title3.copyWith(
            color: emphasize
                ? const Color(0xFFFF9F0A)
                : colors.onSurfaceContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textStyles.footnote2.copyWith(
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}

/// 组内分隔线：一张卡里堆多条订单时，纯留白不足以断开相邻两笔。
class _OrderDivider extends StatelessWidget {
  const _OrderDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      height: 0.6,
      color: MiuixTheme.of(
        context,
      ).colors.onSurfaceVariantSummary.withValues(alpha: 0.16),
    ),
  );
}

/// 一单：品名 + 状态徽章 + 金额 + 时间 + 订单号（可复制）。
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.syncing,
    required this.syncBusy,
    required this.onCopy,
    required this.onSync,
  });

  final PaymentOrder order;

  /// 本行正在补查支付结果。
  final bool syncing;

  /// 列表里有任意一行在补查（用来挡住其余行的按钮）。
  final bool syncBusy;

  final void Function(String text, String label) onCopy;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final statusColor = order.paid
        ? const Color(0xFF3CC756)
        : const Color(0xFFFF9F0A);
    final tradeNo = order.tradeNo;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.title,
                  style: theme.textStyles.body2.copyWith(
                    color: colors.onSurfaceContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: ShapeDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: const MiuixSquircleBorder(cornerRadius: 8),
                ),
                child: Text(
                  order.statusLabel,
                  style: theme.textStyles.footnote2.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '¥${order.amount.toStringAsFixed(2)}',
                style: theme.textStyles.title3.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${order.paid ? '支付于' : '下单于'} ${_formatDateTime(order.displayTime)}',
                  style: theme.textStyles.footnote1.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _metaLine(context, '订单号', order.outTradeNo),
          if (tradeNo != null && tradeNo.isNotEmpty)
            _metaLine(context, '账单号', tradeNo),
          if (!order.paid) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton(
                  syncing ? '查询中…' : '查询支付结果',
                  minHeight: 30,
                  minWidth: 44,
                  insideMargin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  onPressed: (syncing || syncBusy) ? null : onSync,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 「标签 + 值 + 复制」的一行元数据。长订单号用等宽字体，逐字符对着念不出错。
  Widget _metaLine(BuildContext context, String label, String value) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textStyles.footnote2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              style: theme.textStyles.footnote2.copyWith(
                color: colors.onSurfaceContainer,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (value.isNotEmpty)
            MiuixIconButton(
              minHeight: 26,
              minWidth: 26,
              cornerRadius: 26,
              onPressed: () => onCopy(value, label),
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName('copy')!,
                size: 14,
                tint: colors.onSurfaceVariantActions,
              ),
            ),
        ],
      ),
    );
  }
}

/// ISO 时间串 → `yyyy.MM.dd HH:mm`；解析失败回落到原值。
String _formatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  // 后端存的是 UTC ISO 串，DateTime.tryParse 保留偏移后 toLocal 转本机时区，
  // 用户看「支付时间」要看的是自己手表上的时间。
  final local = dt.toLocal();
  return '${local.year}.${two(local.month)}.${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
