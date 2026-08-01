import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/playback/playback_snapshot.dart';
import '../../domain/playback/playback_snapshot_store.dart';

class SharedPreferencesPlaybackSnapshotStore implements PlaybackSnapshotStore {
  factory SharedPreferencesPlaybackSnapshotStore({
    SharedPreferences? preferences,
  }) => SharedPreferencesPlaybackSnapshotStore._(preferences);

  SharedPreferencesPlaybackSnapshotStore._(this._preferences);

  static const _storageKey = 'playback_snapshot_v1';
  SharedPreferences? _preferences;

  @override
  Future<PlaybackSnapshot?> read() async {
    final raw = (await _instance).getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PlaybackSnapshot.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    await (await _instance).setString(
      _storageKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<SharedPreferences> get _instance async =>
      _preferences ??= await SharedPreferences.getInstance();
}
