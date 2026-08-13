import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/auth/account_session_controller.dart';
import '../../application/auth/third_party_accounts_controller.dart';
import '../../domain/models/account.dart';
import '../../domain/models/media_url.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 第三方账号管理与绑定页（对应 Tauri `AccountBindingManager`）。
///
/// 展示网易云 / QQ / 酷狗 三家绑定状态：未绑定点按弹扫码绑定 sheet（网易云
/// 额外支持手机验证码），已绑定显示昵称 + 头像并提供解绑。复用
/// [AccountService] 全部接口，状态由页面级 [ThirdPartyAccountsController] 管理。
///
/// 双端适配同 [SettingsPage]：桌面端经 [onOpenSecondary] 推入设置二级栈，
/// 移动端用 Navigator；[body] 非空时直接渲染（桌面二级页覆盖范式）。
class ThirdPartyAccountsPage extends StatefulWidget {
  const ThirdPartyAccountsPage({
    super.key,
    required this.account,
    this.onOpenSecondary,
    this.body,
  });

  final AccountSessionController account;
  final ValueChanged<Widget>? onOpenSecondary;
  final Widget? body;

  @override
  State<ThirdPartyAccountsPage> createState() => _ThirdPartyAccountsPageState();
}

class _ThirdPartyAccountsPageState extends State<ThirdPartyAccountsPage> {
  late final ThirdPartyAccountsController _controller;

  // HyperOS 系统设置的彩色图标底色（与 settings_page 对齐）。
  static const _iconBlue = Color(0xFF3482FF);
  static const _iconGreen = Color(0xFF3CC756);
  static const _iconOrange = Color(0xFFFF9F0A);

  @override
  void initState() {
    super.initState();
    _controller = ThirdPartyAccountsController();
    _controller.onQrSuccess = _onQrSuccess;
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    final token = widget.account.token;
    final userId = widget.account.state.user?.id;
    if (token == null || userId == null) return;
    await _controller.loadBindings(token);
  }

  void _onQrSuccess(ThirdPartyPlatform platform) {
    final name = _platformLabel(platform);
    CyreneToast.show('$name 绑定成功');
    final token = widget.account.token;
    if (token != null) _controller.loadBindings(token);
    // 关闭绑定 sheet（若打开着）。sheet 自身监听 controller，成功后自行 dismiss。
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondaryBody = widget.body;
    if (secondaryBody != null) return secondaryBody;

    return CyrenePage(
      title: '第三方账号',
      bodyBuilder: (context, topPadding) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
            children: [
              _SectionTitle('账号绑定'),
              CyreneMenuGroup(children: _platformRows(context, state)),
              const SizedBox(height: 12),
              _SafetyNote(),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 12),
                _InlineError(
                  message: state.errorMessage!,
                  onDismiss: _controller.clearError,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _platformRows(BuildContext context, ThirdPartyAccountsState state) {
    final bindings = state.bindings;
    // 加载中且无数据时显示骨架占位，避免空列表闪烁。
    if (bindings == null && state.loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: MiuixCircularProgressIndicator(size: 20, strokeWidth: 2)),
        ),
      ];
    }
    if (bindings == null) {
      return [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '暂时无法获取绑定状态，请下拉重试',
            style: MiuixTheme.of(context).textStyles.body2.copyWith(
              color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
            ),
          ),
        ),
      ];
    }
    return [
      _platformRow(context, ThirdPartyPlatform.netease, bindings.netease),
      _platformRow(context, ThirdPartyPlatform.qq, bindings.qq),
      _platformRow(context, ThirdPartyPlatform.kugou, bindings.kugou),
    ];
  }

  Widget _platformRow(
    BuildContext context,
    ThirdPartyPlatform platform,
    BindingInfo info,
  ) {
    final label = _platformLabel(platform);
    final color = _platformColor(platform);
    if (info.bound) {
      final nickname = platform == ThirdPartyPlatform.kugou
          ? (info.username?.isNotEmpty == true ? info.username! : label)
          : (info.nickname?.isNotEmpty == true ? info.nickname! : label);
      final avatar = platform == ThirdPartyPlatform.kugou
          ? info.avatar
          : info.avatarUrl;
      return CyreneMenuRow(
        leading: _PlatformAvatar(avatar: avatar, fallback: label, fallbackColor: color),
        title: nickname,
        value: '已绑定',
        trailing: _UnbindButton(
          label: label,
          onTap: () => _confirmUnbind(context, platform, label),
        ),
      );
    }
    return CyreneMenuRow(
      vector: _platformVector(platform),
      iconBackground: color,
      title: label,
      subtitle: '点击绑定',
      onTap: () => _openBindSheet(context, platform),
    );
  }

  Future<void> _confirmUnbind(
    BuildContext context,
    ThirdPartyPlatform platform,
    String label,
  ) async {
    final token = widget.account.token;
    if (token == null) return;
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '解绑$label？',
      summary: '解除后该平台的个性推荐、歌单导入等功能将不可用，可随时重新绑定。',
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
                  child: MiuixText('解绑', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final ok = await _controller.unbind(token, platform);
    if (!mounted) return;
    CyreneToast.show(ok ? '$label 已解绑' : '解绑失败，请稍后重试');
  }

  Future<void> _openBindSheet(BuildContext context, ThirdPartyPlatform platform) async {
    final token = widget.account.token;
    final userId = widget.account.state.user?.id;
    if (token == null || userId == null) {
      CyreneToast.show('请先登录 Cyrene 账号');
      return;
    }
    // 打开 sheet 前清掉上一次的二维码会话与错误。
    _controller.cancelQr();
    _controller.clearError();
    await showCyreneSheet<void>(
      context: context,
      title: '绑定${_platformLabel(platform)}',
      insideMargin: 18,
      builder: (sheetContext, dismiss) => _BindSheet(
        controller: _controller,
        platform: platform,
        token: token,
        userId: userId,
        dismiss: dismiss,
      ),
    );
    // sheet 关闭后停掉轮询（dismiss 已带退场动画，这里只清状态）。
    _controller.cancelQr();
  }

  // --- 平台元数据 ---

  static String _platformLabel(ThirdPartyPlatform p) => switch (p) {
    ThirdPartyPlatform.netease => '网易云音乐',
    ThirdPartyPlatform.qq => 'QQ音乐',
    ThirdPartyPlatform.kugou => '酷狗音乐',
  };

  static Color _platformColor(ThirdPartyPlatform p) => switch (p) {
    ThirdPartyPlatform.netease => _iconOrange,
    ThirdPartyPlatform.qq => _iconBlue,
    ThirdPartyPlatform.kugou => _iconGreen,
  };

  static MiuixVectorIcon _platformVector(ThirdPartyPlatform p) {
    // Miuix 矢量库里没有平台 logo，统一用 link/contacts 占位，靠底色区分。
    final icon = switch (p) {
      ThirdPartyPlatform.netease => 'music',
      ThirdPartyPlatform.qq => 'contactsCircle',
      ThirdPartyPlatform.kugou => 'tune',
    };
    return MiuixIcons.extended.byName(icon)!;
  }
}

// ---------------------------------------------------------------------------
// 绑定 sheet（扫码 / 网易云手机号）
// ---------------------------------------------------------------------------

class _BindSheet extends StatefulWidget {
  const _BindSheet({
    required this.controller,
    required this.platform,
    required this.token,
    required this.userId,
    required this.dismiss,
  });

  final ThirdPartyAccountsController controller;
  final ThirdPartyPlatform platform;
  final String token;
  final int userId;
  final void Function([void result]) dismiss;

  @override
  State<_BindSheet> createState() => _BindSheetState();
}

class _BindSheetState extends State<_BindSheet> {
  _BindTab _tab = _BindTab.qr;
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _ctcodeController = TextEditingController(text: '86');
  bool _submitted = false; // 绑定成功后阻止重复交互

  @override
  void initState() {
    super.initState();
    // 网易云默认进扫码 tab 并发起；酷狗/QQ 只有扫码。
    _startQr();
  }

  Future<void> _startQr() async {
    switch (widget.platform) {
      case ThirdPartyPlatform.netease:
        await widget.controller.startNeteaseQr(widget.userId);
      case ThirdPartyPlatform.kugou:
        await widget.controller.startKugouQr(widget.userId);
      case ThirdPartyPlatform.qq:
        await widget.controller.startQqQr(widget.userId);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _ctcodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听 controller：绑定成功时自动关弹窗。
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        // 扫码成功或手机登录成功后关闭 sheet（loadBindings 已触发刷新）。
        // 判据：qrSession.status == '绑定成功'，或手机登录走完且 bindings 已刷新。
        if (!_submitted && state.qrSession?.status == '绑定成功') {
          _submitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.dismiss();
          });
        }
        final showTabs = widget.platform == ThirdPartyPlatform.netease;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTabs) _tabBar(context),
            const SizedBox(height: 18),
            if (showTabs && _tab == _BindTab.phone)
              _phoneForm(context, state)
            else
              _qrView(context, state),
          ],
        );
      },
    );
  }

  Widget _tabBar(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Row(
      children: [
        Expanded(child: _tabButton(context, _BindTab.qr, '扫码登录', theme)),
        const SizedBox(width: 10),
        Expanded(child: _tabButton(context, _BindTab.phone, '手机号登录', theme)),
      ],
    );
  }

  Widget _tabButton(
    BuildContext context,
    _BindTab tab,
    String label,
    MiuixThemeData theme,
  ) {
    final selected = _tab == tab;
    return SizedBox(
      width: double.infinity,
      child: MiuixButton(
        onPressed: () {
          if (tab == _BindTab.phone) {
            // 切到手机号 tab 时停掉扫码轮询，避免后台空转。
            widget.controller.cancelQr();
          } else {
            // 切回扫码 tab 时重新发起（之前的会话已 cancel）。
            _startQr();
          }
          setState(() => _tab = tab);
        },
        colors: selected
            ? MiuixButtonDefaults.buttonColorsPrimary(context)
            : MiuixButtonDefaults.buttonColors(context),
        child: MiuixText(label, style: theme.textStyles.button.copyWith(fontSize: 13)),
      ),
    );
  }

  Widget _qrView(BuildContext context, ThirdPartyAccountsState state) {
    final session = state.qrSession;
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    if (session == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QrImage(session: session),
        const SizedBox(height: 18),
        Text(
          session.status,
          textAlign: TextAlign.center,
          style: theme.textStyles.body2.copyWith(
            color: session.expired ? colors.error : colors.onSurfaceVariantSummary,
          ),
        ),
        if (session.expired) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: MiuixButton(
              onPressed: () => widget.controller.refreshQr(widget.userId),
              colors: MiuixButtonDefaults.buttonColorsPrimary(context),
              child: MiuixText('刷新二维码', style: theme.textStyles.button),
            ),
          ),
        ],
      ],
    );
  }

  Widget _phoneForm(BuildContext context, ThirdPartyAccountsState state) {
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: MiuixTextField(
                controller: _ctcodeController,
                label: '区号',
                useLabelAsPlaceholder: true,
                singleLine: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MiuixTextField(
                controller: _phoneController,
                label: '手机号',
                useLabelAsPlaceholder: true,
                singleLine: true,
                keyboardType: TextInputType.phone,
                autofocus: true,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MiuixTextField(
                controller: _codeController,
                label: '验证码',
                useLabelAsPlaceholder: true,
                singleLine: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _bind(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: MiuixButton(
                onPressed: _canSendCode(state) ? _sendCode : null,
                enabled: _canSendCode(state),
                colors: MiuixButtonDefaults.buttonColors(context),
                child: MiuixText(
                  state.captchaCountdown > 0
                      ? '${state.captchaCountdown} 秒'
                      : (state.captchaSending ? '发送中…' : '发送验证码'),
                  style: theme.textStyles.button.copyWith(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          _InlineError(message: state.errorMessage!, onDismiss: widget.controller.clearError),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: MiuixButton(
            onPressed: (_canBind(state) && !state.binding) ? _bind : null,
            enabled: _canBind(state) && !state.binding,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.binding) ...[
                  const MiuixCircularProgressIndicator(size: 16, strokeWidth: 2),
                  const SizedBox(width: 8),
                ],
                MiuixText(
                  state.binding ? '绑定中…' : '绑定',
                  style: theme.textStyles.button,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _canSendCode(ThirdPartyAccountsState state) =>
      _phoneController.text.trim().isNotEmpty &&
      !state.captchaSending &&
      state.captchaCountdown == 0;

  bool _canBind(ThirdPartyAccountsState state) =>
      _phoneController.text.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty;

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    await widget.controller.sendCaptcha(phone, ctcode: _ctcodeController.text.trim());
  }

  Future<void> _bind() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.isEmpty || code.isEmpty) return;
    final ok = await widget.controller.loginByCellphone(
      widget.token,
      phone,
      code,
      ctcode: _ctcodeController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      _submitted = true;
      CyreneToast.show('网易云音乐绑定成功');
      widget.dismiss();
    }
  }
}

enum _BindTab { qr, phone }

// ---------------------------------------------------------------------------
// 二维码图片渲染
// ---------------------------------------------------------------------------

class _QrImage extends StatelessWidget {
  const _QrImage({required this.session});

  final QrSession session;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    // QQ：后端返回 img，可能是 http URL 或 base64 data URL。
    if (session.platform == ThirdPartyPlatform.qq) {
      final img = session.qrImage;
      if (img != null && img.isNotEmpty) {
        return _box(context, child: _imageFromAny(img));
      }
    }
    // 网易云：优先用后端直出的 base64 data URL（qrimg），否则用 qrUrl 本地生成。
    if (session.platform == ThirdPartyPlatform.netease) {
      final qrimg = session.qrImage;
      if (qrimg != null && qrimg.isNotEmpty) {
        return _box(context, child: _imageFromAny(qrimg));
      }
    }
    // 酷狗 / 网易云无 qrimg：用 qrUrl 本地生成二维码。
    final url = session.qrUrl;
    if (url.isEmpty) {
      return _box(
        context,
        child: const Center(
          child: MiuixCircularProgressIndicator(size: 24, strokeWidth: 2),
        ),
      );
    }
    return _box(
      context,
      child: QrImageView(
        data: url,
        version: QrVersions.auto,
        size: 200,
        eyeStyle: QrEyeStyle(color: colors.onBackground, eyeShape: QrEyeShape.square),
        dataModuleStyle: QrDataModuleStyle(
          color: colors.onBackground,
          dataModuleShape: QrDataModuleShape.square,
        ),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _box(BuildContext context, {required Widget child}) => Container(
    width: 220,
    height: 220,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: MiuixTheme.of(context).colors.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  /// 从「http URL 或 base64 data URL」渲染图片。
  Widget _imageFromAny(String src) {
    if (src.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: src,
        httpHeaders: imageHeaders(src),
        fit: BoxFit.contain,
        memCacheWidth: coverDecodeWidth(200, 1.0),
        errorWidget: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_rounded)),
      );
    }
    // data:image/...;base64,xxxx → 取 base64 部分解码。
    final b64 = _stripDataUrl(src);
    try {
      final bytes = base64Decode(b64);
      return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
    } catch (_) {
      return const Center(child: Icon(Icons.broken_image_rounded));
    }
  }

  static String _stripDataUrl(String src) {
    final comma = src.indexOf(',');
    return comma >= 0 ? src.substring(comma + 1) : src;
  }
}

// ---------------------------------------------------------------------------
// 平台头像（已绑定时行内小头像，失败回退平台首字）
// ---------------------------------------------------------------------------

class _PlatformAvatar extends StatelessWidget {
  const _PlatformAvatar({
    required this.avatar,
    required this.fallback,
    required this.fallbackColor,
  });

  final String? avatar;
  final String fallback;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final initial = fallback.characters.first;
    final url = avatar;
    return CircleAvatar(
      radius: 18,
      foregroundImage: url != null && url.isNotEmpty
          ? CachedNetworkImageProvider(url, headers: imageHeaders(url))
          : null,
      onForegroundImageError: url != null && url.isNotEmpty ? (_, _) {} : null,
      backgroundColor: fallbackColor,
      child: Text(
        initial,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 解绑按钮（行内小按钮）
// ---------------------------------------------------------------------------

class _UnbindButton extends StatelessWidget {
  const _UnbindButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixButton(
      onPressed: onTap,
      colors: MiuixButtonColors(
        color: colors.secondaryContainer,
        contentColor: colors.error,
        disabledColor: colors.disabledSecondary,
        disabledContentColor: colors.disabledOnSecondary,
      ),
      child: MiuixText('解绑', style: theme.textStyles.button.copyWith(fontSize: 12)),
    );
  }
}

// ---------------------------------------------------------------------------
// 安全说明 + 错误条 + 分组标题
// ---------------------------------------------------------------------------

class _SafetyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixIcon(
            vector: MiuixIcons.extended.byName('lock')!,
            size: 15,
            tint: theme.colors.onSurfaceVariantSummary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '第三方账号的登录凭证仅安全保存在服务器，不会下发到本机。',
              style: theme.textStyles.body2.copyWith(
                color: theme.colors.onSurfaceVariantSummary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Stack(
      children: [
        CyreneInlineAlert(
          vector: MiuixIcons.extended.byName('info')!,
          title: '提示',
          description: message,
          destructive: true,
        ),
        Positioned(
          top: 6,
          right: 6,
          child: MiuixIconButton(
            onPressed: onDismiss,
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('close')!,
              size: 16,
              tint: colors.onErrorContainer,
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组小标题：沿用 settings_page._SectionTitle 的样式（常规字重小字）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: MiuixText(
        text,
        style: theme.textStyles.subtitle.copyWith(fontWeight: FontWeight.w400),
        color: theme.colors.onBackgroundVariant,
      ),
    );
  }
}
