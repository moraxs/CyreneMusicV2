import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 静音循环的视频层：动态封面（Spotify Canvas）与播放器视频背景共用。
///
/// 加载完成前、失败时以及不支持的平台（Windows/Linux，video_player 无实现）
/// 都只渲染空白，由调用方垫在下面的静态封面兜底。
class VideoBackgroundPlayer extends StatefulWidget {
  const VideoBackgroundPlayer({
    super.key,
    required this.videoPath,
    this.blurAmount = 0.0,
    this.opacity = 1.0,
    this.paused = false,
    this.onReady,
  });

  /// http(s) 地址或本地文件路径。
  final String videoPath;
  final double blurAmount;
  final double opacity;

  /// 跟随音乐暂停（官方客户端暂停时 Canvas 也会停住）。
  final bool paused;

  /// 首帧可播时回调一次。只从异步加载里触发，不会落在调用方的 build 期间。
  /// 换视频请换 key 重建本组件，不要原地改 [videoPath]——否则调用方收不到
  /// 「旧视频已撤下」的信号。
  final VoidCallback? onReady;

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  State<VideoBackgroundPlayer> createState() => _VideoBackgroundPlayerState();
}

class _VideoBackgroundPlayerState extends State<VideoBackgroundPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(VideoBackgroundPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _close();
      _open();
    } else if (oldWidget.paused != widget.paused && _ready) {
      widget.paused ? _controller?.pause() : _controller?.play();
    }
  }

  Future<void> _open() async {
    if (!VideoBackgroundPlayer.isSupported || widget.videoPath.isEmpty) return;
    final path = widget.videoPath;
    final options = VideoPlayerOptions(
      // Android：不加的话 ExoPlayer 会抢音频焦点，把正在放的歌停掉。
      // iOS：这个开关改的是整个 App 的 AVAudioSession，加上 mixWithOthers
      // 锁屏 Now Playing 就没了（见 NowPlayingBridge）。同一会话里静音的
      // AVPlayer 本来就不会打断我们自己的音频，所以 iOS 不开。
      mixWithOthers: Platform.isAndroid,
    );
    final controller = path.startsWith('http://') || path.startsWith('https://')
        ? VideoPlayerController.networkUrl(
            Uri.parse(path),
            videoPlayerOptions: options,
          )
        : VideoPlayerController.file(File(path), videoPlayerOptions: options);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!identical(_controller, controller)) return;
      if (!widget.paused) await controller.play();
      if (!mounted || !identical(_controller, controller)) return;
      setState(() => _ready = true);
      widget.onReady?.call();
    } catch (e) {
      // 初始化途中被换掉/卸载时，被 dispose 的控制器也会走到这里，不算失败。
      if (identical(_controller, controller)) {
        debugPrint('[VideoBackgroundPlayer] 加载失败 $path: $e');
        _close();
      }
    }
  }

  /// dispose 可重入，初始化途中调用也安全（会等创建完成再释放）。
  void _close() {
    _controller?.dispose();
    _controller = null;
    _ready = false;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final Widget video = _ready && controller != null
        ? SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          )
        : const SizedBox.expand();

    Widget child = video;
    if (widget.blurAmount > 0 || widget.opacity < 1.0) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          video,
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: widget.blurAmount,
              sigmaY: widget.blurAmount,
            ),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 1 - widget.opacity),
            ),
          ),
        ],
      );
    }

    return AnimatedOpacity(
      opacity: _ready ? 1 : 0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: child,
    );
  }
}
