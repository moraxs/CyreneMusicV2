import 'package:flutter/material.dart';

import '../../../../domain/models/track.dart';
import 'player_service.dart';

/// 队列来源（与原版一致）。
enum QueueSource { none, favorites, playlist, history, search, toplist }

/// 原版 `PlaylistQueueService` 兼容层：队列本体存于 PlaybackController，
/// 这里只保留来源标记与原版 API 形状。
class PlaylistQueueService {
  static final PlaylistQueueService _instance =
      PlaylistQueueService._internal();
  factory PlaylistQueueService() => _instance;
  PlaylistQueueService._internal();

  QueueSource _source = QueueSource.none;

  List<Track> get queue => PlayerService().queue;
  QueueSource get source => _source;
  bool get hasQueue => queue.isNotEmpty;

  void setQueue(
    List<Track> tracks,
    int startIndex,
    QueueSource source, {
    Map<String, ImageProvider>? coverProviders,
  }) {
    _source = source;
    PlayerService().setQueueTracks(tracks);
    if (startIndex >= 0 && startIndex < tracks.length) {
      PlayerService().playTrack(tracks[startIndex]);
    }
  }
}
