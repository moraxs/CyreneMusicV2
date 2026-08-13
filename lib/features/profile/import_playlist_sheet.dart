import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../application/playlists/playlist_library_controller.dart';
import '../../domain/models/media_url.dart';
import '../../domain/models/playlist_import.dart';
import '../../infrastructure/services/playlist_import_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_toast.dart';

/// 从第三方平台导入歌单的底部抽屉（对应 Next.js `ImportPlaylistDialog`，
/// 仅保留「第三方平台链接 / ID」模式，不含 JSON 文件模式）。
///
/// 两步：input（选平台 + 粘贴链接/ID） → preview（确认歌单名并写入）。
/// 由 [show] 以 `showCyreneSheet` 承载；成功后由控制器内部 `load` 刷新歌单库。
class ImportPlaylistSheet extends StatefulWidget {
  const ImportPlaylistSheet({
    super.key,
    required this.token,
    required this.playlists,
    required this.dismiss,
  });

  final String token;
  final PlaylistLibraryController playlists;

  /// 抽屉关闭函数（走 Miuix 退场动画）；成功导入后带出 true。
  final void Function([bool? result]) dismiss;

  /// 弹出导入抽屉；返回 true 表示发生了导入（列表刷新已由控制器在
  /// [PlaylistLibraryController.importFetchedExternal] 内完成）。
  static Future<bool?> show(
    BuildContext context, {
    required String token,
    required PlaylistLibraryController playlists,
  }) => showCyreneSheet<bool>(
    context: context,
    title: '导入歌单',
    builder: (_, dismiss) =>
        ImportPlaylistSheet(token: token, playlists: playlists, dismiss: dismiss),
  );

  @override
  State<ImportPlaylistSheet> createState() => _ImportPlaylistSheetState();
}

enum _Step { input, preview }

/// 移动端更紧凑的平台短名（与 Tauri `PLATFORM_CONFIG` 中文名对齐）。
const Map<MusicPlatform, String> _kPlatformShortNames = {
  MusicPlatform.netease: '网易云',
  MusicPlatform.qq: 'QQ',
  MusicPlatform.kugou: '酷狗',
  MusicPlatform.kuwo: '酷我',
  MusicPlatform.apple: 'Apple',
};

class _ImportPlaylistSheetState extends State<ImportPlaylistSheet> {
  _Step _step = _Step.input;
  MusicPlatform _platform = MusicPlatform.netease;
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;

  /// 预览步展示的远端歌单数据。
  ExternalPlaylist? _preview;

  /// 解析出的歌单 ID（进入预览步时暂存，导入时用于绑定 sourcePlaylistId）。
  String? _parsedId;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// 「下一步」：解析 ID → 拉取远端歌单 → 成功则进入预览步。
  Future<void> _handleNext() async {
    final input = _urlController.text.trim();
    if (input.isEmpty) return;
    final id = PlaylistImportService.instance.parsePlaylistId(_platform, input);
    if (id == null) {
      CyreneToast.show('解析 URL 或 ID 失败，请检查输入格式');
      return;
    }
    setState(() => _busy = true);
    try {
      final external = await PlaylistImportService.instance.fetchExternalPlaylist(
        _platform,
        id,
        token: widget.token,
      );
      if (!mounted) return;
      if (external == null) {
        CyreneToast.show('获取歌单信息失败，请检查 ID 或 URL 是否正确');
        return;
      }
      _preview = external;
      _parsedId = id;
      _nameController.text = external.name;
      setState(() => _step = _Step.preview);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 「确认导入」：建新歌单（绑定来源） → 批量写入曲目。
  /// 复用预览步已拉取的 [_preview]，不再二次请求远端。
  Future<void> _handleImport() async {
    final external = _preview;
    final id = _parsedId;
    if (external == null || id == null) return;
    final nameOverride = _nameController.text;
    setState(() => _busy = true);
    try {
      final result = await widget.playlists.importFetchedExternal(
        widget.token,
        _platform,
        id,
        external,
        nameOverride,
      );
      if (!mounted) return;
      switch (result.kind) {
        case ImportExternalResultKind.success:
          CyreneToast.show(
            '成功导入 ${result.importedCount} 首歌曲到新歌单「${result.playlist?.name ?? external.name}」',
          );
          widget.dismiss(true);
        case ImportExternalResultKind.createFailed:
          CyreneToast.show('创建歌单失败');
        case ImportExternalResultKind.addTracksFailed:
          // 歌单已建好但写曲失败：回退到输入步，提示用户可对已建歌单手动同步。
          CyreneToast.show('导入歌曲失败，歌单已创建');
          setState(() => _step = _Step.input);
        case ImportExternalResultKind.parseFailed:
        case ImportExternalResultKind.fetchFailed:
          // 走 importFetchedExternal 路径不会出现这两种；保持防御性提示。
          CyreneToast.show('获取歌单信息失败，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToInput() {
    setState(() {
      _step = _Step.input;
      _preview = null;
      _parsedId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _step == _Step.input ? _buildInput(context) : _buildPreview(context);
  }

  Widget _buildInput(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '选择平台',
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(height: 10),
          _PlatformPicker(
            platform: _platform,
            onChanged: (p) => setState(() => _platform = p),
          ),
          const SizedBox(height: 18),
          MiuixTextField(
            controller: _urlController,
            label: '歌单 URL 或 ID',
            useLabelAsPlaceholder: true,
            singleLine: true,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _handleNext(),
          ),
          const SizedBox(height: 10),
          Text(
            '支持网易云、QQ 等平台的歌单链接，也可直接输入歌单 ID',
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          _ActionRow(
            busy: _busy,
            primary: true,
            label: '下一步',
            enabled: _urlController.text.trim().isNotEmpty,
            onPrimary: _handleNext,
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final external = _preview;
    if (external == null) return const SizedBox.shrink();
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final cover = external.coverImgUrl;
    final fallback = ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.queue_music_rounded,
        size: 24,
        color: colors.onSurfaceVariantSummary,
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 80,
                  child: cover.isEmpty
                      ? fallback
                      : CachedNetworkImage(
                          imageUrl: cover,
                          httpHeaders: imageHeaders(cover),
                          fit: BoxFit.cover,
                          memCacheWidth: coverDecodeWidth(
                            80,
                            MediaQuery.devicePixelRatioOf(context),
                          ),
                          errorWidget: (_, _, _) => fallback,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '原名：${external.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyles.body2.copyWith(
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                    if (external.creator != null &&
                        external.creator!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '创建者：${external.creator}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyles.body2.copyWith(
                          color: colors.onSurfaceVariantSummary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${external.trackCount} 首歌曲',
                      style: theme.textStyles.body2.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          MiuixTextField(
            controller: _nameController,
            label: '歌单名',
            useLabelAsPlaceholder: true,
            singleLine: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _handleImport(),
          ),
          const SizedBox(height: 10),
          Text(
            '可在此修改导入后的歌单名',
            style: theme.textStyles.body2.copyWith(
              color: theme.colors.onSurfaceVariantSummary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ActionRow(
                  busy: _busy,
                  label: '返回修改',
                  onPrimary: _backToInput,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionRow(
                  busy: _busy,
                  primary: true,
                  label: '确认导入',
                  enabled: _nameController.text.trim().isNotEmpty,
                  onPrimary: _handleImport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 平台选择网格：选中态用 primary 色，未选用默认（次要）色。
class _PlatformPicker extends StatelessWidget {
  const _PlatformPicker({required this.platform, required this.onChanged});

  final MusicPlatform platform;
  final ValueChanged<MusicPlatform> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final p in MusicPlatform.values)
          _PlatformChip(
            label: _kPlatformShortNames[p] ?? p.wireName,
            selected: p == platform,
            onPressed: () => onChanged(p),
          ),
      ],
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixButton(
      onPressed: onPressed,
      colors: selected
          ? MiuixButtonDefaults.buttonColorsPrimary(context)
          : MiuixButtonDefaults.buttonColors(context),
      child: MiuixText(
        label,
        style: theme.textStyles.button.copyWith(fontSize: 13),
      ),
    );
  }
}

/// 行动按钮：busy 时显示加载圈并禁用。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.busy,
    required this.label,
    required this.onPrimary,
    this.primary = false,
    this.enabled = true,
  });

  final bool busy;
  final String label;
  final bool primary;
  final bool enabled;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // MiuixButton 内部用 Center(widthFactor:1) 贴内容尺寸，不会自动撑满，
    // 需外套 SizedBox(width: double.infinity) 才能得到 Tauri 那样的整宽按钮。
    return SizedBox(
      width: double.infinity,
      child: MiuixButton(
        onPressed: (enabled && !busy) ? onPrimary : null,
        enabled: enabled && !busy,
        colors: primary
            ? MiuixButtonDefaults.buttonColorsPrimary(context)
            : MiuixButtonDefaults.buttonColors(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              const MiuixCircularProgressIndicator(size: 16, strokeWidth: 2),
              const SizedBox(width: 8),
            ],
            MiuixText(label, style: theme.textStyles.button),
          ],
        ),
      ),
    );
  }
}
