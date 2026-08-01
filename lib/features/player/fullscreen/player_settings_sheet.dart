import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../application/stores/fullscreen_settings_store.dart';
import '../../../domain/lyrics/lyric_fonts.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/playback/player_display_settings.dart';
import '../../../presentation/cyrene/cyrene_overlays.dart';

/// 全屏播放器「更多」设置底部面板（对应 Next.js PlayerSettingsMenu 的移动端 Sheet）。
///
/// Miuix 底部抽屉（[showCyreneSheet] -> [MiuixOverlayBottomSheet]）+ Miuix 偏好组件，
/// 跟随系统明暗主题。开关项：音频律动 / 沉浸模式 / 隐藏封面；歌词样式分段
/// （滚动/轮盘/单行）+ 单行动画分段（仅单行时）；歌词字体下拉；歌词字号、背景模糊滑块。
///
/// 桌面歌词、播放器背景等依赖桌面/平台能力的项在移动端从略。
class PlayerSettingsSheet extends StatefulWidget {
  const PlayerSettingsSheet({super.key, required this.trackSource});

  /// 当前曲目来源，用于判断是否展示「心动模式」（仅网易云，暂未实现）。
  final MusicSource? trackSource;

  static Future<void> show(BuildContext context, {MusicSource? trackSource}) =>
      showCyreneSheet<void>(
        context: context,
        title: '播放器设置',
        builder: (context, dismiss) =>
            PlayerSettingsSheet(trackSource: trackSource),
      );

  @override
  State<PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<PlayerSettingsSheet> {
  FullscreenSettingsStore get _store => FullscreenSettingsStore.instance;

  @override
  Widget build(BuildContext context) {
    // 内容可能较高（单行模式下多一条分段），用约束 + shrinkWrap ListView 收口，
    // 参照 appearance_settings 歌词字体子面板的写法。
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: _sections(context),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final children = <Widget>[
      const MiuixSmallTitle('播放', insideMargin: EdgeInsets.zero),
      MiuixSwitchPreference(
        title: '音频律动',
        value: _store.audioVisualization,
        onChanged: (_) => _store.toggleAudioVisualization(),
      ),
      MiuixSwitchPreference(
        title: '沉浸模式',
        value: _store.isImmersiveMode,
        onChanged: _store.setIsImmersiveMode,
      ),
      MiuixSwitchPreference(
        title: '隐藏封面',
        value: _store.hideAlbumCover,
        onChanged: _store.setHideAlbumCover,
      ),
      const SizedBox(height: 8),
      const MiuixSmallTitle('歌词样式', insideMargin: EdgeInsets.zero),
      _displayStyleTabs(),
      if (_store.lyricDisplayStyle == LyricDisplayStyle.singleLine) ...[
        const SizedBox(height: 10),
        const MiuixSmallTitle('单行动画', insideMargin: EdgeInsets.zero),
        _singleLineAnimationTabs(),
      ],
      const SizedBox(height: 8),
      const MiuixSmallTitle('歌词字体', insideMargin: EdgeInsets.zero),
      _fontDropdown(),
      const SizedBox(height: 8),
      const MiuixSmallTitle('歌词字号', insideMargin: EdgeInsets.zero),
      MiuixSliderPreference(
        title: '字号',
        value: _store.lyricFontSize,
        min: 20,
        max: 60,
        valueText: _store.lyricFontSize.round().toString(),
        onValueChange: _store.setLyricFontSize,
      ),
      const SizedBox(height: 8),
      const MiuixSmallTitle('背景模糊', insideMargin: EdgeInsets.zero),
      MiuixSliderPreference(
        title: '模糊',
        value: _store.lyricBlurStrength,
        min: 0,
        max: 20,
        valueText: _store.lyricBlurStrength.round().toString(),
        onValueChange: _store.setLyricBlurStrength,
      ),
    ];
    return children;
  }

  Widget _displayStyleTabs() {
    const options = [
      (LyricDisplayStyle.scroll, '滚动'),
      (LyricDisplayStyle.roulette, '轮盘'),
      (LyricDisplayStyle.singleLine, '单行'),
    ];
    final index = options.indexWhere((o) => o.$1 == _store.lyricDisplayStyle);
    return MiuixTabRowWithContour(
      tabs: const ['滚动', '轮盘', '单行'],
      selectedTabIndex: index < 0 ? 0 : index,
      onTabSelected: (i) => _store.setLyricDisplayStyle(options[i].$1),
    );
  }

  Widget _singleLineAnimationTabs() {
    const options = [
      (SingleLineAnimation.slideUp, '上推'),
      (SingleLineAnimation.fade, '渐变'),
      (SingleLineAnimation.zoom, '缩放'),
      (SingleLineAnimation.blur, '模糊'),
    ];
    final index =
        options.indexWhere((o) => o.$1 == _store.singleLineAnimation);
    return MiuixTabRowWithContour(
      tabs: const ['上推', '渐变', '缩放', '模糊'],
      selectedTabIndex: index < 0 ? 0 : index,
      onTabSelected: (i) => _store.setSingleLineAnimation(options[i].$1),
    );
  }

  Widget _fontDropdown() {
    final labels = [for (final f in lyricFontOptions) f.label];
    var selectedIndex =
        lyricFontOptions.indexWhere((f) => f.value == _store.lyricFontFamily);
    if (selectedIndex < 0) selectedIndex = 0;
    return MiuixOverlayDropdownPreference(
      title: '字体',
      items: labels,
      selectedIndex: selectedIndex,
      onSelectedIndexChange: (i) =>
          _store.setLyricFontFamily(lyricFontOptions[i].value),
    );
  }
}
