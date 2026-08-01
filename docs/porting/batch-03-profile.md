# 移植批次 03：我的

日期：2026-07-26 · 状态：完成（flutter analyze 0 错误）

## 功能对照（原版 MyPage「歌单 + 听歌统计」）

| 原版功能 | 新版状态 |
| --- | --- |
| 我的歌单列表（封面/名称/曲目数、打开详情） | 已有（Miuix CyreneMenuGroup 行） |
| 删除歌单（确认弹窗） | 已有 |
| **新建歌单** | **本批新增**：节标题右侧 ＋ 按钮 → Miuix 输入弹窗 → `PlaylistLibraryController.create` |
| **同步歌单**（已绑定来源的歌单增量同步） | **本批新增**：绑定了 `source` 的歌单行显示同步按钮，`POST /playlists/{id}/sync`，Toast 报告新增数并刷新列表 |
| 从歌单移除歌曲 | 已有（个人歌单详情页） |
| 听歌统计 | 已有（听歌足迹页，前序批次移植） |
| 播放历史 / 本地音乐入口 | 已有 |
| 网易云收藏库（专辑/歌手/电台/歌单四个子页） | **未移植**，留待后续批次（依赖网易账号绑定接口，规模约 3k 行） |

## 本批改动

- `features/profile/profile_page.dart`：
  - 「我的歌单」节标题新增 ＋（`create-playlist-button`），弹出 Miuix 输入
    对话框创建歌单；
  - `_PlaylistRow` 对绑定来源的歌单显示同步按钮（同步中转圈防重入），
    成功后 Toast + 重新加载歌单列表。
- 同步与批次 02 的「同步收藏」共用 `PlaylistService.syncPlaylist` /
  `bindImportConfig` 后端协议。

## 后续待办

- 网易云收藏库四个子页（批次 05 候选）。
- 原版「导入管理」对话框（导入外部歌单，新架构已有
  `playlist_import_service.dart` 可对接）。
