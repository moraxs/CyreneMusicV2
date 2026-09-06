import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../domain/models/media_url.dart';
import '../../domain/together/together_models.dart';

/// 房间成员头像：登录用户显示真实头像，匿名听众退回首字母色块。
///
/// 成员页和播放器上的房间底板共用这一份——两边各写一套的话，很容易只给其中
/// 一处接上真实头像（曾经就是这样）。
class TogetherMemberAvatar extends StatelessWidget {
  const TogetherMemberAvatar({super.key, required this.member, this.size = 36});

  final TogetherMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final url = member.avatar;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? _FallbackAvatar(member: member, size: size)
            : CachedNetworkImage(
                imageUrl: url,
                // 封面/头像统一走这套请求头，不要强转 https（见 media_url.dart）。
                httpHeaders: imageHeaders(url),
                fit: BoxFit.cover,
                memCacheWidth: coverDecodeWidth(
                  size,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                placeholder: (context, _) =>
                    ColoredBox(color: colors.secondaryContainer),
                errorWidget: (context, _, _) =>
                    _FallbackAvatar(member: member, size: size),
              ),
      ),
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar({required this.member, required this.size});

  final TogetherMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final initial = member.name.characters.isEmpty
        ? '?'
        : member.name.characters.first;
    return ColoredBox(
      color: member.isHost
          ? colors.primary.withValues(alpha: .18)
          : colors.secondaryContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * .42,
            fontWeight: FontWeight.w600,
            color: member.isHost
                ? colors.primary
                : colors.onSurfaceVariantActions,
          ),
        ),
      ),
    );
  }
}
