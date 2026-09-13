import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../infrastructure/services/invite_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 邀请有礼：邀请码 / 邀请战绩 / 积分提现。
///
/// 一页两个标签而非两个路由——提现是邀请的下游，用户看完积分往往紧接着要提，
/// 拆成两页会让「看到积分 → 提现 → 看状态」这条主路径多两次跳转。
/// 两个标签共用同一次数据加载（[_load] 并发拉 summary 与 withdrawals），
/// 任一侧的写操作后都整体刷新，避免积分余额在两个标签间对不上。
class InvitePage extends StatefulWidget {
  const InvitePage({super.key, required this.account});

  final AccountSessionController account;

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconBlue = Color(0xFF3482FF);

  final _service = InviteService.instance;

  var _tab = 0;
  var _loading = true;
  var _busy = false;
  String? _error;

  InviteSummary? _summary;
  List<WithdrawalRecord> _withdrawals = const [];
  var _minWithdrawal = 1;

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
        _error = '登录后即可参与邀请有礼';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      _service.getSummary(token),
      _service.getWithdrawals(token),
    ]);
    if (!mounted) return;
    final summary = results[0] as InviteSummary?;
    final withdrawals =
        results[1]
            as ({int points, int minWithdrawal, List<WithdrawalRecord> records})?;
    setState(() {
      _loading = false;
      if (summary == null) {
        _error = '加载失败，请检查网络后重试';
        return;
      }
      _summary = summary;
      _minWithdrawal = withdrawals?.minWithdrawal ?? summary.minWithdrawal;
      _withdrawals = withdrawals?.records ?? const [];
    });
  }

  /// 可提现积分：提现接口的 points 与 summary 的 points 同源，
  /// 这里以 summary 为准（两者在同一次 [_load] 里取得）。
  int get _points => _summary?.points ?? 0;

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '邀请有礼',
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
      if (_error != null || _summary == null) {
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
      return Column(
        children: [
          Padding(
            padding: topPadding + const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: MiuixTabRowWithContour(
              tabs: const ['邀请', '提现'],
              selectedTabIndex: _tab,
              onTabSelected: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(child: _tab == 0 ? _inviteTab() : _withdrawTab()),
        ],
      );
    },
  );

  // -------------------------------------------------------------------------
  // 邀请标签页
  // -------------------------------------------------------------------------

  Widget _inviteTab() {
    final summary = _summary!;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
      children: [
        _InviteCodeCard(
          code: summary.code,
          busy: _busy,
          onGenerate: _generateCode,
          onCopy: _copyCode,
          onShare: _copyShareText,
        ),
        const SizedBox(height: 12),
        _StatsRow(
          points: summary.points,
          totalPoints: summary.totalPoints,
          invitedCount: summary.invitedCount,
        ),
        const SizedBox(height: 12),
        CyreneInlineAlert(
          vector: MiuixIcons.extended.byName('info')!,
          title: '怎么拿积分',
          description:
              '好友注册时填写你的邀请码（或注册后在个人中心补填），'
              '等他开通 Cyrene Premium，你就得 ${summary.rewardPerInvite} 积分。'
              '1 积分 = 1 元，可在「提现」里提到支付宝。',
        ),
        const SizedBox(height: 12),
        const MiuixSmallTitle(
          '我的邀请人',
          insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        CyreneMenuGroup(
          children: [
            CyreneMenuRow(
              vector: MiuixIcons.extended.byName('contactsCircle')!,
              iconBackground: _iconBlue,
              title: summary.hasBoundInviter ? summary.inviterName! : '填写邀请码',
              subtitle: summary.hasBoundInviter
                  ? '已绑定，邀请关系不可更改'
                  : '如果是朋友推荐你来的，填上他的邀请码',
              trailing: summary.hasBoundInviter
                  ? const SizedBox.shrink()
                  : null,
              onTap: summary.hasBoundInviter ? null : _promptBindCode,
            ),
          ],
        ),
        const SizedBox(height: 12),
        MiuixSmallTitle(
          '邀请记录（${summary.rewardedCount}/${summary.invitedCount} 已开通 Premium）',
          insideMargin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        if (summary.invitees.isEmpty)
          _EmptyHint(
            vector: MiuixIcons.extended.byName('contacts')!,
            text: '还没有人用你的邀请码，把码分享给朋友试试。',
          )
        else
          CyreneMenuGroup(
            children: summary.invitees
                .map(
                  (invitee) => CyreneMenuRow(
                    vector: MiuixIcons.extended.byName('contacts')!,
                    iconBackground: invitee.rewarded ? _iconGreen : _iconBlue,
                    title: invitee.username.isNotEmpty
                        ? invitee.username
                        : '用户 ${invitee.id}',
                    subtitle: [
                      invitee.maskedEmail,
                      if (_formatDate(invitee.joinedAt).isNotEmpty)
                        _formatDate(invitee.joinedAt),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    value: invitee.rewarded
                        ? '+${summary.rewardPerInvite} 积分'
                        : (invitee.hasPremium ? '待入账' : '未开通'),
                    trailing: const SizedBox.shrink(),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 提现标签页
  // -------------------------------------------------------------------------

  Widget _withdrawTab() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
      children: [
        _BalanceCard(
          points: _points,
          minWithdrawal: _minWithdrawal,
          busy: _busy,
          onWithdraw: _points >= _minWithdrawal ? _promptWithdraw : null,
        ),
        const SizedBox(height: 12),
        CyreneInlineAlert(
          vector: MiuixIcons.extended.byName('info')!,
          title: '提现说明',
          description:
              '1 积分 = 1 元，提交后积分立即冻结，由管理员手动打款到你的支付宝。'
              '打款完成前状态显示为「待审核」；若被驳回，积分会退回余额。',
        ),
        const SizedBox(height: 12),
        const MiuixSmallTitle(
          '提现记录',
          insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        if (_withdrawals.isEmpty)
          _EmptyHint(
            vector: MiuixIcons.extended.byName('bankCards')!,
            text: '还没有提现记录，攒够 $_minWithdrawal 积分就能提。',
          )
        else
          CyreneMenuGroup(
            children: _withdrawals
                .map((record) => _WithdrawalRow(record: record))
                .toList(growable: false),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 动作
  // -------------------------------------------------------------------------

  Future<void> _generateCode() async {
    final token = _token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    final code = await _service.generateCode(token);
    if (!mounted) return;
    setState(() => _busy = false);
    if (code == null) {
      CyreneToast.show('生成邀请码失败，请稍后重试');
      return;
    }
    CyreneToast.show('邀请码已生成');
    await _load();
  }

  Future<void> _copyCode() async {
    final code = _summary?.code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) CyreneToast.show('邀请码已复制');
  }

  Future<void> _copyShareText() async {
    final code = _summary?.code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: '来 Cyrene Music 一起听歌吧，注册时填我的邀请码：$code',
      ),
    );
    if (mounted) CyreneToast.show('邀请文案已复制');
  }

  Future<void> _promptBindCode() async {
    final token = _token;
    if (token == null) return;
    final bound = await showBindInviteCodeDialog(context, token: token);
    if (bound && mounted) await _load();
  }

  Future<void> _promptWithdraw() async {
    final draft = await showCyreneDialog<_WithdrawDraft>(
      context: context,
      title: '申请提现',
      summary: '当前可提现 $_points 积分（= ¥$_points）',
      builder: (dialogContext, dismiss) => _WithdrawForm(
        maxPoints: _points,
        minPoints: _minWithdrawal,
        onCancel: () => dismiss(),
        onConfirm: (draft) => dismiss(draft),
      ),
    );
    if (draft == null || !mounted) return;

    final token = _token;
    if (token == null) return;
    setState(() => _busy = true);
    final result = await _service.submitWithdrawal(
      token: token,
      amount: draft.amount,
      alipayAccount: draft.alipayAccount,
      alipayName: draft.alipayName,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    CyreneToast.show(result.message);
    if (result.ok) await _load();
  }
}

/// 弹出「填写邀请码」对话框并完成绑定，返回是否绑定成功。
///
/// 邀请页与个人中心两处入口共用：绑定是一次性动作，两处的校验、大小写处理与
/// 结果提示必须一致，抽出来才不会改一边漏一边。结果 toast 在这里统一弹，
/// 调用方只需要根据返回值决定要不要刷新自己的数据。
Future<bool> showBindInviteCodeDialog(
  BuildContext context, {
  required String token,
}) async {
  final code = await showCyreneDialog<String>(
    context: context,
    title: '填写邀请码',
    summary: '绑定后不可更改，请确认填的是朋友的邀请码。',
    builder: (dialogContext, dismiss) => _SingleFieldForm(
      label: '邀请码',
      hintIcon: 'promotions',
      capitalize: true,
      onCancel: () => dismiss(),
      onConfirm: (value) => dismiss(value),
      validate: (value) => value.isEmpty ? '请输入邀请码' : null,
    ),
  );
  if (code == null || code.isEmpty) return false;

  final result = await InviteService.instance.bindCode(token, code);
  CyreneToast.show(result.message);
  return result.ok;
}

/// ISO 时间串 → `yyyy.MM.dd`；空值与解析失败都回落到空串（调用方负责隐藏）。
String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}.${two(dt.month)}.${two(dt.day)}';
}

/// ISO 时间串 → `yyyy.MM.dd HH:mm`。
String _formatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}.${two(dt.month)}.${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// 邀请码主卡：未生成时给生成按钮，已生成时大号展示 + 复制/分享。
class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({
    required this.code,
    required this.busy,
    required this.onGenerate,
    required this.onCopy,
    required this.onShare,
  });

  final String? code;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final value = code;

    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '我的邀请码',
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 12),
          if (value == null || value.isEmpty) ...[
            Text(
              '还没有邀请码',
              style: theme.textStyles.title3.copyWith(
                color: colors.onSurfaceContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            MiuixButton(
              enabled: !busy,
              onPressed: onGenerate,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('生成邀请码', style: theme.textStyles.button),
            ),
          ] else ...[
            // 邀请码常被口述/手抄，等宽字体 + 字距让 8 位码一眼可读。
            SelectableText(
              value,
              style: theme.textStyles.title1.copyWith(
                color: colors.onSurfaceContainer,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MiuixButton(
                    onPressed: onCopy,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText('复制邀请码', style: theme.textStyles.button),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MiuixButton(
                    onPressed: onShare,
                    child: MiuixText('复制邀请语', style: theme.textStyles.button),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 积分/邀请人数三格概览。
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.points,
    required this.totalPoints,
    required this.invitedCount,
  });

  final int points;
  final int totalPoints;
  final int invitedCount;

  @override
  Widget build(BuildContext context) => MiuixCard(
    cornerRadius: 20,
    insideMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
    child: Row(
      children: [
        Expanded(child: _cell(context, '$points', '可提现积分')),
        Expanded(child: _cell(context, '$totalPoints', '累计获得')),
        Expanded(child: _cell(context, '$invitedCount', '已邀请')),
      ],
    ),
  );

  Widget _cell(BuildContext context, String value, String label) {
    final theme = MiuixTheme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textStyles.title2.copyWith(
            color: theme.colors.onSurfaceContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textStyles.footnote1.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}

/// 提现页顶部余额卡。
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.points,
    required this.minWithdrawal,
    required this.busy,
    required this.onWithdraw,
  });

  final int points;
  final int minWithdrawal;
  final bool busy;

  /// 为 null 表示积分不足，按钮置灰。
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '可提现积分',
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$points',
                style: theme.textStyles.title1.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '≈ ¥$points',
                style: theme.textStyles.body2.copyWith(
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MiuixButton(
            enabled: onWithdraw != null && !busy,
            onPressed: onWithdraw,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: MiuixText(
              onWithdraw != null ? '申请提现' : '满 $minWithdrawal 积分可提现',
              style: theme.textStyles.button,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条提现记录：金额 + 状态徽章 + 收款账号 + 时间 + 驳回备注。
class _WithdrawalRow extends StatelessWidget {
  const _WithdrawalRow({required this.record});

  final WithdrawalRecord record;

  static Color _statusColor(WithdrawalStatus status, MiuixColors colors) =>
      switch (status) {
        WithdrawalStatus.paid => const Color(0xFF3CC756),
        WithdrawalStatus.rejected => colors.error,
        WithdrawalStatus.pending => const Color(0xFFFF9F0A),
      };

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final statusColor = _statusColor(record.status, colors);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '¥${record.amount}',
                style: theme.textStyles.body1.copyWith(
                  color: colors.onSurfaceContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
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
                  record.status.label,
                  style: theme.textStyles.footnote2.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '支付宝 ${record.alipayAccount}'
            '${record.alipayName?.isNotEmpty == true ? '（${record.alipayName}）' : ''}',
            style: theme.textStyles.footnote1.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            record.status == WithdrawalStatus.pending
                ? '提交于 ${_formatDateTime(record.createdAt)}'
                : '${record.status.label}于 ${_formatDateTime(record.processedAt ?? record.createdAt)}',
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
        ],
      ),
    );
  }
}

/// 空列表的轻提示卡（比 CyreneEmptyState 矮，适合嵌在长页中部）。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.vector, required this.text});

  final MiuixVectorIcon vector;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          CyreneIconBox(vector: vector, size: 44),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 提现表单的结果。
class _WithdrawDraft {
  const _WithdrawDraft({
    required this.amount,
    required this.alipayAccount,
    required this.alipayName,
  });

  final int amount;
  final String alipayAccount;
  final String alipayName;
}

/// 提现申请表单：积分数 + 支付宝账号 + 姓名（选填）。
class _WithdrawForm extends StatefulWidget {
  const _WithdrawForm({
    required this.maxPoints,
    required this.minPoints,
    required this.onCancel,
    required this.onConfirm,
  });

  final int maxPoints;
  final int minPoints;
  final VoidCallback onCancel;
  final void Function(_WithdrawDraft draft) onConfirm;

  @override
  State<_WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<_WithdrawForm> {
  // 默认全额提现——绝大多数人就是想把攒的分一次性提走。
  late final _amountController = TextEditingController(
    text: '${widget.maxPoints}',
  );
  final _accountController = TextEditingController();
  final _nameController = TextEditingController();

  String? _amountError;
  String? _accountError;

  @override
  void dispose() {
    _amountController.dispose();
    _accountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = int.tryParse(_amountController.text.trim());
    final account = _accountController.text.trim();
    setState(() {
      _amountError = switch (amount) {
        null => '请输入整数积分',
        final a when a < widget.minPoints => '最少提 ${widget.minPoints} 积分',
        final a when a > widget.maxPoints => '超出可提现积分',
        _ => null,
      };
      _accountError = account.isEmpty ? '请输入支付宝账号' : null;
    });
    if (_amountError != null || _accountError != null) return;
    widget.onConfirm(
      _WithdrawDraft(
        amount: amount!,
        alipayAccount: account,
        alipayName: _nameController.text.trim(),
      ),
    );
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
          controller: _amountController,
          label: '提现积分（1 积分 = 1 元）',
          singleLine: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        if (_amountError != null) _fieldError(_amountError!, theme, colors),
        const SizedBox(height: 12),
        MiuixTextField(
          controller: _accountController,
          label: '支付宝账号（手机号 / 邮箱）',
          singleLine: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_accountError != null) setState(() => _accountError = null);
          },
        ),
        if (_accountError != null) _fieldError(_accountError!, theme, colors),
        const SizedBox(height: 12),
        MiuixTextField(
          controller: _nameController,
          label: '支付宝姓名（选填，便于核对收款人）',
          singleLine: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirm(),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: widget.onCancel),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: _confirm,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('提交申请', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}

/// 通用单字段弹层表单（当前用于填写邀请码）。
class _SingleFieldForm extends StatefulWidget {
  const _SingleFieldForm({
    required this.label,
    required this.hintIcon,
    required this.onCancel,
    required this.onConfirm,
    required this.validate,
    this.capitalize = false,
  });

  final String label;
  final String hintIcon;
  final VoidCallback onCancel;
  final void Function(String value) onConfirm;

  /// 返回错误文案；返回 null 表示通过。入参已 trim（[capitalize] 时也已转大写）。
  final String? Function(String value) validate;

  /// 提交前是否转大写（邀请码大小写不敏感，统一成大写再送后端）。
  final bool capitalize;

  @override
  State<_SingleFieldForm> createState() => _SingleFieldFormState();
}

class _SingleFieldFormState extends State<_SingleFieldForm> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    var value = _controller.text.trim();
    if (widget.capitalize) value = value.toUpperCase();
    final error = widget.validate(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.onConfirm(value);
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
          label: widget.label,
          singleLine: true,
          autofocus: true,
          leadingIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName(widget.hintIcon)!,
              size: 20,
              tint: colors.onSecondaryContainer,
            ),
          ),
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _confirm(),
        ),
        if (_error != null) _fieldError(_error!, theme, colors),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixTextButton('取消', onPressed: widget.onCancel),
            const SizedBox(width: 10),
            MiuixButton(
              onPressed: _confirm,
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('确认', style: theme.textStyles.button),
            ),
          ],
        ),
      ],
    );
  }
}

Widget _fieldError(String message, MiuixThemeData theme, MiuixColors colors) =>
    Padding(
      padding: const EdgeInsets.only(top: 7, left: 4),
      child: Text(
        message,
        style: theme.textStyles.footnote1.copyWith(color: colors.error),
      ),
    );
