# Spotify 首页推荐接入可行性评估

> 调研对象：`demo/spotube` + `demo/spotube-plugin-spotify`
> 实测时间：2026-09-13，实测账号：号池账号（`backend/spotify-streamer` 登录的那个）
> 结论：**可行，且比 spotube 的实现简单得多**——我们已有的 librespot 用户 token 可以直接用。

---

## TL;DR

1. spotube 的丰富首页来自 **Spotify 内部 GraphQL 网关** `api-partner.spotify.com/pathfinder/v2/query`，
   也就是 open.spotify.com 网页播放器自己用的那套 API。不是 Web API，也不是 spclient。
2. spotube 为了拿到这个网关能认的 token，走了一整套 **WebView 登录 → `sp_dc` cookie → TOTP → `open.spotify.com/api/token`** 的流程。
3. **我们不需要这一套。** 实测：`backend/spotify-streamer` 现有的 librespot OAuth 用户 token
   直接打 pathfinder 就是 200，拿到的是号池账号完整的 21 个个性化分区（Daily Mix、Release Radar、
   "Made For xxx"、各类电台与合辑），和官方客户端一致。
4. 附带解决两个老问题：编辑歌单/榜单（`37i9dQZ*`）能拿到**真实名字和真实封面**了；
   `/personalized` 目前只能枚举号池账号音乐库的局限也一并消失。
5. 主要代价是**维护性风险**：persisted query 的 sha256 hash 跟着网页播放器版本走，
   Spotify 一改就得更新；以及必须伪装浏览器 User-Agent。
6. 主要产品限制：首页是**号池账号的口味**，所有用户看到的是同一份。要做到真正千人千面，
   需要让用户绑定自己的 Spotify 账号（方案见 §5.3 阶段 3）。

---

## 一、spotube 是怎么拿到这些数据的

### 1.1 认证链路

代码位置：`demo/spotube-plugin-spotify/spotube_plugin_spotify/src/jsMain/.../core/RealCoreAPI.kt`

```
WebView 打开 https://accounts.spotify.com/
  └─ 用户登录，URL 跳到 accounts.spotify.com/<locale>/status 时判定成功
       └─ 取 https://spotify.com 下的全部 cookie，其中必须有 sp_dc
            │
            ├─ GET https://gist.githubusercontent.com/raw/22ed9c6.../nuances.json
            │     取社区维护的 TOTP 密钥 { s: <base32 secret>, v: <totpVer> }
            │     （Spotify 会轮换这个密钥，所以要从网上拉，且失败时要 bust 缓存重试）
            │
            ├─ GET https://open.spotify.com/api/server-time  → 服务端时间戳
            │     （必须用服务端时间算 TOTP，本地时钟偏移会导致失败）
            │
            ├─ TOTP：HMAC-SHA1 / base32 / period=30 / digits=6
            │     实现见 services/TOTP.kt
            │
            └─ GET https://open.spotify.com/api/token
                     ?reason=transport&productType=web-player
                     &totp=<otp>&totpServer=<otp>&totpVer=<v>
                 Cookie: sp_dc=...
                 → { accessToken, accessTokenExpirationTimestampMs }
```

拿到的 `accessToken` 存进插件持久化存储，并按 `expiration` 定时刷新（`scheduleForRefresh()`）。

> 这一整套存在的唯一原因是 **spotube 只有浏览器 cookie，没有 OAuth 授权码**。
> `open.spotify.com/api/token` 是给网页播放器用的、受 TOTP 保护的换 token 端点。

### 1.2 数据链路

代码位置：`spotify_gql_client/.../gql/SpotifyGQLBaseClient.kt` 与 `gql/browse/BrowseClient.kt`

```http
POST https://api-partner.spotify.com/pathfinder/v2/query
Authorization: Bearer <accessToken>
Cookie: <登录时抓到的全部 cookie>
User-Agent: <随机浏览器 UA>          ← 见 services/UserAgents.kt
Content-Type: application/json

{
  "operationName": "home",
  "variables": { "timeZone": "Asia/Shanghai", "sp_t": "<sp_t cookie>", "facet": "", "sectionItemsLimit": 20 },
  "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "3357ffed...44a1" } }
}
```

用的是 **persisted query**：不发 GraphQL 查询正文，只发操作名 + 服务端预注册查询的 sha256。
插件里把所有 hash 硬编码在各个 Client 里：

| 操作 | 用途 | sha256Hash |
| --- | --- | --- |
| `home` | 首页全部分区 | `3357ffed7961629ba92b4e0a41514e4d5004a14355c964c23ce442205c9e44a1` |
| `homeSection` | 单个分区翻页 | `d62af2714f2623c923cc9eeca4b9545b4363abaa9188a9e94e2b63b823419a2c` |
| `queryWhatsNewFeed` | 新发行 feed | `3b53dede3c6054e8b7c962dd280eb6761c5d1c82b06b039f4110d76a62b4966b` |
| `browseAll` | 分类/流派入口 | `dbd8b55e09a58afc52eab438bc228ba28fd72ac2f2148c6c26354980e4579001` |
| `browsePage` | 某个分类页 | `f5c4e6d668f5716464a231c1cc8b22c1cbf6ad68b09929fd7de813a30581298b` |
| `fetchPlaylist` | 歌单详情 + 曲目 | `cd2275433b29f7316176e7b5b5e098ae7744724e1a52d63549c76636b3257749` |
| `queryArtistOverview` | 艺术家详情 + 热门曲目 | `7f86ff63e38c24973a2842b672abe44c910c1973978dc8a4a0cb648edef34527` |

完整清单：`grep -rn "sha256Hash" demo/spotube-plugin-spotify/spotify_gql_client/`。

### 1.3 响应结构

```
data.home
 ├─ greeting.transformedLabel            "Good evening"
 └─ sectionContainer.sections.items[]    一个分区
      ├─ uri                             spotify:section:0JQ5DA...   ← 翻页用这个
      ├─ data.__typename                 HomeGenericSectionData / HomeRecentlyPlayedSectionData / HomeShortsSectionData
      ├─ data.title.transformedLabel     "Made For Morax Morax"
      ├─ data.subtitle.transformedLabel  "Inspired by your recent activity"（可空，含 HTML 标签需清洗）
      └─ sectionItems.items[].content
           __typename: PlaylistResponseWrapper | AlbumResponseWrapper | ArtistResponseWrapper | TrackResponseWrapper
           data: { uri, name, images/coverArt.sources[], artists, content.totalCount, ... }
```

spotube 侧的映射见 `RealMetadataBrowseAPI.kt`：把每个 section 转成 `MetadataBrowseSection`
（title / description / items / moreLink=section uri），四种 wrapper 各转成对应的
Album / Playlist / Artist / Track 卡片。`moreLink` 拿去调 `homeSection` 翻页。

---

## 二、实测：我们不需要 spotube 那套认证

用 `http://107.149.30.2:8080/token`（streamer 暴露的 librespot OAuth 用户 token）直接打 pathfinder：

| 实验 | 结果 |
| --- | --- |
| librespot 用户 token + 浏览器 UA | **HTTP 200**，完整 21 个分区，199 KB |
| 自建应用的 client-credentials token | HTTP 403 `Client/request not allowed` —— **必须是用户 token** |
| 不带 User-Agent（curl 默认 UA） | HTTP 403 `Client/request not allowed` —— **UA 是硬门槛** |
| `sp_t` 传空字符串 | 200，**个性化内容照常返回**，不需要 cookie |
| 不带任何 Cookie 头 | 200，只靠 Bearer 就够 |
| 连打 15 次 `home` | 15 × 200，**没有触发限流**（对比 api.spotify.com 那边 429 retry-after 27s） |

结论：`sp_dc` / TOTP / nuance gist / server-time **整条链路对我们都是多余的**。
我们已经有一个常驻登录的 librespot session，它换出来的 access token 就是 pathfinder 认的用户 token。

当前 token 的 scope（`backend/spotify-streamer/src/main.rs:426`）：
`streaming` / `user-read-email` / `user-read-private` / `playlist-read-private` /
`playlist-read-collaborative` / `user-library-read` —— 实测已经够用，无需追加。

> 这也解释了为什么 pathfinder 不受我们那个 429 困扰：429 是 `api.spotify.com`
> 按 client_id 算的配额，pathfinder 是另一套网关、另一套配额。详见
> 上一轮排查（keymaster 共享池耗尽）。

### 复现命令

```bash
UT=$(curl -s http://107.149.30.2:8080/token | sed -E 's/.*"access_token":"([^"]+)".*/\1/')
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
curl -s -X POST https://api-partner.spotify.com/pathfinder/v2/query \
  -H "authorization: Bearer $UT" -H "User-Agent: $UA" \
  -H "content-type: application/json;charset=UTF-8" -H "accept: application/json" \
  --data '{"variables":{"timeZone":"Asia/Shanghai","sp_t":"","facet":"","sectionItemsLimit":20},
           "operationName":"home",
           "extensions":{"persistedQuery":{"version":1,"sha256Hash":"3357ffed7961629ba92b4e0a41514e4d5004a14355c964c23ce442205c9e44a1"}}}'
```

---

## 三、实测拿到的首页（号池账号，2026-09-13 晚）

`sectionItemsLimit=20`，返回 21 个分区、约 200 KB：

| # | 分区 | 内容 | 样例 |
| --- | --- | --- | --- |
| 1 | （无标题，Shorts） | Playlist×1 Album×2 Artist×1 | 乌托邦P Mix |
| 2 | Made For Morax Morax | Playlist×6 | Daily Mix 1/2/3 |
| 3 | Your top mixes | Playlist×9 | Hoang Mix, Chill Mix, Mandopop Mix |
| 4 | Recently played | Album×2 Playlist×1 Artist×1 | — |
| 5 | Recommended for today | Album×10 | Cry for Me |
| 6 | Albums featuring songs you like | Album×4 | — |
| 7 | Popular radio | Playlist×10 | Maki Radio |
| 8 | Popular albums and singles | Album×10 | — |
| 9 | Album picks | Album×10 | 大城市中央 |
| 10 | More like 乌托邦P | Playlist×4 Album×3 Artist×3 | J-Pop Hits, Gacha Pop |
| 11 | New releases for you | Album×10 | — |
| 12 | Popular artists | Artist×10 | — |
| 13 | Based on your recent listening | Playlist×9 | Anime On Replay |
| 14 | Throwback | Playlist×10 | All Out 2020s |
| 15 | Fresh new music | Playlist×10 | Release Radar |
| 16 | Soundtrack your Sunday night | Playlist×10 | daylist |
| 17 | Today's biggest hits | Playlist×8 | — |
| 18 | Party | Playlist×9 | — |
| 19 | Chill | Playlist×10 | romanticizing life |
| 20 | Sing-along | Playlist×9 | — |
| 21 | Instrumental | Playlist×10 | 猫とお昼寝 Afternoon Catnap |

对比现状：`/personalized` 目前只能产出 2~3 个分区（rootlist 里的歌单 + 收藏派生的电台种子/专辑），
而且 **Daily Mix / Release Radar / daylist 只有在号池账号手动收藏过时才会出现在 rootlist 里**。
pathfinder 的 `home` 是 Spotify 自己算好的，不依赖收藏状态。

分区标题是**英文**（跟随账号语言设置），中文化需要我们自己做映射表或按 section 类型重命名，见 §6。

---

## 四、顺带解决的老问题

### 编辑歌单 / 榜单的名字和封面

`fetchPlaylist` 对 `37i9dQZ*` 有效：

| 歌单 | Web API | spclient context-resolve | **pathfinder fetchPlaylist** |
| --- | --- | --- | --- |
| `37i9dQZEVXbMDoHDwVN2tF` | 404 | 只有曲目 URI，无名无封面 | **`Top 50 - Global` + 真实封面 + 50 首** |
| `37i9dQZF1DXcBWIGoYBM5M` | 404 | 同上 | **`Today's Top Hits` + 真实封面 + 50 首** |
| `37i9dQZEVXbLiRSasKsNU9` | 404 | 404 | `__typename: NotFound` |
| `37i9dQZF1DWWzBc3Sigger` | 404 | 404 | `__typename: NotFound` |

两点收益：

1. 桌面榜单页不再显示占位名「Spotify 歌单」，封面也不用退化成首曲专辑封面。
2. `NotFound` 是明确信号——可以直接判定 `discovery_service.dart` 里那两个硬编码 ID 已废弃，
   而不是靠猜。顺带一提 `discovery_service.dart:209` 的占位名比较写成了 `'Spotify 榜单'`，
   而后端发的是 `'Spotify 歌单'`，这个错别字得一起修。

---

## 五、落地方案

### 5.1 放在哪一层

**放 `backend/spotify-streamer`（Rust）**，理由：

- pathfinder 要的用户 token 就在这个进程里，现成的 `get_valid_access_token()` / 自动刷新 / 断线重连全都有；
  放到 TS 层就得再把 token 传一次，放到 Dart 层更是要把账号态带到客户端。
- 已有 `/personalized` 的调用方（TS `spotifyDiscovery.ts` → `/spotify/personalized` → Dart
  `DiscoveryService`）链路完整，新端点可以复用同一条管线，包括 2h 缓存 + 落盘保底。
- 唯一需要注意：pathfinder 请求**不能**走 `session.http_client()`。librespot 的 HttpClient
  会在 429 且 `Retry-After ≤ 10s` 时自己 sleep 重试（`http_client.rs:203`），而且不方便设自定义 UA。
  用 `reqwest` 单开一个 client，固定浏览器 UA。

### 5.2 端点设计

```
GET /home?limit=20&locale=zh-CN
```

响应直接复用现有 `/personalized` 的 `sections` 形状，让 Dart 侧零改动就能显示：

```jsonc
{
  "greeting": "Good evening",
  "sections": [
    {
      "id": "spotify:section:0JQ5DAUnp4wcj0bCb3wh3S",   // 翻页用
      "title": "Made For Morax Morax",
      "description": "…",
      "kind": "playlist",        // playlist | album | artist | track | mixed
      "items": [ { "id", "name", "artists", "coverImgUrl", "uri", "trackCount" } ]
    }
  ]
}
```

配套：

- `GET /home/section/:section_id?offset=&limit=` → `homeSection`，给「查看全部」用。
- `GET /playlist/:id` 内部加一级：Web API → **pathfinder fetchPlaylist** → context-resolve。
  把 pathfinder 插在 context-resolve 前面，编辑歌单就能拿到完整元数据。

`kind` 的取法：一个 section 里混排多种类型时（如 `More like 乌托邦P`）标 `mixed`，
每个 item 自带 `type` 字段，让前端按类型渲染卡片。

### 5.3 分阶段

> **实施状态（2026-09-14）**：阶段 1 已完成并通过静态检查与单元测试，**尚未部署**，
> 因此还没有真机验证。阶段 2 的三项小修也已完成（同样待部署）。落点：
>
> | 层 | 改动 |
> | --- | --- |
> | streamer | `PathfinderConfig` / `pathfinder_query()` / `GET /home` / `GET /home/section/:id` / `GET /artist/:id`；映射函数 15 个单元测试全过 |
> | TS | `getSpotifyHome()` + `GET /spotify/home`（三层降级：pathfinder → `/personalized` → 落盘快照，降级内容**不写快照**）；`getSpotifyArtist()` + `GET /spotify/artist/:id`（缓存 6h，无降级路径） |
> | Dart | `getSpotifyHome()` / `getSpotifyArtist()`；`SpotifyPersonalizedKind` 加 `artist`/`mixed`；`SpotifyPlaylistPreview.itemKind` 按卡片自身类型分流；桌面与移动首页均已切换 |
>
> **艺术家卡片已接通**：复用 `PlaylistDetailPage` 渲染（头像 + 「726.3 万粉丝 · 每月
> 407.6 万听众」+ 热门曲目），两端共用，不必各写一套 UI。关键点是必须
> `preserveTrackOrder: true` —— 详情页默认排序会把列表整个反转（歌单是旧曲在前，
> 反转后新曲在前），而热门曲目的顺序就是热度排名，反转正好是错的。
>
> 三处实测踩坑已固化成测试，都是「照着 spotube 抄会踩」的：
> 1. GQL 的 `sources` 数组**无序**——专辑给 300/64/640，艺术家给 640/160/320，取第一个会拿到 64px 缩略图
> 2. 歌单的马赛克封面 `width` 为 null
> 3. 艺术家页 `topTracks[].track.albumOfTrack.coverArt` 的三张**全都没有 width**，
>    按宽度挑会因为全当 0 而静默取到最后一张
>
> 已知缺口：`albumOfTrack` 在 `queryArtistOverview` 里只返回 `uri` 和 `coverArt`，
> **没有专辑名**，所以艺术家页曲目的 album.name 为空串（曲目条目展示艺术家，不影响）。

| 阶段 | 内容 | 产出 |
| --- | --- | --- |
| **1** ✅ | streamer 加 `/home` + `/home/section/:id`，硬编码两个 hash，reqwest + 浏览器 UA | 号池账号的 21 分区首页可用 |
| **2** 部分 | ✅ 修 `Spotify 榜单`/`Spotify 歌单` 错别字；✅ 换掉两个废弃榜单 ID；✅ 元数据成功而曲目 403 时保留真名与官方封面（含 TS 层丢弃 `coverImgUrl` 的 bug）；❌ `/playlist/:id` 插入 pathfinder 兜底 | 榜单页显示真实名字与封面 |
| **3**（可选） | 让用户绑定自己的 Spotify 账号 —— 走 librespot 同款 OAuth（**不需要 TOTP**），token 存用户侧，`/home` 带 token 参数 | 真正的千人千面 |
| **4**（可选） | `browseAll` / `browsePage` 接入，做分类浏览页 | 替代已死的 `/v1/browse/categories` |

阶段 1+2 是主要收益，工作量估计在 streamer 里加 200~300 行 + TS/Dart 各一个薄适配层。

---

## 六、风险与对策

| 风险 | 说明 | 对策 |
| --- | --- | --- |
| **persisted query hash 失效** | hash 跟网页播放器构建版本走，Spotify 更新就可能 400/错误响应 | 不要硬编码死：放 `config.json` 或环境变量可覆盖；失效时降级回现有 `/personalized`，别让首页整个空掉。也可以像 spotube 拉 nuance 那样，从一个自维护的 JSON 拉最新 hash |
| **User-Agent 检测** | 不伪装就 403 | 固定一个合理的桌面 Chrome UA；可参考插件的随机 UA 池（`UserAgents.kt`）但没必要随机 |
| **端点本身随时可能变** | 非公开 API，无 SLA | 所有 pathfinder 调用都必须有降级路径，且降级后 UI 只少分区不报错——现有 `/personalized` 的「各分区独立失败」设计正好复用 |
| **号池账号被限制** | 高频访问内部端点理论上有风险 | 保持现有 2h 缓存 + 落盘保底，不要每次请求都回源；实测 15 连打无限流，正常使用量远低于此 |
| **首页是号池账号口味** | 所有用户看到同一份推荐，且会被号池账号的播放行为带偏 | 短期接受（比现在丰富太多）；长期走阶段 3 让用户绑自己账号 |
| **分区标题是英文** | 跟随账号语言 | 先试着把号池账号的语言/地区设成 zh；不行就按 section 类型做中文映射表，未命中时保留原文 |
| **AGPL** | `spotube-plugin-spotify` 是 AGPL-3.0 | **不要复制它的 Kotlin 代码**。我们用到的是协议事实（端点、hash、字段名），自行用 Rust 实现即可 |

---

## 七、待决策

1. 阶段 1+2 是否现在就做？（估计一个下午）
2. 首页要不要**替换**现有 `/personalized`，还是 pathfinder 作为主源、`/personalized` 作为降级源并存？
   （建议后者——降级路径本来就得有，正好复用）
3. 阶段 3「用户绑定自己的 Spotify 账号」要不要排期？这是唯一能做到真个性化的路，
   而且实测证明**不需要 TOTP/sp_dc 那一套**，成本比想象中低。
4. 分区标题中文化：改号池账号语言 vs 自建映射表。

---

## 附：关键代码位置

| 内容 | 路径 |
| --- | --- |
| 认证全流程 | `demo/spotube-plugin-spotify/spotube_plugin_spotify/src/jsMain/kotlin/.../core/RealCoreAPI.kt` |
| TOTP 实现 | `demo/spotube-plugin-spotify/spotube_plugin_spotify/src/commonMain/kotlin/.../services/TOTP.kt` |
| GQL 基类 / 端点 / 默认头 | `demo/spotube-plugin-spotify/spotify_gql_client/src/commonMain/kotlin/.../gql/SpotifyGQLBaseClient.kt` |
| home / homeSection / browse 请求 | `.../gql/browse/BrowseClient.kt` |
| 响应 → UI section 映射 | `.../spotube_plugin_spotify/core/RealMetadataBrowseAPI.kt` |
| 真实响应样本（21 分区） | `demo/spotube-plugin-spotify/spotify_gql_client/src/commonTest/resources/home_200.json` |
| 可直接改的 HTTP 样例集 | `demo/spotube-plugin-spotify/.bruno/Spotify GQL/`（Bruno 集合，含每个操作的完整请求体） |
| 我们这边的 token 来源 | `backend/spotify-streamer/src/main.rs:238` `get_valid_access_token()` |
| 现有个性化端点 | `backend/spotify-streamer/src/main.rs:900` `get_personalized()` |
