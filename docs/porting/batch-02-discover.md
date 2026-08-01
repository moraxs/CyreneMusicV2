# 移植批次 02：发现页

日期：2026-07-26 · 状态：完成（flutter analyze 0 错误）

## 方向说明

按最新约定，页面移植**只移植功能与内容**，UI 统一采用新版的 miuix HyperOS
风格（不移植原版 Material Expressive / Cupertino / Fluent 主题，桌面端不移植）。
此前误拷的原版 Material 风格发现页已归档至
`.port_archive/discover_original_material/` 仅作参照。

## 功能对照

| 原版功能 | 新版状态 |
| --- | --- |
| 分类标签选择（全部歌单 + 高质量标签 `/netease/playlist/highquality/tags`） | 已有（Miuix 胶囊按钮横滑条） |
| 推荐歌单网格（`/netease/top/playlist?cat=`，播放量角标） | 已有（Miuix 卡片网格 + MiuixBadge） |
| 下拉刷新 / 分类切换加载态 | 已有 |
| 歌单详情（封面/简介/标签/播放全部/曲目列表） | 已有（`PlaylistDetailPage`，本次前序批次补了简介折叠、标题省略号、毛玻璃穿透） |
| **同步收藏**（把在线歌单绑定为自己歌单的来源并增量同步） | **本批新增** |
| 未登录/未配置音源的整页拦截 | 有意不移植：浏览不再要求登录；音源在新架构恒视为已配置 |

## 本批改动

1. `infrastructure/services/playlist_service.dart` 新增
   `bindImportConfig(token, playlistId, {source, sourcePlaylistId})`
   → `PUT /playlists/{id}/import-config`（与原版发现详情页相同的后端协议）。
2. `features/playlist/playlist_detail_page.dart`：
   - 顶栏新增同步按钮（仅在线歌单且已登录时显示，同步中转圈）；
   - 点击后 `showCyreneSheet` 选择目标歌单（默认歌单 ❤ 图标），
     绑定来源 → `POST /playlists/{id}/sync` 增量同步 → Toast 报告新增曲目数。

## 兼容层沉淀（后续批次可复用）

- `compat/url_service.dart`：原版 `UrlService()` 垫片 → 新 `UrlService.instance`。
- `compat/netease_discover{_service,}.dart`：原版发现服务/模型原样移植（直连后端）。
- `compat/theme_manager.dart`：桌面/框架分支恒 false 的垫片。
- `AuthService.isLoggedIn`、`AudioSourceService.isConfigured` 补齐。
