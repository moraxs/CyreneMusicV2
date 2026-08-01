import 'package:flutter/material.dart';

import '../../domain/lyrics/lyric_parser.dart';
import '../../domain/lyrics/lyric_timeline.dart';
import '../../domain/models/track.dart';

class LyricView extends StatelessWidget {
  const LyricView({super.key, required this.track, required this.position});

  final Track track;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final lines = const LyricParser().parse(
      source: track.source,
      lyric: track.lyric,
      yrc: track.yrc,
      translation: track.tlyric,
      verbatimTranslation: track.ytlrc,
    );
    if (lines.isEmpty) {
      return const Center(child: Text('这首歌还没有歌词。'));
    }

    final activeIndex = LyricTimeline(lines).activeLineIndexAt(position);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final active = index == activeIndex;
        final color = active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (line.translation case final translation?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    translation,
                    style: TextStyle(color: color.withValues(alpha: .72)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
