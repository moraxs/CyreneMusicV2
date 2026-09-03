# 项目要点（Cyrene Music）

## 酷狗音乐取流关键约束

- 酷狗概念版音频 CDN（`fs.youthandroid*.kugou.com` 等）**只支持 HTTP**：HTTPS 证书主机名不匹配（SEC_E_WRONG_PRINCIPAL），强制 `http://` → `https://` 会导致客户端永远转圈。`backend/src/lib/services/song.ts` 的 `url` 字段必须原样返回酷狗给的 `http://` 直链（对比参考 `demo/KuGouMusicApi-main` 开源实现也是原样返回）。
- 封面域名 `imge.kugou.com` 的 HTTPS 正常，可安全替换。
- 客户端已允许明文流量：Android `android/app/src/main/res/xml/network_security_config.xml`（base-config cleartextTrafficPermitted=true）、iOS `Info.plist` NSAllowsArbitraryLoads。
- 取流签名链（`/v5/url`，appid=3116 概念版）：signKey = `md5(hash + '185672dd44712f60bb1736df5a377e82' + appid + mid + userid)`；signature = `md5('LnT6xpN3khm36zse0QzvmgTZ3waWdRSA' + 排序参数串 + 盐值)`。
- token 失效时试听兜底（IsFreePart=1）也会被拒（error_code 31863），需去掉 token/userid 并用 userid=0 重算 key 匿名重试。
- error_code 20018 = 账号无 VIP 特权（可尝试 youth/v1 领取/升级 VIP 后重试）。

## Spotify 播放链路与缓存

- 链路：客户端 → Elysia(`/spotify/raw-stream/:id.ogg`) → Rust spotify-streamer(`spotify.streamer_url`，部署在美国机) → Spotify。`direct_stream=true` 时改为 302 直连 Rust 端（不经过 Elysia，与缓存模式互斥）。
- 播放转圈/seek 慢的根因：双跳中转带宽抖动 + Rust 端每次 Range 请求都要重走 Track::get / audio key request / seek 等 Spotify 网络往返。
- 已加整轨磁盘缓存层（`backend/src/lib/services/spotifyAudioCache.ts`，缓存目录 `backend/cache/spotify/`）：命中即本地 serve（完整 Range），未命中透传 + 后台全量预热落盘；LRU 按 mtime（命中时 utimes 刷新）淘汰，限额 `config.json → spotify.audio_cache.max_bytes`（默认 5GB）。
- 缓存文件是 Rust 端解密并剥离 167 字节 Spotify OGG 归一化头后的可播放流，Content-Type 固定 `audio/ogg`。
- Rust 端已知隐患（未修）：`stream_track` 的 `audio_decrypt.seek` 在 async handler 中同步调用，会阻塞 tokio worker 直到上游数据就位；如需进一步优化多并发 seek 场景，应把 seek 也移入 `spawn_blocking` 并重新编译部署美国机。
- 本地验证缓存模块时若缺 node_modules，可用 stub 包（axios/cli-progress）+ `bun test` 实跑；注意 `src/lib/services/` 引用同层 utils 是 `../utils/...`（一级），不是三级。

## 后端项目结构

- `backend/` 是 ElysiaJS (bun) 项目，**未被 git 跟踪**，本地无 `package.json`/`node_modules`（依赖装在服务器上）。
- 生产环境部署在 `https://music.nekofun.top`（端口 4050/4055 体系），本地改动需同步到服务器后重启才生效。
- 设备指纹持久化在 `backend/cookie/kugou_device.json`，登录 token 在 `backend/cookie/kugou_cookie.txt`；扫码登录后 token 由 `/kugou/login/qr/check` → `syncKugouCookie` 更新。
- `/kugou/song` 需要 API Key（`config.json` → `api_key.keys`，支持 `X-API-Key` 头或 `api_key` 查询参数）。

## 快速验证方法

- 酷狗取流可用性：直接对 `gateway.kugou.com/v5/url` 用概念版签名发 GET（参考 `backend/temp_test_anon.mjs` 的写法），或调线上 `https://music.nekofun.top/kugou/song?hash=<HASH>&api_key=<KEY>`。
- 拿到 URL 后务必用 **http** 协议 HEAD 验证（`curl.exe -I http://fs.youthandroid*.kugou.com/...`），不要用 https。
