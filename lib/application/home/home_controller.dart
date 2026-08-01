import 'package:flutter/foundation.dart';

import '../../domain/discovery/home_repository.dart';
import '../../domain/models/discovery.dart';
import '../../domain/models/music_source.dart';
import '../../domain/models/track.dart';

class HomeState {
  const HomeState({
    this.isBound = false,
    this.toplists = const [],
    this.recommendations,
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  final bool isBound;
  final List<Toplist> toplists;
  final RecommendData? recommendations;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;

  bool get hasContent => toplists.isNotEmpty || recommendations != null;

  HomeState copyWith({
    bool? isBound,
    List<Toplist>? toplists,
    RecommendData? recommendations,
    bool clearRecommendations = false,
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) => HomeState(
    isBound: isBound ?? this.isBound,
    toplists: toplists ?? this.toplists,
    recommendations: clearRecommendations
        ? null
        : recommendations ?? this.recommendations,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class HomeController extends ChangeNotifier {
  HomeController(this._repository);

  final HomeRepository _repository;
  HomeState _state = const HomeState();
  int _requestId = 0;
  bool _disposed = false;
  String? _token;

  HomeState get state => _state;

  Future<void> load({String? token, bool forceRefresh = false}) async {
    // 仅对同 token 的重复请求去重；token 变化（如启动时会话恢复完成）必须
    // 重新发起请求，旧的在途请求由 _requestId 判定过期后丢弃。
    if (!forceRefresh && _state.isLoading && token == _token) return;
    final requestId = ++_requestId;
    _token = token;
    // 发布状态前先让出一个微任务：load() 通常在页面 initState 里调用，而桌面
    // 外壳首帧会在 fluent NavigationView 的布局回调里用 IndexedStack 一次性
    // 挂载全部页面——此刻同步 notifyListeners() 会把已挂载的兄弟页在构建期
    // 标脏，直接触发 "setState() called during build" 断言并引发异常雪崩。
    // 让出期间若有更新的请求进来，本次由 _isStale 判定过期后丢弃。
    await Future<void>.microtask(() {});
    if (_isStale(requestId)) return;
    _publish(
      _state.copyWith(
        isLoading: !forceRefresh && !_state.hasContent,
        isRefreshing: forceRefresh,
        clearError: true,
      ),
    );

    try {
      final hasToken = token?.isNotEmpty ?? false;
      final bindingFuture = hasToken
          ? _repository.hasRecommendationBinding(token!)
          : Future<bool>.value(false);
      final toplistsFuture = _repository.getToplists(
        forceRefresh: forceRefresh,
      );
      final isBound = await bindingFuture;
      final recommendationsFuture = isBound
          ? _repository.getRecommendations(token!, forceRefresh: forceRefresh)
          : Future<RecommendData?>.value();
      final results = await Future.wait<Object?>([
        toplistsFuture,
        recommendationsFuture,
      ]);
      if (_isStale(requestId)) return;
      _publish(
        HomeState(
          isBound: isBound,
          toplists: results[0] as List<Toplist>,
          recommendations: results[1] as RecommendData?,
        ),
      );
    } catch (_) {
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          isLoading: false,
          isRefreshing: false,
          errorMessage: '首页内容加载失败，请检查网络后重试。',
        ),
      );
    }
  }

  Future<void> refresh() => load(token: _token, forceRefresh: true);

  List<Track> convertTracks(Iterable<dynamic> items) => items
      .whereType<Map>()
      .map((item) => _trackFromMap(Map<String, Object?>.from(item)))
      .where((track) => track.id.isNotEmpty)
      .toList(growable: false);

  List<Track> tracksForToplist(Toplist toplist) => toplist.tracks
      .map(
        (item) => Track(
          id: item.mid?.isNotEmpty == true ? item.mid! : item.id,
          name: item.name,
          artists: item.artists,
          album: item.album,
          picUrl: item.picUrl,
          source: item.source ?? toplist.source ?? MusicSource.netease,
          duration: item.duration == null
              ? null
              : Duration(milliseconds: item.duration!),
        ),
      )
      .where((track) => track.id.isNotEmpty)
      .toList(growable: false);

  Track _trackFromMap(Map<String, Object?> item) {
    // 个性化新歌接口把歌曲详情包在 song 字段里（{id, name, picUrl, song: {ar, al, …}}），
    // 展开后保留外层 picUrl 作为封面兜底。
    final songData = item['song'];
    if (songData is Map) {
      item = {
        if (item['picUrl'] != null) 'picUrl': item['picUrl'],
        ...Map<String, Object?>.from(songData),
      };
    }
    final albumData = item['al'] ?? item['album'];
    final artistsData = item['ar'] ?? item['artists'];
    final artists = artistsData is List
        ? artistsData
              .map(
                (artist) => artist is Map
                    ? artist['name']?.toString() ?? ''
                    : artist.toString(),
              )
              .where((name) => name.isNotEmpty)
              .join(' / ')
        : artistsData?.toString() ?? '';
    final album = albumData is Map
        ? albumData['name']?.toString() ?? ''
        : albumData?.toString() ?? '';
    final picUrl = item['picUrl']?.toString().isNotEmpty == true
        ? item['picUrl'].toString()
        : albumData is Map
        ? albumData['picUrl']?.toString() ?? ''
        : '';
    final source = item['source']?.toString() == 'qq' || item['mid'] != null
        ? MusicSource.qq
        : MusicSource.fromWireName(item['source']?.toString() ?? 'netease');
    final duration = item['dt'] ?? item['duration'];
    final durationNumber = duration is num
        ? duration
        : num.tryParse(duration?.toString() ?? '');
    return Track(
      id: (item['mid'] ?? item['id'])?.toString() ?? '',
      name: item['name']?.toString() ?? '',
      artists: artists,
      album: album,
      picUrl: picUrl,
      source: source,
      duration: durationNumber == null
          ? null
          : Duration(
              // dt 恒为毫秒；duration 通常为秒，但个性化新歌 song.duration
              // 是毫秒——超过 10000 的值不可能是秒数，按毫秒处理。
              milliseconds: item['dt'] != null || durationNumber > 10000
                  ? durationNumber.round()
                  : (durationNumber * 1000).round(),
            ),
    );
  }

  bool _isStale(int requestId) => _disposed || requestId != _requestId;

  void _publish(HomeState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
