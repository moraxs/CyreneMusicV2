import 'package:cyrene_music_reborn/features/player/classic_record_stage.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/lyric_parser.dart';
import 'package:cyrene_music_reborn/features/player/mobile/compat/player_service.dart';
import 'package:cyrene_music_reborn/features/settings/player_style_preview.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

/// 样式预览的核心不变量：真实组件能在「没有播放上下文」的设置页里跑起来，
/// 且不碰任何全局状态。
void main() {
  test('示例曲目的逐字歌词可被解析，定格进度落在某个词的中段', () {
    final lyrics = LyricParser.parseNeteaseLyric(
      previewTrack.lyric!,
      yrcLyric: previewTrack.yrc,
    );
    // YRC 优先：解析结果必须带逐字数据，否则 SuperCyrene 会退化成逐行高亮，
    // 预览就看不出「逐字」这个卖点了。
    expect(lyrics, hasLength(7));
    expect(lyrics.every((line) => line.hasWordByWord), isTrue);

    final index = LyricParser.findCurrentLineIndex(lyrics, previewPosition);
    final line = lyrics[index];
    expect(line.text, '让星光落进你眼底');

    // 定格点必须落在某个词的内部（而非词与词的边界），这样高亮会停在半个词上。
    final word = line.words!.firstWhere(
      (word) =>
          previewPosition >= word.startTime &&
          previewPosition < word.startTime + word.duration,
    );
    expect(word.text, '落进');
    expect(previewPosition, greaterThan(word.startTime));
  });

  testWidgets('预览渲染真实组件，且不绑定全局 PlayerService', (tester) async {
    final preview = PreviewPlayback();
    addTearDown(preview.dispose);
    await preview.seed();

    // 示例曲目经 restore() 进入 controller —— 没有走 playTrack()，因此不会
    // 触发音源解析与网络请求。
    expect(preview.controller.state.currentTrack?.name, '晚风与星光');
    expect(preview.controller.positionListenable.value, previewPosition);

    await tester.pumpWidget(
      _testApp(
        Center(
          child: SizedBox(
            width: 254,
            height: 190,
            child: DesktopClassicPreview(playback: preview.controller),
          ),
        ),
      ),
    );
    await tester.pump();

    // 真实黑胶唱台，而非手绘示意图。
    expect(find.byType(ClassicRecordStage), findsOneWidget);
    // 歌词组件解析出了内容（没有落到「暂无歌词」占位）。
    expect(find.text('暂无歌词'), findsNothing);

    // 最要紧的一条：预览全程没有 bind 全局单例，真实播放器状态不受污染。
    expect(PlayerService().currentTrack, isNull);
    expect(PlayerService().isPlaying, isFalse);
  });

  testWidgets('SuperCyrene 预览按歌词主题分派，四种主题都能渲染', (tester) async {
    final preview = PreviewPlayback();
    addTearDown(preview.dispose);
    await preview.seed();

    for (final theme in ['default', 'pixel', 'chat', 'sonnet']) {
      await tester.pumpWidget(
        _testApp(
          Center(
            child: SizedBox(
              width: 254,
              height: 190,
              child: SuperCyrenePreview(
                playback: preview.controller,
                lyricsTheme: theme,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '主题 $theme 渲染抛异常');
    }

    expect(PlayerService().currentTrack, isNull);
  });

  testWidgets('移动经典预览是纯静态复刻，不依赖 controller', (tester) async {
    await tester.pumpWidget(_testApp(const MobileClassicPreview()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('晚风与星光'), findsOneWidget);
    expect(PlayerService().currentTrack, isNull);
  });
}

Widget _testApp(Widget home) => MiuixSystemTheme(
  child: Builder(
    builder: (context) => MaterialApp(
      theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
      home: Scaffold(body: home),
    ),
  ),
);
