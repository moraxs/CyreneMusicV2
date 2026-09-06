import 'package:flutter/foundation.dart';

import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/services/netease_comment_service.dart';
import '../../infrastructure/services/qq_comment_service.dart';

/// 喂给模型的「这首歌的材料」。
///
/// 存在的意义：不让模型靠记忆答题。只给歌名/歌手时，冷门歌必然是「我不了解这首
/// 歌」——这不是模型的问题，是没给材料。有了材料，任务就从「回忆」变成「读材料
/// 写评述」，模型认不认识这首歌都不影响。
class SongContext {
  const SongContext({
    required this.track,
    this.lyric = '',
    this.styles = const [],
    this.language = '',
    this.bpm = '',
    this.artistBio = '',
    this.comments = const [],
  });

  final Track track;

  /// 去掉时间戳后的纯歌词文本。
  final String lyric;
  final List<String> styles;
  final String language;
  final String bpm;
  final String artistBio;

  /// 热门评论正文（真实听感，对赏析很有用）。
  final List<String> comments;

  bool get hasLyric => lyric.trim().isNotEmpty;

  bool get hasFacts =>
      styles.isNotEmpty ||
      language.isNotEmpty ||
      bpm.isNotEmpty ||
      artistBio.trim().isNotEmpty;

  /// 除了歌名歌手之外，一点材料都没有。
  bool get isBare => !hasLyric && !hasFacts && comments.isEmpty;

  /// 拼成给模型看的材料块。刻意用朴素的分节标题，不用 Markdown——
  /// 这是给模型读的输入，不是给人看的排版。
  String toPrompt() {
    final buffer = StringBuffer()
      ..writeln('歌名：${track.name}')
      ..writeln('歌手：${track.artists}');
    if (track.album.isNotEmpty) buffer.writeln('专辑：${track.album}');
    if (styles.isNotEmpty) buffer.writeln('曲风：${styles.join(' / ')}');
    if (language.isNotEmpty) buffer.writeln('语种：$language');
    if (bpm.isNotEmpty) buffer.writeln('BPM：$bpm');
    if (artistBio.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('【歌手简介】')
        ..writeln(_cap(artistBio.trim(), _artistBioLimit));
    }
    if (hasLyric) {
      buffer
        ..writeln()
        ..writeln('【歌词】')
        ..writeln(_cap(lyric.trim(), _lyricLimit));
    }
    if (comments.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('【听众热评】')
        ..writeln(
          comments
              .take(_commentCount)
              .map((text) => '- ${_cap(text.trim(), _commentLimit)}')
              .join('\n'),
        );
    }
    return buffer.toString();
  }

  /// 这次赏析是基于什么写的，用来告诉模型「把依据说清楚」。
  String get basis {
    final parts = [
      if (hasLyric) '歌词',
      if (styles.isNotEmpty || bpm.isNotEmpty || language.isNotEmpty) '曲目资料',
      if (artistBio.trim().isNotEmpty) '歌手简介',
      if (comments.isNotEmpty) '听众热评',
    ];
    return parts.join('、');
  }

  // 各段的长度上限：材料是按 token 计费的，而且塞太多反而会稀释重点。
  static const _lyricLimit = 1600;
  static const _artistBioLimit = 600;
  static const _commentLimit = 120;
  static const _commentCount = 8;

  static String _cap(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';
}

/// 收集一首歌的可用材料。
///
/// 曲风/BPM/语种/歌手简介由调用方传入——「歌曲信息」面板早就把它们加载好了，
/// 这里再拉一遍纯属浪费。只有热门评论是这里现取的（面板里的评论组件自己管自己
/// 的分页状态，拿不到），而且只在用户真的点了「生成赏析」时才会走到。
class SongContextBuilder {
  const SongContextBuilder();

  Future<SongContext> build(
    Track track, {
    List<String> styles = const [],
    String language = '',
    String bpm = '',
    String artistBio = '',
    bool includeComments = true,
  }) async {
    return SongContext(
      track: track,
      lyric: stripTimestamps(track.lyric ?? ''),
      styles: styles,
      language: language,
      bpm: bpm,
      artistBio: artistBio,
      comments: includeComments ? await _hotComments(track) : const [],
    );
  }

  Future<List<String>> _hotComments(Track track) async {
    try {
      final comments = switch (track.source) {
        MusicSource.netease => await NeteaseCommentService.instance
            .fetchSongComments(track.id, limit: 20, sortType: 1),
        MusicSource.qq => await QqCommentService.instance.fetchSongComments(
          track.id,
          pagesize: 20,
          sortType: 1,
        ),
        _ => null,
      };
      if (comments == null) return const [];
      final hot = comments.hotComments.isNotEmpty
          ? comments.hotComments
          : comments.comments;
      return hot
          .map((item) => item.content.trim())
          .where((text) => text.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      // 评论只是加分项，取不到就算了，别把整个赏析拖垮。
      debugPrint('[AI] 取热评失败: $error');
      return const [];
    }
  }

  /// 去掉 `[00:12.34]` 这类时间戳与空行，只留可读的歌词正文。
  ///
  /// 逐字歌词（yrc）里还有 `(1234,567,0)` 这种逐字时间，一并清掉。
  @visibleForTesting
  static String stripTimestamps(String raw) {
    if (raw.trim().isEmpty) return '';
    final lines = raw
        .split('\n')
        .map(
          (line) => line
              .replaceAll(RegExp(r'\[[0-9:.\s]+\]'), '')
              .replaceAll(RegExp(r'\(\d+,\d+,\d+\)'), '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        // 元数据行（作词/作曲/编曲…）留着有用，但 `[by:xxx]` 这类已经被上面清空了。
        .toList();
    return lines.join('\n');
  }
}
