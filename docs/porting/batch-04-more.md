# 移植批次 04：「更多」及设置子页补齐

日期：2026-07-27 · 状态：完成（flutter analyze 0 错误）

## 功能对照

原版「更多」菜单及其子页在新版中的落位：

| 原版入口 | 新版状态 |
| --- | --- |
| 播放历史 / 本地音乐 / 设置 / 帮助与支持 | 已有（更多抽屉 MoreMenuDrawer） |
| **公告** | **本批新增**：设置 → 应用 → 公告（`AnnouncementService.fetchAnnouncement`，Miuix 对话框展示，无公告 Toast 提示） |
| **检查更新** | **本批新增**：设置 → 应用 → 检查更新（行内显示当前版本 v1.0.0；`UpdateService.checkUpdate` 按 Android ABI 挑选安装包，弹窗展示更新说明并可复制下载链接） |
| 开发者页面 | 未移植（原版调试用途，暂无需求） |
| 均衡器 | 占位（入口保留，提示未开放，见批次 01） |

## 本批改动

- 新增 `lib/app/app_version.dart`（`appVersion` 常量，需与 pubspec 同步），
  `main()` 注入 `UpdateService.setCurrentVersion`。
- `features/settings/settings_page.dart` 应用分组新增「公告」「检查更新」两行
  （HyperOS 彩色图标：蓝/绿），弹窗均为 Miuix 风格。
- 下载链接以复制到剪贴板方式交付（未引入 url_launcher 依赖）。

## 全部批次总览

1. 批次 01：全屏播放器（经典 + 流体云 + 兼容适配层） — `batch-01-player.md`
2. 批次 02：发现页（同步收藏） — `batch-02-discover.md`
3. 批次 03：我的（新建歌单 / 歌单同步） — `batch-03-profile.md`
4. 批次 04：更多（公告 / 检查更新） — 本文档

## 后续批次候选

- 网易云收藏库四子页（专辑/歌手/电台/歌单）
- 导入外部歌单管理界面（对接 `playlist_import_service`）
- 均衡器、下载管理、开发者页面
