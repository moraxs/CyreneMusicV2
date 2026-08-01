import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../domain/models/media_url.dart';
import '../../domain/models/user.dart';

/// 已登录的沉浸式用户卡片：模糊放大的头像铺满卡片背景 + 渐变遮罩，
/// 前景为大头像 / 用户名 / 邮箱 / Sponsor 徽章。
///
/// 由「我的」页头部与「个人中心」页头部共用。无头像时背景退回主题色渐变。
class CyreneUserHeroCard extends StatelessWidget {
  const CyreneUserHeroCard({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final avatarUrl = user.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    // RepaintBoundary：整卡先栅格化再随滚动平移。否则模糊背景 + 高光描边
    // 每帧在亚像素偏移下重新光栅化，裁剪边缘的抗锯齿接缝会时隐时现。
    return RepaintBoundary(
      child: ClipPath.shape(
        shape: const MiuixSquircleBorder(cornerRadius: 20),
        // 不透明深色兜底：裁剪边缘的 AA 过渡像素采样到深色而非页面浅底，
        // 消除滚动时卡片边缘的白色发丝线。
        child: ColoredBox(
          color: const Color(0xFF24272C),
          // 注：这里不叠 MiuixHighlight——bloom 描边会沿上下边画白色发丝亮线，
          // 卡片随滚动做亚像素平移时亮线在重采样中时隐时现（用户实测反馈）。
          child: Stack(
            children: [
              // 背景：模糊放大的头像（对应原版沉浸式头部），无头像时退回
              // 主题色渐变；四边外扩 1px，盖住裁剪边缘的抗锯齿缝隙。
              Positioned.fill(
                left: -1,
                top: -1,
                right: -1,
                bottom: -1,
                child: hasAvatar
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Transform.scale(
                          // 放大再模糊，避免高斯采样在边缘露出透明晕圈。
                          scale: 1.4,
                          child: CachedNetworkImage(
                            imageUrl: avatarUrl,
                            httpHeaders: imageHeaders(avatarUrl),
                            fit: BoxFit.cover,
                            // sigma 30 的重模糊会抹掉一切细节,低分辨率解码在视觉上
                            // 完全等价,却省掉全尺寸头像解码 + 让模糊处理更小的缓冲。
                            memCacheWidth: coverDecodeWidth(
                              120,
                              MediaQuery.devicePixelRatioOf(context),
                            ),
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: colors.primary),
                          ),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colors.primary,
                              colors.primary.withValues(alpha: .65),
                            ],
                          ),
                        ),
                      ),
              ),
              // 遮罩：保证白色前景文字在任意头像上可读。
              Positioned.fill(
                left: -1,
                top: -1,
                right: -1,
                bottom: -1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .18),
                        Colors.black.withValues(alpha: .42),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                child: Row(
                  children: [
                    _HeroAvatar(user: user),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.title4.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyles.footnote1.copyWith(
                              color: Colors.white.withValues(alpha: .78),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 徽章优先级：Cyrene Premium（紫）> Sponsor（琥珀）。
                    // 后端 has_listening_card 与 is_sponsor 解耦，买 Premium
                    // 只置前者，故这里以 hasListeningCard 为最高优先级。
                    if (user.hasListeningCard) ...[
                      const SizedBox(width: 10),
                      const MiuixBadge(
                        containerColor: Color(0xFF8A64FF),
                        contentColor: Colors.white,
                        child: MiuixText(
                          'Cyrene Premium',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else if (user.isSponsor) ...[
                      const SizedBox(width: 10),
                      const MiuixBadge(
                        containerColor: Color(0xFFFFC107),
                        contentColor: Color(0xE6000000),
                        child: MiuixText(
                          'Sponsor',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 大头像：真实头像图 + 软描边；加载失败/无头像回退首字母圆。
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final username = user.username.trim();
    final initial = username.isEmpty
        ? '?'
        : username.characters.first.toUpperCase();
    final avatarUrl = user.avatarUrl;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 低对比软描边：纯白细环在卡片亚像素平移时会在圆环上下切点处
        // 闪出白色短线，降低对比 + 加宽可消除。
        border: Border.all(
          color: Colors.white.withValues(alpha: .4),
          width: 2.5,
        ),
      ),
      child: CircleAvatar(
        radius: 30,
        backgroundColor: colors.primary,
        foregroundImage: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImageProvider(
                avatarUrl,
                headers: imageHeaders(avatarUrl),
              )
            : null,
        // 加载失败时静默回退到首字母，避免未处理的异步图片异常。
        onForegroundImageError: avatarUrl != null && avatarUrl.isNotEmpty
            ? (_, _) {}
            : null,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
