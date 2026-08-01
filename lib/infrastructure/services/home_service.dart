import '../../domain/discovery/home_repository.dart';
import '../../domain/models/discovery.dart';
import 'account_service.dart';
import 'discovery_service.dart';

class HomeService implements HomeRepository {
  HomeService({
    AccountService? accountService,
    DiscoveryService? discoveryService,
  }) : _accountService = accountService ?? AccountService.instance,
       _discoveryService = discoveryService ?? DiscoveryService.instance;

  final AccountService _accountService;
  final DiscoveryService _discoveryService;

  @override
  Future<bool> hasRecommendationBinding(
    String token, {
    String source = 'netease',
  }) async {
    final bindings = await _accountService.getBindings(token);
    return source == 'qq'
        ? bindings?.qq.bound ?? false
        : bindings?.netease.bound ?? false;
  }

  @override
  Future<List<Toplist>> getToplists({
    bool forceRefresh = false,
    String source = 'netease',
  }) =>
      _discoveryService.getToplists(forceRefresh: forceRefresh, source: source);

  @override
  Future<RecommendData?> getRecommendations(
    String token, {
    bool forceRefresh = false,
    String source = 'netease',
  }) => _discoveryService.getRecommendForYou(
    token,
    forceRefresh: forceRefresh,
    source: source,
  );
}
