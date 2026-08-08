import 'package:cyrene_music_reborn/application/playback/playback_controller.dart';
import 'package:cyrene_music_reborn/domain/models/discovery.dart';
import 'package:cyrene_music_reborn/domain/models/music_source.dart';
import 'package:cyrene_music_reborn/domain/playback/audio_player_gateway.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot.dart';
import 'package:cyrene_music_reborn/domain/playback/playback_snapshot_store.dart';
import 'package:cyrene_music_reborn/features/player/track_artwork.dart';
import 'package:cyrene_music_reborn/features/playlist/playlist_detail_page.dart';
import 'package:cyrene_music_reborn/presentation/cyrene/cyrene_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop playlist lazily builds track rows', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final playback = PlaybackController(
      audio: const _SilentAudioGateway(),
      store: _MemorySnapshotStore(),
    );
    addTearDown(playback.dispose);

    final tracks = List.generate(
      500,
      (index) => ToplistTrack(
        id: '$index',
        name: 'Song $index',
        artists: 'Artist',
        album: 'Album',
        picUrl: '',
        source: MusicSource.netease,
      ),
    );
    final playlist = PlaylistDetail(
      id: 1,
      name: 'Large playlist',
      coverImgUrl: '',
      description: '',
      tracks: tracks,
      playCount: 0,
      creator: 'Tester',
      trackCount: tracks.length,
      createTime: 0,
      updateTime: 0,
      tags: const [],
    );

    await tester.pumpWidget(
      MiuixSystemTheme(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: CyreneMiuixTheme.material(MiuixTheme.of(context)),
            home: PlaylistDetailPage(
              playlistId: playlist.id,
              title: playlist.name,
              coverUrl: '',
              playback: playback,
              desktopLayout: true,
              initialPlaylist: playlist,
              reloadable: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 499'), findsNothing);
    expect(find.byType(TrackArtwork).evaluate().length, lessThan(50));
    expect(tester.takeException(), isNull);
  });
}

class _SilentAudioGateway implements AudioPlayerGateway {
  const _SilentAudioGateway();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<PlaybackStatus> get statusStream => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<Duration?> load(Uri source) async => null;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

class _MemorySnapshotStore implements PlaybackSnapshotStore {
  @override
  Future<PlaybackSnapshot?> read() async => null;

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {}
}
