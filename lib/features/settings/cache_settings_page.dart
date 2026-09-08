import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/cache/song_cache_service.dart';
import '../../presentation/cyrene/cyrene_overlays.dart';
import '../../presentation/cyrene/cyrene_page.dart';
import '../../presentation/cyrene/cyrene_toast.dart';
import 'settings_body.dart';

/// 缓存容量上限选项（0 = 不限制）。
const _limitOptions = <(int, String)>[
  (512 * 1024 * 1024, '512 MB'),
  (1024 * 1024 * 1024, '1 GB'),
  (2 * 1024 * 1024 * 1024, '2 GB'),
  (5 * 1024 * 1024 * 1024, '5 GB'),
  (0, '不限制'),
];

String formatCacheSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return '${value.toStringAsFixed(value >= 100 || unit <= 1 ? 0 : 1)} ${units[unit]}';
}

String cacheLocationName(SongCacheLocation location) => switch (location) {
  SongCacheLocation.internal => '应用内部存储',
  SongCacheLocation.external => '外部专属目录',
  SongCacheLocation.custom => '自选目录',
};

String cacheLocationDescription(SongCacheLocation location) =>
    switch (location) {
      SongCacheLocation.internal => '应用私有目录，卸载时一并清除，无需任何权限',
      SongCacheLocation.external =>
        'Android 的 /Android/data 专属目录，容量大且可在文件管理器中查看',
      SongCacheLocation.custom => '自行指定磁盘位置（仅桌面端），会在其中建立 CyreneMusicCache 子目录',
    };

/// 歌曲缓存管理页。
///
/// 缓存的读写逻辑全在 [SongCacheService]；这里只负责开关、目录、容量三项设置
/// 与用量展示 / 清理。
class CacheSettingsPage extends StatelessWidget {
  const CacheSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '歌曲缓存',
    bodyBuilder: (context, topPadding) =>
        CacheSettingsBody(topPadding: topPadding),
  );
}

/// 歌曲缓存设置正文，不含页面骨架。
///
/// 独立成组件是为了让桌面端的合并设置页直接嵌这一份——列表的加载状态、
/// 清理中的忙碌标记都是这里的 State，抄一份出去就会有两套。
class CacheSettingsBody extends StatefulWidget {
  const CacheSettingsBody({
    super.key,
    this.topPadding = EdgeInsets.zero,
    this.embedded = false,
    this.onOpenSecondary,
  });

  final EdgeInsets topPadding;

  /// 嵌进桌面端合并设置页时为 true。
  ///
  /// 此时「已缓存歌曲」不再就地铺开——缓存有多少首这一段就有多长，会把那条
  /// 长页拉到没边。改成一行入口，列表挪进 [CachedSongsPage]。
  final bool embedded;

  /// 二级页在右侧栏打开（与设置主页同一套约定）。
  final ValueChanged<Widget>? onOpenSecondary;

  @override
  State<CacheSettingsBody> createState() => _CacheSettingsBodyState();
}

class _CacheSettingsBodyState extends State<CacheSettingsBody> {
  final _cache = SongCacheService.instance;

  List<CachedSongInfo> _items = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _openCachedSongs(BuildContext context) async {
    const page = CachedSongsPage();
    final openSecondary = widget.onOpenSecondary;
    if (openSecondary != null) {
      openSecondary(page);
      return;
    }
    await Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => page));
    if (mounted) await _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _cache.refreshStats();
    final items = await _cache.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _cache,
    builder: (context, _) {
      final enabled = _cache.enabled;
      final stats = _cache.stats;
      return SettingsBody(
        topPadding: widget.topPadding,
        embedded: widget.embedded,
        children: [
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                key: const Key('toggle-song-cache'),
                vector: MiuixIcons.extended.byName('download')!,
                iconBackground: const Color(0xFF3482FF),
                title: '启用歌曲缓存',
                subtitle: '首次播放时顺手存到本机，不额外耗流量',
                trailing: MiuixSwitch(
                  value: enabled,
                  onChanged: (value) => _cache.setEnabled(value),
                ),
                onTap: () => _cache.setEnabled(!enabled),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CyreneInlineAlert(
            vector: MiuixIcons.extended.byName('info')!,
            description:
                '首次播放的音频会在播放过程中直接存下来，不会为了缓存再下载一遍。'
                '缓存文件与歌曲信息均以 ChaCha20 加密存放，只有本应用能解密播放；'
                '再次播放时直接读本地文件，无需联网，也不再消耗音源解析次数。',
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '存储',
            insideMargin: EdgeInsets.fromLTRB(16, 4, 16, 8),
          ),
          CyreneMenuGroup(
            children: [
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('folder')!,
                iconBackground: const Color(0xFFFF9F0A),
                title: '存储位置',
                subtitle: _cache.directoryPath ?? '尚未创建',
                value: cacheLocationName(_cache.location),
                onTap: _busy ? null : _chooseLocation,
              ),
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('backup')!,
                iconBackground: const Color(0xFF8A64FF),
                title: '容量上限',
                subtitle: '超出后自动清理最久未播放的缓存',
                value: _limitName(_cache.limitBytes),
                onTap: _chooseLimit,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MiuixSmallTitle(
            '已用空间',
            insideMargin: EdgeInsets.fromLTRB(16, 4, 16, 8),
          ),
          _UsageCard(
            stats: stats,
            loading: _loading,
            onClear: stats.count == 0 ? null : _confirmClear,
          ),
          const SizedBox(height: 12),
          if (widget.embedded)
            CyreneMenuGroup(
              children: [
                CyreneMenuRow(
                  key: const Key('open-cached-songs'),
                  vector: MiuixIcons.extended.byName('music')!,
                  iconBackground: const Color(0xFF3CC756),
                  title: '已缓存歌曲',
                  subtitle: '逐首查看与删除',
                  value: _loading ? '统计中…' : '${stats.count} 首',
                  onTap: () => _openCachedSongs(context),
                ),
              ],
            )
          else ...[
            const MiuixSmallTitle(
              '已缓存歌曲',
              insideMargin: EdgeInsets.fromLTRB(16, 4, 16, 8),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: MiuixCircularProgressIndicator(
                    size: 22,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (_items.isEmpty)
              CyreneEmptyState(
                vector: MiuixIcons.extended.byName('music')!,
                title: '暂无缓存',
                description: enabled
                    ? '播放歌曲后会自动缓存到本机'
                    : '开启缓存后，播放过的歌曲会出现在这里',
              )
            else
              CyreneMenuGroup(
                children: [
                  for (final item in _items)
                    cachedSongRow(
                      context,
                      item: item,
                      onRemove: () => _remove(item),
                    ),
                ],
              ),
          ],
        ],
      );
    },
  );

  static String _limitName(int bytes) {
    for (final (value, name) in _limitOptions) {
      if (value == bytes) return name;
    }
    return formatCacheSize(bytes);
  }

  Future<void> _chooseLocation() async {
    final locations = SongCacheService.availableLocations;
    await showCyreneSheet<void>(
      context: context,
      title: '存储位置',
      builder: (sheetContext, dismiss) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final location in locations)
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName(
                  location == SongCacheLocation.custom ? 'addFolder' : 'folder',
                )!,
                title: cacheLocationName(location),
                subtitle: cacheLocationDescription(location),
                trailing: _cache.location == location
                    ? MiuixIcon(
                        vector: MiuixIcons.basic.check,
                        size: 20,
                        tint: MiuixTheme.of(sheetContext).colors.primary,
                      )
                    : const SizedBox(width: 20),
                onTap: () {
                  dismiss();
                  _applyLocation(location);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyLocation(SongCacheLocation location) async {
    var customPath = '';
    if (location == SongCacheLocation.custom) {
      final picked = await FilePicker.getDirectoryPath(dialogTitle: '选择缓存目录');
      if (picked == null || picked.isEmpty) return;
      customPath = picked;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await _cache.setLocation(
      location,
      customPath: location == SongCacheLocation.custom ? customPath : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      CyreneToast.show('该目录不可写，已保持原设置');
      return;
    }
    CyreneToast.show('缓存目录已切换，原有缓存已迁移');
    await _reload();
  }

  Future<void> _chooseLimit() async {
    await showCyreneSheet<void>(
      context: context,
      title: '容量上限',
      builder: (sheetContext, dismiss) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (value, name) in _limitOptions)
              CyreneMenuRow(
                vector: MiuixIcons.extended.byName('backup')!,
                title: name,
                trailing: _cache.limitBytes == value
                    ? MiuixIcon(
                        vector: MiuixIcons.basic.check,
                        size: 20,
                        tint: MiuixTheme.of(sheetContext).colors.primary,
                      )
                    : const SizedBox(width: 20),
                onTap: () {
                  dismiss();
                  _cache.setLimitBytes(value).then((_) => _reload());
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(CachedSongInfo item) async {
    await _cache.remove(item.key);
    if (!mounted) return;
    setState(() {
      _items = _items.where((cached) => cached.key != item.key).toList();
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showCyreneDialog<bool>(
      context: context,
      title: '清空全部缓存？',
      summary:
          '将删除 ${_cache.stats.count} 首歌曲的缓存，释放 '
          '${formatCacheSize(_cache.stats.bytes)} 空间。清空后再次播放需要重新联网。',
      builder: (dialogContext, dismiss) {
        final theme = MiuixTheme.of(dialogContext);
        final colors = theme.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('取消', onPressed: () => dismiss(false)),
                const SizedBox(width: 10),
                MiuixButton(
                  onPressed: () => dismiss(true),
                  colors: MiuixButtonColors(
                    color: colors.error,
                    disabledColor: colors.disabledPrimaryButton,
                    contentColor: colors.onError,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  child: MiuixText('清空', style: theme.textStyles.button),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _cache.clear();
    if (!mounted) return;
    CyreneToast.show('缓存已清空');
    await _reload();
  }
}

/// 用量卡片：曲目数 + 占用空间 + 一键清空。
class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.stats,
    required this.loading,
    required this.onClear,
  });

  final SongCacheStats stats;
  final bool loading;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return MiuixCard(
      cornerRadius: 20,
      insideMargin: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '已缓存',
                  value: loading ? '—' : '${stats.count}',
                  unit: '首',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: colors.onBackground.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _Metric(
                  label: '占用空间',
                  value: loading ? '—' : formatCacheSize(stats.bytes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MiuixButton(
            onPressed: onClear,
            colors: MiuixButtonColors(
              color: colors.error.withValues(alpha: 0.12),
              disabledColor: colors.disabledPrimaryButton,
              contentColor: colors.error,
              disabledContentColor: colors.disabledOnPrimaryButton,
            ),
            child: MiuixText('一键清空缓存', style: theme.textStyles.button),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            MiuixText(
              value,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: colors.onBackground,
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              MiuixText(unit!, fontSize: 13, color: colors.onBackgroundVariant),
            ],
          ],
        ),
        const SizedBox(height: 4),
        MiuixText(label, fontSize: 13, color: colors.onBackgroundVariant),
      ],
    );
  }
}

/// 设置主页那一行右侧的摘要：关闭时显示「已关闭」，否则显示曲目数与占用。
String songCacheSummary() {
  final cache = SongCacheService.instance;
  if (!cache.enabled) return '已关闭';
  final stats = cache.stats;
  if (stats.count == 0) return '已开启';
  return '${stats.count} 首 · ${formatCacheSize(stats.bytes)}';
}

/// 「已缓存歌曲」列表里的一行。两处共用（移动端就地铺开 / 桌面端二级页），
/// 免得删除按钮与副标题的格式在两边分叉。
Widget cachedSongRow(
  BuildContext context, {
  required CachedSongInfo item,
  required VoidCallback onRemove,
}) => CyreneMenuRow(
  key: Key('cached-${item.key}'),
  vector: MiuixIcons.extended.byName('music')!,
  iconBackground: const Color(0xFF3CC756),
  title: item.track.name,
  subtitle:
      '${item.track.artists.isEmpty ? '未知歌手' : item.track.artists}'
      ' · ${formatCacheSize(item.bytes)}',
  trailing: MiuixIconButton(
    onPressed: onRemove,
    child: MiuixIcon(
      vector: MiuixIcons.extended.byName('delete')!,
      size: 18,
      tint: MiuixTheme.of(context).colors.onSurfaceVariantActions,
    ),
  ),
);

/// 「已缓存歌曲」二级页。
///
/// 存在的理由只有一个：这份列表的长度等于用户缓存了多少首歌，就地铺在设置里
/// 会把页面拉到没边（桌面端的合并长页尤其明显）。这里给它一条自己的滚动，
/// 并且行是**懒构建**的——卡片外壳套一个 `ListView.builder`，几百首也只画屏内那些。
class CachedSongsPage extends StatefulWidget {
  const CachedSongsPage({super.key});

  @override
  State<CachedSongsPage> createState() => _CachedSongsPageState();
}

class _CachedSongsPageState extends State<CachedSongsPage> {
  final _cache = SongCacheService.instance;

  List<CachedSongInfo> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _cache.refreshStats();
    final items = await _cache.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _remove(CachedSongInfo item) async {
    await _cache.remove(item.key);
    if (!mounted) return;
    setState(() {
      _items = _items.where((cached) => cached.key != item.key).toList();
    });
  }

  @override
  Widget build(BuildContext context) => CyrenePage(
    title: '已缓存歌曲',
    bodyBuilder: (context, topPadding) {
      if (_loading) {
        return Padding(
          padding: topPadding,
          child: const Center(
            child: MiuixCircularProgressIndicator(size: 22, strokeWidth: 2),
          ),
        );
      }

      if (_items.isEmpty) {
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            CyreneEmptyState(
              vector: MiuixIcons.extended.byName('music')!,
              title: '暂无缓存',
              description: _cache.enabled
                  ? '播放歌曲后会自动缓存到本机'
                  : '开启缓存后，播放过的歌曲会出现在这里',
            ),
          ],
        );
      }

      return Padding(
        padding: topPadding + const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: CyreneMenuGroup.custom(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _items.length,
            itemBuilder: (context, index) => cachedSongRow(
              context,
              item: _items[index],
              onRemove: () => _remove(_items[index]),
            ),
          ),
        ),
      );
    },
  );
}
