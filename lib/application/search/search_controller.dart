import 'package:flutter/foundation.dart';

import '../../domain/search/search_repository.dart';
import 'search_state.dart';

class SearchController extends ChangeNotifier {
  SearchController(this._repository);

  final SearchRepository _repository;
  SearchState _state = const SearchState();
  int _requestId = 0;
  bool _disposed = false;

  SearchState get state => _state;

  Future<void> search(String rawKeyword) async {
    final keyword = rawKeyword.trim();
    final requestId = ++_requestId;
    if (keyword.isEmpty) {
      _publish(const SearchState());
      return;
    }

    _publish(SearchState(keyword: keyword, isLoading: true));
    try {
      final result = await _repository.search(keyword);
      if (_isStale(requestId)) return;
      _publish(SearchState(keyword: keyword, result: result));
    } on SearchFailure catch (error) {
      if (_isStale(requestId)) return;
      _publish(SearchState(keyword: keyword, errorMessage: error.message));
    } catch (_) {
      if (_isStale(requestId)) return;
      _publish(SearchState(keyword: keyword, errorMessage: '搜索失败，请检查网络后重试。'));
    }
  }

  void clear() {
    ++_requestId;
    _publish(const SearchState());
  }

  bool _isStale(int requestId) => _disposed || requestId != _requestId;

  void _publish(SearchState state) {
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
