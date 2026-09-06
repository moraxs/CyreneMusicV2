import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/ai/ai_models.dart';
import '../../domain/models/track.dart';
import '../../infrastructure/ai/ai_client.dart';
import 'song_context.dart';

/// 单曲赏析的生成状态（一首歌一份）。
class SongAppreciation {
  const SongAppreciation({
    this.text = '',
    this.streaming = false,
    this.error,
  });

  final String text;
  final bool streaming;
  final String? error;

  bool get isEmpty => text.isEmpty && error == null && !streaming;
}

/// 「单曲赏析」：按需生成，按曲目缓存。
///
/// 两条硬规矩：
/// - **绝不自动触发**。用户点了才发请求——这是花用户自己的钱，切一首歌就烧一次
///   token 是不能接受的。
/// - **结果按曲目缓存**。面板来回切、歌单里切回同一首，都不该重复付费。
class SongAppreciationController extends ChangeNotifier {
  SongAppreciationController._();

  static final SongAppreciationController instance =
      SongAppreciationController._();

  @visibleForTesting
  SongAppreciationController.forTest({AiClient? client, SongContextBuilder? contextBuilder})
    : _client = client ?? AiClient.instance,
      _contextBuilder = contextBuilder ?? const SongContextBuilder();

  AiClient _client = AiClient.instance;
  SongContextBuilder _contextBuilder = const SongContextBuilder();

  @visibleForTesting
  set client(AiClient value) => _client = value;

  @visibleForTesting
  set contextBuilder(SongContextBuilder value) => _contextBuilder = value;

  final Map<String, SongAppreciation> _byTrack = {};
  final Map<String, StreamSubscription<String>> _running = {};

  /// 缓存上限：一次听歌不会翻几百首，留这些足够，也不至于常驻一大坨文本。
  static const _cacheLimit = 40;

  SongAppreciation of(Track track) =>
      _byTrack[track.key] ?? const SongAppreciation();

  /// 生成（或重新生成）赏析。已在生成中就忽略。
  ///
  /// [styles] / [language] / [bpm] / [artistBio] 由调用方从「歌曲信息」面板
  /// 已加载的数据里传进来——那边早就取过了，这里再拉一遍纯属浪费。
  Future<void> generate(
    Track track, {
    bool force = false,
    List<String> styles = const [],
    String language = '',
    String bpm = '',
    String artistBio = '',
  }) async {
    final key = track.key;
    if (_running.containsKey(key)) return;
    if (!force && (_byTrack[key]?.text.isNotEmpty ?? false)) return;

    _put(key, const SongAppreciation(streaming: true));
    final context = await _contextBuilder.build(
      track,
      styles: styles,
      language: language,
      bpm: bpm,
      artistBio: artistBio,
    );
    final buffer = StringBuffer();
    final completer = Completer<void>();
    final subscription = _client
        .stream(system: _systemPrompt, prompt: _promptFor(context))
        .listen(
          (delta) {
            buffer.write(delta);
            _put(key, SongAppreciation(text: buffer.toString(), streaming: true));
          },
          onError: (Object error) {
            _running.remove(key);
            _put(
              key,
              SongAppreciation(
                text: buffer.toString(),
                error: error is AiException ? error.message : '$error',
              ),
            );
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            _running.remove(key);
            final text = buffer.toString().trim();
            _put(
              key,
              text.isEmpty
                  ? const SongAppreciation(error: '模型没有返回内容，换个模型试试')
                  : SongAppreciation(text: text),
            );
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    _running[key] = subscription;
    await completer.future;
  }

  /// 放弃这首歌正在进行的生成（用户切走了/收起了卡片）。
  void cancel(Track track) {
    final subscription = _running.remove(track.key);
    if (subscription == null) return;
    unawaited(subscription.cancel());
    final current = _byTrack[track.key];
    _put(
      track.key,
      SongAppreciation(text: current?.text ?? '', streaming: false),
    );
  }

  void _put(String key, SongAppreciation value) {
    _byTrack[key] = value;
    if (_byTrack.length > _cacheLimit) {
      _byTrack.remove(_byTrack.keys.first);
    }
    notifyListeners();
  }

  /// 提示词的关键在于**任务性质**：不是「回忆这首歌」，而是「读材料写评述」。
  ///
  /// 只给歌名歌手时，冷门歌必然换来「我不了解这首歌，不便编造」——那是正确的
  /// 拒答，问题出在没给材料。所以这里明确要求它以材料为准、不要依赖记忆，
  /// 同时保留「不许编造材料里没有的事实」这条底线。
  static const _systemPrompt =
      '你是一位懂行但不掉书袋的乐评人。下面会给你一首歌的资料，'
      '请**只依据这些资料**用中文写一段赏析，150 到 250 字，一到两段，'
      '不要标题、不要列表、不要 Markdown 标记。\n'
      '几条要求：\n'
      '1. 不要因为「没听过这首歌」而拒绝——你的任务是读资料写评述，不是回忆。\n'
      '2. 不要编造资料里没有的事实（获奖、销量、发行背景、创作故事等）。'
      '有歌词就谈歌词的意象与情绪，有曲风/BPM 就谈它对听感的影响，'
      '有热评就谈听众在意什么。\n'
      '3. 资料很少时就写短一点，并在开头一句话说明你是基于什么写的，'
      '不要硬凑字数。';

  static String _promptFor(SongContext context) {
    final buffer = StringBuffer('请赏析这首歌。\n\n')..writeln(context.toPrompt());
    if (context.isBare) {
      buffer
        ..writeln()
        ..writeln(
          '注意：这首歌除了歌名和歌手之外没有任何可用资料。'
          '请直接说明资料不足、无法给出有依据的赏析，不要靠猜测展开。',
        );
    } else {
      buffer
        ..writeln()
        ..writeln('你手上的依据是：${context.basis}。请以此为准。');
    }
    return buffer.toString();
  }
}
