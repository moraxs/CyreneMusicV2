import 'dart:async';

import '../application/audio_sources/audio_source_preferences_controller.dart';
import '../application/auth/account_session_controller.dart';
import '../application/discovery/discover_controller.dart';
import '../application/home/home_controller.dart';
import '../application/playback/playback_controller.dart';
import '../application/playlists/playlist_library_controller.dart';
import '../application/search/search_controller.dart';
import '../domain/discovery/discover_repository.dart';
import '../domain/models/discovery.dart';
import '../domain/playback/audio_player_gateway.dart';
import '../infrastructure/audio/equalizer_service.dart';
import '../infrastructure/audio/media_kit_player_gateway.dart';
import '../infrastructure/core/api_client.dart';
import '../infrastructure/core/url_service.dart';
import '../infrastructure/services/auth_service.dart';
import '../infrastructure/services/configured_audio_source_importer.dart';
import '../infrastructure/services/configured_audio_source_resolver.dart';
import '../infrastructure/services/cross_platform_fallback_service.dart';
import '../infrastructure/services/discovery_service.dart';
import '../infrastructure/services/home_service.dart';
import '../infrastructure/services/playback_url_resolver_service.dart';
import '../infrastructure/services/search_service.dart';
import '../infrastructure/storage/no_op_audio_cache.dart';
import '../infrastructure/storage/shared_preferences_auth_session_store.dart';
import '../infrastructure/storage/shared_preferences_audio_source_preferences_store.dart';
import '../infrastructure/storage/shared_preferences_playback_snapshot_store.dart';
import 'silent_audio_player_gateway.dart';

class AppDependencies {
  AppDependencies._({
    required this.account,
    required this.audioSources,
    required this.discover,
    required this.home,
    required this.playback,
    required this.playlists,
    required this.search,
  });

  factory AppDependencies.production() {
    final gateway = MediaKitPlayerGateway();
    // 均衡器直接操作 libmpv 的 af 属性，需拿到底层 Player；
    // preview（SilentAudioPlayerGateway）下不绑定，设置仍可编辑与持久化。
    unawaited(EqualizerService.instance.attach(gateway.player));
    return AppDependencies._build(
      gateway,
      discoverRepository: DiscoveryService.instance,
    );
  }

  factory AppDependencies.preview() => AppDependencies._build(
    const SilentAudioPlayerGateway(),
    discoverRepository: const _PreviewDiscoverRepository(),
  );

  factory AppDependencies._build(
    AudioPlayerGateway audio, {
    required DiscoverRepository discoverRepository,
  }) {
    final urls = UrlService.instance;
    final apiClient = ApiClient.instance;
    // 官方 OmniParse 音源不预置到默认列表：未购买 Cyrene Premium 且未导入音源时，
    // 解析服务区显示空态，而非无用的 Cyrene Official 占位卡。该源仅在持卡
    // 下发（/card/config）后由 ListeningCardSync 以稳定 id official-omniparse 落地。
    final preferences = SharedPreferencesAudioSourcePreferencesStore();
    final audioSources = AudioSourcePreferencesController(
      store: preferences,
      importer: ConfiguredAudioSourceImporter(),
    );
    final sourceClient = PlaybackUrlResolverService(
      apiClient: apiClient,
      urls: urls,
    );
    final sourceResolver = ConfiguredAudioSourceResolver(
      preferences: preferences,
      sourceClient: sourceClient,
      cache: const NoOpAudioCache(),
      crossPlatformFallback: CrossPlatformFallbackService(
        apiClient: apiClient,
        urls: urls,
      ),
    );

    final account = AccountSessionController(
      AuthService(apiClient: apiClient, urls: urls),
      SharedPreferencesAuthSessionStore(),
    );
    apiClient.onSessionExpired = account.expireSession;

    return AppDependencies._(
      account: account,
      audioSources: audioSources,
      discover: DiscoverController(discoverRepository),
      home: HomeController(
        HomeService(discoveryService: DiscoveryService.instance),
      ),
      playback: PlaybackController(
        audio: audio,
        store: SharedPreferencesPlaybackSnapshotStore(),
        sourceResolver: sourceResolver,
      ),
      playlists: PlaylistLibraryController(),
      search: SearchController(
        SearchService(
          apiClient: apiClient,
          urls: urls,
          preferences: preferences,
        ),
      ),
    );
  }

  final AccountSessionController account;
  final AudioSourcePreferencesController audioSources;
  final DiscoverController discover;
  final HomeController home;
  final PlaybackController playback;
  final PlaylistLibraryController playlists;
  final SearchController search;

  void dispose() {
    ApiClient.instance.onSessionExpired = null;
    account.dispose();
    audioSources.dispose();
    discover.dispose();
    home.dispose();
    playback.dispose();
    playlists.dispose();
    search.dispose();
  }
}

class _PreviewDiscoverRepository implements DiscoverRepository {
  const _PreviewDiscoverRepository();

  @override
  Future<List<DiscoveryPlaylist>> getPlaylists({
    String category = '全部歌单',
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<List<DiscoveryTag>> getTags() async => const [];
}
