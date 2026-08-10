import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../application/auth/account_session_controller.dart';
import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/media_url.dart';
import '../../../domain/models/track.dart';
import 'super_cyrene_hex_grid.dart';

/// SuperCyrene「展览馆」播放队列页：点击左下角控制面板的「歌曲列表」后进入。
///
/// 复刻 folia-major 前端 `GridView.tsx` 歌单详情页的蜂巢拍立得卡片效果——
/// 歌曲卡片按中心外扩的六边形螺旋排布，近大远淡；拖拽/滚轮平移整个卡片场，
/// 居中卡片出现播放按钮；左侧 Cut-in 信息面板展示当前高亮曲目，右侧滑出
/// 虚拟化曲目列表。整页 `overflow` 锁死，仅靠拖拽浏览。
///
/// 队列的读取恒定走 `playback.state.queue`；**写**操作与关闭动作可由调用方
/// 接管（[onClose] / [onPlayTrack] / [onRemoveTrack] / [onClearQueue]）。
/// 桌面歌词覆盖层需要这些钩子：那边是独立引擎，本地 controller 只是显示层，
/// 写操作必须回传主窗口，且它没有路由栈（展览馆挂在 Stack 里而非 push 出来）。
/// 全部留空时行为与原先完全一致。
class SuperCyreneSongGallery extends StatefulWidget {
  const SuperCyreneSongGallery({
    super.key,
    required this.playback,
    this.account,
    this.onClose,
    this.onPlayTrack,
    this.onRemoveTrack,
    this.onClearQueue,
    this.backdrop,
  });

  final PlaybackController playback;
  final AccountSessionController? account;

  /// 关闭展览馆。默认 `Navigator.pop`。
  final VoidCallback? onClose;

  /// 播放指定曲目。默认 `playback.playTrack(track, queue: 当前队列)`。
  final void Function(Track track)? onPlayTrack;

  /// 从队列移除。默认 `playback.removeFromQueue(track)`。
  final void Function(Track track)? onRemoveTrack;

  /// 清空队列。默认 `playback.clearQueue()` 后关闭本页。
  final Future<void> Function()? onClearQueue;

  /// 替换整层背景（默认是当前曲封面的全屏大模糊 + 一层压暗）。
  ///
  /// 桌面歌词覆盖层传 [SizedBox.shrink]：那边整个窗口是透明的，背景由 DWM
  /// 的壁纸亚克力直接模糊真实桌面，Flutter 侧画任何底都会把它糊死。
  final Widget? backdrop;

  @override
  State<SuperCyreneSongGallery> createState() => _SuperCyreneSongGalleryState();
}

class _SuperCyreneSongGalleryState extends State<SuperCyreneSongGallery>
    with SingleTickerProviderStateMixin {
  // 卡片场平移量：渲染坐标 = baseX + _pan.dx / baseY + _pan.dy。
  // 用 ValueNotifier 驱动单帧重绘，避免整页 setState 抖动。
  final ValueNotifier<Offset> _pan = ValueNotifier<Offset>(Offset.zero);

  late AnimationController _spring;
  Animation<Offset>? _springAnim;

  Size _viewport = Size.zero;
  HexLayoutConfig _layout = const HexLayoutConfig(
    cardWidth: 220, cardHeight: 330, spacingX: 250, spacingY: 320,
    maxDistance: 500, lodStart: 340, lodEnd: 385,
  );

  int _focusedIndex = 0;
  bool _showInfoPanel = false;
  bool _showSidePanel = false;
  bool _entering = true;

  /// 搜索词（已 trim + 小写）。空串表示不过滤。
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  /// 搜索框焦点。方向键在展览馆里被绑定为卡片跳转，而 [CallbackShortcuts]
  /// 位于焦点链上 `DefaultTextEditingShortcuts` 之下——不加守卫的话，在输入框
  /// 里按左右键会被 [_stepFocus] 截走，光标动不了。
  final FocusNode _searchFocus = FocusNode();

  /// 过滤后的队列。蜂巢坐标、焦点索引、右侧列表**统一**以它为基准——
  /// 若只过滤显示而索引仍按原队列算，卡片与曲目会整体错位。
  ///
  /// 空查询时直接返回原列表本身（不复制），避免每帧构造新 List。
  List<Track> get _visibleQueue {
    final queue = widget.playback.state.queue;
    if (_query.isEmpty) return queue;
    return [
      for (final track in queue)
        if (_matches(track)) track,
    ];
  }

  bool _matches(Track track) =>
      track.name.toLowerCase().contains(_query) ||
      track.artists.toLowerCase().contains(_query) ||
      track.album.toLowerCase().contains(_query);

  /// 应用新的搜索词：重排蜂巢并把焦点收回结果集内。
  void _onQueryChanged(String raw) {
    final next = raw.trim().toLowerCase();
    if (next == _query) return;
    setState(() {
      _query = next;
      // 结果集变了，旧坐标缓存必然失效（长度对不上会被 _coords 自动重建，
      // 但同长度不同内容的情况必须显式作废）。
      _coordsCache = null;
      _coordsForLength = -1;
      _focusedIndex = 0;
    });
    // 重排后把焦点居中；清空搜索时回到当前播放曲，符合直觉。
    final target = _query.isEmpty ? _currentIndex() : 0;
    if (target >= 0) _centerOnIndex(target, snap: true);
  }

  Offset? _dragStartPan;
  Offset? _dragStartPointer;
  bool _dragged = false;

  // 拖拽边界缓存（仅随布局/队列长度变化），避免 _clampPan 每帧 O(n) 扫描。
  double _boundsMinX = 0, _boundsMaxX = 0, _boundsMinY = 0, _boundsMaxY = 0;
  // 上次构建坐标时的队列长度，用于检测增删后失效缓存。
  int _coordsForLength = -1;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(vsync: this);
    // _pan 不再触发整页 setState：蜂巢画布用 AnimatedBuilder(animation: _pan)
    // 局部重建，避免全屏模糊背景每帧重绘。结构性变化（焦点/面板）才走 setState。
    // 首帧后用入场动画淡入卡片场，并居中到当前曲。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _entering = false);
      final idx = _currentIndex();
      if (idx >= 0) _centerOnIndex(idx, snap: true);
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    _pan.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int _currentIndex() {
    final queue = _visibleQueue;
    final current = widget.playback.state.currentTrack;
    if (current == null) return queue.isEmpty ? -1 : 0;
    final idx = queue.indexWhere((t) => t.key == current.key);
    // 当前曲被搜索词过滤掉时退回结果集首项。
    return idx >= 0 ? idx : (queue.isEmpty ? -1 : 0);
  }

  void _centerOnIndex(int index, {bool snap = true}) {
    final coords = _coords();
    if (index < 0 || index >= coords.length) return;
    final target = Offset(-coords[index].baseX, -coords[index].baseY);
    _focusedIndex = index;
    if (!snap) {
      _pan.value = target;
      return;
    }
    _springAnim = Tween<Offset>(begin: _pan.value, end: target).animate(
      CurvedAnimation(parent: _spring, curve: Curves.easeOutCubic),
    )..addListener(() {
        if (mounted) _pan.value = _springAnim!.value;
      });
    _spring
      ..duration = const Duration(milliseconds: 420)
      ..forward(from: 0);
  }

  List<HexGridCoord> _coords() {
    final len = _visibleQueue.length;
    final cached = _coordsCache;
    if (cached != null && len == _coordsForLength) return cached;
    final built = buildHexGridCoords(len, _layout.spacingX, _layout.spacingY);
    _coordsCache = built;
    _coordsForLength = len;
    // 重新计算拖拽边界（坐标范围随布局/队列长度变化）。
    if (built.isEmpty) {
      _boundsMinX = _boundsMaxX = _boundsMinY = _boundsMaxY = 0;
    } else {
      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;
      for (final c in built) {
        if (c.baseX < minX) minX = c.baseX;
        if (c.baseX > maxX) maxX = c.baseX;
        if (c.baseY < minY) minY = c.baseY;
        if (c.baseY > maxY) maxY = c.baseY;
      }
      _boundsMinX = minX;
      _boundsMaxX = maxX;
      _boundsMinY = minY;
      _boundsMaxY = maxY;
    }
    return built;
  }
  List<HexGridCoord>? _coordsCache;

  double _clipRadius() {
    if (_viewport.isEmpty) return 800;
    final halfW = _viewport.width / 2;
    final halfH = _viewport.height / 2;
    final viewportRadius = math.sqrt(halfW * halfW + halfH * halfH);
    final cardHalfW = _layout.cardWidth / 2;
    final cardHalfH = _layout.cardHeight / 2;
    final cardRadius = math.sqrt(cardHalfW * cardHalfW + cardHalfH * cardHalfH);
    return viewportRadius + cardRadius + 200;
  }

  void _onLayout(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    _layout = HexLayoutConfig.forViewportWidth(size.width);
    _coordsCache = null;
    // 重排后把焦点重新居中，避免布局换挡时焦点跑偏。
    final len = _visibleQueue.length;
    if (len > 0) {
      final idx = _focusedIndex.clamp(0, len - 1);
      _centerOnIndex(idx, snap: true);
    }
  }

  // —— 拖拽平移 ——
  void _onPanStart(DragStartDetails d) {
    _dragStartPan = _pan.value;
    _dragStartPointer = d.globalPosition;
    _dragged = false;
    _springAnim = null;
    _spring.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragStartPan == null || _dragStartPointer == null) return;
    _dragged = true;
    final delta = d.globalPosition - _dragStartPointer!;
    _pan.value = _clampPan(_dragStartPan! + delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragged && _focusedIndex >= 0) {
      // 单击空白：不切歌，仅记录未拖动。
    }
    _dragStartPan = null;
    _dragStartPointer = null;
    // 拖拽结束后把离视口中心最近的卡作为新焦点（不在每帧 setState）。
    final closest = _closestIndex();
    if (closest >= 0 && closest != _focusedIndex) {
      _focusedIndex = closest;
      if (mounted) setState(() {});
    }
  }

  Offset _clampPan(Offset value) {
    if (_coordsCache == null || _coordsCache!.isEmpty) return value;
    final bufX = math.max(0.0, _viewport.width / 2 - 2 * _layout.spacingX);
    final bufY = math.max(0.0, _viewport.height / 2 - 2 * _layout.spacingY);
    // 用 _coords() 时预算好的边界，避免拖拽时每帧 O(n) 扫描。
    return Offset(
      value.dx.clamp(-_boundsMaxX - bufX, -_boundsMinX + bufX),
      value.dy.clamp(-_boundsMaxY - bufY, -_boundsMinY + bufY),
    );
  }

  int _closestIndex() {
    final coords = _coords();
    if (coords.isEmpty) return -1;
    int best = _focusedIndex;
    double minSq = double.infinity;
    for (final c in coords) {
      final cx = c.baseX + _pan.value.dx;
      final cy = c.baseY + _pan.value.dy;
      final sq = cx * cx + cy * cy;
      if (sq < minSq) {
        minSq = sq;
        best = c.index;
      }
    }
    return best;
  }

  void _stepFocus(int dirX, int dirY) {
    final coords = _coords();
    if (coords.isEmpty || _focusedIndex < 0) return;
    final curr = coords[_focusedIndex];
    int best = _focusedIndex;
    double minDist = double.infinity;
    for (final c in coords) {
      if (c.index == _focusedIndex) continue;
      final dx = c.baseX - curr.baseX;
      final dy = c.baseY - curr.baseY;
      bool match = false;
      if (dirX < 0 && dx < -50 && dy.abs() < 180) match = true;
      if (dirX > 0 && dx > 50 && dy.abs() < 180) match = true;
      if (dirY < 0 && dy < -50 && dx.abs() < 200) match = true;
      if (dirY > 0 && dy > 50 && dx.abs() < 200) match = true;
      if (match) {
        final dist = dx * dx + dy * dy;
        if (dist < minDist) {
          minDist = dist;
          best = c.index;
        }
      }
    }
    if (best != _focusedIndex) _centerOnIndex(best, snap: true);
  }

  void _play(Track track) {
    final override = widget.onPlayTrack;
    if (override != null) {
      override(track);
      return;
    }
    // 队列传**完整**队列而非筛选结果：搜索只是查找手段，不该把用户的播放
    // 队列裁成搜索结果——那样播完这几首就没有下一首了。
    widget.playback.playTrack(track, queue: widget.playback.state.queue);
  }

  void _remove(Track track) {
    final override = widget.onRemoveTrack;
    if (override != null) {
      override(track);
      return;
    }
    widget.playback.removeFromQueue(track);
  }

  void _close() {
    final override = widget.onClose;
    if (override != null) {
      override();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    final override = widget.onClearQueue;
    if (override != null) {
      await override();
      return;
    }
    await widget.playback.clearQueue();
    if (!mounted) return;
    _close();
  }

  /// 方向键跳转卡片。搜索框聚焦时让位给文本光标移动。
  void _stepFocusUnlessTyping(int dirX, int dirY) {
    if (_searchFocus.hasFocus) return;
    _stepFocus(dirX, dirY);
  }

  /// Esc：有搜索词时先退出搜索，否则关闭展览馆。
  ///
  /// 输入框不处理 Esc，按键会冒泡到这里；若直接 [_close]，用户想「取消搜索」
  /// 却整个页面被关掉。
  void _onEscape() {
    if (_query.isEmpty) {
      _close();
      return;
    }
    _searchController.clear();
    _onQueryChanged('');
    // 交还焦点，让方向键重新用于卡片间跳转。
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              () => _stepFocusUnlessTyping(-1, 0),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              () => _stepFocusUnlessTyping(1, 0),
          const SingleActivator(LogicalKeyboardKey.arrowUp):
              () => _stepFocusUnlessTyping(0, -1),
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              () => _stepFocusUnlessTyping(0, 1),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: widget.playback,
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    _onLayout(constraints.biggest);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.backdrop != null)
                          widget.backdrop!
                        else ...[
                          _BlurredBackdrop(track: _coverTrack()),
                          const ColoredBox(color: Color(0x26000000)),
                        ],
                        _HoneycombCanvas(owner: this),
                        Positioned(
                          top: 20,
                          left: 24,
                          child: _BackButton(onTap: _close),
                        ),
                        Positioned(
                          top: 18,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _TitleCapsule(
                                  title: '播放队列',
                                  subtitle: _query.isEmpty
                                      ? '${widget.playback.state.queue.length} 首歌曲'
                                      : '${_visibleQueue.length} 首匹配 · '
                                          '共 ${widget.playback.state.queue.length} 首',
                                  onTap: () => setState(
                                    () => _showInfoPanel = !_showInfoPanel,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _SearchBox(
                                  controller: _searchController,
                                  focusNode: _searchFocus,
                                  onChanged: _onQueryChanged,
                                  onClear: () {
                                    _searchController.clear();
                                    _onQueryChanged('');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showInfoPanel)
                          _CutInInfoPanel(
                            playback: widget.playback,
                            track: _focusedTrack(),
                            onClose: () => setState(() => _showInfoPanel = false),
                            onPlayAll: () {
                              final q = widget.playback.state.queue;
                              if (q.isEmpty) return;
                              _play(q.first);
                            },
                            onClear: _clear,
                          ),
                        if (_showSidePanel)
                          _SideTrackPanel(
                            playback: widget.playback,
                            // 右侧列表与蜂巢共用同一份筛选结果，两边始终一致。
                            tracks: _visibleQueue,
                            query: _query,
                            onClose: () => setState(() => _showSidePanel = false),
                            onPlay: _play,
                            onRemove: _remove,
                          ),
                        Positioned(
                          right: 24,
                          bottom: 28,
                          child: _FloatingListButton(
                            onTap: () => setState(() => _showSidePanel = !_showSidePanel),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

  Track? _coverTrack() {
    final queue = widget.playback.state.queue;
    final current = widget.playback.state.currentTrack;
    return current ?? (queue.isNotEmpty ? queue.first : null);
  }

  Track? _focusedTrack() {
    final queue = _visibleQueue;
    if (queue.isEmpty) return null;
    final idx = _focusedIndex.clamp(0, queue.length - 1);
    return queue[idx];
  }
}

/// 全屏模糊封面背景（低清 + 大模糊 + 低透明度）。
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.track});
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final url = track?.picUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Color(0xFF0E0E12));
    }
    return Positioned.fill(
      child: ImageFiltered(
        // 参考项目 blur-[30px]；ImageFilter.blur 用 sigma，30 与之接近。
        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Transform.scale(
          scale: 1.1,
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: imageHeaders(url),
            fit: BoxFit.cover,
            memCacheWidth: 150,
            errorWidget: (_, _, _) =>
                const ColoredBox(color: Color(0xFF0E0E12)),
          ),
        ),
      ),
    );
  }
}

/// 蜂巢卡片画布：根据平移量渲染可见卡片，近大远淡。
class _HoneycombCanvas extends StatelessWidget {
  const _HoneycombCanvas({required this.owner});

  final _SuperCyreneSongGalleryState owner;

  @override
  Widget build(BuildContext context) {
    // 只在 _pan 变化时重建蜂巢画布子树，把全屏模糊背景 / 标题 / 面板隔离出去，
    // 避免拖拽时整页（含最贵的全屏 blur 背景）每帧重绘。
    return AnimatedBuilder(
      animation: owner._pan,
      builder: (context, _) {
        final queue = owner._visibleQueue;
        if (queue.isEmpty) {
          return Center(
            child: Text(
              owner._query.isEmpty ? '队列空空如也' : '没有匹配的歌曲',
              style: const TextStyle(color: Colors.white30, letterSpacing: 2),
            ),
          );
        }
        final coords = owner._coords();
        final pan = owner._pan.value;
        final clip = owner._clipRadius();
        final currentKey = owner.widget.playback.state.currentTrack?.key;
        final halfW = owner._viewport.width / 2;
        final halfH = owner._viewport.height / 2;

        // 视口 culling：只构建可见卡片，避免大队列时全量渲染。
        final visible = resolveVisibleHexIndexes(
          coords: coords,
          dx: pan.dx,
          dy: pan.dy,
          pixelRadius: clip,
        );

        return Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                owner._spring.stop();
                owner._pan.value = owner._clampPan(
                  owner._pan.value + Offset(event.scrollDelta.dx * 0.6, event.scrollDelta.dy * 0.6),
                );
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: owner._onPanStart,
              onPanUpdate: owner._onPanUpdate,
              onPanEnd: owner._onPanEnd,
              // RepaintBoundary 让整张卡片场作为独立图层，平移时直接复用
              // 已栅格化的位图，不必每帧重绘每张卡片的内容。
              child: RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final idx in visible)
                      _buildCard(context, queue, coords, idx, pan, currentKey, clip, halfW, halfH),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    List<Track> queue,
    List<HexGridCoord> coords,
    int idx,
    Offset pan,
    String? currentKey,
    double clip,
    double halfW,
    double halfH,
  ) {
    final coord = coords[idx];
    final frame = computeHexCardFrame(coord, pan.dx, pan.dy,
        config: owner._layout, clipRadius: clip);
    if (!frame.visible || frame.opacity <= 0) return const SizedBox.shrink();
    final track = queue[idx];
    final isFocused = idx == owner._focusedIndex;
    // 视口中心承载蜂巢世界原点 (0,0)：渲染坐标 = 视口中心 + 世界坐标 - 卡片半宽。
    return Positioned(
      left: halfW + coord.baseX + pan.dx - owner._layout.cardWidth / 2,
      top: halfH + coord.baseY + pan.dy - owner._layout.cardHeight / 2,
      child: IgnorePointer(
        // 透明度过低的卡片不再响应点击。
        ignoring: frame.opacity < 0.2,
        child: Opacity(
          opacity: frame.opacity,
          child: Transform.scale(
            scale: frame.scale,
            // RepaintBoundary 卡在动态变换之内、稳定内容之外：卡片位图只
            // 栅格化一次，每帧仅做位移/缩放/透明度的 GPU 图层合成。
            child: RepaintBoundary(
              child: SizedBox(
                width: owner._layout.cardWidth,
                height: owner._layout.cardHeight,
                child: _PolaroidCard(
                  track: track,
                  // 序号显示它在**原队列**中的位置：筛选后若重新从 01 编号，
                  // 就失去了「这首歌在队列第几位」的定位意义。
                  index: owner._query.isEmpty
                      ? idx
                      : owner.widget.playback.state.queue
                          .indexWhere((t) => t.key == track.key),
                  isActive: track.key == currentKey,
                  isFocused: isFocused,
                  playOpacity: frame.playOpacity,
                  playScale: frame.playScale,
                  entering: owner._entering,
                  cardWidth: owner._layout.cardWidth,
                  cardHeight: owner._layout.cardHeight,
                  onTap: () {
                    if (isFocused) {
                      owner._play(track);
                    } else {
                      owner._centerOnIndex(idx, snap: true);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 拍立得卡片：方形封面 + 底部歌名/歌手/专辑/时长 + 居中时播放按钮。
class _PolaroidCard extends StatelessWidget {
  const _PolaroidCard({
    required this.track,
    required this.index,
    required this.isActive,
    required this.isFocused,
    required this.playOpacity,
    required this.playScale,
    required this.entering,
    required this.cardWidth,
    required this.cardHeight,
    required this.onTap,
  });

  final Track track;
  final int index;
  final bool isActive;
  final bool isFocused;
  final double playOpacity;
  final double playScale;
  final bool entering;
  final double cardWidth;
  final double cardHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final frameWidth = cardWidth;
    final photoSize = frameWidth - 24; // p-3 = 12 两侧
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: entering ? 0 : 1,
          duration: const Duration(milliseconds: 420),
          child: AnimatedScale(
            scale: entering ? 0.9 : 1,
            alignment: Alignment.center,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: Container(
              width: frameWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isFocused ? .32 : .10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .45),
                    blurRadius: isFocused ? 32 : 18,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: photoSize,
                      height: photoSize,
                      child: _Cover(track: track, size: photoSize),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: frameWidth - 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              (index + 1).toString().padLeft(2, '0'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .35),
                                fontSize: 9,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                track.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .92),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artists,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .55),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (track.album.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            track.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .35),
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _durationLabel(track.duration),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .35),
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                      // 居中卡显示播放按钮，其余卡淡出。
                      AnimatedOpacity(
                        opacity: playOpacity.clamp(0.0, 1.0),
                        duration: const Duration(milliseconds: 200),
                        child: Transform.scale(
                          scale: playScale,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFA78BFA)
                                  : Colors.white.withValues(alpha: .92),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isActive
                                          ? const Color(0xFF8B5CF6)
                                          : Colors.black)
                                      .withValues(alpha: .35),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Icon(
                              isActive ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _durationLabel(Duration? d) {
    if (d == null) return '';
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.size});
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (track.picUrl.isEmpty) {
      return ColoredBox(
        color: Colors.white.withValues(alpha: .06),
        child: Center(
          child: Icon(Icons.music_note_rounded,
              size: size * .3, color: Colors.white.withValues(alpha: .2)),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: track.picUrl,
      httpHeaders: imageHeaders(track.picUrl),
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: coverDecodeWidth(size, MediaQuery.devicePixelRatioOf(context)),
      placeholder: (_, _) => ColoredBox(
        color: Colors.white.withValues(alpha: .06),
        child: Center(
          child: SizedBox(
            width: size * .25,
            height: size * .25,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withValues(alpha: .3),
            ),
          ),
        ),
      ),
      errorWidget: (_, _, _) => ColoredBox(
        color: Colors.white.withValues(alpha: .06),
        child: Center(
          child: Icon(Icons.music_note_rounded,
              size: size * .3, color: Colors.white.withValues(alpha: .2)),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.white.withValues(alpha: .08),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.chevron_left_rounded,
                    size: 22, color: Colors.white),
              ),
            ),
          ),
        ),
      );
}

class _TitleCapsule extends StatelessWidget {
  const _TitleCapsule({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '详情',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .60),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .50),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 左侧 Cut-in 信息面板：展示当前高亮曲目 + 操作按钮。
class _CutInInfoPanel extends StatelessWidget {
  const _CutInInfoPanel({
    required this.playback,
    required this.track,
    required this.onClose,
    required this.onPlayAll,
    required this.onClear,
  });

  final PlaybackController playback;
  final Track? track;
  final VoidCallback onClose;
  final VoidCallback onPlayAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Positioned(
        left: 24,
        top: 84,
        bottom: 100,
        width: 304,
        child: _SlideIn(
          offset: const Offset(-60, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _RoundIcon(icon: Icons.close_rounded, size: 18, onTap: onClose),
                      ],
                    ),
                    if (track != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 200,
                          height: 200,
                          child: _Cover(track: track!, size: 200),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        track!.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${track!.artists}${track!.album.isEmpty ? '' : ' · ${track!.album}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .55),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _PanelButton(
                        icon: Icons.play_arrow_rounded,
                        label: '播放全部',
                        primary: true,
                        onTap: onPlayAll,
                      ),
                      const SizedBox(height: 8),
                      _PanelButton(
                        icon: Icons.delete_outline_rounded,
                        label: '清空队列',
                        danger: true,
                        onTap: onClear,
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          '暂无曲目',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .4),
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

/// 右侧曲目列表侧滑面板（窗口化 ListView）。
class _SideTrackPanel extends StatefulWidget {
  const _SideTrackPanel({
    required this.playback,
    required this.tracks,
    required this.query,
    required this.onClose,
    required this.onPlay,
    required this.onRemove,
  });

  final PlaybackController playback;

  /// 已按搜索词筛选的曲目（与蜂巢卡片场同一份）。
  final List<Track> tracks;

  /// 当前搜索词，仅用于区分「队列为空」与「无匹配」的空态文案。
  final String query;

  final VoidCallback onClose;
  final void Function(Track track) onPlay;
  final void Function(Track track) onRemove;

  @override
  State<_SideTrackPanel> createState() => _SideTrackPanelState();
}

class _SideTrackPanelState extends State<_SideTrackPanel> {
  final _controller = ScrollController();
  static const _rowHeight = 56.0;
  bool _scrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollToCurrent();
  }

  void _scrollToCurrent() {
    if (_scrolled) return;
    final queue = widget.tracks;
    final current = widget.playback.state.currentTrack;
    final idx = current == null ? -1 : queue.indexWhere((t) => t.key == current.key);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateTo(
        math.max(0, idx * _rowHeight - 80),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      _scrolled = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned(
        right: 24,
        top: 84,
        bottom: 100,
        width: 320,
        child: _SlideIn(
          offset: const Offset(60, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .12)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '曲目列表',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _RoundIcon(icon: Icons.close_rounded, size: 18, onTap: widget.onClose),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: widget.playback,
                        builder: (context, _) {
                          final queue = widget.tracks;
                          final currentKey =
                              widget.playback.state.currentTrack?.key;
                          if (queue.isEmpty) {
                            return Center(
                              child: Text(
                                widget.query.isEmpty
                                    ? '队列空空如也'
                                    : '没有匹配的歌曲',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .4),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            controller: _controller,
                            padding: const EdgeInsets.only(right: 4),
                            itemExtent: _rowHeight,
                            itemCount: queue.length,
                            itemBuilder: (context, index) {
                              final track = queue[index];
                              final isActive = track.key == currentKey;
                              return _SideTrackRow(
                                track: track,
                                index: index,
                                isActive: isActive,
                                onPlay: () => widget.onPlay(track),
                                onRemove: () => widget.onRemove(track),
                              );
                            },
                          );
                        },
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

class _SideTrackRow extends StatefulWidget {
  const _SideTrackRow({
    required this.track,
    required this.index,
    required this.isActive,
    required this.onPlay,
    required this.onRemove,
  });

  final Track track;
  final int index;
  final bool isActive;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  State<_SideTrackRow> createState() => _SideTrackRowState();
}

class _SideTrackRowState extends State<_SideTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? Colors.white.withValues(alpha: .10)
                  : _hovered
                      ? Colors.white.withValues(alpha: .05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _Cover(track: widget.track, size: 40),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.isActive
                              ? const Color(0xFFA78BFA)
                              : Colors.white.withValues(alpha: .90),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .50),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hovered)
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: Colors.white.withValues(alpha: .55)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 42,
          decoration: BoxDecoration(
            color: primary
                ? Colors.white
                : danger
                    ? const Color(0x33EF4444)
                    : Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(99),
            border: danger
                ? Border.all(color: const Color(0x55EF4444))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: primary
                      ? Colors.black
                      : danger
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: .85)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: primary
                      ? Colors.black
                      : danger
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: .90),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class _FloatingListButton extends StatefulWidget {
  const _FloatingListButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_FloatingListButton> createState() => _FloatingListButtonState();
}

class _FloatingListButtonState extends State<_FloatingListButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _hovered ? .18 : .10),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: .20)),
              boxShadow: const [
                BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8)),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: const Center(
                  child: Icon(Icons.list_rounded, size: 22, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
}

/// 队列搜索框（标题胶囊下方的玻璃条）。
///
/// 只过滤已在队列里的歌，不联网——桌面歌词覆盖层是独立引擎，没有网络与鉴权栈
/// （见 SuperCyreneSongGallery 的类注释），本地筛选让两端行为完全一致。
class _SearchBox extends StatefulWidget {
  const _SearchBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 260,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: .45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    onChanged: widget.onChanged,
                    // 展览馆用方向键在卡片间跳转（见 CallbackShortcuts）。
                    // 输入框获得焦点时那些绑定会拦掉光标移动，因此不自动聚焦，
                    // 由用户主动点击进入输入态。
                    autofocus: false,
                    cursorColor: const Color(0xFFA78BFA),
                    cursorHeight: 14,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '搜索队列中的歌曲',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: .35),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                // 有内容时才占位，避免空搜索时右侧留一块空白。
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: widget.onClear,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: Colors.white.withValues(alpha: .55),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.size, required this.onTap});
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size, color: Colors.white.withValues(alpha: .70)),
        ),
      );
}

/// 从 [offset] 滑入的玻璃面板容器。
class _SlideIn extends StatefulWidget {
  const _SlideIn({required this.offset, required this.child});
  final Offset offset;
  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<Offset> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _anim = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: _anim.value,
            child: child,
          ),
        ),
        child: widget.child,
      );
}
