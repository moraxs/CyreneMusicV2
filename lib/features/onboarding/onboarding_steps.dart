import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 首启引导的四个步骤。顺序即用户看到的顺序。
///
/// 步骤本身不持久化——当前该停在哪一步由 [resolveOnboardingStep] 从
/// 「协议是否已同意 / 是否已登录 / 音源与样式是否已配置」等真实状态推导。这样
/// 无论中途被杀进程、还是事后主动退出登录，落点都由状态说了算，不会出现
/// 「进度记着第 3 步、但其实已经退出登录」的错位。
enum OnboardingStep {
  /// 第一步：阅读并同意免责协议。
  terms,

  /// 第二步：登录账号。用户手动退出登录后也会回到这一步。
  login,

  /// 第三步：配置音源。
  audioSource,

  /// 第四步：选择播放器样式与桌面/任务栏播放器。
  styleSettings;

  String get title => switch (this) {
    OnboardingStep.terms => '免责协议',
    OnboardingStep.login => '登录账号',
    OnboardingStep.audioSource => '设置音源',
    OnboardingStep.styleSettings => '样式设置',
  };

  String get subtitle => switch (this) {
    OnboardingStep.terms => '请完整阅读以下条款，滑动到底部后即可继续',
    OnboardingStep.login => '登录以同步你的歌单、收藏与听歌记录',
    OnboardingStep.audioSource => '至少启用一个音源，才能解析并播放在线歌曲',
    OnboardingStep.styleSettings => '选择全屏播放器风格，桌面端可开启桌面与任务栏播放器',
  };
}

/// 顶部进度指示：4 个圆点，当前步的圆点丝滑扩宽成胶囊形。
///
/// 仅在同意协议后由 [OnboardingPage] 渲染（此时已在第二步登录）。配色走 Miuix
/// 语义角色：已完成打勾、当前步胶囊显序号、未到达为空圆。圆点之间无连接线——
/// 胶囊本身已足够标示「现在在哪」，连线只会让胶囊变形时视觉打架。
class OnboardingProgressHeader extends StatelessWidget {
  const OnboardingProgressHeader({super.key, required this.current});

  final OnboardingStep current;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in OnboardingStep.values) ...[
              if (step.index > 0) const SizedBox(width: 10),
              _StepDot(
                index: step.index,
                done: step.index < current.index,
                active: step == current,
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(
          current.title,
          textAlign: TextAlign.center,
          style: theme.textStyles.title2.copyWith(
            color: colors.onBackground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          current.subtitle,
          textAlign: TextAlign.center,
          style: theme.textStyles.body2.copyWith(
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.done,
    required this.active,
  });

  final int index;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    // 已完成与进行中都用 primary：已完成打勾、进行中显序号，靠图形区分而非
    // 再引入一个绿色——引导页整体只用主题色一个强调色。
    final filled = done || active;
    // 当前步扩宽成胶囊（56×26、圆角 13），其余为 26×26 圆形；320ms easeOut
    // 让宽度变化丝滑，而非瞬间跳变。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      width: active ? 56 : 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? colors.primary : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(13),
      ),
      child: done
          ? MiuixIcon(
              vector: MiuixIcons.basic.check,
              size: 14,
              tint: colors.onPrimary,
            )
          : Text(
              '${index + 1}',
              style: theme.textStyles.footnote1.copyWith(
                color: active ? colors.onPrimary : colors.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// 底部主操作条：整行宽的主按钮 + 可选的次级按钮。
///
/// 三步共用同一个底栏，位置与高度恒定——按钮在步骤间不跳动，点击热区稳定。
class OnboardingActionBar extends StatelessWidget {
  const OnboardingActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.busy = false,
    this.secondary,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool busy;

  /// 次级操作（如「暂不登录」），显示在主按钮下方。
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: MiuixButton(
            key: const Key('onboarding-primary-action'),
            enabled: enabled && !busy,
            minHeight: 50,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
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
                MiuixText(label, style: theme.textStyles.button),
              ],
            ),
          ),
        ),
        if (secondary != null) ...[const SizedBox(height: 6), secondary!],
      ],
    );
  }
}
