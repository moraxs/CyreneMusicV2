import '../models/search.dart';

abstract interface class SearchRepository {
  Future<SearchResult> search(String keyword);
}

class SearchFailure implements Exception {
  const SearchFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
