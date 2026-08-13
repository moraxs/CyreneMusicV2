import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../application/auth/account_session_controller.dart';
import '../../application/stores/onboarding_store.dart';
import '../../app/desktop/window_caption_bar.dart';
import '../../presentation/cyrene/cyrene_aurora_backdrop.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../settings/audio_source_settings_page.dart';
import '../settings/login_page.dart';
import '../settings/player_style_settings_body.dart';
import '../settings/user_agreement_page.dart';
import 'onboarding_steps.dart';

/// 首次启动引导页：免责协议 → 登录账号 → 设置音源 → 样式设置。
///
/// 四步的正文全部复用既有组件（[UserAgreementBody] / [LoginView] /
/// [AudioSourceSettingsBody] / [PlayerStyleSettingsBody]），本页只负责外壳：
/// 光斑背景、进度指示、底部操作条与步骤间的推进。复用而非重写是刻意的——
/// 协议文本、登录校验、音源增删、样式切换逻辑各自只有一份，引导页与设置页
/// 不会随时间分叉。
///
/// 当前停在哪一步由外部（[AppGate]）根据真实状态算好后传进来，本页不自持
/// 进度：用户在第 3 步退出登录、或登录态过期，外部会立即把 [step] 切回登录
/// 步，无需本页参与。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.step,
    required this.account,
    required this.audioSources,
    required this.onAudioSourceDone,
    required this.onCompleted,
  });

  final OnboardingStep step;
  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;

  /// 越过音源配置步（第三步 → 第四步）时回调，由外部落「音源步已完成」标记。
  final VoidCallback onAudioSourceDone;

  /// 四步全部走完时回调，由外部落「引导已完成」标记并进主界面。
  final VoidCallback onCompleted;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _agreementScrollController = ScrollController();

  /// 登录/注册表单的句柄：登录步是硬门槛（不支持跳过），底部操作条用它在
  /// 「注册新账号 / 已有账号直接登录」之间联动。
  final _loginViewKey = GlobalKey<LoginViewState>();

  /// 表单尚未挂载（首帧）时 [ValueListenableBuilder] 的兜底监听源；挂载后
  /// 即被 [LoginViewState.registerMode] 取代。恒为 false，只占位不驱动 UI。
  final _registerModeFallback = ValueNotifier<bool>(false);

  /// 协议是否已读到底部。未读完不允许同意（与原版 mobile_setup_page 一致）。
  var _agreementReadToEnd = false;

  /// 当前查看的步骤。`widget.step` 是 AppGate 推导的「最靠前未完成步」，本页
  /// 不持有进度。`_viewStep` 可在 [login, widget.step] 区间内向后漂移，供用户
  /// 左右滑动回看已解锁的步骤；`widget.step` 前进/后退时 _viewStep 都 clamp 跟上。
  late OnboardingStep _viewStep;

  @override
  void initState() {
    super.initState();
    _viewStep = widget.step;
    _agreementScrollController.addListener(_onAgreementScroll);
    // 协议短到不足一屏时（大字体 / 平板 / 桌面宽窗）永远不会触发滚动回调，
    // 按钮就会永久卡在禁用态。首帧后按「内容是否可滚动」直接放行。
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAgreementScroll());
  }

  @override
  void didUpdateWidget(covariant OnboardingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // widget.step 是真实进度（AppGate 推导）。它前进时，视图跟上不留在旧步；
    // 它后退时（如登出），视图也跟随。结果：_viewStep 永远 ≤ widget.step，
    // 只有用户主动滑动时 _viewStep 才会落到 widget.step 之前。
    if (widget.step != oldWidget.step) {
      final next = widget.step;
      if (next.index > _viewStep.index || next.index < _viewStep.index) {
        _viewStep = next;
      }
    }
  }

  @override
  void dispose() {
    _registerModeFallback.dispose();
    _agreementScrollController
      ..removeListener(_onAgreementScroll)
      ..dispose();
    super.dispose();
  }

  void _onAgreementScroll() {
    if (_agreementReadToEnd || !_agreementScrollController.hasClients) return;
    final position = _agreementScrollController.position;
    // maxScrollExtent 为 0 即内容不足一屏，视为已读完（见 initState）。
    final atEnd = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 20;
    if (atEnd && mounted) setState(() => _agreementReadToEnd = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      // 显式给不透明底色：桌面端窗口本身是透明的（为透出 Win11 云母/亚克力），
      // 引导页不接主界面那套材质，若不铺底就会直接露出 DWM 的深色背景，浅色
      // 模式下整页看着是暗的。这里恒取主题 surface，明暗随主题走。
      containerColor: theme.colors.surface,
      content: (padding) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 光斑层横跨整个引导流程：挂在步骤切换之外，步骤间过渡时背景
            // 保持静止，不会跟着重绘或跳色。
            const Positioned.fill(child: CyreneAuroraBackdrop()),
            Column(
              children: [
                // 原生标题栏已在 main 里隐藏，引导页不经过 DesktopShell，
                // 必须自绘一条，否则窗口拖不动、也没有最小化/关闭按钮。
                // 移动端该组件塌缩为零高度。
                const WindowCaptionBar(),
                Expanded(
                  child: SafeArea(
                    // 标题栏已占掉顶部，SafeArea 不必再避让上边。
                    top: !WindowCaptionBar.isSupported,
                    child: Center(
                      child: ConstrainedBox(
                        // 桌面宽窗下不让内容拉成一整行，与登录页 460 同宽收敛。
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          children: [
                            // 圆点进度头仅在同意协议后渲染（此时已在 login 步及之后）。
                            // terms 步无圆点头，正文自然上移。
                            if (_viewStep != OnboardingStep.terms)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  20,
                                  24,
                                  20,
                                ),
                                child: OnboardingProgressHeader(
                                  current: _viewStep,
                                ),
                              ),
                            Expanded(
                              // 滑动手势包在正文区：左右滑动在已解锁步骤间切换
                              // （区间 [login, widget.step]，见 _goToStep）。只用
                              // drag-end 判方向，不实现 start/update，避免抢子树
                              // （ListView 垂直滚动）的手势。
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragEnd: _onHorizontalDragEnd,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  // 步骤各自持有滚动位置与输入焦点，切换时必须整棵
                                  // 子树换掉，否则 AnimatedSwitcher 会复用上一步的
                                  // State。
                                  child: KeyedSubtree(
                                    key: ValueKey(_viewStep),
                                    child: _buildStepBody(),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                // 键盘弹出时（登录步骤）底栏跟着上移，按钮不被遮住。
                                16 + MediaQuery.viewInsetsOf(context).bottom,
                              ),
                              child: _buildActionBar(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() => switch (_viewStep) {
    // 协议正文关在卡片里：与背景光斑拉开层次，也让「可滚动区域到哪为止」
    // 一眼可见——用户得知道自己要把哪一块读到底。
    OnboardingStep.terms => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: MiuixCard(
        insideMargin: EdgeInsets.zero,
        child: UserAgreementBody(
          controller: _agreementScrollController,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        ),
      ),
    ),
    // 登录成功不在这里跳转：AppGate 监听会话状态，登录态一变就把 step 推到
    // 下一步，本页只管把表单画出来。注册入口交给底部操作条的「注册」按钮，
    // 故隐藏表单内的注册链接（showRegisterSwitch: false）。
    OnboardingStep.login => LoginView(
      key: _loginViewKey,
      account: widget.account,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      showRegisterSwitch: false,
    ),
    OnboardingStep.audioSource => AudioSourceSettingsBody(
      controller: widget.audioSources,
      account: widget.account,
      topPadding: EdgeInsets.zero,
      // 已登录才显示 Cyrene Premium 区块（购买后自动下发官方音源），这正是
      // 引导把登录排在音源前面的原因。
      token: widget.account.state.isLoggedIn ? widget.account.token : null,
    ),
    OnboardingStep.styleSettings => const PlayerStyleSettingsBody(),
  };

  Widget _buildActionBar() => switch (_viewStep) {
    OnboardingStep.terms => OnboardingActionBar(
      label: _agreementReadToEnd ? '同意并继续' : '请滑动阅读至底部',
      enabled: _agreementReadToEnd,
      onPressed: OnboardingStore.instance.acceptTerms,
    ),
    // 登录步骤：登录是硬门槛，底部不留「暂不登录」退路。提交按钮在表单内
    // （[LoginView] 自带），底栏用小按钮在两模式间互切注册/登录，随表单当前
    // 模式联动文案与动作。
    OnboardingStep.login => ValueListenableBuilder<bool>(
      valueListenable:
          _loginViewKey.currentState?.registerMode ?? _registerModeFallback,
      builder: (context, registering, _) => Align(
        alignment: Alignment.center,
        child: MiuixTextButton(
          registering ? '已有账号？直接登录' : '没有账号？注册新账号',
          onPressed: () => registering
              ? _loginViewKey.currentState?.switchToLogin()
              : _loginViewKey.currentState?.switchToRegister(),
        ),
      ),
    ),
    // 音源步骤：启用一个音源后「下一步」进入样式设置；也可跳过（一样进下一步，
    // 只是以后没音源放不了在线歌）。
    OnboardingStep.audioSource => AnimatedBuilder(
      animation: widget.audioSources,
      builder: (context, _) {
        final hasEnabledSource = widget.audioSources.state.sources.any(
          (source) => source.isEnabled,
        );
        return OnboardingActionBar(
          label: hasEnabledSource ? '下一步' : '请先添加并启用一个音源',
          enabled: hasEnabledSource,
          onPressed: widget.onAudioSourceDone,
          secondary: MiuixTextButton('跳过，稍后在设置里配置', onPressed: _skipAudioSource),
        );
      },
    ),
    // 样式设置是最后一步：选择完毕即完成整个引导。
    OnboardingStep.styleSettings => OnboardingActionBar(
      label: '完成设置，开始使用',
      onPressed: widget.onCompleted,
    ),
  };

  Future<void> _skipAudioSource() async {
    final confirmed = await _confirmSkip(
      title: '跳过音源配置？',
      summary: '没有可用音源时无法解析在线歌曲，搜索到的歌会播放失败。'
          '你可以随时在「设置 → 播放与音源」里补上。',
    );
    // 跳过音源不等于跳过引导：仍要进样式设置步，最后统一完成。
    if (confirmed == true) widget.onAudioSourceDone();
  }

  /// 左右滑动切换步骤：仅在已解锁区间 [login, widget.step] 内移动。
  /// - 手指向右（primaryVelocity < 0）= 回退一步
  /// - 手指向左（primaryVelocity > 0）= 前进一步
  /// 小幅滑动（|v| < 400）忽略，避免误触。clamp 保证不能滑过 widget.step
  /// （未到达的步）也不能回到 terms（硬门槛、圆点不渲染）。
  void _onHorizontalDragEnd(DragEndDetails details) {
    const threshold = 400.0;
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < threshold) return;
    final target = v < 0 ? _viewStep.index - 1 : _viewStep.index + 1;
    _goToStep(target);
  }

  void _goToStep(int targetIndex) {
    final clamped = targetIndex.clamp(
      OnboardingStep.login.index,
      widget.step.index,
    );
    if (clamped == _viewStep.index) return;
    setState(() => _viewStep = OnboardingStep.values[clamped]);
  }

  Future<bool?> _confirmSkip({
    required String title,
    required String summary,
  }) => showCyreneDialog<bool>(
    context: context,
    title: title,
    summary: summary,
    builder: (dialogContext, dismiss) {
      final theme = MiuixTheme.of(dialogContext);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MiuixTextButton('返回', onPressed: () => dismiss(false)),
              const SizedBox(width: 10),
              MiuixButton(
                onPressed: () => dismiss(true),
                child: MiuixText('确认跳过', style: theme.textStyles.button),
              ),
            ],
          ),
        ],
      );
    },
  );
}
