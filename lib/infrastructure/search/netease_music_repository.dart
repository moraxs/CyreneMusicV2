import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app/music_api_configuration.dart';
import '../../domain/models/search.dart';
import '../../domain/models/track.dart';
import '../../domain/playback/audio_source_resolver.dart';
import '../../domain/search/search_repository.dart';
import 'netease_track_dto.dart';

class NeteaseMusicRepository implements SearchRepository, AudioSourceResolver {
  NeteaseMusicRepository({
    required MusicApiConfiguration configuration,
    http.Client? client,
  }) : this._(configuration, client ?? http.Client());

  NeteaseMusicRepository._(this._configuration, this._client);

  final MusicApiConfiguration _configuration;
  final http.Client _client;

  @override
  Future<SearchResult> search(String keyword) async {
    final response = await _client.post(
      _configuration.endpoint('/search'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'keywords': keyword, 'limit': '20'},
    );
    final payload = _decodeMap(response);
    if (response.statusCode != 200 || payload['status'] != 200) {
      throw SearchFailure(payload['message']?.toString() ?? '搜索服务暂时不可用。');
    }

    final results = payload['result'];
    if (results is! List) return SearchResult.initial;
    final tracks = results
        .whereType<Map>()
        .map(
          (item) => NeteaseTrackDto(Map<String, Object?>.from(item)).toTrack(),
        )
        .toList(growable: false);
    return SearchResult(neteaseResults: tracks);
  }

  @override
  Future<ResolvedAudioSources> resolve(
    Track track, {
    Set<String>? exclude,
  }) async {
    if (track.playbackUrl != null) {
      return ResolvedAudioSources([
        PlaybackCandidate(track: track, sourceId: 'embedded'),
      ]);
    }
    final response = await _client.post(
      _configuration.endpoint('/song'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'ids': track.id,
        'url': '',
        'level': _configuration.audioQuality,
        'type': 'json',
      },
    );
    final payload = _decodeMap(response);
    final rawUrl = payload['url']?.toString();
    final playbackUrl = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (response.statusCode != 200 ||
        payload['status'] != 200 ||
        playbackUrl == null) {
      throw AudioSourceResolutionFailure(
        payload['msg']?.toString() ?? '未能获取当前歌曲的播放地址。',
      );
    }

    final resolvedTrack = track.copyWith(
      playbackUrl: playbackUrl,
      lyric: payload['lyric']?.toString(),
      yrc: payload['yrc']?.toString(),
      tlyric: payload['tlyric']?.toString(),
      ytlrc: payload['ytlrc']?.toString(),
    );
    return ResolvedAudioSources([
      PlaybackCandidate(track: resolvedTrack, sourceId: 'netease'),
    ]);
  }

  Map<String, Object?> _decodeMap(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      return payload is Map ? Map<String, Object?>.from(payload) : const {};
    } on FormatException {
      throw const SearchFailure('服务器返回了无法识别的数据。');
    }
  }
}
