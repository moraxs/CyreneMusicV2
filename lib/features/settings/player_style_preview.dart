/// 播放器样式选择卡片里的**真实组件**缩略预览。
///
/// 与手绘示意图的区别：这里跑的是全屏播放器用的同一批组件（黑胶唱台、流体云
/// 歌词、SuperCyrene 逐行逐字画布），因此字体、排版、逐字高亮与用户之后每天
/// 看到的界面完全一致，而不是一张会随播放器改版而失真的插画。
///
/// 三条不可逾越的红线，改动本文件时务必守住：
///
/// 1. **不碰全局单例。** `PlayerService` / `PlayerBackgroundService` 都是硬单例
///    且 `bind()` 没有反向解绑——在预览里 bind 一个假 controller 会把真实的
///    迷你播放器一起切成示例曲目。因此预览只走「自建 [PlaybackController]
///    实例」这条路（[PreviewPlayback]），且只挑那些能注入 controller 的组件。
/// 2. **不落盘。** [PlaybackController] 的多数写操作默认 `persist: true`，会把
///    示例队列覆盖进用户真实的续播快照。[_PreviewSnapshotStore.write] 是空实现，
///    这是唯一的防线。
/// 3. **不联网、不出声。** 示例曲目的 `picUrl` 恒为空串（不触发
///    CachedNetworkImage），gateway 的所有写操作为空实现。
///
/// 移动端的「经典」是手工静态复刻而非真实组件——见 [MobileClassicPreview]。
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../application/playback/playback_controller.dart';
import '../../application/stores/fullscreen_settings_store.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_player_gateway.dart';
import '../../domain/playback/playback_snapshot.dart';
import '../../domain/playback/playback_snapshot_store.dart';
// RepeatMode 与 flutter/material 的同名类冲突，加前缀消歧。
import '../../domain/playback/repeat_mode.dart' as playback;
import '../desktop_player/desktop_classic_lyrics.dart';
import '../player/classic_record_stage.dart';
import '../player/super_cyrene/super_cyrene_chat_lyrics.dart';
import '../player/super_cyrene/super_cyrene_classic_lyrics.dart';
import '../player/super_cyrene/super_cyrene_pixel_lyrics.dart';

/// 预览定格的播放进度。
///
/// 刻意落在第 5 行「让星光落进你眼底」的「落进」二字中间（80.3s~81.2s），
/// 这样 SuperCyrene 的逐字高亮会停在半个词上，一眼能看出「逐字」而非「逐行」。
/// 这个不变量由 player_style_preview_test 守着——改动示例歌词的时间戳时，
/// 要么同步改这里，要么测试会告诉你高亮已经飘到了词边界上。
const previewPosition = Duration(milliseconds: 80800);

/// 示例曲目的时长。让定格进度落在 36% 左右，进度条不至于贴着两端。
const _kPreviewDuration = Duration(seconds: 222);

/// 预览用的示例曲目。
///
/// `picUrl` 必须留空：非空会让 `TrackArtwork` 走 CachedNetworkImage 发真实网络
/// 请求。封面一律用 [PreviewCover] 自绘。
///
/// 时间戳按「歌曲已经播到第二段」编排（62s 起），不是从 0 开始——这样进度条、
/// 歌词滚动位置都处在一个自然的中段状态。`lyric` 与 `yrc` 必须同时给：解析器
/// 优先用 YRC（逐字），但 `DesktopClassicLyrics._adaptTrack` 会先判 `lyric` 是否
/// 为空并直接短路，只给 yrc 会得到一片「暂无歌词」。
const previewTrack = Track(
  id: 'cyrene-preview',
  name: '晚风与星光',
  artists: 'Cyrene',
  album: '示例专辑',
  picUrl: '',
  source: MusicSource.netease,
  duration: _kPreviewDuration,
  lyric: '[01:02.00]夜色漫过无人的街\n'
      '[01:06.00]路灯把影子拉得很长\n'
      '[01:10.00]晚风轻轻吹过窗台\n'
      '[01:14.00]把心事写进晚风里\n'
      '[01:18.50]让星光落进你眼底\n'
      '[01:23.00]这一夜我们都不说话\n'
      '[01:28.00]就让时间停在这里\n',
  // YRC 逐字格式：[行起ms,行长ms] 后跟若干 (词起ms,词长ms,0)词。
  // 注意这不是 JSON，且词文本里不能出现左括号（解析正则以 '(' 分词）。
  yrc: '[62000,3500](62000,900,0)夜色(62900,900,0)漫过(63800,900,0)无人的(64700,800,0)街\n'
      '[66000,3500](66000,800,0)路灯(66800,900,0)把影子(67700,900,0)拉得(68600,900,0)很长\n'
      '[70000,4000](70000,900,0)晚风(70900,900,0)轻轻(71800,1000,0)吹过(72800,1200,0)窗台\n'
      '[74000,4500](74000,900,0)把(74900,1000,0)心事(75900,1200,0)写进(77100,1400,0)晚风里\n'
      '[78500,4500](78500,900,0)让(79400,900,0)星光(80300,900,0)落进(81200,1800,0)你眼底\n'
      '[83000,4500](83000,1200,0)这一夜(84200,1300,0)我们都(85500,2000,0)不说话\n'
      '[88000,4500](88000,1300,0)就让(89300,1300,0)时间(90600,1900,0)停在这里\n',
);

/// 预览专用的假播放源：一个真实的 [PlaybackController]，接空实现的音频与存储。
///
/// 手法与桌面壁纸播放器子窗口同源（见 `desktop_player_playback.dart`）——歌词
/// 组件只要 `positionListenable` 与 `state.currentTrack` 两样东西，喂一个不接
/// 音频的 controller 就能零改动复用它们。
///
/// 与那边的唯一差别：这里不接 MethodChannel，状态只灌一次就定格，因此**不起
/// 任何定时器**——[seed] 之后 position 再不变化，卡片是一张静止的真实截图。
class PreviewPlayback {
  PreviewPlayback() {
    _controller = PlaybackController(audio: _gateway, store: _store);
  }

  final _PreviewAudioGateway _gateway = _PreviewAudioGateway();
  final _PreviewSnapshotStore _store = _PreviewSnapshotStore();
  late final PlaybackController _controller;

  PlaybackController get controller => _controller;

  /// 把示例曲目灌进 controller 并定格。
  ///
  /// `currentTrack` 是 controller 的私有状态，外部只能经 `playTrack()`（会真去
  /// 解析音源、拉音频）或 `restore()`（从快照读）写入，显示层必须走后者。
  Future<void> seed() async {
    _store.snapshot = const PlaybackSnapshot(
      queue: [previewTrack],
      currentTrackKey: 'netease:cyrene-preview',
      volume: 1,
      repeatMode: playback.RepeatMode.all,
      position: previewPosition,
      duration: _kPreviewDuration,
    );
    await _controller.restore();
    // 顺序要紧：_onDuration / _onStatus 都有 currentTrack == null 的守卫，
    // 在 restore() 之前 emit 会被直接丢弃。
    _gateway.emitDuration(_kPreviewDuration);
    _gateway.emitStatus(PlaybackStatus.paused);
    _gateway.emitPosition(previewPosition);
  }

  void dispose() {
    _controller.dispose();
    // controller.dispose() 已经会调 gateway.dispose()，这里不重复关闭。
  }
}

/// 空实现 gateway：只把 [PreviewPlayback.seed] 灌的那一帧转成流事件。
class _PreviewAudioGateway implements AudioPlayerGateway {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _status = StreamController<PlaybackStatus>.broadcast();

  void emitPosition(Duration value) => _position.add(value);
  void emitDuration(Duration value) => _duration.add(value);
  void emitStatus(PlaybackStatus value) => _status.add(value);

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<PlaybackStatus> get statusStream => _status.stream;

  // 预览不出声：全部空实现。
  @override
  Future<Duration?> load(Uri source) async => null;
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _status.close();
  }
}

/// 只读的内存快照源。
///
/// [write] 必须保持空实现：controller 的 `setQueue` 等写操作默认会落盘，接真实
/// store 的话预览一挂载就把用户的续播快照覆盖成示例曲目。
class _PreviewSnapshotStore implements PlaybackSnapshotStore {
  PlaybackSnapshot? snapshot;

  @override
  Future<PlaybackSnapshot?> read() async => snapshot;

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {}
}

/// 预览用的自绘封面。
///
/// 不用 `TrackArtwork` 的空封面占位：那个占位取 `Theme.of(context).colorScheme`，
/// 在浅色主题下会于黑胶正中糊出一块亮灰方块。这里恒定深紫蓝，明暗主题下都
/// 与唱片/沉浸背景协调。
class PreviewCover extends StatelessWidget {
  const PreviewCover({super.key, this.iconSize = 44});

  final double iconSize;

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B7BD8), Color(0xFF3B4FA8), Color(0xFF1E2450)],
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: gradient),
    child: Center(
      child: Icon(
        Icons.music_note_rounded,
        size: iconSize,
        color: Colors.white.withValues(alpha: .82),
      ),
    ),
  );
}

/// 把一块固定逻辑尺寸的「真实画面」等比缩进卡片。
///
/// 固定画布是必须的：歌词组件按可用空间算字号与行距，直接塞进 160px 高的卡片
/// 会得到一套为缩略图重新排版的布局，那就不是预览了。先按 [width] × [height]
/// 正常排版，再整体缩放，得到的才是真实比例的缩影。
///
/// **画布尺寸要往小了取。** 卡片实宽只有 250px 上下，画布越大缩放比越狠：
/// `MobilePlayerFluidCloudLyric` 的字号是写死的 18px，1280 宽的画布缩进卡片后
/// 只剩 3.6px，糊成一团灰；640 宽的画布则有 7px 出头，还能看出是字。
/// SuperCyrene 的画布字号按可用空间算，不受此影响。取 640 是两者的折中。
///
/// 缩略图终究只能传达构图与配色，读不了字——这与系统主题选择器的取舍一致，
/// 不是缺陷。
///
/// [IgnorePointer] 同样不能省：`MobilePlayerFluidCloudLyric` 内部挂着
/// `onVerticalDrag` 手势，会与设置页外层的 `ListView` 抢手势竞技场，导致在卡片
/// 上竖划时页面滚不动。
class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({
    required this.width,
    required this.height,
    required this.backdrop,
    required this.child,
  });

  final double width;
  final double height;

  /// letterbox 留白的填充色。画布比例与卡槽不一致时（移动竖屏预览塞进 3:4 卡槽）
  /// 两侧会露白，不填就会露出卡片的 surfaceContainer，像是渲染坏了。
  final Color backdrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: ColoredBox(
        color: backdrop,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      ),
    ),
  );
}

/// 经典播放器的底色。
///
/// 真实播放器这里是 `MobilePlayerBackground`（模糊封面 + isolate 取色），它会
/// 回写 `PlayerService().themeColorNotifier` —— 明确的全局污染，预览不能用。
/// 换成与其取色结果相近的静态渐变，这是刻意的降级。
const _kClassicBackdrop = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2E2B3A), Color(0xFF17151D)],
);

/// SuperCyrene 的底色。
///
/// 同理不用 `SuperCyreneAmllBackground`：它要一个 `ImageProvider`，传 null 只会
/// 画一块纯 `#17151D`；喂合成图则要付全屏 sigma-48 `ImageFiltered` 的 GPU 成本，
/// 而缩到卡片大小后与直接画渐变几乎没有视觉差。
const _kSuperCyreneBackdrop = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4B3E7A), Color(0xFF241F45), Color(0xFF14172E)],
);

/// 桌面「经典」预览：左黑胶唱台 + 右流体云歌词，与 [DesktopFullscreenPlayer]
/// 的主区域同构（省掉底部控制胶囊与悬停标题栏——它们挂着 windowManager 回调，
/// 在预览里既无意义也有误触风险）。
class DesktopClassicPreview extends StatelessWidget {
  const DesktopClassicPreview({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => _PreviewCanvas(
    width: 640,
    height: 480,
    backdrop: _kClassicBackdrop.colors.last,
    child: DecoratedBox(
      decoration: const BoxDecoration(gradient: _kClassicBackdrop),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: Row(
          children: [
            const Expanded(
              flex: 45,
              // isPlaying: false —— 定格预览，唱片不转、唱臂停在起始角度。
              child: ClassicRecordStage(
                track: previewTrack,
                size: 210,
                isPlaying: false,
                cover: PreviewCover(iconSize: 52),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 55,
              child: DesktopClassicLyrics(
                playback: playback,
                track: previewTrack,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// SuperCyrene 预览：沉浸底色 + 当前歌词主题的真实渲染。
///
/// 主题分派与桌面壁纸播放器 (`desktop_player_view.dart`) 同源，用户在设置里换过
/// 歌词主题后，这张卡片会跟着变——预览的是「我现在选它会看到什么」，不是一张
/// 固定插画。
class SuperCyrenePreview extends StatelessWidget {
  const SuperCyrenePreview({
    super.key,
    required this.playback,
    required this.lyricsTheme,
  });

  final PlaybackController playback;
  final String lyricsTheme;

  @override
  Widget build(BuildContext context) => _PreviewCanvas(
    width: 640,
    height: 480,
    backdrop: _kSuperCyreneBackdrop.colors.last,
    child: DecoratedBox(
      decoration: const BoxDecoration(gradient: _kSuperCyreneBackdrop),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: switch (lyricsTheme) {
          'pixel' => SuperCyrenePixelLyrics(
            playback: playback,
            track: previewTrack,
            onTranslationChanged: _ignoreTranslation,
          ),
          // cover: null —— 聊天主题的头像/封面会发网络请求，预览一律不联网。
          'chat' => SuperCyreneChatLyrics(
            playback: playback,
            track: previewTrack,
            cover: null,
          ),
          _ => SuperCyreneClassicLyrics(
            playback: playback,
            track: previewTrack,
            onTranslationChanged: _ignoreTranslation,
          ),
        },
      ),
    ),
  );

  static void _ignoreTranslation(String? _) {}
}

/// 移动「经典」预览：竖屏大封面 + 曲目信息 + 进度与控制键。
///
/// **这一张是手工静态复刻，不是真实组件**，与另外两张预览的性质不同。原因是
/// 移动端经典布局 (`MobilePlayerFluidCloudLayout`) 被三个硬单例彻底渗透：十余处
/// 直读 `PlayerService()`、背景层会回写 `themeColorNotifier`、顶栏一点就弹
/// bottom sheet，内部还有 `Navigator.pop` 与 `ScaffoldMessenger`。把它塞进设置页
/// 既会污染全局状态，也会在预览里挂上一堆能被误触的入口。
///
/// 复刻的是用户打开播放器看到的**第一屏**（封面模式，`_showCoverMode` 初值为
/// true），而不是点一下封面之后的歌词满屏态。若日后移动端播放器改版，这里要
/// 跟着手动对齐——这是选择复刻付出的代价，已知且刻意。
class MobileClassicPreview extends StatelessWidget {
  const MobileClassicPreview({super.key});

  @override
  Widget build(BuildContext context) => _PreviewCanvas(
    width: 390,
    height: 844,
    backdrop: _kClassicBackdrop.colors.last,
    child: DecoratedBox(
      decoration: const BoxDecoration(gradient: _kClassicBackdrop),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 72, 32, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: const AspectRatio(
                aspectRatio: 1,
                child: PreviewCover(iconSize: 120),
              ),
            ),
            const Spacer(),
            const Text(
              '晚风与星光',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cyrene',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .7),
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 34),
            const _PreviewProgressBar(),
            const SizedBox(height: 30),
            const _PreviewTransportRow(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

/// 移动预览里的静态进度条，进度取 [previewPosition] / [_kPreviewDuration]。
class _PreviewProgressBar extends StatelessWidget {
  const _PreviewProgressBar();

  @override
  Widget build(BuildContext context) {
    final progress =
        previewPosition.inMilliseconds / _kPreviewDuration.inMilliseconds;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: .2),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _time(previewPosition),
            _time(_kPreviewDuration),
          ],
        ),
      ],
    );
  }

  Widget _time(Duration value) => Text(
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}',
    style: TextStyle(
      color: Colors.white.withValues(alpha: .6),
      fontSize: 13,
    ),
  );
}

/// 移动预览里的播放控制键：复刻流体云布局 `_buildControlsSection` 的 iOS 风格
/// （上一首/下一首为 CupertinoIcons.backward/forward_fill、播放/暂停为大号
/// play_fill/pause_fill，纯图标无方块背景），与真实「经典」=流体云播放器一致。
/// 预览定格在暂停态，故主键显示 play_fill。
class _PreviewTransportRow extends StatelessWidget {
  const _PreviewTransportRow();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      IconButton(
        icon: const Icon(CupertinoIcons.backward_fill),
        color: Colors.white.withValues(alpha: .9),
        iconSize: 42,
        padding: EdgeInsets.zero,
        onPressed: () {},
      ),
      IconButton(
        icon: const Icon(CupertinoIcons.play_fill),
        color: Colors.white,
        iconSize: 72,
        padding: EdgeInsets.zero,
        onPressed: () {},
      ),
      IconButton(
        icon: const Icon(CupertinoIcons.forward_fill),
        color: Colors.white.withValues(alpha: .9),
        iconSize: 42,
        padding: EdgeInsets.zero,
        onPressed: () {},
      ),
    ],
  );
}

/// 按当前歌词主题挑一句副标题，让卡片文案与真实渲染对得上。
String superCyreneSubtitle(FullscreenSettingsStore store) =>
    switch (store.superCyreneLyricsTheme) {
      'pixel' => '沉浸式背景 · 像素歌词',
      'chat' => '沉浸式背景 · 聊天歌词',
      _ => '沉浸式背景 · 逐行逐字歌词',
    };
