import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/services/sponsor_admin_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 订阅与赞助管理页（开发者工具）。
///
/// 搜索用户，进入详情后可手动开关订阅（Cyrene Premium）与赞助状态、
/// 添加/删除赞助金额记录。
class SponsorAdminPage extends StatefulWidget {
  const SponsorAdminPage({super.key, required this.token});

  /// 管理后台会话 token（进入页面时已通过密码校验取得）。
  final String token;

  @override
  State<SponsorAdminPage> createState() => _SponsorAdminPageState();
}

class _SponsorAdminPageState extends State<SponsorAdminPage> {
  final _service = SponsorAdminService.instance;
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;
  List<AdminUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchController.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _service.searchUsers(widget.token, keyword);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _openDetail(AdminUser user) async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => _UserSponsorDetailPage(
          token: widget.token,
          userId: user.id,
          username: user.username,
        ),
      ),
    );
    if (mounted) _search();
  }

  @override
  Widget build(BuildContext context) {
    return CyrenePage(
      title: '订阅与赞助管理',
      bodyBuilder: (context, topPadding) => Column(
        children: [
          Padding(
            padding: topPadding + const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: MiuixTextField(
              controller: _searchController,
              label: '搜索用户（ID / 用户名 / 邮箱）',
              singleLine: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
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
            onPressed: _search,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: MiuixText('重试', style: MiuixTheme.of(context).textStyles.button),
          ),
        ],
      );
    }
    if (_users.isEmpty) {
      return CyreneEmptyState(
        vector: MiuixIcons.extended.byName('contacts')!,
        title: '未找到用户',
        description: '换个关键词试试。',
      );
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
      children: [
        CyreneMenuGroup(
          children: _users.map(_userRow).toList(growable: false),
        ),
      ],
    );
  }

  Widget _userRow(AdminUser user) {
    return CyreneMenuRow(
      vector: MiuixIcons.extended.byName('contacts')!,
      iconBackground: const Color(0xFF3482FF),
      title: user.username.isNotEmpty ? user.username : '用户 ${user.id}',
      subtitle: 'ID ${user.id}',
      value: _badgeText(user),
      onTap: () => _openDetail(user),
    );
  }

  String _badgeText(AdminUser user) {
    final tags = <String>[
      if (user.hasListeningCard) 'Premium',
      if (user.isSponsor) '赞助',
    ];
    return tags.isEmpty ? '-' : tags.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// 用户订阅/赞助详情页
// ---------------------------------------------------------------------------

class _UserSponsorDetailPage extends StatefulWidget {
  const _UserSponsorDetailPage({
    required this.token,
    required this.userId,
    required this.username,
  });

  final String token;
  final int userId;
  final String username;

  @override
  State<_UserSponsorDetailPage> createState() => _UserSponsorDetailPageState();
}

class _UserSponsorDetailPageState extends State<_UserSponsorDetailPage> {
  final _service = SponsorAdminService.instance;

  bool _loading = true;
  String? _error;
  SponsorDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.getDetails(widget.token, widget.userId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleSponsor(bool value) async {
    final ok = await _service.toggleSponsor(widget.token, widget.userId, value);
    if (!mounted) return;
    CyreneToast.show(ok ? (value ? '已设为赞助用户' : '已取消赞助') : '操作失败');
    if (ok) _load();
  }

  Future<void> _togglePremium(bool value) async {
    final ok = await _service.togglePremium(widget.token, widget.userId, value);
    if (!mounted) return;
    CyreneToast.show(
      ok ? (value ? '已授予 Cyrene Premium' : '已撤销 Cyrene Premium') : '操作失败',
    );
    if (ok) _load();
  }

  Future<void> _addDonation() async {
    final amount = await showCyreneDialog<double>(
      context: context,
      title: '添加赞助记录',
      summary: '手动为用户添加一笔已支付的赞助金额',
      builder: (dialogContext, dismiss) => _AmountInput(
        onCancel: () => dismiss(),
        onConfirm: (amount) => dismiss(amount),
      ),
    );
    if (amount == null || !mounted) return;
    final ok = await _service.addDonation(widget.token, widget.userId, amount);
    if (!mounted) return;
    CyreneToast.show(ok ? '赞助记录已添加' : '添加失败');
    if (ok) _load();
  }

  Future<void> _deleteDonation(DonationItem donation) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '删除赞助记录？',
      summary: '将删除金额 ¥${donation.amount.toStringAsFixed(2)} 的赞助记录，此操作不可撤销。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        final colors = theme.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('取消', onPressed: () => dismiss(false)),
                const SizedBox(width: 10),
                MiuixButton(
                  onPressed: () => dismiss(true),
                  colors: MiuixButtonColors(
                    color: colors.error,
                    disabledColor: colors.disabledPrimaryButton,
                    contentColor: colors.onError,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  child: MiuixText('删除', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final ok = await _service.deleteDonation(widget.token, donation.id);
    if (!mounted) return;
    CyreneToast.show(ok ? '赞助记录已删除' : '删除失败');
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return CyrenePage(
      title: widget.username.isNotEmpty ? widget.username : '用户 ${widget.userId}',
      largeTitle: false,
      bodyBuilder: (context, topPadding) {
        if (_loading) {
          return const Center(
            child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2),
          );
        }
        if (_error != null || _detail == null) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: topPadding + const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              CyreneInlineAlert(
                vector: MiuixIcons.extended.byName('info')!,
                title: '加载失败',
                description: _error ?? '用户不存在',
                destructive: true,
              ),
              const SizedBox(height: 12),
              MiuixButton(
                onPressed: _load,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: MiuixText('重试', style: MiuixTheme.of(context).textStyles.button),
              ),
            ],
          );
        }
        final detail = _detail!;
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            const MiuixSmallTitle(
              '权益状态',
              insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
            ),
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('download')!,
                  iconBackground: const Color(0xFF3482FF),
                  title: 'Cyrene Premium 订阅',
                  subtitle: detail.hasListeningCard ? '已持有' : '未持有',
                  trailing: MiuixSwitch(
                    value: detail.hasListeningCard,
                    onChanged: _togglePremium,
                  ),
                  onTap: () => _togglePremium(!detail.hasListeningCard),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('favorites')!,
                  iconBackground: const Color(0xFFFF9F0A),
                  title: '赞助状态',
                  subtitle: detail.isSponsor ? '已赞助' : '未赞助',
                  trailing: MiuixSwitch(
                    value: detail.isSponsor,
                    onChanged: _toggleSponsor,
                  ),
                  onTap: () => _toggleSponsor(!detail.isSponsor),
                ),
                CyreneMenuRow(
                  vector: MiuixIcons.extended.byName('bankCards')!,
                  iconBackground: const Color(0xFF3CC756),
                  title: '累计赞助金额',
                  value: '¥${detail.totalAmount.toStringAsFixed(2)}',
                  trailing: const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const MiuixSmallTitle(
              '赞助记录',
              insideMargin: EdgeInsets.fromLTRB(16, 8, 16, 8),
            ),
            MiuixCard(
              insideMargin: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (detail.donations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '暂无赞助记录',
                        textAlign: TextAlign.center,
                        style: MiuixTheme.of(context).textStyles.body2.copyWith(
                          color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                        ),
                      ),
                    )
                  else
                    ...detail.donations.map(_donationRow),
                  const SizedBox(height: 8),
                  MiuixButton(
                    onPressed: _addDonation,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText(
                      '添加赞助记录',
                      style: MiuixTheme.of(context).textStyles.button,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _donationRow(DonationItem donation) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¥${donation.amount.toStringAsFixed(2)}',
                  style: theme.textStyles.body2.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  donation.paid ? '已支付' : '待支付',
                  style: theme.textStyles.footnote1.copyWith(
                    color: donation.paid
                        ? const Color(0xFF3CC756)
                        : colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
          ),
          MiuixIconButton(
            onPressed: () => _deleteDonation(donation),
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('delete')!,
              size: 20,
              tint: colors.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// 赞助金额输入弹层。
class _AmountInput extends StatefulWidget {
  const _AmountInput({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final void Function(double amount) onConfirm;

  @override
  State<_AmountInput> createState() => _AmountInputState();
}

class _AmountInputState extends State<_AmountInput> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = double.tryParse(_controller.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = '请输入有效的金额');
      return;
    }
    widget.onConfirm(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiuixTextField(
          controller: _controller,
          label: '金额（元）',
          singleLine: true,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirm(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textStyles.footnote1.copyWith(color: colors.error),
          ),
        ],
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
