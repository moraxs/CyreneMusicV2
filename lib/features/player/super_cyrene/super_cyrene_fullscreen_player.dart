import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, LogicalKeyboardKey, SystemChrome, SystemUiMode;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../../application/audio_sources/audio_source_preferences_controller.dart';
import '../../../application/auth/account_session_controller.dart';
import '../../../application/playback/playback_controller.dart';
import '../../../application/stores/fullscreen_settings_store.dart';
import '../mobile/compat/player_service.dart';
import 'super_cyrene_amll_background.dart';
import 'super_cyrene_chat_lyrics.dart';
import 'super_cyrene_classic_lyrics.dart';
import 'super_cyrene_control_panel.dart';
import 'super_cyrene_pixel_lyrics.dart';
import 'super_cyrene_sonnet_lyrics.dart';
import 'super_cyrene_textured_glass_background.dart';

/// SuperCyrene lives in its own feature subtree so every lyric theme can be
/// added without increasing the classic desktop player's file size.
class SuperCyreneFullscreenPlayer extends StatefulWidget {
  const SuperCyreneFullscreenPlayer({
    super.key,
    required this.playback,
    required this.audioSources,
    required this.account,
    required this.onSwitchToClassic,
  });

  final PlaybackController playback;
  final AudioSourcePreferencesController audioSources;
  final AccountSessionController account;
  final VoidCallback onSwitchToClassic;

  @override
  State<SuperCyreneFullscreenPlayer> createState() =>
      _SuperCyreneFullscreenPlayerState();
}

class _SuperCyreneFullscreenPlayerState
    extends State<SuperCyreneFullscreenPlayer>
    with WindowListener {
  Timer? _titleBarTimer;
  bool _titleBarVisible = false;
  bool _isMaximized = false;
  String? _translation;
  String? _romaji;
  String _lyricsTheme = 'default';
  String _backgroundStyle = 'default';

  /// 桌面端才有窗口概念（windowManager / 标题栏 / 最大化）。移动端走横屏
  /// 全屏，这些桌面专属逻辑全部跳过。
  bool get _isDesktop => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _lyricsTheme =
        FullscreenSettingsStore.instance.superCyreneLyricsTheme;
    _backgroundStyle =
        FullscreenSettingsStore.instance.superCyreneBackgroundStyle;
    PlayerService().bind(
      widget.playback,
      accountController: widget.account,
      audioSourcesController: widget.audioSources,
    );
    if (_isDesktop) {
      windowManager.addListener(this);
      _syncMaximizedState();
    } else {
      // 移动端：解除方向锁定，支持竖屏与横屏自适应旋转。
      _applyMobileOrientation();
    }
  }

  @override
  void dispose() {
    _titleBarTimer?.cancel();
    if (_isDesktop) {
      windowManager.removeListener(this);
    } else {
      _restoreMobileOrientation();
    }
    super.dispose();
  }

  /// 移动端解除方向锁定，允许自由旋转（竖屏与横屏自适应排版）。
  void _applyMobileOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// 移动端退出 SuperCyrene 时恢复方向。
  void _restoreMobileOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  Future<void> _syncMaximizedState() async {
    _setMaximized(await windowManager.isMaximized());
  }

  void _setMaximized(bool value) {
    if (!mounted || value == _isMaximized) return;
    setState(() => _isMaximized = value);
  }

  void _showTitleBar() {
    _titleBarTimer?.cancel();
    if (!_titleBarVisible) setState(() => _titleBarVisible = true);
  }

  void _scheduleTitleBarHide() {
    _titleBarTimer?.cancel();
    _titleBarTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _titleBarVisible = false);
    });
  }

  void _handleTranslationChanged(String? value) {
    if (!mounted || value == _translation) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && value != _translation) {
        setState(() => _translation = value);
      }
    });
  }

  void _handleRomajiChanged(String? value) {
    if (!mounted || value == _romaji) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && value != _romaji) {
        setState(() => _romaji = value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        !_isDesktop && MediaQuery.orientationOf(context) == Orientation.portrait;
    final padding = MediaQuery.paddingOf(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.space):
            widget.playback.togglePlay,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: widget.playback,
            builder: (context, _) {
              final track = widget.playback.state.currentTrack;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (_backgroundStyle == 'textured_glass')
                    ListenableBuilder(
                      listenable: FullscreenSettingsStore.instance,
                      builder: (context, _) {
                        final store = FullscreenSettingsStore.instance;
                        return SuperCyreneTexturedGlassBackground(
                          imageProvider:
                              PlayerService().currentCoverImageProvider,
                          isPlaying: widget.playback.state.isPlaying,
                          fluteWidth: store.texturedGlassFluteWidth,
                          refractionStrength:
                              store.texturedGlassRefractionStrength,
                          lightingIntensity:
                              store.texturedGlassLightingIntensity,
                          grooveDepth: store.texturedGlassGrooveDepth,
                          dispersion: store.texturedGlassDispersion,
                        );
                      },
                    )
                  else ...[
                    SuperCyreneAmllBackground(
                      imageProvider: PlayerService().currentCoverImageProvider,
                      isPlaying: widget.playback.state.isPlaying,
                    ),
                    const ColoredBox(color: Color(0x26000000)),
                  ],
                  if (track != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: isPortrait ? (padding.bottom + 100) : 0,
                      child: switch (_lyricsTheme) {
                        'chat' => SuperCyreneChatLyrics(
                          playback: widget.playback,
                          track: track,
                          cover: PlayerService().currentCoverImageProvider,
                          rightAvatarUrl:
                              widget.account.state.user?.avatarUrl,
                        ),
                        'pixel' => SuperCyrenePixelLyrics(
                          playback: widget.playback,
                          track: track,
                          onTranslationChanged: _handleTranslationChanged,
                          onRomajiChanged: _handleRomajiChanged,
                        ),
                        'sonnet' => SuperCyreneSonnetLyrics(
                          playback: widget.playback,
                          track: track,
                          cover: PlayerService().currentCoverImageProvider,
                          onTranslationChanged: _handleTranslationChanged,
                          onRomajiChanged: _handleRomajiChanged,
                        ),
                        _ => SuperCyreneClassicLyrics(
                          playback: widget.playback,
                          track: track,
                          onTranslationChanged: _handleTranslationChanged,
                          onRomajiChanged: _handleRomajiChanged,
                        ),
                      },
                    )
                  else
                    Center(
                      child: Text(
                        '暂无正在播放的歌曲',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .3),
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  if (_isDesktop) ...[
                    // 桌面端：顶部悬停触发标题栏（含最小化/最大化/关闭）。
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: MouseRegion(
                        onEnter: (_) => _showTitleBar(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: !_titleBarVisible,
                        child: AnimatedSlide(
                          offset: _titleBarVisible
                              ? Offset.zero
                              : const Offset(0, -1),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: _titleBarVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 350),
                            child: MouseRegion(
                              onEnter: (_) => _showTitleBar(),
                              onExit: (_) => _scheduleTitleBarHide(),
                              child: _SuperCyreneTitleBar(
                                title: track?.name ?? 'SuperCyrene',
                                isMaximized: _isMaximized,
                                onSwitchToClassic: widget.onSwitchToClassic,
                                onExit: () => Navigator.of(context).pop(),
                                onMinimize: windowManager.minimize,
                                onToggleMaximize: () => _isMaximized
                                    ? windowManager.unmaximize()
                                    : windowManager.maximize(),
                                onClose: windowManager.close,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // 移动端：返回按钮与切回经典按钮（根据屏幕方向自适应排布）。
                    Positioned(
                      top: padding.top + 8,
                      left: 16,
                      child: _MobileTopAction(
                        icon: CupertinoIcons.back,
                        tooltip: '退出',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Positioned(
                      top: padding.top + 8,
                      right: 16,
                      child: _MobileTopAction(
                        icon: CupertinoIcons.chevron_left_square,
                        tooltip: '切回经典',
                        onTap: widget.onSwitchToClassic,
                      ),
                    ),
                  ],
                  if (isPortrait) ...[
                    // 移动端竖屏：歌词翻译 + 罗马音浮层
                    if (_translation?.isNotEmpty == true ||
                        _romaji?.isNotEmpty == true)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: padding.bottom + 88,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Column(
                            key: ValueKey(_translation),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_translation?.isNotEmpty == true)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    _translation!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .75),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: .5,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 16,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_romaji?.isNotEmpty == true)
                                Text(
                                  _romaji!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .5),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: .5,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 16,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    // 移动端竖屏：左侧控制面板入口（独立绝对定位，不挤占胶囊横向空间）
                    Positioned(
                      left: 16,
                      bottom: padding.bottom + 14,
                      child: SuperCyreneControlPanel(
                        playback: widget.playback,
                        account: widget.account,
                        track: track,
                        cover: PlayerService().currentCoverImageProvider,
                        lyricsTheme: _lyricsTheme,
                        onLyricsThemeChanged: (value) {
                          if (_lyricsTheme == value) return;
                          setState(() {
                            _lyricsTheme = value;
                            if (value == 'chat') _translation = null;
                          });
                          FullscreenSettingsStore.instance
                              .setSuperCyreneLyricsTheme(value);
                        },
                        backgroundStyle: _backgroundStyle,
                        onBackgroundStyleChanged: (value) {
                          if (_backgroundStyle == value) return;
                          setState(() => _backgroundStyle = value);
                          FullscreenSettingsStore.instance
                              .setSuperCyreneBackgroundStyle(value);
                        },
                      ),
                    ),
                    // 移动端竖屏：播放控制胶囊（拥有充裕的自适应宽度，杜绝溢出）
                    Positioned(
                      left: 74,
                      right: 16,
                      bottom: padding.bottom + 14,
                      child: _PlaybackCapsule(
                        playback: widget.playback,
                      ),
                    ),
                  ] else ...[
                    // 横屏与桌面端：居中胶囊 + 左下角面板。
                    Positioned(
                      left: 80,
                      right: 80,
                      bottom: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: (_translation?.isNotEmpty == true ||
                                    _romaji?.isNotEmpty == true)
                                ? Padding(
                                    key: ValueKey(_translation),
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_translation?.isNotEmpty == true)
                                          Text(
                                            _translation!,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withValues(alpha: .75),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: .5,
                                              shadows: const [
                                                Shadow(
                                                  color: Colors.black87,
                                                  blurRadius: 16,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (_translation?.isNotEmpty == true &&
                                            _romaji?.isNotEmpty == true)
                                          const SizedBox(height: 4),
                                        if (_romaji?.isNotEmpty == true)
                                          Text(
                                            _romaji!,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withValues(alpha: .5),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: .5,
                                              shadows: const [
                                                Shadow(
                                                  color: Colors.black87,
                                                  blurRadius: 16,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Center(
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 384),
                              child: _PlaybackCapsule(
                                playback: widget.playback,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 20,
                      child: SuperCyreneControlPanel(
                        playback: widget.playback,
                        account: widget.account,
                        track: track,
                        cover: PlayerService().currentCoverImageProvider,
                        lyricsTheme: _lyricsTheme,
                        onLyricsThemeChanged: (value) {
                          if (_lyricsTheme == value) return;
                          setState(() {
                            _lyricsTheme = value;
                            if (value == 'chat') _translation = null;
                          });
                          FullscreenSettingsStore.instance
                              .setSuperCyreneLyricsTheme(value);
                        },
                        backgroundStyle: _backgroundStyle,
                        onBackgroundStyleChanged: (value) {
                          if (_backgroundStyle == value) return;
                          setState(() => _backgroundStyle = value);
                          FullscreenSettingsStore.instance
                              .setSuperCyreneBackgroundStyle(value);
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SuperCyreneTitleBar extends StatelessWidget {
  const _SuperCyreneTitleBar({
    required this.title,
    required this.isMaximized,
    required this.onSwitchToClassic,
    required this.onExit,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final String title;
  final bool isMaximized;
  final VoidCallback onSwitchToClassic;
  final VoidCallback onExit;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        height: 52,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xA6000000),
              Color(0x59000000),
              Color(0x1A000000),
              Colors.transparent,
            ],
            stops: [0, .4, .72, 1],
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: DragToMoveArea(
                child: SizedBox(
                  height: 44,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .3),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.05,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _CaptionButton(
              icon: Icons.album_rounded,
              tooltip: '切换到经典播放器',
              onPressed: onSwitchToClassic,
            ),
            const _Divider(),
            _CaptionButton(
              icon: Icons.close_fullscreen_rounded,
              tooltip: '折叠全屏播放器',
              onPressed: onExit,
            ),
            const _Divider(),
            _CaptionButton(
              icon: CupertinoIcons.minus,
              tooltip: '最小化窗口',
              onPressed: onMinimize,
            ),
            _CaptionButton(
              icon: isMaximized
                  ? CupertinoIcons.square_on_square
                  : CupertinoIcons.square,
              iconSize: isMaximized ? 13 : 11,
              tooltip: isMaximized ? '还原窗口' : '最大化窗口',
              onPressed: onToggleMaximize,
            ),
            _CaptionButton(
              icon: CupertinoIcons.xmark,
              tooltip: '关闭窗口',
              closeButton: true,
              onPressed: onClose,
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    ),
  );
}

class _PlaybackCapsule extends StatefulWidget {
  const _PlaybackCapsule({required this.playback});

  final PlaybackController playback;

  @override
  State<_PlaybackCapsule> createState() => _PlaybackCapsuleState();
}

class _PlaybackCapsuleState extends State<_PlaybackCapsule> {
  double? _dragValue;

  /// 控制按钮（上一首/播放/下一首）是否展开。超过 [_kIdleTimeout] 无交互
  /// 自动折叠，只留进度条；鼠标移入区域或拖拽进度条时重新展开。
  bool _expanded = true;
  bool _hovering = false;
  Timer? _idleTimer;
  static const _kIdleTimeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _scheduleCollapse();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _scheduleCollapse() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, () {
      if (mounted && !_hovering) {
        setState(() => _expanded = false);
      }
    });
  }

  void _onUserActivity() {
    if (!_expanded && mounted) setState(() => _expanded = true);
    _scheduleCollapse();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) {
          _hovering = true;
          _onUserActivity();
        },
        onExit: (_) {
          _hovering = false;
          _scheduleCollapse();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 折叠态防误触：点击胶囊仅唤醒展开，不触发进度调整。
            if (!_expanded) _onUserActivity();
          },
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x3D000000),
                  blurRadius: 34,
                  spreadRadius: -4,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (defaultTargetPlatform == TargetPlatform.windows)
                  const Positioned.fill(child: _WindowsGlassRefraction()),
                GlassContainer(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 28),
                  settings: const LiquidGlassSettings(
                    glassColor: Color(0x0FFFFFFF),
                    thickness: 10,
                    // The Windows refraction layer below owns backdrop sampling. Keep
                    // this at zero so blur kernels cannot pull the translation line
                    // above the controller into the capsule.
                    blur: 0,
                    chromaticAberration: 0,
                    lightIntensity: 0,
                    ambientStrength: 0,
                    ambientRim: 0,
                    glowIntensity: 0,
                    shadowElevation: 0,
                    whitenStrength: 0,
                  ),
                  useOwnLayer: true,
                  clipBehavior: Clip.antiAlias,
                  allowElevation: false,
                  glowIntensity: 0,
                  padding: const EdgeInsets.fromLTRB(18, 11, 18, 10),
                  child: AnimatedBuilder(
                    animation: widget.playback,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 控制按钮行：折叠时淡出 + 收缩高度，只留进度条可见。
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedOpacity(
                            opacity: _expanded ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: _expanded
                                ? _buildControls()
                                : const SizedBox(width: double.infinity),
                          ),
                        ),
                        // 折叠态上沿保留一点间距，避免进度条贴顶。
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          child: SizedBox(height: _expanded ? 8 : 2),
                        ),
                        ValueListenableBuilder<Duration>(
                          valueListenable: widget.playback.positionListenable,
                          builder: (context, position, _) {
                            final duration = widget.playback.state.duration;
                            final value =
                                _dragValue ??
                                (duration.inMilliseconds <= 0
                                    ? 0.0
                                    : (position.inMilliseconds /
                                              duration.inMilliseconds)
                                          .clamp(0.0, 1.0));
                            // 折叠态下提高轨道透明度 + 加粗进度条，让仅剩的进度条更醒目。
                            return TweenAnimationBuilder<double>(
                              tween: Tween(
                                end: _expanded ? 0.18 : 0.45,
                              ),
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (context, trackOpacity, _) =>
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(
                                      end: _expanded ? 4.0 : 6.0,
                                    ),
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, barHeight, _) =>
                                        _GlassProgressTrack(
                                          value: value,
                                          enabled: _expanded,
                                          trackOpacity: trackOpacity,
                                          barHeight: barHeight,
                                          onChanged: (next) {
                                            setState(() => _dragValue = next);
                                            _onUserActivity();
                                          },
                                          onChangeEnd: (next) {
                                            widget.playback.seek(duration * next);
                                            setState(() => _dragValue = null);
                                            _onUserActivity();
                                          },
                                        ),
                                  ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildControls() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PlayerButton(
            icon: CupertinoIcons.backward_fill,
            onPressed: () {
              widget.playback.playPrevious();
              _onUserActivity();
            },
          ),
          const SizedBox(width: 22),
          _PlayerButton(
            icon: widget.playback.state.isPlaying
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            iconSize: 23,
            prominent: true,
            onPressed: () {
              widget.playback.togglePlay();
              _onUserActivity();
            },
          ),
          const SizedBox(width: 22),
          _PlayerButton(
            icon: CupertinoIcons.forward_fill,
            onPressed: () {
              widget.playback.playNext();
              _onUserActivity();
            },
          ),
        ],
      );
}

/// Windows/Skia cannot run the package's Impeller-only premium refraction.
/// This compact fallback samples the live backdrop through one continuous
/// affine lens. It stays fully GPU-composited and avoids both hard internal
/// refraction seams and expensive screen-to-image readbacks.
class _WindowsGlassRefraction extends StatelessWidget {
  const _WindowsGlassRefraction();

  static const _radius = 28.0;

  Matrix4 _lensMatrix(Size size, double scale) => Matrix4.identity()
    // Horizontal-only deformation is intentional. Scaling Y would make the
    // filter sample pixels above/below the capsule, which can drag the nearby
    // translated lyric into the controller even though the output is clipped.
    ..setEntry(0, 0, scale)
    ..setEntry(0, 3, (1 - scale) * size.width * .5);

  Widget _lens(Size size, double scale) => BackdropFilter(
    filter: ImageFilter.matrix(
      _lensMatrix(size, scale).storage,
      filterQuality: FilterQuality.high,
    ),
    blendMode: BlendMode.srcOver,
    child: const SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty || !size.isFinite) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A horizontal-only frost restores the soft glass appearance
              // without sampling the translated lyric above the capsule.
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 0),
                blendMode: BlendMode.srcOver,
                child: const SizedBox.expand(),
              ),
              // One continuous deformation avoids the visible seam produced
              // by switching to a stronger transform in a hard-clipped rim.
              _lens(size, 1.018),
              const CustomPaint(painter: _GlassOpticsPainter()),
            ],
          ),
        );
      },
    ),
  );
}

class _GlassOpticsPainter extends CustomPainter {
  const _GlassOpticsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rim = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.8),
      const Radius.circular(27.2),
    );

    // Opposing sub-pixel colored rims imitate wavelength separation at a
    // curved glass boundary without requiring a sampled fragment shader.
    canvas.drawRRect(
      rim.shift(const Offset(-.65, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = const Color(0x405DEBFF),
    );
    canvas.drawRRect(
      rim.shift(const Offset(.65, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = const Color(0x38D86CFF),
    );

    final bottomRect = Rect.fromLTWH(
      5,
      size.height * .65,
      size.width - 10,
      size.height * .35,
    );
    canvas.drawRect(
      bottomRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x20000000)],
        ).createShader(bottomRect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassOpticsPainter oldDelegate) => false;
}

class _GlassProgressTrack extends StatelessWidget {
  const _GlassProgressTrack({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
    this.trackOpacity = 0.18,
    this.barHeight = 4,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final bool enabled;

  /// 背景轨道透明度；折叠态调高让进度条更醒目。
  final double trackOpacity;

  /// 进度条高度（dp）；折叠态可加粗。
  final double barHeight;

  double _valueFor(Offset local, double width) =>
      (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled
              ? (details) => onChangeEnd(
                  _valueFor(details.localPosition, constraints.maxWidth))
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) => onChanged(
                  _valueFor(details.localPosition, constraints.maxWidth))
              : null,
          onHorizontalDragEnd: enabled ? (_) => onChangeEnd(value) : null,
          child: SizedBox(
            height: 16,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Stack(
                  children: [
                    Container(
                      height: barHeight,
                      color: Colors.white.withValues(alpha: trackOpacity),
                    ),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        height: barHeight,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFFFFF), Color(0xFFDDD6FE)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _PlayerButton extends StatelessWidget {
  const _PlayerButton({
    required this.icon,
    required this.onPressed,
    this.iconSize = 17,
    this.prominent = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final bool prominent;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onPressed,
    radius: prominent ? 25 : 20,
    child: Container(
      width: prominent ? 44 : 34,
      height: prominent ? 44 : 34,
      decoration: prominent
          ? BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .92),
              boxShadow: const [
                BoxShadow(color: Color(0x448B5CF6), blurRadius: 18),
              ],
            )
          : null,
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: iconSize,
        color: prominent ? Colors.black : Colors.white.withValues(alpha: .82),
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 12,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: Colors.white.withValues(alpha: .1),
  );
}

/// 移动端 SuperCyrene 顶部的半透明圆形操作按钮（返回 / 切回经典）。
class _MobileTopAction extends StatelessWidget {
  const _MobileTopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: .35),
          border: Border.all(color: Colors.white.withValues(alpha: .15)),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Colors.white.withValues(alpha: .9),
        ),
      ),
    ),
  );
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 15,
    this.closeButton = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool closeButton;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? (widget.closeButton
                      ? const Color(0xFFD93B3B).withValues(alpha: .82)
                      : Colors.white.withValues(alpha: .1))
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: Colors.white.withValues(alpha: _hovered ? .8 : .25),
          ),
        ),
      ),
    ),
  );
}
