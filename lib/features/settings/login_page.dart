import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/auth/account_session_controller.dart';
import '../../presentation/cyrene/cyrene_aurora_backdrop.dart';
import '../../presentation/cyrene/cyrene_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.account});

  final AccountSessionController account;

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '登录',
    largeTitle: true,
    // 登录页背景是 CyreneAuroraBackdrop 渐变光斑，顶栏默认 0.55 灰白半透明会把它
    // 洗淡、使栏偏浅；这里置 0 让栏完全透明、只留模糊，栏与内容区颜色连成一片。
    topBarTintAlpha: 0,
    bodyBuilder: (context, topPadding) => Stack(
      children: [
        // 光斑层垫在最底：不参与滚动，随主题色变化。
        const Positioned.fill(child: CyreneAuroraBackdrop()),
        LoginView(
          account: account,
          padding: EdgeInsets.fromLTRB(20, topPadding.top + 32, 20, 32),
          // 独立登录页登录成功即回上一级；首启引导里则由 AppGate 接手推进
          // 到下一步（见 OnboardingPage），故该回调是可选的。
          onSignedIn: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
}

/// 登录表单本体（品牌头 + 账号密码 + 提交），不含页面骨架与背景。
///
/// 独立登录页 [LoginPage] 与首启引导的登录步骤共用：两处的字段校验、错误提示
/// 与登录中态必须完全一致，抽出来才不会改一边漏一边。背景光斑由调用方铺
/// （[CyreneAuroraBackdrop]），因为引导页的光斑要横跨整个流程、不能随步骤重建。
class LoginView extends StatefulWidget {
  const LoginView({
    super.key,
    required this.account,
    this.padding = const EdgeInsets.all(20),
    this.onSignedIn,
    this.showRegisterSwitch = true,
  });

  final AccountSessionController account;

  /// 滚动视图的内边距。底部会自动叠加键盘遮挡高度，调用方不必自己算。
  final EdgeInsets padding;

  /// 登录成功后的回调；为空表示由外部监听会话状态自行处理跳转。
  final VoidCallback? onSignedIn;

  /// 是否在登录模式底部展示「注册新账号」切换链接。
  ///
  /// 引导页把注册入口放在底部操作条（注册按钮），为免同屏出现两处相同的注册
  /// 入口，引导页把它置为 false；独立登录页没有底部条，默认 true 依赖链接触发。
  /// 注册模式内部的「直接登录」回切链接不受此开关影响，始终保留。
  final bool showRegisterSwitch;

  @override
  State<LoginView> createState() => LoginViewState();
}

/// 登录/注册表单主体状态。公开以支持引导页用 [GlobalKey] 从底部操作条切入注册模式。
class LoginViewState extends State<LoginView> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  // 登录/注册双模式。注册表单复用同一外壳（品牌头 + 滚动 + 模式切换链接），
  // 主体换成 `_RegisterForm`；独立登录页与引导页两处入口因此自动同步获得注册能力。
  var _showRegister = false;

  /// 当前是否为注册模式。引导页底部操作条监听它在「注册新账号 / 已有账号直接登录」
  /// 之间切换文案与动作；独立登录页不依赖它。
  final ValueNotifier<bool> registerMode = ValueNotifier(false);

  String? _accountError;
  String? _passwordError;
  var _obscurePassword = true;

  /// 切入注册模式（供引导页底部「注册」按钮触发）。
  void switchToRegister() {
    if (_showRegister) return;
    setState(() => _showRegister = true);
    registerMode.value = true;
    widget.account.clearError();
  }

  /// 切回登录模式（供注册流程自身回切 / 外部兜底）。
  void switchToLogin() {
    if (!_showRegister) return;
    setState(() => _showRegister = false);
    registerMode.value = false;
    widget.account.clearError();
  }

  @override
  void initState() {
    super.initState();
    widget.account.clearError();
  }

  @override
  void dispose() {
    registerMode.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.account,
    builder: (context, _) {
      final state = widget.account.state;
      final theme = MiuixTheme.of(context);
      final colors = theme.colors;
      final isBusy = state.isBusy;
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: widget.padding.copyWith(
          bottom:
              widget.padding.bottom + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandHeader(registering: _showRegister),
                  const SizedBox(height: 32),
                  if (_showRegister)
                    _RegisterForm(
                      account: widget.account,
                      onSignedIn: () => widget.onSignedIn?.call(),
                      onAutoLoginFailed: _handleAutoLoginFailed,
                    )
                  else ...[
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
                    if (_passwordError != null) _FieldError(_passwordError!),
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
                  ],
                  const SizedBox(height: 14),
                  Text(
                    _showRegister
                        ? '注册即表示你同意我们的服务条款与隐私政策'
                        : '登录即表示你同意在此设备上安全保存会话信息',
                    textAlign: TextAlign.center,
                    style: theme.textStyles.footnote1.copyWith(
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 注册模式里的「直接登录」回切链接始终保留；登录模式里的注册链接
                  // 由 [showRegisterSwitch] 决定（引导页把它交给底部操作条，不重复展示）。
                  if (_showRegister || widget.showRegisterSwitch)
                    _ModeSwitchLink(
                      registering: _showRegister,
                      onTap: _toggleMode,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
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
    if (success && mounted) widget.onSignedIn?.call();
  }

  void _toggleMode() {
    setState(() => _showRegister = !_showRegister);
    registerMode.value = _showRegister;
    // 切换语境时清掉登录态的错误提示，避免上一个模式的报错残留在新模式。
    widget.account.clearError();
  }

  /// 注册成功但自动登录失败：切回登录并预填刚注册的邮箱，用户只需再输一次密码。
  void _handleAutoLoginFailed(String account) {
    setState(() {
      _showRegister = false;
      _accountController.text = account;
    });
    registerMode.value = false;
    widget.account.clearError();
  }
}

/// 品牌头部：应用图标 + 一句欢迎/注册语。
///
/// 顶栏的「登录」已交代页面用途，这里只承担品牌识别与语气，不重复标题。
/// [registering] 决定文案落在登录还是注册语境。
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.registering});

  final bool registering;

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
          registering ? '创建账号' : '欢迎回来',
          style: theme.textStyles.title2.copyWith(
            color: theme.colors.onBackground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          registering
              ? '注册后即可登录，同步你的歌单、收藏与听歌记录'
              : '登录以同步你的歌单、收藏与听歌记录',
          textAlign: TextAlign.center,
          style: theme.textStyles.body2.copyWith(
            color: theme.colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}

/// 登录/注册双模式的切换链接（表单底部，两模式互切）。
class _ModeSwitchLink extends StatelessWidget {
  const _ModeSwitchLink({required this.registering, required this.onTap});

  final bool registering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: MiuixTextButton(
      registering ? '已有账号？直接登录' : '没有账号？注册新账号',
      key: Key(
        registering ? 'register-to-login-toggle' : 'login-to-register-toggle',
      ),
      onPressed: onTap,
    ),
  );
}

/// 注册表单本体（QQ号/用户名/密码/确认密码/验证码 + 注册按钮）。
///
/// 挂在 [LoginView] 的注册模式下。注册是叶子操作，不经过会话状态机：发送验证码、
/// 提交注册都直接透传到 [AccountSessionController]；只有注册成功后的自动登录会复用
/// `login()` 走既有会话链路。
class _RegisterForm extends StatefulWidget {
  const _RegisterForm({
    required this.account,
    required this.onSignedIn,
    required this.onAutoLoginFailed,
  });

  final AccountSessionController account;

  /// 注册成功并自动登录后的回调（独立页 pop / 引导页由会话态驱动推进）。
  final VoidCallback onSignedIn;

  /// 注册成功但自动登录失败时回调；父级切回登录并预填刚注册的邮箱。
  final ValueChanged<String> onAutoLoginFailed;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

enum _RegField { qq, username, password, confirm, code }

class _RegisterFormState extends State<_RegisterForm> {
  final _qqController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _codeController = TextEditingController();

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  final _codeFocus = FocusNode();

  String? _qqError;
  String? _usernameError;
  String? _passwordError;
  String? _confirmError;
  String? _codeError;

  var _obscurePassword = true;
  var _obscureConfirm = true;

  // 注册开关状态：切入注册模式先查一次后端，关闭则锁定表单并提示。
  var _registrationEnabled = false;
  String? _statusMessage;

  var _sendingCode = false;
  var _codeSent = false;
  var _countdown = 0;
  Timer? _timer;

  var _registering = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _checkRegistrationStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _qqController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// 后端只接受 QQ 邮箱（validateQQEmail），故只收数字 QQ 号、自动补 @qq.com。
  String get _email => '${_qqController.text.trim()}@qq.com';

  Future<void> _checkRegistrationStatus() async {
    final result = await widget.account.checkRegistrationStatus();
    if (!mounted) return;
    setState(() {
      if (result.success && result.enabled) {
        _registrationEnabled = true;
      } else {
        _statusMessage = result.success
            ? '因滥用，我们暂时关闭了公开注册'
            : '无法确认注册状态，请稍后重试';
      }
    });
  }

  Future<void> _sendCode() async {
    final qq = _qqController.text.trim();
    final username = _usernameController.text.trim();
    setState(() {
      _qqError = qq.isEmpty
          ? '请输入 QQ 号'
          : (_isValidQq(qq) ? null : 'QQ 号应为 5-11 位数字');
      _usernameError = username.isEmpty ? '请输入用户名' : null;
      _errorMessage = null;
    });
    if (_qqError != null || _usernameError != null) return;

    setState(() => _sendingCode = true);
    final result = await widget.account.sendRegisterCode(_email, username);
    if (!mounted) return;
    setState(() {
      _sendingCode = false;
      if (result.success) {
        _startCountdown();
        _successMessage = result.message;
        _errorMessage = null;
      } else {
        _errorMessage = result.message ?? '发送失败，请稍后重试';
        _successMessage = null;
      }
    });
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _codeSent = true;
      _countdown = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 1) {
          _countdown--;
        } else {
          _codeSent = false;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _register() async {
    final qq = _qqController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    final code = _codeController.text.trim();
    setState(() {
      _qqError = qq.isEmpty
          ? '请输入 QQ 号'
          : (_isValidQq(qq) ? null : 'QQ 号应为 5-11 位数字');
      _usernameError = username.isEmpty
          ? '请输入用户名'
          : (_isValidUsername(username) ? null : '用户名格式不正确');
      _passwordError = password.length < 8 ? '密码至少 8 个字符' : null;
      _confirmError = confirm.isEmpty
          ? '请确认密码'
          : (confirm != password ? '两次密码不一致' : null);
      _codeError = code.length != 6 ? '请输入 6 位验证码' : null;
      _errorMessage = null;
      _successMessage = null;
    });
    if (_qqError != null ||
        _usernameError != null ||
        _passwordError != null ||
        _confirmError != null ||
        _codeError != null) {
      return;
    }

    setState(() => _registering = true);
    final result = await widget.account.register(
      _email,
      username,
      password,
      code,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _registering = false;
        _errorMessage = result.message ?? '注册失败，请稍后重试';
      });
      return;
    }
    setState(() => _registering = false);

    // 注册接口响应不含 token，须复用登录链路建立会话（已确认：注册后自动登录）。
    final loggedIn = await widget.account.login(_email, password);
    if (!mounted) return;
    if (loggedIn) {
      widget.onSignedIn.call();
    } else {
      widget.onAutoLoginFailed(_email);
    }
  }

  static bool _isValidQq(String qq) => RegExp(r'^\d{5,11}$').hasMatch(qq);

  static bool _isValidUsername(String username) =>
      RegExp(r'^[一-龥a-zA-Z0-9_]{2,20}$').hasMatch(username);

  void _clearFieldError(_RegField field) {
    switch (field) {
      case _RegField.qq:
        if (_qqError != null) setState(() => _qqError = null);
      case _RegField.username:
        if (_usernameError != null) setState(() => _usernameError = null);
      case _RegField.password:
        if (_passwordError != null) setState(() => _passwordError = null);
      case _RegField.confirm:
        if (_confirmError != null) setState(() => _confirmError = null);
      case _RegField.code:
        if (_codeError != null) setState(() => _codeError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    // 状态未确认/注册关闭时整体锁定，避免提交到必然失败的接口。
    final canType = _registrationEnabled && !_registering;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_registrationEnabled) ...[
          CyreneInlineAlert(
            key: const Key('register-disabled-message'),
            vector: MiuixIcons.extended.byName('info')!,
            title: '注册已关闭',
            description: _statusMessage ?? '注册功能暂不可用',
            destructive: true,
          ),
          const SizedBox(height: 14),
        ],
        if (_errorMessage != null) ...[
          CyreneInlineAlert(
            key: const Key('register-error-message'),
            vector: MiuixIcons.extended.byName('info')!,
            title: '注册失败',
            description: _errorMessage!,
            destructive: true,
          ),
          const SizedBox(height: 14),
        ],
        if (_successMessage != null) ...[
          CyreneInlineAlert(
            key: const Key('register-success-message'),
            vector: MiuixIcons.extended.byName('ok')!,
            title: '验证码已发送',
            description: _successMessage!,
          ),
          const SizedBox(height: 14),
        ],
        MiuixTextField(
          key: const Key('register-qq-field'),
          controller: _qqController,
          enabled: canType,
          label: 'QQ 号',
          singleLine: true,
          leadingIcon: _FieldIcon(
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('email')!,
              size: 20,
              tint: colors.onSecondaryContainer,
            ),
          ),
          trailingIcon: Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: Text(
              '@qq.com',
              style: theme.textStyles.footnote1.copyWith(
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearFieldError(_RegField.qq),
          onSubmitted: (_) => _usernameFocus.requestFocus(),
        ),
        if (_qqError != null) _FieldError(_qqError!),
        const SizedBox(height: 12),
        MiuixTextField(
          key: const Key('register-username-field'),
          controller: _usernameController,
          focusNode: _usernameFocus,
          enabled: canType,
          label: '用户名',
          singleLine: true,
          leadingIcon: _FieldIcon(
            child: MiuixIcon(
              vector: MiuixIcons.extended.byName('contacts')!,
              size: 20,
              tint: colors.onSecondaryContainer,
            ),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearFieldError(_RegField.username),
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),
        if (_usernameError != null) _FieldError(_usernameError!),
        const SizedBox(height: 12),
        MiuixTextField(
          key: const Key('register-password-field'),
          controller: _passwordController,
          focusNode: _passwordFocus,
          enabled: canType,
          label: '密码（至少 8 位）',
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
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearFieldError(_RegField.password),
          onSubmitted: (_) => _confirmFocus.requestFocus(),
        ),
        if (_passwordError != null) _FieldError(_passwordError!),
        const SizedBox(height: 12),
        MiuixTextField(
          key: const Key('register-confirm-field'),
          controller: _confirmController,
          focusNode: _confirmFocus,
          enabled: canType,
          label: '确认密码',
          singleLine: true,
          obscureText: _obscureConfirm,
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
                () => _obscureConfirm = !_obscureConfirm,
              ),
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName(
                  _obscureConfirm ? 'hide' : 'show',
                )!,
                size: 20,
                tint: colors.onSecondaryContainer,
              ),
            ),
          ),
          textInputAction: TextInputAction.next,
          onChanged: (_) => _clearFieldError(_RegField.confirm),
          onSubmitted: (_) => _codeFocus.requestFocus(),
        ),
        if (_confirmError != null) _FieldError(_confirmError!),
        const SizedBox(height: 12),
        // 验证码与「发送验证码」并排：IntrinsicHeight 让按钮高度贴合输入框。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MiuixTextField(
                  key: const Key('register-code-field'),
                  controller: _codeController,
                  focusNode: _codeFocus,
                  enabled: canType,
                  label: '验证码',
                  singleLine: true,
                  leadingIcon: _FieldIcon(
                    child: MiuixIcon(
                      vector: MiuixIcons.extended.byName('promotions')!,
                      size: 20,
                      tint: colors.onSecondaryContainer,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _clearFieldError(_RegField.code),
                  onSubmitted: (_) => _register(),
                ),
              ),
              const SizedBox(width: 10),
              MiuixButton(
                key: const Key('register-send-code-button'),
                enabled: _registrationEnabled &&
                    !_sendingCode &&
                    !_codeSent &&
                    !_registering,
                onPressed: _sendCode,
                child: MiuixText(
                  _codeSent
                      ? '$_countdown 秒'
                      : (_sendingCode ? '发送中…' : '发送验证码'),
                  style: theme.textStyles.button,
                ),
              ),
            ],
          ),
        ),
        if (_codeError != null) _FieldError(_codeError!),
        const SizedBox(height: 20),
        _RegisterButton(
          isRegistering: _registering,
          enabled: _registrationEnabled && !_sendingCode,
          onPressed: _register,
        ),
      ],
    );
  }
}

/// 注册提交按钮：整行宽，与登录 [_SubmitButton] 同构。
class _RegisterButton extends StatelessWidget {
  const _RegisterButton({
    required this.isRegistering,
    required this.enabled,
    required this.onPressed,
  });

  final bool isRegistering;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: MiuixButton(
        key: const Key('register-submit-button'),
        enabled: enabled,
        colors: MiuixButtonDefaults.buttonColorsPrimary(context),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isRegistering) ...[
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
              isRegistering ? '正在注册…' : '注册',
              style: theme.textStyles.button,
            ),
          ],
        ),
      ),
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
