import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../domain/models/sponsor.dart';
import '../../infrastructure/services/sponsor_service.dart';
import '../../presentation/cyrene/cyrene_page.dart';

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
    final response = await SponsorService.instance.getSponsorList();
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _loading = false;
      _list = response.data;
      if (response.code != 200 || response.data == null) {
        _error = response.message ?? '赞助墙加载失败，请稍后重试。';
      }
    });
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
