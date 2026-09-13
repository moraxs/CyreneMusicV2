import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/services/invite_service.dart';
import '../../infrastructure/services/sponsor_admin_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 提现管理（开发者工具，挂在「订阅与赞助管理」下）。
///
/// 打款由管理员在支付宝手动完成，这个页面只负责：看清楚该给谁打多少钱、
/// 把账号复制走、打完把状态从「待提现」改成「已提现」。驳回会把积分退还用户，
/// 所以驳回入口要求填一句原因（选填但会展示给用户）。
class WithdrawalAdminPage extends StatefulWidget {
  const WithdrawalAdminPage({super.key, required this.token});

  /// 管理后台会话 token（进入页面时已通过密码校验取得）。
  final String token;

  @override
  State<WithdrawalAdminPage> createState() => _WithdrawalAdminPageState();
}

class _WithdrawalAdminPageState extends State<WithdrawalAdminPage> {
  /// 标签顺序与 [_filters] 一一对应；null 表示「全部」。
  static const _filters = <WithdrawalStatus?>[
    null,
    WithdrawalStatus.pending,
    WithdrawalStatus.paid,
    WithdrawalStatus.rejected,
  ];
  static const _filterLabels = ['全部', '待提现', '已提现', '已驳回'];

  final _service = SponsorAdminService.instance;
  final _searchController = TextEditingController();
  Timer? _debounce;

  var _filterIndex = 1; // 默认停在「待提现」——这是唯一需要动手的那一档。
  var _loading = true;
  var _busy = false;
  String? _error;
  List<WithdrawalRecord> _records = const [];
  var _stats = WithdrawalStats.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.getWithdrawals(
        widget.token,
        status: _filters[_filterIndex],
        keyword: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (result == null) {
          _error = '加载失败，请确认管理会话是否仍然有效';
          return;
        }
        _records = result.records;
        _stats = result.stats;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _setStatus(
    WithdrawalRecord record,
    WithdrawalStatus status, {
    String? note,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _service.updateWithdrawalStatus(
      widget.token,
      record.id,
      status,
      note: note,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    CyreneToast.show(result.message);
    if (result.ok) await _load();
  }

  Future<void> _confirmPaid(WithdrawalRecord record) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '标记为已提现？',
      summary:
          '确认已向 ${record.alipayAccount} 打款 ¥${record.amount}。'
          '此操作只改状态，不会真的发起转账。',
      builder: (dialogContext, dismiss) => _ConfirmActions(
        confirmLabel: '已打款',
        onCancel: () => dismiss(false),
        onConfirm: () => dismiss(true),
      ),
    );
    if (confirmed != true) return;
    await _setStatus(record, WithdrawalStatus.paid);
  }

  Future<void> _confirmReject(WithdrawalRecord record) async {
    final note = await showCyreneDialog<String>(
      context: context,
      title: '驳回提现？',
      summary: '¥${record.amount} 的积分会退回 ${record.username} 的余额。',
      builder: (dialogContext, dismiss) => _NoteForm(
        onCancel: () => dismiss(),
        // 空串也要能带出去：dismiss(null) 会被当成「取消」。
        onConfirm: (value) => dismiss(value.isEmpty ? ' ' : value),
      ),
    );
    if (note == null) return;
    await _setStatus(
      record,
      WithdrawalStatus.rejected,
      note: note.trim().isEmpty ? null : note.trim(),
    );
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '提现管理',
    actions: [
      CyreneBarButton(
        onPressed: _loading ? null : _load,
        tooltip: '刷新',
        child: MiuixIcon(vector: MiuixIcons.os4.refresh, size: 24),
      ),
    ],
    bodyBuilder: (context, topPadding) => Column(
      children: [
        Padding(
          padding: topPadding + const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            children: [
              MiuixTabRowWithContour(
                tabs: _filterLabels,
                selectedTabIndex: _filterIndex,
                onTabSelected: (i) {
                  setState(() => _filterIndex = i);
                  _load();
                },
              ),
              const SizedBox(height: 10),
              MiuixTextField(
                controller: _searchController,
                label: '搜索（用户 ID / 用户名 / 支付宝账号）',
                singleLine: true,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _load(),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    ),
  );

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          CyreneInlineAlert(
            vector: MiuixIcons.extended.byName('info')!,
            title: '加载失败',
            description: _error!,
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
      children: [
        _StatsCard(stats: _stats),
        const SizedBox(height: 12),
        if (_records.isEmpty)
          CyreneEmptyState(
            vector: MiuixIcons.extended.byName('bankCards')!,
            title: '没有提现申请',
            description: _filterIndex == 1 ? '待提现队列是空的，暂时不用打款。' : '换个筛选条件看看。',
          )
        else
          ..._records.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WithdrawalCard(
                record: record,
                busy: _busy,
                onMarkPaid: () => _confirmPaid(record),
                onReject: () => _confirmReject(record),
                onReopen: () => _setStatus(record, WithdrawalStatus.pending),
              ),
            ),
          ),
      ],
    );
  }
}

/// 顶部概览：待打款是唯一需要行动的数字，放在最前。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final WithdrawalStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _cell(
              context,
              '¥${stats.pendingAmount}',
              '待打款（${stats.pendingCount} 笔）',
              const Color(0xFFFF9F0A),
            ),
          ),
          Expanded(
            child: _cell(
              context,
              '¥${stats.paidAmount}',
              '已打款（${stats.paidCount} 笔）',
              const Color(0xFF3CC756),
            ),
          ),
          Expanded(
            child: _cell(
              context,
              '${stats.rejectedCount}',
              '已驳回',
              theme.colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String value, String label, Color color) {
    final theme = MiuixTheme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textStyles.title3.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textStyles.footnote2.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}

/// 单条提现卡：金额 / 用户 / 收款信息（点按复制）/ 时间 / 操作按钮。
class _WithdrawalCard extends StatelessWidget {
  const _WithdrawalCard({
    required this.record,
    required this.busy,
    required this.onMarkPaid,
    required this.onReject,
    required this.onReopen,
  });

  final WithdrawalRecord record;
  final bool busy;
  final VoidCallback onMarkPaid;
  final VoidCallback onReject;
  final VoidCallback onReopen;

  static Color _statusColor(WithdrawalStatus status, MiuixColors colors) =>
      switch (status) {
        WithdrawalStatus.paid => const Color(0xFF3CC756),
        WithdrawalStatus.rejected => colors.error,
        WithdrawalStatus.pending => const Color(0xFFFF9F0A),
      };

  /// 管理端把 pending 叫「待提现」（要我去打款），用户端叫「待审核」。
  static String _adminLabel(WithdrawalStatus status) => switch (status) {
    WithdrawalStatus.pending => '待提现',
    WithdrawalStatus.paid => '已提现',
    WithdrawalStatus.rejected => '已驳回',
  };

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final statusColor = _statusColor(record.status, colors);
    final isPending = record.status == WithdrawalStatus.pending;

    return MiuixCard(
      insideMargin: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '¥${record.amount}',
                style: theme.textStyles.title4.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${record.username}（ID ${record.userId}）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.footnote1.copyWith(
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: ShapeDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: const MiuixSquircleBorder(cornerRadius: 8),
                ),
                child: Text(
                  _adminLabel(record.status),
                  style: theme.textStyles.footnote2.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 打款时账号要靠复制粘贴，做成整行可点、点一下就进剪贴板。
          _CopyableLine(
            label: '支付宝',
            value: record.alipayAccount,
            theme: theme,
            colors: colors,
          ),
          if (record.alipayName?.isNotEmpty == true)
            _CopyableLine(
              label: '收款人',
              value: record.alipayName!,
              theme: theme,
              colors: colors,
            ),
          const SizedBox(height: 4),
          Text(
            '单号 ${record.id} · 提交于 ${_formatDateTime(record.createdAt)}'
            '${record.processedAt != null && !isPending ? ' · 处理于 ${_formatDateTime(record.processedAt)}' : ''}',
            style: theme.textStyles.footnote2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          if (record.note?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              '备注：${record.note}',
              style: theme.textStyles.footnote2.copyWith(color: statusColor),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (isPending) ...[
                Expanded(
                  child: MiuixButton(
                    enabled: !busy,
                    onPressed: onMarkPaid,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText('标记已提现', style: theme.textStyles.button),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MiuixButton(
                    enabled: !busy,
                    onPressed: onReject,
                    colors: MiuixButtonColors(
                      color: colors.error,
                      disabledColor: colors.disabledPrimaryButton,
                      contentColor: colors.onError,
                      disabledContentColor: colors.disabledOnPrimaryButton,
                    ),
                    child: MiuixText('驳回', style: theme.textStyles.button),
                  ),
                ),
              ] else
                Expanded(
                  child: MiuixButton(
                    enabled: !busy,
                    onPressed: onReopen,
                    child: MiuixText('改回待提现', style: theme.textStyles.button),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一行「标签 + 可点复制的值」。
class _CopyableLine extends StatelessWidget {
  const _CopyableLine({
    required this.label,
    required this.value,
    required this.theme,
    required this.colors,
  });

  final String label;
  final String value;
  final MiuixThemeData theme;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        CyreneToast.show('$label已复制');
      },
      child: Row(
        children: [
          Text(
            '$label  ',
            style: theme.textStyles.footnote1.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textStyles.footnote1.copyWith(
                color: colors.onSurface,
                decoration: TextDecoration.underline,
                decorationColor: colors.onSurfaceVariantSummary,
              ),
            ),
          ),
          MiuixIcon(
            vector: MiuixIcons.extended.byName('copy')!,
            size: 14,
            tint: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    ),
  );
}

/// 通用「取消 / 确认」按钮行。
class _ConfirmActions extends StatelessWidget {
  const _ConfirmActions({
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: onCancel),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: onConfirm,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText(confirmLabel, style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}

/// 驳回原因输入（选填，会展示给用户）。
class _NoteForm extends StatefulWidget {
  const _NoteForm({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final void Function(String note) onConfirm;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixTextField(
          controller: _controller,
          label: '驳回原因（选填，用户可见）',
          singleLine: true,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => widget.onConfirm(value.trim()),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: widget.onCancel),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: () => widget.onConfirm(_controller.text.trim()),
              colors: MiuixButtonColors(
                color: colors.error,
                disabledColor: colors.disabledPrimaryButton,
                contentColor: colors.onError,
                disabledContentColor: colors.disabledOnPrimaryButton,
              ),
              child: MiuixText('确认驳回', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}

/// ISO 时间串 → `yyyy.MM.dd HH:mm`；解析失败回落到原值。
String _formatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}.${two(dt.month)}.${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
