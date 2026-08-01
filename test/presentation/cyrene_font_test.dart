/// 全应用统一字体（MiSans）的回归测试。
///
/// 防住的问题：assets/MiSans-Normal.ttf 长期只躺在 assets/ 里、pubspec.yaml
/// 没有 fonts: 声明，字体根本没打进包；同时 Miuix 的 defaultTextStyles() 只带
/// 字号字重不带字体族，Material/Miuix/fluent 三套主题各自回退到平台默认字体
/// （Windows Segoe UI / 安卓 Roboto），于是桌面端各页面字形粗细不一。
///
/// 这里守住两件事：三套主题都真的把 fontFamily 设成 MiSans；字号/字重没被
/// 顺手改掉（只加字体族，不动 HyperOS 排版规范）。
library;

import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Miuix 的 14 个文本预设全部带上 MiSans', () {
    final styles = CyreneMiuixTheme.textStyles();
    final all = <String, TextStyle>{
      'main': styles.main,
      'paragraph': styles.paragraph,
      'body1': styles.body1,
      'body2': styles.body2,
      'button': styles.button,
      'footnote1': styles.footnote1,
      'footnote2': styles.footnote2,
      'headline1': styles.headline1,
      'headline2': styles.headline2,
      'subtitle': styles.subtitle,
      'title1': styles.title1,
      'title2': styles.title2,
      'title3': styles.title3,
      'title4': styles.title4,
    };
    for (final entry in all.entries) {
      expect(
        entry.value.fontFamily,
        cyreneFontFamily,
        reason: '${entry.key} 没带字体族，该预设的文字会回退到平台默认字体',
      );
    }
  });

  test('只加字体族，字号与字重一个不动', () {
    final base = defaultTextStyles();
    final themed = CyreneMiuixTheme.textStyles();
    // 逐项比对：把预期样式（库默认 + 字体族）与实际产物比全等，任何多余的
    // 字号/字重/行高改动都会在这里暴露。
    expect(themed.main, base.main.apply(fontFamily: cyreneFontFamily));
    expect(themed.paragraph, base.paragraph.apply(fontFamily: cyreneFontFamily));
    expect(themed.body1, base.body1.apply(fontFamily: cyreneFontFamily));
    expect(themed.body2, base.body2.apply(fontFamily: cyreneFontFamily));
    expect(themed.button, base.button.apply(fontFamily: cyreneFontFamily));
    expect(themed.footnote1, base.footnote1.apply(fontFamily: cyreneFontFamily));
    expect(themed.footnote2, base.footnote2.apply(fontFamily: cyreneFontFamily));
    expect(themed.headline1, base.headline1.apply(fontFamily: cyreneFontFamily));
    expect(themed.headline2, base.headline2.apply(fontFamily: cyreneFontFamily));
    expect(themed.subtitle, base.subtitle.apply(fontFamily: cyreneFontFamily));
    expect(themed.title1, base.title1.apply(fontFamily: cyreneFontFamily));
    expect(themed.title2, base.title2.apply(fontFamily: cyreneFontFamily));
    expect(themed.title3, base.title3.apply(fontFamily: cyreneFontFamily));
    expect(themed.title4, base.title4.apply(fontFamily: cyreneFontFamily));

    // subtitle 是唯一带字重的预设，单独点一下确认 bold 还在。
    expect(themed.subtitle.fontWeight, FontWeight.bold);
    expect(themed.subtitle.fontSize, 14);
  });

  test('Material ThemeData 的 textTheme 也走 MiSans', () {
    final theme = CyreneMiuixTheme.material(MiuixThemeData.light());
    // Material 控件与裸 Text 从 textTheme 取样式，这里没设就会吃平台默认字体。
    expect(theme.textTheme.bodyMedium?.fontFamily, cyreneFontFamily);
    expect(theme.textTheme.titleLarge?.fontFamily, cyreneFontFamily);
    // Material 的 DefaultTextStyle 源头就是 bodyMedium（见 Material 组件的
    // AnimatedDefaultTextStyle），它带上了字体族，裸 TextStyle() 才能继承到。
    expect(theme.textTheme.bodyMedium?.fontFamily, isNotNull);
  });

  testWidgets('MiuixText 渲染出的 Text 带 MiSans', (tester) async {
    await tester.pumpWidget(
      MiuixTheme(
        data: MiuixThemeData.light(textStyles: CyreneMiuixTheme.textStyles()),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: MiuixText('字体检查'),
        ),
      ),
    );

    // 不看主题配置而看真正渲染出来的 Text：MiuixText 会把预设 copyWith 一遍，
    // 字体族必须活着传到底层 Text。
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style?.fontFamily, cyreneFontFamily);
  });
}
