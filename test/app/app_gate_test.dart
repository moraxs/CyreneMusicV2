/// 首启引导落点推导的回归测试。
///
/// [resolveOnboardingStep] 是整个引导流程的大脑：它决定用户看到哪一步、
/// 什么时候放行进主界面。这里守住需求里的每条规则，尤其是「用户手动退出
/// 账号后跳回第一步登录」——那条在引导已完成之后依然必须生效。
library;

import 'package:cyrene_music_reborn/app/app_gate.dart';
import 'package:cyrene_music_reborn/features/onboarding/onboarding_steps.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各参数默认取「全新用户」的状态，测试只覆写自己关心的那几个。
OnboardingStep? resolve({
  bool termsAccepted = false,
  bool onboardingCompleted = false,
  bool isLoggedIn = false,
  bool audioSourceDone = false,
  bool styleSettingsDone = false,
}) => resolveOnboardingStep(
  termsAccepted: termsAccepted,
  onboardingCompleted: onboardingCompleted,
  isLoggedIn: isLoggedIn,
  audioSourceDone: audioSourceDone,
  styleSettingsDone: styleSettingsDone,
);

void main() {
  group('全新用户按顺序走完四步', () {
    test('第一步：什么都没做时停在协议', () {
      expect(resolve(), OnboardingStep.terms);
    });

    test('第二步：同意协议后要求登录', () {
      expect(resolve(termsAccepted: true), OnboardingStep.login);
    });

    test('第三步：登录后要求配音源', () {
      expect(
        resolve(termsAccepted: true, isLoggedIn: true),
        OnboardingStep.audioSource,
      );
    });

    test('第四步：越过音源步后进入样式设置', () {
      expect(
        resolve(termsAccepted: true, isLoggedIn: true, audioSourceDone: true),
        OnboardingStep.styleSettings,
      );
    });

    test('完成样式设置并标记完成后放行进主界面', () {
      expect(
        resolve(
          termsAccepted: true,
          isLoggedIn: true,
          audioSourceDone: true,
          styleSettingsDone: true,
        ),
        isNull,
      );
    });
  });

  group('协议是硬门槛', () {
    test('即便已登录且走完引导，未同意协议仍停在第一步', () {
      expect(
        resolve(
          isLoggedIn: true,
          audioSourceDone: true,
          styleSettingsDone: true,
        ),
        OnboardingStep.terms,
      );
    });
  });

  group('退出登录后回到第二步', () {
    test('引导已完成的老用户退出登录 → 登录步', () {
      expect(
        resolve(
          termsAccepted: true,
          onboardingCompleted: true,
          isLoggedIn: false,
        ),
        OnboardingStep.login,
      );
    });

    test('重新登录后直接回主界面，不再重走音源与样式步', () {
      expect(
        resolve(
          termsAccepted: true,
          onboardingCompleted: true,
          isLoggedIn: true,
        ),
        isNull,
      );
    });
  });

  group('老用户兼容', () {
    test('历史已完成的用户（第四步标记缺省）直接进主界面', () {
      // onboardingCompleted=true，但新加的 audioSourceDone/styleSettingsDone
      // 对老用户都是 false——不能被重新要求走一遍。
      expect(
        resolve(termsAccepted: true, onboardingCompleted: true, isLoggedIn: true),
        isNull,
      );
    });
  });
}
