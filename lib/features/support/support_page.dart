import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/auth/account_session_controller.dart';
import '../../domain/models/qq_group.dart';
import '../../domain/models/sponsor.dart';
import '../../infrastructure/services/public_config_service.dart';
import '../../infrastructure/services/sponsor_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.account});

  final AccountSessionController account;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  var _loading = true;
  var _requestId = 0;
  String? _error;
  SponsorListResponse? _list;

  /// 服务端下发的 QQ 群配置。null = 还没拉到 / 拉取失败，此时不渲染入口。
  QqGroup? _qqGroup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    // 两个请求并行：QQ 群配置慢/失败不该拖住赞助墙，反之亦然。
    // 先各自起飞再逐个 await——Future.wait 在这里会把两个不同的返回类型
    // 归并成 List<Object?>，落地时还得强转回来。
    final sponsorRequest = SponsorService.instance.getSponsorList();
    final qqGroupRequest = PublicConfigService.instance.fetchQqGroup();
    final response = await sponsorRequest;
    final qqGroup = await qqGroupRequest;
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _loading = false;
      _list = response.data;
      _qqGroup = qqGroup;
      if (response.code != 200 || response.data == null) {
        _error = response.message ?? '赞助墙加载失败，请稍后重试。';
      }
    });
  }

  /// 跳到 QQ 的入群链接。
  ///
  /// 走 externalApplication：这个链接在装了 QQ 的机器上应当由 QQ 接管，
  /// 塞进应用内 WebView 只会得到一个「请在 QQ 中打开」的空页。
  Future<void> _joinQqGroup(QqGroup group) async {
    final uri = Uri.tryParse(group.url);
    if (uri == null) {
      CyreneToast.show('入群链接无效');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) CyreneToast.show('无法打开入群链接');
    } catch (e) {
      CyreneToast.show('无法打开入群链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return CyrenePage(
      title: '帮助与支持',
      bodyBuilder: (context, topPadding) => CyrenePullToRefresh(
        onRefresh: _load,
        contentPadding: EdgeInsets.only(top: topPadding.top),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: topPadding + const EdgeInsets.fromLTRB(16, 20, 16, 36),
          children: [
            MiuixCard(
              insideMargin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '支持 Cyrene Music',
                    style: theme.textStyles.title4.copyWith(
                      color: colors.onSurfaceContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '感谢每一位帮助项目持续前进的朋友',
                    style: theme.textStyles.body2.copyWith(
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        const CyreneIconBox(
                          icon: Icons.volunteer_activism_rounded,
                          size: 52,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            widget.account.state.user?.isSponsor == true
                                ? '感谢你的支持，你已是 Cyrene Sponsor。'
                                : '可以通过反馈问题、分享项目或参与社区来支持我们。移动端支付流程暂未开放。',
                            style: theme.textStyles.body2.copyWith(
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 交流群入口完全由服务端 config.json 的 qq_group 决定：
            // enabled 为 false（或没配 url）时整块不渲染，不留占位也不留死按钮。
            if (_qqGroup?.canJoin == true) ...[
              const SizedBox(height: 24),
              const CyreneSectionTitle(
                title: '交流与反馈',
                description: '遇到问题或想提建议，来群里找我们',
              ),
              const SizedBox(height: 12),
              CyreneMenuGroup(
                children: [
                  CyreneMenuRow(
                    key: const Key('join-qq-group'),
                    vector: MiuixIcons.extended.byName('community')!,
                    iconBackground: const Color(0xFF12B7F5),
                    title: '加入 QQ 群',
                    subtitle: _qqGroup!.name.isEmpty
                        ? 'Cyrene Music 用户群'
                        : _qqGroup!.name,
                    onTap: () => _joinQqGroup(_qqGroup!),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            const CyreneSectionTitle(title: '赞助墙', description: '感谢这些同行者'),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: MiuixCircularProgressIndicator()),
              )
            else if (_error != null)
              CyreneEmptyState(
                icon: Icons.cloud_off_rounded,
                title: '赞助墙暂时不可用',
                description: _error!,
                action: MiuixTextButton('重试', onPressed: _load),
              )
            else if (_list!.sponsors.isEmpty)
              const CyreneEmptyState(
                icon: Icons.favorite_rounded,
                title: '赞助墙还在等待第一束光',
                description: '感谢你关注 Cyrene Music。',
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _list!.sponsors
                    .map((sponsor) => _SponsorChip(sponsor: sponsor))
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _SponsorChip extends StatelessWidget {
  const _SponsorChip({required this.sponsor});

  final Sponsor sponsor;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixBadge(
      containerColor: colors.secondaryContainer,
      contentColor: colors.onSecondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiuixIcon(
              vector: MiuixIcons.extended.byName('favorites')!,
              size: 13,
            ),
            const SizedBox(width: 6),
            MiuixText(sponsor.username, style: theme.textStyles.footnote2),
          ],
        ),
      ),
    );
  }
}
