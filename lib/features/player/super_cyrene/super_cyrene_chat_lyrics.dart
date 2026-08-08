import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../application/playback/playback_controller.dart';
import '../../../domain/models/music_source.dart';
import '../../../domain/models/track.dart';
import '../mobile/compat/color_extraction_service.dart';
import '../mobile/compat/lyric_line.dart';
import '../mobile/compat/lyric_parser.dart';
import 'default_core/default_types.dart';
import 'super_cyrene_lyric_timing.dart';

enum _ChatSide { left, right }

sealed class _ChatMessage {
  const _ChatMessage(this.id);
  final String id;
}

class _ChatTitleMessage extends _ChatMessage {
  const _ChatTitleMessage({required this.text}) : super('title');
  final String text;
}

class _ChatLineMessage extends _ChatMessage {
  const _ChatLineMessage({
    required String id,
    required this.line,
    required this.lineIndex,
    required this.side,
    required this.avatarIndex,
  }) : super(id);
  final DefaultLine line;
  final int lineIndex;
  final _ChatSide side;
  final int avatarIndex;
}

class _ChatDividerMessage extends _ChatMessage {
  const _ChatDividerMessage({
    required String id,
    required this.lineIndex,
    required this.label,
  }) : super(id);
  final int lineIndex;
  final String label;
}

class _ChatSender {
  const _ChatSender(this.side, this.avatarIndex);
  final _ChatSide side;
  final int avatarIndex;
}

class _ChatTheme {
  const _ChatTheme({
    required this.primary,
    required this.accent,
    required this.secondary,
    required this.background,
  });
  final Color primary;
  final Color accent;
  final Color secondary;
  final Color background;

  factory _ChatTheme.fromHue(double sourceHue) {
    final warmHue = 34 + 16 * math.cos((sourceHue % 360 / 360) * math.pi * 2);
    Color hsl(double hue, double saturation, double lightness) =>
        HSLColor.fromAHSL(1, hue % 360, saturation, lightness).toColor();
    return _ChatTheme(
      primary: hsl(warmHue, .16, .95),
      accent: hsl(warmHue, .52, .68),
      secondary: hsl(warmHue + 8, .34, .50),
      background: hsl(warmHue, .30, .14),
    );
  }
}

const _chatMaxTextWidth = 513.0;
const _chatActiveFontSize = 18 * 1.24;
const _chatActiveLineHeight = 1.45;
const _chatActiveScale = 1.08;
const _chatActivePaddingY = 16.0;
const _chatBubbleSizeLookahead = .32;

double _chatLyricSlotHeight(
  String text, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text.isEmpty ? ' ' : text,
      style: const TextStyle(
        fontSize: _chatActiveFontSize,
        fontWeight: FontWeight.w400,
        height: _chatActiveLineHeight,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout(maxWidth: _chatMaxTextWidth);
  // Flutter's decorated Container also includes the one-pixel border in its
  // padding. Reserve the fully enlarged bubble, not its inactive dimensions.
  final bubbleHeight = math.max(
    64.0,
    painter.height + _chatActivePaddingY * 2 + 2,
  );
  painter.dispose();
  return math.max(40.0, bubbleHeight * _chatActiveScale);
}

class SuperCyreneChatLyrics extends StatefulWidget {
  const SuperCyreneChatLyrics({
    super.key,
    required this.playback,
    required this.track,
    required this.cover,
    this.rightAvatarUrl,
  });

  final PlaybackController playback;
  final Track track;
  final ImageProvider? cover;
  final String? rightAvatarUrl;

  @override
  State<SuperCyreneChatLyrics> createState() => _SuperCyreneChatLyricsState();
}

class _SuperCyreneChatLyricsState extends State<SuperCyreneChatLyrics> {
  static const _sideSequence = <_ChatSide>[
    _ChatSide.left,
    _ChatSide.right,
    _ChatSide.left,
    _ChatSide.right,
    _ChatSide.right,
  ];
  static const _rightAvatarIndex = 8;

  List<DefaultLine> _lines = const [];
  List<_ChatMessage> _messages = const [];
  _ChatTheme _theme = _ChatTheme.fromHue(258);
  int _currentLineIndex = -1;
  int _visibleLineIndex = -1;
  String? _enteringMessageId;
  int _colorRequest = 0;

  @override
  void initState() {
    super.initState();
    widget.playback.positionListenable.addListener(_onPosition);
    _adaptTrack();
    _extractTheme();
  }

  @override
  void didUpdateWidget(covariant SuperCyreneChatLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.positionListenable.removeListener(_onPosition);
      widget.playback.positionListenable.addListener(_onPosition);
    }
    if (_signature(oldWidget.track) != _signature(widget.track)) {
      _adaptTrack();
      _extractTheme();
    }
  }

  int _signature(Track track) =>
      Object.hash(track.key, track.lyric, track.yrc, track.tlyric, track.ytlrc);

  @override
  void dispose() {
    _colorRequest++;
    widget.playback.positionListenable.removeListener(_onPosition);
    super.dispose();
  }

  Future<void> _extractTheme() async {
    final request = ++_colorRequest;
    final url = widget.track.picUrl;
    if (url.isEmpty) {
      setState(() => _theme = _ChatTheme.fromHue(258));
      return;
    }
    final result = await ColorExtractionService().extractColorsFromUrl(
      url,
      sampleSize: 32,
      timeout: const Duration(seconds: 3),
    );
    if (!mounted || request != _colorRequest) return;
    final color = result?.themeColor;
    final hue = color == null ? 258.0 : HSVColor.fromColor(color).hue;
    setState(() => _theme = _ChatTheme.fromHue(hue));
  }

  void _adaptTrack() {
    final lyric = widget.track.lyric;
    final parsed = lyric == null || lyric.isEmpty
        ? const <LyricLine>[]
        : switch (widget.track.source) {
            MusicSource.qq => LyricParser.parseQQLyric(
              lyric,
              translation: widget.track.tlyric,
              qrcLyric: widget.track.yrc,
              qrcTranslation: widget.track.ytlrc,
            ),
            MusicSource.kugou => LyricParser.parseKugouLyric(
              lyric,
              translation: widget.track.tlyric,
            ),
            _ => LyricParser.parseNeteaseLyric(
              lyric,
              translation: widget.track.tlyric,
              yrcLyric: widget.track.yrc,
              yrcTranslation: widget.track.ytlrc,
            ),
          };
    _lines = parsed.indexed
        .where((entry) => entry.$2.text.trim().isNotEmpty)
        .map((entry) => _adaptLine(entry.$2, entry.$1, parsed))
        .toList(growable: false);
    _messages = _buildMessages(_lines, widget.track.name);
    _currentLineIndex = _findLine(_positionSeconds);
    _visibleLineIndex = _currentLineIndex;
    _enteringMessageId = null;
  }

  DefaultLine _adaptLine(LyricLine line, int index, List<LyricLine> source) {
    final fallbackEnd = index + 1 < source.length
        ? source[index + 1].startTime
        : line.startTime + (line.lineDuration ?? const Duration(seconds: 4));
    final declaredEnd =
        line.startTime + (line.lineDuration ?? fallbackEnd - line.startTime);
    final end =
        index + 1 < source.length && declaredEnd > source[index + 1].startTime
        ? source[index + 1].startTime
        : declaredEnd;
    return DefaultLine(
      id: '${line.startTime.inMilliseconds}-$index',
      fullText: line.text,
      startTime: line.startTime.inMicroseconds / 1000000,
      endTime: end.inMicroseconds / 1000000,
      translation: line.translation,
      words: buildSuperCyreneWordTimeline(line: line, lineEnd: end),
    );
  }

  double get _positionSeconds =>
      widget.playback.positionListenable.value.inMicroseconds / 1000000 + .3;

  int _findLine(double time) {
    for (var index = _lines.length - 1; index >= 0; index--) {
      if (time >= _lines[index].startTime) return index;
    }
    return -1;
  }

  void _onPosition() {
    if (!mounted) return;
    final next = _findLine(_positionSeconds);
    if (next == _currentLineIndex && next == _visibleLineIndex) return;
    final shouldEnter = next >= 0 && next > _visibleLineIndex;
    setState(() {
      _currentLineIndex = next;
      _visibleLineIndex = next;
      _enteringMessageId = shouldEnter
          ? 'line-${_lines[next].startTime}-$next'
          : null;
    });
  }

  List<_ChatMessage> _buildMessages(List<DefaultLine> lines, String title) {
    final messages = <_ChatMessage>[
      _ChatTitleMessage(text: title.trim().isEmpty ? '对话' : title.trim()),
    ];
    var sequenceCursor = 0;
    var nextLeftAvatar = 0;
    _ChatSender? lastSender;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (index > 0 && line.startTime - lines[index - 1].endTime >= 8) {
        messages.add(
          _ChatDividerMessage(
            id: 'divider-${line.startTime}-$index',
            lineIndex: index,
            label: _timestamp(line.startTime),
          ),
        );
      }
      final shortLine =
          line.fullText.replaceAll(RegExp(r'\s'), '').characters.length <= 12;
      final forceRight = (index + 1) % 5 == 0;
      final carry =
          !forceRight &&
          shortLine &&
          lastSender != null &&
          _seededUnit('carry', line.startTime, index) <= .68;
      final base = _sideSequence[sequenceCursor % _sideSequence.length];
      final flip =
          !forceRight && _seededUnit('flip', line.startTime, index) < .18;
      final resolved = flip
          ? (base == _ChatSide.left ? _ChatSide.right : _ChatSide.left)
          : base;
      late final _ChatSender sender;
      if (forceRight) {
        sender = const _ChatSender(_ChatSide.right, _rightAvatarIndex);
      } else if (carry) {
        sender = lastSender;
      } else {
        sender = _ChatSender(
          resolved,
          resolved == _ChatSide.left ? nextLeftAvatar : _rightAvatarIndex,
        );
      }
      messages.add(
        _ChatLineMessage(
          id: 'line-${line.startTime}-$index',
          line: line,
          lineIndex: index,
          side: sender.side,
          avatarIndex: sender.avatarIndex,
        ),
      );
      if (forceRight) {
        sequenceCursor = 0;
        lastSender = null;
      } else if (!carry) {
        if (sender.side == _ChatSide.left) nextLeftAvatar++;
        sequenceCursor++;
        lastSender = sender;
      } else {
        lastSender = sender;
      }
    }
    return List.unmodifiable(messages);
  }

  int _hash(String input) {
    var hash = 2166136261;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash;
  }

  double _seededUnit(Object a, Object b, Object c) =>
      (_hash('$a|$b|$c') & 0xffffffff) / 0xffffffff;

  String _timestamp(double seconds) {
    final total = math.max(0, seconds.floor());
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  List<_ChatMessage> _visibleMessages(
    double viewportHeight,
    TextScaler textScaler,
  ) {
    final available = _messages.where((message) {
      if (message is _ChatTitleMessage) return true;
      if (message is _ChatDividerMessage) {
        return message.lineIndex <= _visibleLineIndex;
      }
      return (message as _ChatLineMessage).lineIndex <= _visibleLineIndex;
    }).toList();
    final usableHeight = math.max(200.0, viewportHeight - 240);
    var height = 0.0;
    final result = <_ChatMessage>[];
    for (var index = available.length - 1; index >= 0; index--) {
      final message = available[index];
      final estimate = message is _ChatTitleMessage
          ? 40.0
          : message is _ChatDividerMessage
          ? 44.0
          : _chatLyricSlotHeight(
              (message as _ChatLineMessage).line.fullText,
              textScaler: textScaler,
            );
      if (height + estimate > usableHeight && result.length >= 2) break;
      height += estimate + 12;
      result.insert(0, message);
      if (result.length >= 20) break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .30),
            fontSize: 14,
            letterSpacing: 2.8,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final messages = _visibleMessages(
          constraints.maxHeight,
          MediaQuery.textScalerOf(context),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(56, 80, 56, 160),
          child: Align(
            // Anchor the conversation to the bottom. When the incoming row
            // expands from zero height, existing messages are pushed upward
            // like a real Telegram conversation instead of staying fixed.
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 896),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < messages.length; index++)
                    _buildVisibleMessageEntry(
                      messages[index],
                      hasTopGap: index > 0,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVisibleMessageEntry(
    _ChatMessage message, {
    required bool hasTopGap,
  }) {
    final content = Padding(
      padding: EdgeInsets.only(top: hasTopGap ? 12 : 0),
      child: _buildMessage(message),
    );
    return KeyedSubtree(
      key: ValueKey(message.id),
      child: message.id == _enteringMessageId
          ? _ChatMessageEntrance(
              key: ValueKey('entrance-${message.id}'),
              child: content,
            )
          : content,
    );
  }

  Widget _buildMessage(_ChatMessage message) => switch (message) {
    final _ChatDividerMessage divider => _ChatDivider(
      label: divider.label,
      theme: _theme,
    ),
    final _ChatTitleMessage title => _ChatBubbleRow(
      id: title.id,
      side: _ChatSide.right,
      avatarIndex: _rightAvatarIndex,
      text: title.text,
      theme: _theme,
      cover: widget.cover,
      rightAvatarUrl: widget.rightAvatarUrl,
      active: false,
      passed: false,
    ),
    final _ChatLineMessage line => _ChatBubbleRow(
      id: line.id,
      side: line.side,
      avatarIndex: line.avatarIndex,
      text: line.line.fullText,
      line: line.line,
      playback: widget.playback,
      theme: _theme,
      cover: widget.cover,
      rightAvatarUrl: widget.rightAvatarUrl,
      active: line.lineIndex == _currentLineIndex,
      passed: line.lineIndex < _currentLineIndex,
    ),
  };
}

class _ChatBubbleRow extends StatelessWidget {
  const _ChatBubbleRow({
    required this.id,
    required this.side,
    required this.avatarIndex,
    required this.text,
    required this.theme,
    required this.cover,
    required this.rightAvatarUrl,
    required this.active,
    required this.passed,
    this.line,
    this.playback,
  });

  final String id;
  final _ChatSide side;
  final int avatarIndex;
  final String text;
  final DefaultLine? line;
  final PlaybackController? playback;
  final _ChatTheme theme;
  final ImageProvider? cover;
  final String? rightAvatarUrl;
  final bool active;
  final bool passed;

  Color _mix(Color a, Color b, double amount, [double opacity = 1]) =>
      Color.fromRGBO(
        (a.r * 255 + (b.r - a.r) * 255 * amount).round(),
        (a.g * 255 + (b.g - a.g) * 255 * amount).round(),
        (a.b * 255 + (b.b - a.b) * 255 * amount).round(),
        opacity,
      );

  @override
  Widget build(BuildContext context) {
    final right = side == _ChatSide.right;
    final avatarTone = (avatarIndex % 9) / 8;
    final accentMix = .18 + avatarTone * .62;
    final background = right
        ? _mix(theme.accent, theme.primary, .18, .94)
        : _mix(theme.secondary, theme.accent, accentMix);
    final border = right
        ? _mix(theme.accent, theme.primary, .34, .30)
        : _mix(
            theme.secondary,
            theme.accent,
            math.min(accentMix + .18, 1),
            .26,
          );
    final textColor = right ? theme.background : theme.primary;
    final fontSize = active
        ? _chatActiveFontSize
        : line == null
        ? 18.0
        : 18 * .95;
    final padding = active
        ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

    Widget bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(
        maxWidth: 553,
        minWidth: active ? 72 : 0,
        minHeight: active ? 64 : 44,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        gradient: active
            ? LinearGradient(
                begin: const Alignment(-1, -.45),
                end: const Alignment(1, .45),
                colors: [
                  background,
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: right ? .22 : .12),
                    background,
                  ),
                  background,
                ],
                stops: const [0, .38, 1],
              )
            : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(24),
          topRight: const Radius.circular(24),
          bottomLeft: Radius.circular(right ? 24 : 4),
          bottomRight: Radius.circular(right ? 4 : 24),
        ),
        border: Border.all(color: border),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _mix(theme.background, theme.accent, .2, .26),
                  blurRadius: 48,
                  offset: const Offset(0, 18),
                ),
              ]
            : const [],
      ),
      child: active && line != null && playback != null
          ? _ActiveChatText(
              line: line!,
              playback: playback!,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            )
          : Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
    );
    if (line != null && passed) {
      final total = math.max(0, line!.endTime.floor());
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          Positioned(
            bottom: 4,
            left: right ? null : -40,
            right: right ? -40 : null,
            child: Text(
              '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                color: theme.secondary.withValues(alpha: .62),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }
    bubble = AnimatedScale(
      scale: active
          ? _chatActiveScale
          : passed
          ? .95
          : 1,
      // Keep the top edge stable. Bottom anchoring made an outgoing bubble
      // shrink downward immediately before the incoming row pushed the queue
      // upward, producing a conspicuous down-then-up movement.
      alignment: right ? Alignment.topRight : Alignment.topLeft,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: passed ? .86 : 1,
        duration: const Duration(milliseconds: 240),
        child: bubble,
      ),
    );

    final row = Row(
      mainAxisAlignment: right
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: right
          ? [
              const Spacer(flex: 32),
              Flexible(flex: 68, child: bubble),
              const SizedBox(width: 12),
              _ChatAvatar(
                side: side,
                avatarIndex: avatarIndex,
                cover: cover,
                rightAvatarUrl: rightAvatarUrl,
                theme: theme,
              ),
            ]
          : [
              _ChatAvatar(
                side: side,
                avatarIndex: avatarIndex,
                cover: cover,
                rightAvatarUrl: rightAvatarUrl,
                theme: theme,
              ),
              const SizedBox(width: 12),
              Flexible(flex: 68, child: bubble),
              const Spacer(flex: 32),
            ],
    );
    if (line == null) return row;

    // Every lyric row owns the height of its fully revealed, active and scaled
    // bubble. Inactive shrinking is paint-only, so changing the active message
    // can no longer move the surrounding queue.
    return SizedBox(
      height: _chatLyricSlotHeight(
        line!.fullText,
        textScaler: MediaQuery.textScalerOf(context),
      ),
      child: Align(alignment: Alignment.topCenter, child: row),
    );
  }
}

class _ChatMessageEntrance extends StatefulWidget {
  const _ChatMessageEntrance({super.key, required this.child});

  final Widget child;

  @override
  State<_ChatMessageEntrance> createState() => _ChatMessageEntranceState();
}

class _ChatMessageEntranceState extends State<_ChatMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _size;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _size = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .82, curve: Curves.easeOutCubic),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .62, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, .48),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _scale = Tween<double>(
      begin: .965,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    alignment: Alignment.bottomCenter,
    child: FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          alignment: Alignment.bottomCenter,
          scale: _scale,
          child: widget.child,
        ),
      ),
    ),
  );
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.side,
    required this.avatarIndex,
    required this.cover,
    required this.rightAvatarUrl,
    required this.theme,
  });
  final _ChatSide side;
  final int avatarIndex;
  final ImageProvider? cover;
  final String? rightAvatarUrl;
  final _ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final rightUser =
        side == _ChatSide.right && rightAvatarUrl?.isNotEmpty == true;
    final resolvedIndex = side == _ChatSide.right
        ? 8
        : const [0, 4][avatarIndex % 2];
    final col = resolvedIndex % 3;
    final row = resolvedIndex ~/ 3;
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [theme.primary, theme.accent]),
        border: Border.all(color: Colors.white.withValues(alpha: .24)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12)],
      ),
      child: rightUser
          ? Image.network(rightAvatarUrl!, fit: BoxFit.cover)
          : cover == null
          ? null
          : SizedBox(
              width: 40,
              height: 40,
              child: OverflowBox(
                maxWidth: 120,
                maxHeight: 120,
                alignment: Alignment(
                  col == 0
                      ? -1
                      : col == 1
                      ? 0
                      : 1,
                  row == 0
                      ? -1
                      : row == 1
                      ? 0
                      : 1,
                ),
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: Image(image: cover!, fit: BoxFit.cover),
                ),
              ),
            ),
    );
  }
}

class _ActiveChatText extends StatefulWidget {
  const _ActiveChatText({
    required this.line,
    required this.playback,
    required this.style,
  });
  final DefaultLine line;
  final PlaybackController playback;
  final TextStyle style;

  @override
  State<_ActiveChatText> createState() => _ActiveChatTextState();
}

class _ActiveChatTextState extends State<_ActiveChatText>
    with SingleTickerProviderStateMixin {
  static const _springStiffness = 260.0;
  static const _springDamping = 34.0;
  static const _springMass = .8;

  late final AnimationController _visualClock;
  final Stopwatch _wallClock = Stopwatch();
  double _anchorPosition = 0;
  Duration _anchorWallTime = Duration.zero;
  Duration _lastSpringWallTime = Duration.zero;
  double _bubbleWidth = 0;
  double _bubbleHeight = 0;
  double _bubbleWidthVelocity = 0;
  double _bubbleHeightVelocity = 0;
  bool _springInitialized = false;

  @override
  void initState() {
    super.initState();
    _wallClock.start();
    _visualClock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    widget.playback.positionListenable.addListener(_syncPosition);
    widget.playback.addListener(_syncPlaybackState);
    _syncPosition();
    // The original Framer Motion spring keeps ticking independently from the
    // playback clock so it can finish settling after pauses and seeks.
    _visualClock.repeat();
  }

  @override
  void didUpdateWidget(covariant _ActiveChatText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.positionListenable.removeListener(_syncPosition);
      oldWidget.playback.removeListener(_syncPlaybackState);
      widget.playback.positionListenable.addListener(_syncPosition);
      widget.playback.addListener(_syncPlaybackState);
      _syncPosition();
    }
    if (oldWidget.line != widget.line || oldWidget.style != widget.style) {
      _springInitialized = false;
      _bubbleWidthVelocity = 0;
      _bubbleHeightVelocity = 0;
    }
  }

  void _syncPosition() {
    _anchorPosition =
        widget.playback.positionListenable.value.inMicroseconds / 1000000 + .3;
    _anchorWallTime = _wallClock.elapsed;
    // A paused seek has no running visual ticker to request a frame.
    if (mounted && !_visualClock.isAnimating) setState(() {});
  }

  void _syncPlaybackState() {
    _syncPosition();
  }

  double get _visualPosition {
    if (!widget.playback.state.isPlaying) return _anchorPosition;
    return _anchorPosition +
        (_wallClock.elapsed - _anchorWallTime).inMicroseconds / 1000000;
  }

  @override
  void dispose() {
    widget.playback.positionListenable.removeListener(_syncPosition);
    widget.playback.removeListener(_syncPlaybackState);
    _visualClock.dispose();
    _wallClock.stop();
    super.dispose();
  }

  List<(String, double, double)> _characters() {
    final result = <(String, double, double)>[];
    for (final word in widget.line.words) {
      final chars = word.text.characters.toList();
      final duration = math.max(.04, word.endTime - word.startTime);
      for (var index = 0; index < chars.length; index++) {
        final start = word.startTime + duration * index / chars.length;
        final fade = math.max(.04, math.min(.22, duration / chars.length));
        result.add((chars[index], start, fade));
      }
    }
    if (result.isEmpty) return result;

    // A few lyric providers let the final word timing extend past the line's
    // effective end. Compress only when necessary so every character finishes
    // revealing before this row is replaced by the next one.
    final sourceEnd = result.fold<double>(
      result.first.$2 + result.first.$3,
      (latest, item) => math.max(latest, item.$2 + item.$3),
    );
    final anchor = math.min(widget.line.startTime, result.first.$2);
    final deadline = math.max(anchor + .008, widget.line.endTime - .06);
    if (sourceEnd <= deadline) return result;

    final sourceSpan = math.max(.001, sourceEnd - anchor);
    final scale = math.max(.001, (deadline - anchor) / sourceSpan);
    return result
        .map(
          (item) =>
              (item.$1, anchor + (item.$2 - anchor) * scale, item.$3 * scale),
        )
        .toList(growable: false);
  }

  double _springStep(double value, double target, double velocity, double dt) {
    final acceleration =
        (-_springStiffness * (value - target) - _springDamping * velocity) /
        _springMass;
    return velocity + acceleration * dt;
  }

  void _advanceBubbleSpring(double targetWidth, double targetHeight) {
    final now = _wallClock.elapsed;
    if (!_springInitialized) {
      // Framer's spring.jump() is also used by the Next.js implementation when
      // a line first becomes active, avoiding a visible expansion from zero.
      _bubbleWidth = targetWidth;
      _bubbleHeight = targetHeight;
      _lastSpringWallTime = now;
      _springInitialized = true;
      return;
    }

    double remaining = math.min(
      .05,
      math.max(0.0, (now - _lastSpringWallTime).inMicroseconds / 1000000),
    );
    _lastSpringWallTime = now;
    while (remaining > 0) {
      final double dt = math.min(remaining, 1 / 120);
      _bubbleWidthVelocity = _springStep(
        _bubbleWidth,
        targetWidth,
        _bubbleWidthVelocity,
        dt,
      );
      _bubbleHeightVelocity = _springStep(
        _bubbleHeight,
        targetHeight,
        _bubbleHeightVelocity,
        dt,
      );
      _bubbleWidth += _bubbleWidthVelocity * dt;
      _bubbleHeight += _bubbleHeightVelocity * dt;
      remaining -= dt;
    }

    if ((_bubbleWidth - targetWidth).abs() < .02 &&
        _bubbleWidthVelocity.abs() < .02) {
      _bubbleWidth = targetWidth;
      _bubbleWidthVelocity = 0;
    }
    if ((_bubbleHeight - targetHeight).abs() < .02 &&
        _bubbleHeightVelocity.abs() < .02) {
      _bubbleHeight = targetHeight;
      _bubbleHeightVelocity = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _characters();
    return AnimatedBuilder(
      animation: _visualClock,
      builder: (context, _) {
        final time = _visualPosition;
        final textScaler = MediaQuery.textScalerOf(context);
        final spans = <InlineSpan>[];
        for (final item in plan) {
          if (time + _chatBubbleSizeLookahead < item.$2) break;
          final opacity = ((time - item.$2) / item.$3).clamp(0.0, 1.0);
          spans.add(
            TextSpan(
              text: item.$1,
              style: widget.style.copyWith(
                color: widget.style.color?.withValues(alpha: opacity),
              ),
            ),
          );
        }
        final paragraph = TextPainter(
          text: TextSpan(children: spans),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout(maxWidth: _chatMaxTextWidth);
        final lineHeight =
            textScaler.scale(widget.style.fontSize ?? 18) *
            (widget.style.height ?? 1);
        final targetWidth = math.max(
          textScaler.scale(widget.style.fontSize ?? 18),
          paragraph.width.ceilToDouble() + 1,
        );
        final targetHeight = math.max(
          lineHeight,
          paragraph.height.ceilToDouble() + 1,
        );
        paragraph.dispose();
        _advanceBubbleSpring(targetWidth, targetHeight);

        return SizedBox(
          width: _bubbleWidth,
          height: _bubbleHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: _chatMaxTextWidth,
              maxWidth: _chatMaxTextWidth,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Text.rich(
                TextSpan(children: spans),
                textScaler: textScaler,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatDivider extends StatelessWidget {
  const _ChatDivider({required this.label, required this.theme});
  final String label;
  final _ChatTheme theme;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 64,
        height: 1,
        color: theme.secondary.withValues(alpha: .24),
      ),
      const SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(
          color: theme.primary.withValues(alpha: .70),
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 2.8,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(width: 12),
      Container(
        width: 64,
        height: 1,
        color: theme.secondary.withValues(alpha: .24),
      ),
    ],
  );
}
