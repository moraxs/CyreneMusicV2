import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取自 AMLL 的播放器图标必须都能被 flutter_svg 解析。
///
/// 这些 SVG 是从 applemusic-like-lyrics 的 react-full 包原样拷进来的，里头有
/// `currentColor`、CSS class（如 `class="amll-forward-left-arrow"`）这类 Web
/// 味儿很重的写法。flutter_svg 对 CSS 的支持有限，解析失败时不会抛在编译期，
/// 而是到运行时才变成一个空白方块 —— 所以在这儿一次性全部渲染一遍兜住。
void main() {
  const icons = <String>[
    // 播放控制（本来就在用，一并回归）
    'assets/icons/icon_play.svg',
    'assets/icons/icon_pause.svg',
    'assets/icons/icon_rewind.svg',
    'assets/icons/icon_forward.svg',
    // 本次新增
    'assets/icons/icon_shuffle.svg',
    'assets/icons/icon_shuffle_active.svg',
    'assets/icons/icon_repeat.svg',
    'assets/icons/icon_repeat_active.svg',
    'assets/icons/icon_repeat_one_active.svg',
    'assets/icons/icon_lyrics_on.svg',
    'assets/icons/icon_lyrics_off.svg',
    'assets/icons/icon_playlist_on.svg',
    'assets/icons/icon_playlist_off.svg',
    'assets/icons/icon_star.svg',
    'assets/icons/icon_star_filled.svg',
    'assets/icons/icon_more.svg',
    'assets/icons/icon_airplay.svg',
    'assets/icons/icon_info.svg',
    'assets/icons/icon_list_bullet.svg',
  ];

  for (final asset in icons) {
    testWidgets('$asset 能解析并渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SvgPicture.asset(
                asset,
                width: 32,
                height: 32,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      );
      // SvgPicture 走异步解码，pumpAndSettle 等它落地；解析失败会在此抛出。
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
