import '../../domain/models/search.dart';
import '../../domain/models/track.dart';

class SearchState {
  const SearchState({
    this.keyword = '',
    this.result = SearchResult.initial,
    this.isLoading = false,
    this.errorMessage,
  });

  final String keyword;
  final SearchResult result;
  final bool isLoading;
  final String? errorMessage;

  List<Track> get results => result.mergedTracks;

  SearchState copyWith({
    String? keyword,
    SearchResult? result,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) => SearchState(
    keyword: keyword ?? this.keyword,
    result: result ?? this.result,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}
