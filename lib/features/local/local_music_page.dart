import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playback/playback_controller.dart';
import '../../domain/models/local_track.dart';
import '../../infrastructure/services/local_music_native.dart'
    show LocalMusicNative, ImportedNativeFile;
import '../../infrastructure/services/local_music_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import '../player/cyrene_track_tile.dart';

class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends State<LocalMusicPage> {
  final _searchController = TextEditingController();
  List<LocalTrackEntry> _entries = const [];
  String? _errorMessage;
  var _isLoading = true;
  var _isImporting = false;
  var _requestId = 0;

  List<LocalTrackEntry> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.artists.toLowerCase().contains(query) ||
              entry.album.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestId++;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final entries = await LocalMusicService.instance.getAll();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _errorMessage = '无法读取本地音乐，请稍后重试。';
        _isLoading = false;
      });
    }
  }

  /// 弹出导入方式选择：单个/多个音频文件 或 扫描整个文件夹。
  Future<void> _chooseImportMode() async {
    await showCyreneSheet<void>(
      context: context,
      title: '导入方式',
      builder: (context, dismiss) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CyreneMenuRow(
              vector: MiuixIcons.extended.byName('notes')!,
              title: '选择音频文件',
              subtitle: '导入单个或多个音频文件',
              onTap: () {
                dismiss();
                _importFiles();
              },
            ),
            CyreneMenuRow(
              vector: MiuixIcons.extended.byName('folder')!,
              title: '扫描文件夹',
              subtitle: '自动扫描目录内所有音频与歌词',
              onTap: () {
                dismiss();
                _importFolder();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFiles() async {
    // Android 上走原生 SAF 通道：file_picker 会把文件拷进缓存 / 返回可能不存在的
    // 目录路径，原生侧复制成应用私有真实文件后按「真实路径 + 原始文件名」入库。
    if (LocalMusicNative.instance.isSupported) {
      await _importNative(() => LocalMusicNative.instance.pickFiles());
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'flac', 'wav', 'm4a', 'ape', 'ogg'],
      );
      if (!mounted || result == null) return;
      final paths = result.files
          .map((file) => file.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (paths.isEmpty) {
        _showToast('未获取到可导入的文件路径');
        return;
      }

      setState(() => _isImporting = true);
      final count = await LocalMusicService.instance.importFiles(paths);
      if (!mounted) return;
      if (count == 0) {
        _showToast('未导入任何歌曲', description: '当前设备暂不支持音频元数据导入。');
      } else {
        _showToast('已导入 $count 首歌曲');
      }
      await _load();
    } catch (_) {
      if (mounted) {
        _showToast('导入失败', description: '无法读取所选音频文件。');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// 选择文件夹并扫描目录内所有音频（含同名 .lrc 歌词）。
  Future<void> _importFolder() async {
    // Android 上走原生 SAF 目录选择，递归扫描并复制真实文件。
    if (LocalMusicNative.instance.isSupported) {
      await _importNative(() => LocalMusicNative.instance.pickFolder());
      return;
    }

    try {
      final folderPath = await FilePicker.getDirectoryPath(
        dialogTitle: '选择要扫描的文件夹',
      );
      if (!mounted || folderPath == null || folderPath.isEmpty) return;

      setState(() => _isImporting = true);
      final count = await LocalMusicService.instance.scanFolder(folderPath);
      if (!mounted) return;
      if (count == 0) {
        _showToast('未扫描到任何歌曲', description: '该目录下没有支持的音频文件。');
      } else {
        _showToast('已导入 $count 首歌曲');
      }
      await _load();
    } catch (_) {
      if (mounted) {
        _showToast('导入失败', description: '无法扫描所选文件夹。');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// 走原生导入通道，统一处理返回结果、进度态与提示。
  Future<void> _importNative(
    Future<List<ImportedNativeFile>?> Function() pick,
  ) async {
    try {
      setState(() => _isImporting = true);
      final files = await pick();
      if (!mounted || files == null) return;
      if (files.isEmpty) {
        _showToast('未导入任何歌曲', description: '所选位置没有支持的音频文件。');
        return;
      }
      final count = await LocalMusicService.instance.importNativeFiles(files);
      if (!mounted) return;
      _showToast('已导入 $count 首歌曲');
      await _load();
    } catch (_) {
      if (mounted) {
        _showToast('导入失败', description: '无法读取所选音频文件。');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _remove(LocalTrackEntry entry) async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '移除本地歌曲？',
      summary: '“${entry.name}”将从本地音乐列表移除，不会删除原始文件。',
      builder: (context, dismiss) {
        final theme = MiuixTheme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: MiuixTextButton('取消', onPressed: () => dismiss()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MiuixButton(
                    onPressed: () => dismiss(true),
                    colors: MiuixButtonColors(
                      color: theme.colors.error,
                      disabledColor: theme.colors.disabledPrimaryButton,
                      contentColor: theme.colors.onError,
                      disabledContentColor:
                          theme.colors.disabledOnPrimaryButton,
                    ),
                    child: MiuixText('移除', style: theme.textStyles.button),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await LocalMusicService.instance.remove(entry.filePath);
      if (!mounted) return;
      setState(
        () => _entries = _entries.where((item) => item != entry).toList(),
      );
      _showToast('已移除 ${entry.name}');
    } catch (_) {
      if (mounted) _showToast('移除失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return CyrenePage(
      title: '本地音乐',
      actions: [
        MiuixIconButton(
          key: const Key('refresh-local-music-button'),
          enabled: !_isLoading && !_isImporting,
          onPressed: _load,
          child: MiuixIcon(
            vector: MiuixIcons.extended.byName('refresh')!,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: MiuixTextField(
                    controller: _searchController,
                    label: '搜索歌曲、歌手或专辑',
                    singleLine: true,
                    leadingIcon: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: MiuixIcon(
                        vector: MiuixIcons.extended.byName('search')!,
                        size: 18,
                        tint: theme.colors.onSecondaryContainer,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                MiuixButton(
                  key: const Key('import-local-music-button'),
                  enabled: !_isImporting,
                  onPressed: _chooseImportMode,
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isImporting)
                        MiuixCircularProgressIndicator(
                          size: 16,
                          strokeWidth: 2,
                          colors: MiuixProgressIndicatorColors(
                            foregroundColor: theme.colors.onPrimary,
                            disabledForegroundColor: theme.colors.onPrimary,
                            backgroundColor: Colors.transparent,
                          ),
                        )
                      else
                        MiuixIcon(
                          vector: MiuixIcons.extended.byName('import')!,
                          size: 18,
                        ),
                      const SizedBox(width: 8),
                      MiuixText('导入', style: theme.textStyles.button),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final theme = MiuixTheme.of(context);
    if (_isLoading) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return CyreneEmptyState(
        icon: Icons.error_outline,
        title: '本地音乐加载失败',
        description: _errorMessage!,
        action: MiuixButton(
          onPressed: _load,
          child: MiuixText('重试', style: theme.textStyles.button),
        ),
      );
    }

    final entries = _filteredEntries;
    if (entries.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return CyrenePullToRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          children: [
            const SizedBox(height: 80),
            CyreneEmptyState(
              icon: searching ? Icons.search_off : Icons.music_note,
              title: searching ? '没有匹配的歌曲' : '还没有本地音乐',
              description: searching ? '换个关键词试试。' : '选择设备上的音频文件或文件夹，将它们加入本地音乐。',
              action: searching
                  ? null
                  : MiuixButton(
                      onPressed: _chooseImportMode,
                      child: MiuixText(
                        '导入音乐',
                        style: theme.textStyles.button,
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    final tracks = entries
        .map(LocalMusicService.instance.toTrack)
        .map((track) => track.copyWith(playbackUrl: Uri.file(track.filePath!)))
        .toList(growable: false);
    return CyrenePullToRefresh(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final track = tracks[index];
          return CyreneTrackTile(
            track: track,
            onPlay: () => widget.playback.playTrack(track, queue: tracks),
            trailing: MiuixIconButton(
              key: Key('remove-local-${entry.filePath}'),
              onPressed: () => _remove(entry),
              child: MiuixIcon(
                vector: MiuixIcons.extended.byName('delete')!,
                size: 20,
                tint: theme.colors.error,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showToast(String title, {String? description}) {
    CyreneToast.show(description == null ? title : '$title：$description');
  }
}
