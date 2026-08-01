import 'package:flutter/foundation.dart';

import '../../../../domain/models/history.dart';
import '../../../../domain/models/music_source.dart';
import '../../../../domain/models/track.dart';
import '../../../../infrastructure/services/history_service.dart';

/// 原版 `PlayHistoryItem` 兼容形状。
class PlayHistoryItem {
  const PlayHistoryItem(this._entry);

  final HistoryEntry _entry;

  Track toTrack() => Track(
    id: _entry.id,
    name: _entry.name,
    artists: _entry.artists,
    album: _entry.album,
    picUrl: _entry.picUrl,
    source: MusicSource.fromWireName(_entry.source),
  );
}

/// 原版 `PlayHistoryService` 兼容层：内部缓存新架构 HistoryService 的
/// 记录，保持原版同步 getter 形状（首次访问触发异步刷新）。
class PlayHistoryService extends ChangeNotifier {
  static final PlayHistoryService _instance = PlayHistoryService._internal();
  factory PlayHistoryService() => _instance;
  PlayHistoryService._internal();

  List<PlayHistoryItem> _history = const [];
  bool _loading = false;

  List<PlayHistoryItem> get history {
    if (_history.isEmpty && !_loading) refresh();
    return _history;
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final entries = await HistoryService.instance.getHistory(limit: 100);
      _history = entries.map(PlayHistoryItem.new).toList(growable: false);
      notifyListeners();
    } catch (e) {
      debugPrint('[PlayHistoryService compat] 加载历史失败: $e');
    } finally {
      _loading = false;
    }
  }
}
