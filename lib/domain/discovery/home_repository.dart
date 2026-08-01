import '../models/discovery.dart';

abstract interface class HomeRepository {
  Future<bool> hasRecommendationBinding(String token, {String source});

  Future<List<Toplist>> getToplists({
    bool forceRefresh = false,
    String source = 'netease',
  });

  Future<RecommendData?> getRecommendations(
    String token, {
    bool forceRefresh = false,
    String source = 'netease',
  });
}
