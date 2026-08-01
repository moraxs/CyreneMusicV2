import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../domain/models/media_url.dart';
import '../../../domain/models/playlist.dart';
import '../../../domain/models/track.dart';
import '../../../infrastructure/services/playlist_service.dart';
import '../../../presentation/cyrene/cyrene_overlays.dart';
import '../../../presentation/cyrene/cyrene_toast.dart';

/// 管理歌曲所在歌单（对应 Next.js AddToPlaylistDialog 的移动端 Sheet 分支）。
///
/// 一次性批量编辑归属：勾选要加入的歌单、取消勾选已加入项即移除，保存后统一
/// 提交。支持新建歌单。需要登录态 [token]。
class AddToPlaylistSheet extends StatefulWidget {
  const AddToPlaylistSheet({
    super.key,
    required this.token,
    required this.track,
    this.showOnlyJoinedInitially = false,
  });

  final String token;
  final Track track;
  final bool showOnlyJoinedInitially;

  /// 返回 true 表示发生了改动（调用方据此刷新收藏状态）。
  static Future<bool?> show(
    BuildContext context, {
    required String token,
    required Track track,
    bool showOnlyJoinedInitially = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AddToPlaylistSheet(
        token: token,
        track: track,
        showOnlyJoinedInitially: showOnlyJoinedInitially,
      ),
    );
  }

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

enum _RowState { kept, willAdd, willRemove, idle }

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  final _service = PlaylistService.instance;

  List<Playlist> _playlists = const [];
  Set<int> _inPlaylistIds = {};
  Set<int> _selectedIds = {};

  bool _loading = false;
  bool _saving = false;
  bool _creating = false;
  bool _showOnlyJoined = false;

  @override
  void initState() {
    super.initState();
    _showOnlyJoined = widget.showOnlyJoinedInitially;
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getPlaylists(widget.token),
        _service.checkTrackInPlaylists(
          widget.token,
          widget.track.id,
          widget.track.source.wireName,
        ),
      ]);
      final playlists = results[0] as List<Playlist>;
      final status = results[1] as CheckTrackResult;
      final ids = status.playlistIds.toSet();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _inPlaylistIds = ids;
        _selectedIds = {...ids};
      });
    } catch (_) {
      if (mounted) _toast('获取歌单信息失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _RowState _rowState(int id) {
    final wasIn = _inPlaylistIds.contains(id);
    final selected = _selectedIds.contains(id);
    if (wasIn && selected) return _RowState.kept;
    if (wasIn && !selected) return _RowState.willRemove;
    if (!wasIn && selected) return _RowState.willAdd;
    return _RowState.idle;
  }

  Set<int> get _toAdd => _selectedIds.difference(_inPlaylistIds);
  Set<int> get _toRemove => _inPlaylistIds.difference(_selectedIds);
  bool get _hasChanges => _toAdd.isNotEmpty || _toRemove.isNotEmpty;

  List<Playlist> get _visiblePlaylists {
    if (!_showOnlyJoined) return _playlists;
    return _playlists
        .where(
          (p) => _inPlaylistIds.contains(p.id) || _selectedIds.contains(p.id),
        )
        .toList();
  }

  void _toggleSelect(int id) {
    if (_saving) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _createPlaylist() async {
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      final created = await _service.createPlaylist(widget.token, name.trim());
      if (created == null) {
        _toast('创建歌单失败');
        return;
      }
      if (!mounted) return;
      setState(() {
        _playlists = [created, ..._playlists];
        _selectedIds.add(created.id);
      });
      _toast('已创建歌单「${name.trim()}」，保存后将自动加入');
    } catch (_) {
      _toast('创建失败');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<String?> _promptName() {
    final controller = TextEditingController();
    return showCyreneDialog<String>(
      context: context,
      title: '新建歌单',
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MiuixTextField(
              controller: controller,
              label: '输入新歌单名称',
              singleLine: true,
              autofocus: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MiuixTextButton('取消', onPressed: () => dismiss()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixButton(
                  onPressed: () => dismiss(controller.text),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(
                    '创建',
                    style: MiuixTheme.of(context).textStyles.button,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_hasChanges) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    var added = 0, removed = 0, failed = 0;
    try {
      for (final id in _toAdd) {
        final ok = await _service.addTrackToPlaylist(
          widget.token,
          id,
          widget.track.id,
          widget.track.name,
          widget.track.artists,
          widget.track.album,
          widget.track.picUrl,
          widget.track.source.wireName,
        );
        ok ? added++ : failed++;
      }
      for (final id in _toRemove) {
        final ok = await _service.removeTrackFromPlaylist(
          widget.token,
          id,
          widget.track.id,
          widget.track.source.wireName,
        );
        ok ? removed++ : failed++;
      }
      final parts = <String>[];
      if (added > 0) parts.add('添加 $added');
      if (removed > 0) parts.add('移除 $removed');
      if (parts.isNotEmpty) _toast(parts.join(' · '));
      if (failed > 0) _toast('$failed 项操作失败');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _toast('保存失败');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    CyreneToast.show(message);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 12),
                  height: 5,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                _header(),
                const SizedBox(height: 12),
                Flexible(child: _list()),
                const SizedBox(height: 8),
                _summaryBar(),
                const SizedBox(height: 8),
                _actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      const Icon(Icons.queue_music, color: Colors.white, size: 20),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          '管理所在歌单',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );

  Widget _list() {
    if (_loading && _playlists.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: MiuixCircularProgressIndicator(
            size: 36,
            colors: MiuixProgressIndicatorColors(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      );
    }
    final visible = _visiblePlaylists;
    return ListView(
      shrinkWrap: true,
      children: [
        _createRow(),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                _showOnlyJoined ? '该歌曲未在任何歌单中' : '暂无歌单',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          )
        else ...[
          for (final playlist in visible) _row(playlist),
          if (_showOnlyJoined)
            TextButton(
              onPressed: () => setState(() => _showOnlyJoined = false),
              child: Text(
                '显示全部歌单',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _createRow() => InkWell(
    onTap: _creating ? null : _createPlaylist,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          style: BorderStyle.solid,
        ),
      ),
      alignment: Alignment.center,
      child: _creating
          ? const MiuixCircularProgressIndicator(
              size: 18,
              strokeWidth: 2,
              colors: MiuixProgressIndicatorColors(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                backgroundColor: Colors.transparent,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  '新建歌单',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _row(Playlist playlist) {
    final state = _rowState(playlist.id);
    final (bg, border) = switch (state) {
      _RowState.kept => (const Color(0x2634D399), const Color(0x4D34D399)),
      _RowState.willAdd => (const Color(0x264F9DFF), const Color(0x664F9DFF)),
      _RowState.willRemove => (
        const Color(0x22EF4444),
        const Color(0x66EF4444),
      ),
      _RowState.idle => (
        Colors.white.withValues(alpha: 0.06),
        Colors.transparent,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _toggleSelect(playlist.id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              _cover(playlist),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        decoration: state == _RowState.willRemove
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(playlist, state),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _trailing(state),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(Playlist playlist, _RowState state) {
    final base = '${playlist.trackCount} 首';
    return switch (state) {
      _RowState.willAdd => '$base · 待添加',
      _RowState.willRemove => '$base · 待移除',
      _ => base,
    };
  }

  Widget _cover(Playlist playlist) {
    final url = playlist.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                httpHeaders: imageHeaders(url),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _coverFallback(),
              )
            : _coverFallback(),
      ),
    );
  }

  Widget _coverFallback() => Container(
    color: Colors.white.withValues(alpha: 0.1),
    alignment: Alignment.center,
    child: Icon(
      Icons.music_note,
      size: 18,
      color: Colors.white.withValues(alpha: 0.5),
    ),
  );

  Widget _trailing(_RowState state) => switch (state) {
    _RowState.kept => const _Badge(color: Color(0xFF34D399), icon: Icons.check),
    _RowState.willAdd => const _Badge(
      color: Color(0xFF4F9DFF),
      icon: Icons.add,
    ),
    _RowState.willRemove => const _Badge(
      color: Color(0xFFEF4444),
      icon: Icons.remove,
    ),
    _RowState.idle => Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
    ),
  };

  Widget _summaryBar() {
    final parts = <Widget>[];
    if (_toAdd.isNotEmpty) {
      parts.add(
        _summaryChip('添加 ${_toAdd.length}', const Color(0xFF4F9DFF), Icons.add),
      );
    }
    if (_toRemove.isNotEmpty) {
      parts.add(
        _summaryChip(
          '移除 ${_toRemove.length}',
          const Color(0xFFEF4444),
          Icons.remove,
        ),
      );
    }
    if (parts.isEmpty) {
      parts.add(
        Text(
          '未做任何更改',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 12, children: parts),
    );
  }

  Widget _summaryChip(String label, Color color, IconData icon) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _actions() => Row(
    children: [
      Expanded(
        child: MiuixTextButton(
          '取消',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 3,
        child: MiuixButton(
          onPressed: (!_hasChanges || _saving) ? null : _save,
          colors: MiuixButtonDefaults.buttonColorsPrimary(context),
          child: _saving
              ? const MiuixCircularProgressIndicator(
                  size: 18,
                  strokeWidth: 2,
                  colors: MiuixProgressIndicatorColors(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : MiuixText(
                  _hasChanges
                      ? '保存更改 (${_toAdd.length + _toRemove.length})'
                      : '完成',
                  style: MiuixTheme.of(context).textStyles.button,
                ),
        ),
      ),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: Icon(icon, size: 14, color: Colors.white),
  );
}
