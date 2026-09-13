import 'package:cyrene_music_reborn/features/player/mobile/widgets/apple_music/apple_music_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppleMusicProgressBar] 的行为约束。
///
/// 这条进度条对标 AMLL 的 BouncingSlider：**没有圆形滑块**，靠轨道本身按下变粗。
/// 之前那版是 Material [Slider] + 自定义 thumb，所以这里专门钉住「不许再冒出
/// 一个 Slider / thumb」这件事。
void main() {
  Widget host({
    required double value,
    ValueChanged<double>? onSeek,
    ValueChanged<double>? onSeekEnd,
    List<Map<String, int>>? chorusTimes,
    double durationMs = 200000,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: AppleMusicProgressBar(
              value: value,
              onSeek: onSeek ?? (_) {},
              onSeekEnd: onSeekEnd,
              chorusTimes: chorusTimes,
              durationMs: durationMs,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('不再使用 Material Slider，也没有滑块', (tester) async {
    await tester.pumpWidget(host(value: 0.5));
    expect(find.byType(Slider), findsNothing,
        reason: 'Apple Music 风格进度条不该退回 Material Slider');
  });

  testWidgets('触摸热区高度约 37px（AMLL 的 1.16em * 2）', (tester) async {
    await tester.pumpWidget(host(value: 0.5));
    final size = tester.getSize(find.byType(AppleMusicProgressBar));
    expect(size.height, closeTo(37, 0.5));
  });

  testWidgets('点击位置换算成进度回报出去', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(host(value: 0, onSeek: seeks.add));

    final bar = find.byType(AppleMusicProgressBar);
    final topLeft = tester.getTopLeft(bar);
    final size = tester.getSize(bar);
    // 点在四分之一处。
    await tester.tapAt(
      Offset(topLeft.dx + size.width * 0.25, topLeft.dy + size.height / 2),
    );
    await tester.pump();

    expect(seeks, isNotEmpty);
    expect(seeks.first, closeTo(0.25, 0.02));
  });

  testWidgets('拖动过程中持续回报，松手回报最终值', (tester) async {
    final seeks = <double>[];
    double? ended;
    await tester.pumpWidget(
      host(value: 0, onSeek: seeks.add, onSeekEnd: (v) => ended = v),
    );

    final bar = find.byType(AppleMusicProgressBar);
    final topLeft = tester.getTopLeft(bar);
    final size = tester.getSize(bar);
    final y = topLeft.dy + size.height / 2;

    final gesture = await tester.startGesture(Offset(topLeft.dx + 10, y));
    await tester.pump();
    await gesture.moveTo(Offset(topLeft.dx + size.width * 0.5, y));
    await tester.pump();
    await gesture.moveTo(Offset(topLeft.dx + size.width * 0.8, y));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(seeks.length, greaterThanOrEqualTo(2));
    expect(seeks.last, closeTo(0.8, 0.02));
    expect(ended, closeTo(0.8, 0.02));
  });

  /// 读出当前实际绘制的轨道高度 / 填充透明度。
  AppleMusicProgressBarPainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AppleMusicProgressBar),
        matching: find.byType(CustomPaint),
      ),
    );
    return paint.painter! as AppleMusicProgressBarPainter;
  }

  testWidgets('按下后轨道由 6.4px 弹到 15.12px，松手收回', (tester) async {
    await tester.pumpWidget(host(value: 0.5));

    // 静息高度就是 AMLL 的 80 * 0.08。
    expect(painterOf(tester).trackHeight, closeTo(6.4, 0.01));
    expect(painterOf(tester).fillOpacity, closeTo(0.4, 0.001));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppleMusicProgressBar)),
    );

    // 弹簧由 Ticker 驱动，推进到收敛。damping 10 / stiffness 150 是欠阻尼
    // （阻尼比约 0.41），所以中途会冲过目标再荡回来 —— AMLL 管它叫
    // BouncingSlider 就是这个意思，这里把超调也一并钉住。
    var peak = 0.0;
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final h = painterOf(tester).trackHeight;
      if (h > peak) peak = h;
    }

    expect(peak, greaterThan(15.12),
        reason: '欠阻尼弹簧应当冲过目标高度（这是 Bouncing 的来源）');
    expect(painterOf(tester).trackHeight, closeTo(15.12, 0.1),
        reason: '收敛后停在 AMLL 的 189 * 0.08 = 15.12px');
    // CSS `:active` 把已播放部分从 0.4 提到 0.9。
    expect(painterOf(tester).fillOpacity, closeTo(0.9, 0.001));

    await gesture.up();
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(painterOf(tester).trackHeight, closeTo(6.4, 0.1),
        reason: '松手后应收回静息高度');
    expect(painterOf(tester).fillOpacity, closeTo(0.4, 0.001));
  });

  testWidgets('弹簧收敛后停掉 Ticker，不再逐帧重建', (tester) async {
    await tester.pumpWidget(host(value: 0.5));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppleMusicProgressBar)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    // pumpAndSettle 会在仍有动画驱动时超时，能settle说明 ticker 已停。
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('带副歌区间时能正常绘制，不抛异常', (tester) async {
    await tester.pumpWidget(host(
      value: 0.3,
      durationMs: 200000,
      chorusTimes: const [
        {'startTime': 40000, 'endTime': 70000},
        {'startTime': 120000, 'endTime': 150000},
      ],
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('durationMs 为 0 时不因除零崩溃', (tester) async {
    await tester.pumpWidget(host(
      value: 0,
      durationMs: 0,
      chorusTimes: const [
        {'startTime': 0, 'endTime': 1000},
      ],
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
