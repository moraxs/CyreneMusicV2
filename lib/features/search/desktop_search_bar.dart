import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../infrastructure/services/search_suggestion_service.dart';

/// 桌面融合标题栏正中的搜索框 + 下拉浮层。
///
/// 结构：一枚压扁到标题栏高度的 [MiuixTextField]（Miuix 风格，聚焦即在正下方
/// 弹出下拉），下拉浮层用 [OverlayPortal] + [LayerLink] 锚定到输入框底部，配全屏
/// 透明 barrier 实现点外部关闭。浮层内容复刻移动端搜索页的「热搜榜 / 搜索历史 /
/// 搜索建议」三态，数据同源 [SearchSuggestionService]。
///
/// 本组件不负责展示结果——提交（回车 / 点热搜 / 点历史 / 点建议）时先落库历史,
/// 再把关键词交给 [onSubmit],由外层桌面外壳切到「搜索」页展示完整结果。
///
/// **不能放进标题栏的 `DragToMoveArea`**：输入框 hover / 聚焦会触发子树重建,
/// 打断窗口拖拽（见 `desktop_title_bar.dart` 类文档）。故由标题栏把它夹在两段
/// 拖拽区之间、拖拽区之外。
class DesktopSearchBar extends StatefulWidget {
  const DesktopSearchBar({super.key, required this.onSubmit});

  /// 提交关键词（已 trim、非空）。由外壳切到搜索页并驱动 [SearchController]。
  final ValueChanged<String> onSubmit;

  @override
  State<DesktopSearchBar> createState() => _DesktopSearchBarState();
}

class _DesktopSearchBarState extends State<DesktopSearchBar> {
  final _focusNode = FocusNode();
  final _link = LayerLink();
  final _portalController = OverlayPortalController();
  final _service = SearchSuggestionService.instance;

  /// 面板宽度与输入框对齐，浮层左对齐贴在输入框正下方。
  static const _panelWidth = 360.0;

  /// MiuixInputField 默认最小高度为 45dp；桌面标题栏使用其 80%，避免在
  /// 48dp 的标题栏内显得过于饱满。
  static const _fieldHeight = 36.0;

  /// 输入防抖 300ms（与移动端 SearchPage 一致）；seq 丢弃过期响应。
  Timer? _suggestDebounce;
  int _suggestSeq = 0;

  String _query = '';
  // MiuixInputField 只在获得焦点时上报 expanded=true，失焦要自己收（见
  // _onFocusChanged），否则占位标签不会恢复。
  bool _expanded = false;
  List<String> _suggestions = const [];
  List<String> _hotSearches = const [];
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _loadDiscover();
  }

  Future<void> _loadDiscover() async {
    final history = await _service.loadHistory();
    if (mounted) setState(() => _history = history);
    final hots = await _service.fetchHotSearches();
    if (mounted) setState(() => _hotSearches = hots);
  }

  // 获得焦点开浮层；失焦不主动关浮层（点浮层内的 chip 会先让输入框失焦，
  // 若在此关闭会吞掉那次点击），但要把 MiuixInputField 的 expanded 收回。
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _open();
    } else if (_expanded) {
      setState(() => _expanded = false);
    }
  }

  void _open() {
    if (_portalController.isShowing) return;
    _portalController.show();
    // 打开时刷新历史：可能在搜索页 / 其他入口改过。
    _refreshHistory();
    setState(() {});
  }

  Future<void> _refreshHistory() async {
    final history = await _service.loadHistory();
    if (mounted) setState(() => _history = history);
  }

  void _close() {
    if (_portalController.isShowing) _portalController.hide();
    if (_focusNode.hasFocus) _focusNode.unfocus();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _suggestDebounce?.cancel();
    final keywords = value.trim();
    if (keywords.isEmpty) {
      _suggestSeq++;
      setState(() => _suggestions = const []);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 300), () async {
      final seq = ++_suggestSeq;
      final results = await _service.fetchSuggestions(keywords);
      if (!mounted || seq != _suggestSeq || _query.trim() != keywords) return;
      setState(() => _suggestions = results);
    });
  }

  Future<void> _submit(String term) async {
    final keyword = term.trim();
    if (keyword.isEmpty) return;
    setState(() => _query = keyword);
    _close();
    // 与移动端一致：提交即写入搜索历史（去重置顶）。
    final history = await _service.saveHistory(keyword);
    if (mounted) setState(() => _history = history);
    widget.onSubmit(keyword);
  }

  Future<void> _removeHistory(String term) async {
    final history = await _service.removeHistory(term);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _clearHistory() async {
    await _service.clearHistory();
    if (mounted) setState(() => _history = const []);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(
        link: _link,
        child: _buildField(),
      ),
    );
  }

  // 胶囊形状的 Miuix 搜索输入（MiuixSearchBar 的输入部件）：自带搜索图标、
  // 清除按钮与占位标签，圆角为全椭圆胶囊。受控于 _query / _expanded。
  Widget _buildField() => SizedBox(
    height: _fieldHeight,
    child: MiuixInputField(
      query: _query,
      onQueryChange: _onQueryChanged,
      onSearch: _submit,
      expanded: _expanded,
      onExpandedChange: (value) => setState(() => _expanded = value),
      focusNode: _focusNode,
      label: '搜索音乐、歌手',
    ),
  );

  Widget _buildOverlay(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return Stack(
      children: [
        // 全屏 barrier：点输入框 / 面板以外的任何位置都收起下拉。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: Align(
            alignment: Alignment.topLeft,
            child: _buildPanel(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(MiuixThemeData theme) {
    final colors = theme.colors;
    final showSuggestions =
        _query.trim().isNotEmpty && _suggestions.isNotEmpty;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: _panelWidth,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.dividerLine),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: showSuggestions
            ? _buildSuggestions(theme)
            : _buildDiscover(theme),
      ),
    );
  }

  Widget _buildSuggestions(MiuixThemeData theme) => ListView.builder(
    shrinkWrap: true,
    padding: const EdgeInsets.symmetric(vertical: 6),
    itemCount: _suggestions.length,
    itemBuilder: (context, index) {
      final keyword = _suggestions[index];
      return InkWell(
        onTap: () => _submit(keyword),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              MiuixIcon(
                vector: MiuixIcons.basic.search,
                size: 15,
                tint: theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyles.body2.copyWith(
                    color: theme.colors.onSurfaceContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildDiscover(MiuixThemeData theme) {
    final colors = theme.colors;
    if (_hotSearches.isEmpty && _history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '输入关键词，从音源搜索歌曲与歌手',
          style: theme.textStyles.body2.copyWith(
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }
    final headerStyle = theme.textStyles.footnote1.copyWith(
      color: colors.onSurfaceVariantSummary,
      fontWeight: FontWeight.w600,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hotSearches.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.local_fire_department,
                  size: 15,
                  color: Color(0xFFFF6D00),
                ),
                const SizedBox(width: 5),
                Text('热搜榜', style: headerStyle),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 与移动端一致：仅取前 10，前三名序号高亮。
                for (final (index, name) in _hotSearches.take(10).indexed)
                  _SearchChip(
                    leading: Text(
                      '${index + 1}',
                      style: theme.textStyles.footnote1.copyWith(
                        fontWeight: FontWeight.w600,
                        color: index < 3
                            ? const Color(0xFFFF6D00)
                            : colors.onSurfaceVariantSummary,
                      ),
                    ),
                    label: name,
                    onTap: () => _submit(name),
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (_history.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 15,
                  color: colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 5),
                Text('搜索历史', style: headerStyle),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearHistory,
                  child: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in _history)
                  _SearchChip(
                    label: term,
                    onTap: () => _submit(term),
                    onRemove: () => _removeHistory(term),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 圆角胶囊标签（热搜 / 历史），可带前缀序号与移除按钮。视觉与移动端
/// `SearchPage` 的同名部件一致。
class _SearchChip extends StatelessWidget {
  const _SearchChip({
    required this.label,
    required this.onTap,
    this.leading,
    this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? leading;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyles.footnote1.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
