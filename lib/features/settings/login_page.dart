import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../presentation/cyrene/cyrene_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.account});

  final AccountSessionController account;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  String? _accountError;
  String? _passwordError;
  var _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    widget.account.clearError();
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '登录',
    largeTitle: true,
    // 登录页背景是 _AuroraBackdrop 渐变光斑，顶栏默认 0.55 灰白半透明会把它洗淡、
    // 使栏偏浅；这里置 0 让栏完全透明、只留模糊，栏与内容区颜色连成一片。
    topBarTintAlpha: 0,
    bodyBuilder: (context, topPadding) => AnimatedBuilder(
      animation: widget.account,
      builder: (context, _) {
        final state = widget.account.state;
        final theme = MiuixTheme.of(context);
        final colors = theme.colors;
        final isBusy = state.isBusy;
        return Stack(
          children: [
            // 光斑层垫在最底：不参与滚动，随主题色变化。
            const Positioned.fill(child: _AuroraBackdrop()),
            ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                20,
                topPadding.top + 32,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 32,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandHeader(),
                        const SizedBox(height: 32),
                        // 字段自带浮动标签与填充底色，直接铺排、不再套外部容器。
                        MiuixTextField(
                          key: const Key('login-account-field'),
                          controller: _accountController,
                          enabled: !isBusy,
                          label: '邮箱或用户名',
                          singleLine: true,
                          leadingIcon: _FieldIcon(
                            child: MiuixIcon(
                              vector: MiuixIcons.extended.byName('contacts')!,
                              size: 20,
                              tint: colors.onSecondaryContainer,
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => _clearFieldError(account: true),
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        if (_accountError != null) _FieldError(_accountError!),
                        const SizedBox(height: 12),
                        MiuixTextField(
                          key: const Key('login-password-field'),
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          enabled: !isBusy,
                          label: '密码',
                          singleLine: true,
                          obscureText: _obscurePassword,
                          leadingIcon: _FieldIcon(
                            child: MiuixIcon(
                              vector: MiuixIcons.extended.byName('lock')!,
                              size: 20,
                              tint: colors.onSecondaryContainer,
                            ),
                          ),
                          trailingIcon: Padding(
                            padding: const EdgeInsets.only(left: 4, right: 8),
                            child: MiuixIconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              child: MiuixIcon(
                                vector: MiuixIcons.extended.byName(
                                  _obscurePassword ? 'hide' : 'show',
                                )!,
                                size: 20,
                                tint: colors.onSecondaryContainer,
                              ),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => _clearFieldError(account: false),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_passwordError != null)
                          _FieldError(_passwordError!),
                        if (state.errorMessage != null) ...[
                          const SizedBox(height: 14),
                          CyreneInlineAlert(
                            key: const Key('login-error-message'),
                            vector: MiuixIcons.extended.byName('info')!,
                            title: '登录失败',
                            description: state.errorMessage!,
                            destructive: true,
                          ),
                        ],
                        const SizedBox(height: 20),
                        _SubmitButton(
                          isSigningIn:
                              state.status == AccountSessionStatus.signingIn,
                          enabled: !isBusy,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '登录即表示你同意在此设备上安全保存会话信息',
                          textAlign: TextAlign.center,
                          style: theme.textStyles.footnote1.copyWith(
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  void _clearFieldError({required bool account}) {
    if (account) {
      if (_accountError != null) setState(() => _accountError = null);
    } else {
      if (_passwordError != null) setState(() => _passwordError = null);
    }
  }

  Future<void> _submit() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _accountError = account.isEmpty ? '请输入账号' : null;
      _passwordError = password.isEmpty ? '请输入密码' : null;
    });
    if (_accountError != null || _passwordError != null) return;

    final success = await widget.account.login(account, password);
    if (success && mounted) Navigator.pop(context, true);
  }
}

/// 登录页背景光斑：三团柔和的彩色光晕，色相由主题 primary 派生。
///
/// 实现刻意**不用高斯模糊**：`RadialGradient` 的柔和边缘是渐变自带的，
/// 而 `ImageFilter.blur` 需要逐帧离屏采样，在中低端安卓上是实打实的掉帧源。
/// 这里整层是静态的，套 `RepaintBoundary` 后只光栅化一次，滚动/转场零成本。
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // 从 primary 出发在 OkLch 里转色相：感知均匀，转到任何角度都不会
    // 突然变暗或发灰（HSV 转色相就会）。三团构成邻近色和谐配色。
    final base = theme.colors.primary.toOkLch();
    // 暗色下光斑要更收敛，否则在深底上糊成一片亮斑。
    final isDark = theme.brightness == Brightness.dark;
    final lightness = isDark ? 62.0 : 78.0;
    final chroma = isDark ? 26.0 : 34.0;
    Color spot(double hueShift, double alpha) =>
        OkLch(lightness, chroma, (base.h + hueShift) % 360).toColor(alpha);

    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(
          // 主色团偏左上（品牌图标后方），另两团做冷暖呼应。
          spots: [
            _AuroraSpot(
              center: const Alignment(-0.75, -0.85),
              radius: 0.95,
              color: spot(0, isDark ? .34 : .30),
            ),
            _AuroraSpot(
              center: const Alignment(0.95, -0.35),
              radius: 0.8,
              color: spot(48, isDark ? .26 : .24),
            ),
            _AuroraSpot(
              center: const Alignment(-0.3, 0.9),
              radius: 1.05,
              color: spot(-42, isDark ? .22 : .20),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个光斑的几何与颜色。[radius] 是相对于画布短边的倍数。
class _AuroraSpot {
  const _AuroraSpot({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Alignment center;
  final double radius;
  final Color color;
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter({required this.spots});

  final List<_AuroraSpot> spots;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    for (final spot in spots) {
      final center = spot.center.withinRect(Offset.zero & size);
      final radius = shortestSide * spot.radius;
      final rect = Rect.fromCircle(center: center, radius: radius);
      // stops 让中心保持一段实色再向外衰减，避免看起来像个硬边圆；
      // 末端 alpha 归零，光斑之间叠加处自然过渡。
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              spot.color,
              spot.color.withValues(alpha: spot.color.a * 0.45),
              spot.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) {
    if (oldDelegate.spots.length != spots.length) return true;
    for (var i = 0; i < spots.length; i++) {
      final a = oldDelegate.spots[i];
      final b = spots[i];
      if (a.color != b.color || a.center != b.center || a.radius != b.radius) {
        return true;
      }
    }
    return false;
  }
}

/// 品牌头部：应用图标 + 唯一一句欢迎语。
///
/// 顶栏的「登录」已交代页面用途，这里只承担品牌识别与语气，
/// 不再重复「登录账号」之类的标题。
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      children: [
        // 用真实应用图标而非通用音符图标，与「关于」页保持同一品牌形象。
        // 裁剪用 Miuix 超椭圆（本项目 HyperOS 圆角惯例），非普通圆角。
        ClipPath.shape(
          shape: const MiuixSquircleBorder(cornerRadius: 20),
          child: Image.asset(
            'assets/icons/new_ico_white.png',
            width: 76,
            height: 76,
            // 图标按显示尺寸解码，避免 2048² 原图占用无谓内存。
            cacheWidth: (76 * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '欢迎回来',
          style: theme.textStyles.title2.copyWith(
            color: theme.colors.onBackground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '登录以同步你的歌单、收藏与听歌记录',
          textAlign: TextAlign.center,
          style: theme.textStyles.body2.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}

/// 输入框前置图标的统一间距（对齐 MiuixTextField 的 16 内边距）。
class _FieldIcon extends StatelessWidget {
  const _FieldIcon({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(left: 16, right: 8), child: child);
}

/// 提交按钮：整行宽（Miuix 按钮默认贴合内容，需自行撑满）。
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isSigningIn,
    required this.enabled,
    required this.onPressed,
  });

  final bool isSigningIn;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: MiuixButton(
        key: const Key('login-submit-button'),
        enabled: enabled,
        colors: MiuixButtonDefaults.buttonColorsPrimary(context),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 登录中才加指示器：正常态只留文字，不用图标重复「登录」语义。
            if (isSigningIn) ...[
              MiuixCircularProgressIndicator(
                size: 16,
                strokeWidth: 2,
                colors: MiuixProgressIndicatorColors(
                  foregroundColor: theme.colors.onPrimary,
                  disabledForegroundColor: theme.colors.onPrimary,
                  backgroundColor: Colors.transparent,
                ),
              ),
              const SizedBox(width: 10),
            ],
            MiuixText(
              isSigningIn ? '正在登录…' : '登录',
              style: theme.textStyles.button,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 7, left: 4),
      child: Row(
        children: [
          MiuixIcon(
            vector: MiuixIcons.extended.byName('info')!,
            size: 14,
            tint: theme.colors.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: theme.textStyles.footnote1.copyWith(
                color: theme.colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
