/// Cyrene Premium 会员卡区块：持有状态展示、下单购买与音源配置下发。
///
/// 从「播放与音源」设置页抽出，供两处复用：音源页要给出购买入口（Premium 的
/// 权益就是官方音源自动下发），「设置 → 会员中心」也要显示会员身份与购买入口。
/// 付款链路（下单 → 拉起支付 → 轮询 `/pay/query` → 下发 `.cyrene`）只此一份
/// 实现，两处入口不会行为分叉。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/models/cyrene_config.dart';
import '../../infrastructure/services/listening_card_service.dart';
import '../../infrastructure/services/sponsor_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 默认官方音源 id（app_dependencies 装配），Cyrene Premium 下发后覆盖它而非新增，避免重复源。
///
/// 音源列表页与会员中心都要靠这个稳定 id 判断「官方源是否已落地本机」，故常量
/// 随本组件一起搬到这里，不再各写一份字面量。
const officialOmniParseSourceId = 'official-omniparse';

/// 官方 Cyrene Premium 音源在列表中的固定显示名。
/// 该源由服务端下发、锁定不可编辑，故统一以品牌名展示，与存储的 name 无关。
const officialOmniParseDisplayName = 'Cyrene Premium';

/// Cyrene Premium 区块：显示持有状态、购买入口、重新下发。
///
/// [onStatusChanged] 在每次从 `/card/status` 拿到权威结果、以及本地完成支付时回调，
/// 供外层（会员中心页）同步自己的会员状态行/订单汇总：本组件只拥有「卡片」的
/// 视觉与支付链路，不替外层决定要不要回写会话快照。
class PremiumMembershipSection extends StatefulWidget {
  const PremiumMembershipSection({
    super.key,
    required this.controller,
    required this.account,
    required this.sources,
    required this.token,
    this.onStatusChanged,
  });

  final AudioSourcePreferencesController controller;
  final AccountSessionController account;
  final List<AudioSourceConfig> sources;
  final String token;
  final void Function({required bool hasCard, String? grantedAt})?
  onStatusChanged;

  @override
  State<PremiumMembershipSection> createState() =>
      _PremiumMembershipSectionState();
}

class _PremiumMembershipSectionState extends State<PremiumMembershipSection> {
  bool? _hasCard;
  bool _loading = true;

  /// Cyrene Premium 当前定价（元），由 /card/status 下发，取自后端 config.json。
  double _price = ListeningCardService.defaultCardPrice;

  /// 持卡开通时间（后端 listening_card_since）。会员卡上展示。
  String? _grantedAt;
  Timer? _pollTimer;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 本机 official-omniparse 是否已下发 apiKey（非空）。
  bool get _hasLocalApiKey {
    final src = widget.sources
        .where((s) => s.id == officialOmniParseSourceId)
        .cast<AudioSourceConfig?>()
        .firstWhere((s) => s != null, orElse: () => null);
    return src != null && src.apiKey.isNotEmpty;
  }

  /// 把当前状态广播给外层。
  ///
  /// `_hasCard == null` 是「服务端不可达且本机也没拿到音源 apiKey」的未知态，
  /// 不能当成「未开通」报上去——否则一次 `/card/status` 抖动就会把
  /// 会员中心已开通用户的「会员状态」行误刷成普通用户。
  void _notifyStatus() {
    final hasCard = _hasCard;
    if (hasCard == null) return;
    widget.onStatusChanged?.call(hasCard: hasCard, grantedAt: _grantedAt);
  }

  Future<void> _loadStatus() async {
    final result = await ListeningCardService.instance.getCardStatus(
      widget.token,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _hasCard = _hasLocalApiKey ? true : null;
      });
      return;
    }
    setState(() {
      _hasCard = result.hasCard;
      _price = result.price;
      _grantedAt = result.grantedAt;
      _loading = false;
    });
    _notifyStatus();
  }

  Future<void> _purchase() async {
    final type = await _choosePaymentMethod(context);
    if (type == null || !mounted) return;

    final ip = await SponsorService.instance.getClientIp();
    if (ip == null || ip.isEmpty) {
      if (mounted) CyreneToast.show('获取 IP 地址失败');
      return;
    }

    final result = await ListeningCardService.instance.purchaseCard(
      token: widget.token,
      type: type,
      clientip: ip,
    );
    if (result == null) {
      if (mounted) CyreneToast.show('下单失败，请稍后重试');
      return;
    }

    await _launchPayment(result.payInfo);
    if (!mounted) return;
    _startPolling(result.outTradeNo);
  }

  Future<String?> _choosePaymentMethod(BuildContext context) {
    return showCyreneDialog<String>(
      context: context,
      title: '选择支付方式',
      summary: 'Cyrene Premium ¥${_price.toStringAsFixed(2)}，永久买断。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const SizedBox(height: 12),
            MiuixButton(
              minHeight: 52,
              onPressed: () => dismiss('alipay'),
              child: Row(
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('bankCards')!,
                    size: 19,
                    tint: const Color(0xFF3482FF),
                  ),
                  const SizedBox(width: 10),
                  MiuixText('支付宝', style: theme.textStyles.button),
                ],
              ),
            ),
            MiuixButton(
              minHeight: 52,
              onPressed: () => dismiss('wxpay'),
              child: Row(
                children: [
                  MiuixIcon(
                    vector: MiuixIcons.extended.byName('messages')!,
                    size: 19,
                    tint: const Color(0xFF3CC756),
                  ),
                  const SizedBox(width: 10),
                  MiuixText('微信支付', style: theme.textStyles.button),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 在系统默认浏览器打开支付链接。
  ///
  /// 网关返回字段名不固定，按 Next.js demo 的兜底链取值：
  /// `pay_info || qrcode || payurl || urlscheme`（见 DonateDialog.tsx）。
  /// 后端 /card/purchase 把整个网关响应塞进 data.pay_info，故这里在 payInfo 对象
  /// 内部按该链找第一个非空字符串字段。
  Future<void> _launchPayment(Map<String, Object?> payInfo) async {
    final url =
        [
              payInfo['pay_info'],
              payInfo['qrcode'],
              payInfo['payurl'],
              payInfo['urlscheme'],
            ]
            .map((e) => e?.toString() ?? '')
            .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (url.isEmpty) {
      debugPrint('[ListeningCard] payInfo 无可用链接: $payInfo');
      if (mounted) CyreneToast.show('未获取到支付链接');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('[ListeningCard] 支付链接无效: $url');
      if (mounted) CyreneToast.show('支付链接无效');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      if (mounted) CyreneToast.show('无法打开支付链接，请重试');
      return;
    }
    if (mounted) CyreneToast.show('请在新打开的页面完成支付');
  }

  /// 轮询 /pay/query，status==1 视为支付成功，落卡配置。
  void _startPolling(String outTradeNo) {
    _pollTimer?.cancel();
    _pollCount = 0;
    if (mounted) {
      setState(() => _loading = true);
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      _pollCount++;
      if (_pollCount > 100) {
        // 5 分钟超时
        t.cancel();
        if (mounted) {
          setState(() => _loading = false);
          CyreneToast.show('支付超时，如已付款请稍后重试下发');
        }
        return;
      }
      try {
        final result = await SponsorService.instance.queryPayStatus(outTradeNo);
        final status = result['status'];
        if (status == 1 || status == '1') {
          t.cancel();
          await _finalizeCard();
        }
      } catch (_) {
        // 单次查询失败继续轮询
      }
    });
  }

  /// 支付成功：拉取下发配置并应用，避免重复源。
  Future<void> _finalizeCard() async {
    // 优先回写持卡状态：即便下方 fetchCardConfig 因网络抖动失败，个人中心/
    // 我的页的徽章与「赞助状态」行也能先反映 Cyrene Premium（支付已成功，
    // 用户不该因音源下发失败而看不到 Premium 状态）。
    final grantedAt = DateTime.now().toIso8601String();
    await widget.account.patchUser(
      (u) => u.copyWith(
        hasListeningCard: true,
        listeningCardSince: u.listeningCardSince ?? grantedAt,
      ),
    );
    if (mounted) {
      setState(() {
        _hasCard = true;
        _grantedAt ??= grantedAt;
      });
      _notifyStatus();
    }
    try {
      final config = await ListeningCardService.instance.fetchCardConfig(
        widget.token,
      );
      if (config == null) {
        if (mounted) {
          setState(() => _loading = false);
          CyreneToast.show('Cyrene Premium 已激活，音源配置下发失败，请稍后重试下发');
        }
        return;
      }
      final success = await _applyConfig(config);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasCard = true;
      });
      if (mounted) {
        CyreneToast.show(
          success ? 'Cyrene Premium 已激活' : 'Cyrene Premium 已激活（音源已更新）',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        CyreneToast.show('Cyrene Premium 已激活，音源配置下发失败，请稍后重试下发');
      }
    }
  }

  /// 应用下发的 CyreneConfig：覆盖 official-omniparse，不存在则新增。
  ///
  /// 固定以稳定 id `official-omniparse` 落地，使其后续可被识别为官方源
  /// （UI 锁定不可编辑、显示品牌名 Cyrene Premium）。name 仅作存储记录，
  /// 真实展示名以 [officialOmniParseDisplayName] 为准。
  Future<bool> _applyConfig(CyreneConfig config) async {
    final existing = widget.sources
        .where((s) => s.id == officialOmniParseSourceId)
        .cast<AudioSourceConfig?>()
        .firstWhere((s) => s != null, orElse: () => null);
    if (existing != null) {
      return widget.controller.updateOmniParse(
        id: officialOmniParseSourceId,
        name: config.name.isEmpty ? existing.name : config.name,
        url: config.url.isEmpty ? existing.url : config.url,
        apiKey: config.apiKey,
      );
    }
    return widget.controller.addOmniParse(
      id: officialOmniParseSourceId,
      name: config.name.isEmpty ? 'Cyrene Premium' : config.name,
      url: config.url,
      apiKey: config.apiKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final hasCard = _hasCard == true;

    // 持卡：展示仿真会员卡（类 Visa 卡面）；未持卡：保持原购买卡片不变。
    if (hasCard) {
      return _PremiumMembershipCard(
        grantedAt: _grantedAt,
        loading: _loading,
        onRedeliver: _redeliver,
      );
    }

    return MiuixCard(
      insideMargin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MiuixIcon(
                vector: MiuixIcons.extended.byName('promotions')!,
                size: 22,
                tint: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cyrene Premium',
                  style: theme.textStyles.body1.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '付款 ${_price.toStringAsFixed(2)} 元，自动下发并激活 OmniParse 音源配置，永久买断。',
            style: theme.textStyles.body2.copyWith(
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: MiuixCircularProgressIndicator(),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: MiuixButton(
                    key: const Key('listening-card-action'),
                    onPressed: _purchase,
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    child: MiuixText(
                      '购买 Cyrene Premium ¥${_price.toStringAsFixed(2)}',
                      style: theme.textStyles.button,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 已持卡用户主动重新下发（服务端轮换 apiKey 后手动刷新）。
  Future<void> _redeliver() async {
    if (mounted) setState(() => _loading = true);
    try {
      final config = await ListeningCardService.instance.fetchCardConfig(
        widget.token,
      );
      if (config == null) {
        if (mounted) {
          setState(() => _loading = false);
          CyreneToast.show('配置下发失败，请稍后重试');
        }
        return;
      }
      await _applyConfig(config);
      if (!mounted) return;
      setState(() => _loading = false);
      CyreneToast.show('配置已更新');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        CyreneToast.show('配置下发失败，请稍后重试');
      }
    }
  }
}

/// 持卡用户的仿真会员卡（类 Visa 卡面）。
///
/// 深紫渐变卡身 + 金色 EMV 芯片 + 品牌 wordmark + 持卡人（用户名）+
/// 永久买断标识 + 开通时间。卡身本身仅展示，下方接「重新下发配置」入口。
/// 卡片下方留按钮行，与未持卡卡片在同一区块内对齐。
class _PremiumMembershipCard extends StatelessWidget {
  const _PremiumMembershipCard({
    required this.grantedAt,
    required this.loading,
    required this.onRedeliver,
  });

  final String? grantedAt;
  final bool loading;
  final VoidCallback onRedeliver;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MembershipCardFace(grantedAt: grantedAt),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: MiuixButton(
                key: const Key('listening-card-action'),
                onPressed: loading ? null : onRedeliver,
                colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: MiuixCircularProgressIndicator(strokeWidth: 2),
                      )
                    : MiuixText('重新下发配置', style: theme.textStyles.button),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 卡面本体：渐变 + 光泽 + 芯片 + 文案。固定高度，比例接近真实卡（1.585）。
class _MembershipCardFace extends StatelessWidget {
  const _MembershipCardFace({required this.grantedAt});

  final String? grantedAt;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // 卡面主色：Premium 紫，与个人中心徽章同源（0xFF8A64FF）。
    const primary = Color(0xFF8A64FF);
    final memberSince = _formatMemberSince(grantedAt);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1.585,
        child: Stack(
          children: [
            // 卡身渐变：左上深紫 → 右下近黑，营造金属质感。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primary,
                      const Color(0xFF5B3FD6),
                      const Color(0xFF2A1B5C),
                    ],
                  ),
                ),
              ),
            ),
            // 光泽：右上角高光弧，模拟卡面反光。
            Positioned(
              top: -60,
              right: -40,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: 220,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: Colors.white.withValues(alpha: .12),
                  ),
                ),
              ),
            ),
            // 细网格纹理：极淡，增加卡面质感。
            Positioned.fill(child: CustomPaint(painter: _CardGridPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 顶部：品牌 wordmark + 永久买断标。
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        MiuixIcon(
                          vector: MiuixIcons.extended.byName('promotions')!,
                          size: 20,
                          tint: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cyrene Premium',
                          style: theme.textStyles.body1.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (constraints.maxWidth >= 300) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: .16),
                            ),
                            child: Text(
                              '永久买断',
                              style: theme.textStyles.footnote2.copyWith(
                                color: Colors.white.withValues(alpha: .92),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 中部：金色 EMV 芯片。
                  _EmvChip(),
                  // 底部：开通时间 + 品牌 wordmark。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '开通时间',
                              style: theme.textStyles.footnote2.copyWith(
                                color: Colors.white.withValues(alpha: .65),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              memberSince,
                              style: theme.textStyles.body2.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'CYRENE',
                        style: theme.textStyles.body1.copyWith(
                          color: Colors.white.withValues(alpha: .85),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ISO 时间串 → 卡面风格 "yyyy.MM.dd"；解析失败回落到占位。
  String _formatMemberSince(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}.${two(dt.month)}.${two(dt.day)}';
  }
}

/// 金色 EMV 芯片：圆角矩形 + 横向分槽，模拟银行卡芯片外观。
class _EmvChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 32,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFFD479),
                      const Color(0xFFFFC107),
                      const Color(0xFFC8901A),
                    ],
                  ),
                ),
              ),
            ),
            // 横向分槽线。
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  3,
                  (_) => Container(
                    height: 0.6,
                    color: Colors.black.withValues(alpha: .25),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 极淡网格纹理，给卡面加质感，不影响主信息可读性。
class _CardGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .04)
      ..strokeWidth = 0.5;
    const step = 16.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
