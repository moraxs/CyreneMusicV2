import 'package:flutter/foundation.dart';

import '../../domain/models/audio_quality.dart';
import '../../domain/models/audio_source_config.dart';
import '../../domain/playback/audio_source_importer.dart';
import '../../domain/playback/audio_source_preferences_store.dart';

enum AudioSourcePreferencesStatus { initial, loading, ready, saving }

class AudioSourcePreferencesState {
  const AudioSourcePreferencesState({
    this.status = AudioSourcePreferencesStatus.initial,
    this.preferences = const AudioSourcePreferences(),
    this.errorMessage,
  });

  final AudioSourcePreferencesStatus status;
  final AudioSourcePreferences preferences;
  final String? errorMessage;

  List<AudioSourceConfig> get sources => preferences.sources;
  AudioQuality get quality => preferences.quality;
  bool get isBusy =>
      status == AudioSourcePreferencesStatus.loading ||
      status == AudioSourcePreferencesStatus.saving;

  AudioSourcePreferencesState copyWith({
    AudioSourcePreferencesStatus? status,
    AudioSourcePreferences? preferences,
    String? errorMessage,
    bool clearError = false,
  }) => AudioSourcePreferencesState(
    status: status ?? this.status,
    preferences: preferences ?? this.preferences,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

class AudioSourcePreferencesController extends ChangeNotifier {
  factory AudioSourcePreferencesController({
    required AudioSourcePreferencesStore store,
    required AudioSourceImporter importer,
  }) => AudioSourcePreferencesController._(store, importer);

  AudioSourcePreferencesController._(this._store, this._importer);

  final AudioSourcePreferencesStore _store;
  final AudioSourceImporter _importer;

  AudioSourcePreferencesState _state = const AudioSourcePreferencesState();
  AudioSourcePreferencesState get state => _state;

  Future<void> restore() async {
    _emit(_state.copyWith(status: AudioSourcePreferencesStatus.loading));
    try {
      final preferences = await _store.read();
      _emit(
        AudioSourcePreferencesState(
          status: AudioSourcePreferencesStatus.ready,
          preferences: preferences,
        ),
      );
    } catch (error) {
      _emit(
        _state.copyWith(
          status: AudioSourcePreferencesStatus.ready,
          errorMessage: '读取音源配置失败：$error',
        ),
      );
    }
  }

  Future<bool> addOmniParse({
    required String name,
    required String url,
    String apiKey = '',
    String? id,
  }) => _importAndAppend(
    () => Future.sync(
      () => _importer.createOmniParse(
        name: name,
        url: url,
        apiKey: apiKey,
        id: id,
      ),
    ),
  );

  Future<bool> importOmniParse(Uint8List bytes) =>
      _importAndAppend(() => _importer.importOmniParse(bytes));

  Future<bool> importLxMusicScript(
    String script, {
    required String sourceLabel,
  }) => _importAndAppend(
    () => _importer.importLxMusicScript(script, sourceLabel: sourceLabel),
  );

  Future<bool> importLxMusicUrl(String url) =>
      _importAndAppend(() => _importer.importLxMusicUrl(url));

  Future<bool> setSourceEnabled(String id, bool isEnabled) {
    final source = _sourceById(id);
    if (source == null) return Future.value(false);
    return updateSource(source.copyWith(isEnabled: isEnabled));
  }

  Future<bool> updateOmniParse({
    required String id,
    required String name,
    required String url,
    String apiKey = '',
  }) async {
    if (_state.isBusy) return false;
    try {
      final validated = _importer.createOmniParse(
        name: name,
        url: url,
        apiKey: apiKey,
      );
      final current = _sourceById(id);
      if (current == null) return false;
      return updateSource(
        validated.copyWith(id: id, isEnabled: current.isEnabled),
      );
    } catch (error) {
      _emit(_state.copyWith(errorMessage: error.toString()));
      return false;
    }
  }

  Future<bool> updateSource(AudioSourceConfig source) => _persist(
    _state.preferences.copyWith(
      sources: _state.sources
          .map((current) => current.id == source.id ? source : current)
          .toList(growable: false),
    ),
  );

  Future<bool> removeSource(String id) => _persist(
    _state.preferences.copyWith(
      sources: _state.sources
          .where((source) => source.id != id)
          .toList(growable: false),
    ),
  );

  Future<bool> reorderSources(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _state.sources.length) return false;
    var insertionIndex = newIndex;
    if (oldIndex < insertionIndex) insertionIndex--;
    insertionIndex = insertionIndex.clamp(0, _state.sources.length - 1);
    if (oldIndex == insertionIndex) return true;

    final next = List<AudioSourceConfig>.of(_state.sources);
    final moved = next.removeAt(oldIndex);
    next.insert(insertionIndex, moved);
    return _persist(_state.preferences.copyWith(sources: next));
  }

  Future<bool> setQuality(AudioQuality quality) =>
      _persist(_state.preferences.copyWith(quality: quality));

  void clearError() {
    if (_state.errorMessage == null) return;
    _emit(_state.copyWith(clearError: true));
  }

  Future<bool> _importAndAppend(
    Future<AudioSourceConfig> Function() import,
  ) async {
    if (_state.isBusy) return false;
    _emit(
      _state.copyWith(
        status: AudioSourcePreferencesStatus.saving,
        clearError: true,
      ),
    );
    try {
      final source = await import();
      final next = _state.preferences.copyWith(
        sources: [..._state.sources, source],
      );
      await _store.write(next);
      _emit(
        AudioSourcePreferencesState(
          status: AudioSourcePreferencesStatus.ready,
          preferences: next,
        ),
      );
      return true;
    } catch (error) {
      _emit(
        _state.copyWith(
          status: AudioSourcePreferencesStatus.ready,
          errorMessage: error.toString(),
        ),
      );
      return false;
    }
  }

  Future<bool> _persist(AudioSourcePreferences next) async {
    if (_state.isBusy) return false;
    final previous = _state.preferences;
    _emit(
      _state.copyWith(
        status: AudioSourcePreferencesStatus.saving,
        preferences: next,
        clearError: true,
      ),
    );
    try {
      await _store.write(next);
      _emit(
        AudioSourcePreferencesState(
          status: AudioSourcePreferencesStatus.ready,
          preferences: next,
        ),
      );
      return true;
    } catch (error) {
      _emit(
        AudioSourcePreferencesState(
          status: AudioSourcePreferencesStatus.ready,
          preferences: previous,
          errorMessage: '保存音源配置失败：$error',
        ),
      );
      return false;
    }
  }

  AudioSourceConfig? _sourceById(String id) {
    for (final source in _state.sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  void _emit(AudioSourcePreferencesState value) {
    _state = value;
    notifyListeners();
  }
}
