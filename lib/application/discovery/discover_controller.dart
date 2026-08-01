import 'package:flutter/foundation.dart';

import '../../domain/discovery/discover_repository.dart';
import '../../domain/models/discovery.dart';

class DiscoverState {
  const DiscoverState({
    this.tags = const [],
    this.playlists = const [],
    this.selectedCategory = '全部歌单',
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  final List<DiscoveryTag> tags;
  final List<DiscoveryPlaylist> playlists;
  final String selectedCategory;
  final bool isInitialLoading;
  final bool isRefreshing;
  final String? errorMessage;

  DiscoverState copyWith({
    List<DiscoveryTag>? tags,
    List<DiscoveryPlaylist>? playlists,
    String? selectedCategory,
    bool? isInitialLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) => DiscoverState(
    tags: tags ?? this.tags,
    playlists: playlists ?? this.playlists,
    selectedCategory: selectedCategory ?? this.selectedCategory,
    isInitialLoading: isInitialLoading ?? this.isInitialLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class DiscoverController extends ChangeNotifier {
  DiscoverController(this._repository);

  final DiscoverRepository _repository;
  DiscoverState _state = const DiscoverState();
  int _requestId = 0;
  bool _disposed = false;

  /// 首屏 [load] 是否在途。**必须与 `isInitialLoading` 分开**：后者要等让出
  /// 微任务后才发布（见 [load]），在那之前不足以给重复调用去重——桌面首页与
  /// 发现页会各调一次 `load()`，只靠状态判断会打两次请求。
  bool _loadStarted = false;

  DiscoverState get state => _state;

  /// 首屏加载（已有数据或在途则跳过）。
  ///
  /// **发布状态前先让出一个微任务**：`load()` 通常在页面 `initState` 里调用，
  /// 而桌面外壳首帧会在 fluent `NavigationView` 的布局回调里用 IndexedStack
  /// 一次性挂载全部页面——此刻同步 `notifyListeners()` 会把已挂载的兄弟页
  /// （如同样监听本控制器的桌面首页）在构建期标脏，直接触发
  /// "setState() called during build" 断言并引发异常雪崩。
  Future<void> load() async {
    if (_loadStarted || _state.isInitialLoading || _state.playlists.isNotEmpty) {
      return;
    }
    _loadStarted = true;
    try {
      await _load();
    } finally {
      _loadStarted = false;
    }
  }

  Future<void> _load() async {
    await Future<void>.microtask(() {});
    if (_disposed) return;
    _publish(_state.copyWith(isInitialLoading: true, clearError: true));
    final requestId = ++_requestId;
    try {
      final results = await Future.wait([
        _repository.getTags(),
        _repository.getPlaylists(category: _state.selectedCategory),
      ]);
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          tags: results[0] as List<DiscoveryTag>,
          playlists: results[1] as List<DiscoveryPlaylist>,
          isInitialLoading: false,
          clearError: true,
        ),
      );
    } catch (_) {
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          isInitialLoading: false,
          errorMessage: '发现内容加载失败，请检查网络后重试。',
        ),
      );
    }
  }

  Future<void> selectCategory(String category) async {
    if (category == _state.selectedCategory && _state.playlists.isNotEmpty) {
      return;
    }
    _publish(
      _state.copyWith(
        selectedCategory: category,
        isRefreshing: true,
        clearError: true,
      ),
    );
    await _loadPlaylists(category);
  }

  Future<void> refresh() async {
    _publish(_state.copyWith(isRefreshing: true, clearError: true));
    final requestId = ++_requestId;
    try {
      final results = await Future.wait([
        _repository.getTags(),
        _repository.getPlaylists(
          category: _state.selectedCategory,
          forceRefresh: true,
        ),
      ]);
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          tags: results[0] as List<DiscoveryTag>,
          playlists: results[1] as List<DiscoveryPlaylist>,
          isInitialLoading: false,
          isRefreshing: false,
          clearError: true,
        ),
      );
    } catch (_) {
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          isInitialLoading: false,
          isRefreshing: false,
          errorMessage: '刷新失败，请稍后重试。',
        ),
      );
    }
  }

  Future<void> _loadPlaylists(String category) async {
    final requestId = ++_requestId;
    try {
      final playlists = await _repository.getPlaylists(category: category);
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          playlists: playlists,
          isInitialLoading: false,
          isRefreshing: false,
          clearError: true,
        ),
      );
    } catch (_) {
      if (_isStale(requestId)) return;
      _publish(
        _state.copyWith(
          isInitialLoading: false,
          isRefreshing: false,
          errorMessage: '该分类加载失败，请稍后重试。',
        ),
      );
    }
  }

  bool _isStale(int requestId) => _disposed || requestId != _requestId;

  void _publish(DiscoverState state) {
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
