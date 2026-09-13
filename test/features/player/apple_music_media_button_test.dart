import 'package:cyrene_music_reborn/features/player/mobile/widgets/apple_music/apple_music_media_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppleMusicMediaButton] 的行为约束。
void main() {
  Widget host({VoidCallback? onPressed, String asset = 'assets/icons/icon_play.svg'}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: AppleMusicMediaButton(
            asset: asset,
            semanticLabel: '播放',
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  testWidgets('点击触发回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(onPressed: () => taps++));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppleMusicMediaButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('onPressed 为 null 时不可点，且图标置灰', (tester) async {
    await tester.pumpWidget(host(onPressed: null));
    await tester.pumpAndSettle();

    // 点下去不该抛异常，也不该有任何反应。
    await tester.tap(find.byType(AppleMusicMediaButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final semantics = tester.getSemantics(find.byType(AppleMusicMediaButton));
    expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
  });

  testWidgets('按下时出现圆形底色，松手后退去', (tester) async {
    await tester.pumpWidget(host(onPressed: () {}));
    await tester.pumpAndSettle();

    Color? bg() {
      final c = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppleMusicMediaButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    expect(bg(), Colors.transparent);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(AppleMusicMediaButton)));
    await tester.pump();
    // AMLL 的 `&:active { background-color: #fff2 }`，约白 13%。
    expect(bg()!.a, closeTo(0.13, 0.01));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(bg(), Colors.transparent);
  });

  testWidgets('点击后播放一段 1 → 0.85 → 1.1 → 1 的缩放，并回到原大小', (tester) async {
    await tester.pumpWidget(host(onPressed: () {}));
    await tester.pumpAndSettle();

    double scale() {
      final t = tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(AppleMusicMediaButton),
          matching: find.byType(ScaleTransition),
        ),
      );
      return t.scale.value;
    }

    expect(scale(), closeTo(1.0, 0.001));

    await tester.tap(find.byType(AppleMusicMediaButton));

    var minSeen = 2.0;
    var maxSeen = 0.0;
    // 动画全长 700ms，逐帧采样。
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = scale();
      if (s < minSeen) minSeen = s;
      if (s > maxSeen) maxSeen = s;
    }

    expect(minSeen, lessThan(0.9), reason: '应先缩到 0.85 附近');
    expect(maxSeen, greaterThan(1.05), reason: '随后应过冲到 1.1 附近');

    await tester.pumpAndSettle();
    expect(scale(), closeTo(1.0, 0.001), reason: '最终必须回到原大小');
  });
}
