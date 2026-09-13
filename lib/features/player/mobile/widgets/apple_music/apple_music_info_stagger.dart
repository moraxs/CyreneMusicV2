import 'package:flutter/animation.dart';

/// 封面模式 ↔ 歌词模式切换时，两块歌曲信息的「错位交叉淡入」算法。
///
/// 对标 AMLL（applemusic-like-lyrics）`react-full` 的
/// `PrebuiltLyricPlayer/index.module.css`：
///
/// ```css
/// --info-timing-func-in:  cubic-bezier(0.5, 0, 0.75, 0);  /* 离场：加速 */
/// --info-timing-func-out: cubic-bezier(0.25, 1, 0.5, 1);  /* 入场：减速 */
///
/// .smallMusicInfo            { transform: translateY(0);      opacity: 1 }
/// .smallMusicInfo.hideLyric  { transform: translateY(25vh);   opacity: 0 }
/// .bigMusicInfo              { transform: translateY(-25vh);  opacity: 0 }
/// .bigMusicInfo.hideLyric    { transform: translateY(0);      opacity: 1 }
/// ```
///
/// 关键点有两个：
///
/// 1. **同向位移**。小信息往下走 +25vh，大信息从上方 -25vh 下来，两块朝同一个
///    方向移动，像一个纵向轮播；反向切换时双双上浮。
/// 2. **错位**。离场那块 0.3s 走完，入场那块延迟 0.3s 再花 0.5s，先腾位再进场，
///    中间不会两块都半透明糊在一起。
///
/// 与 AMLL 的差异：AMLL 靠 CSS 的 transition-delay 做错位，我们整套过渡只有
/// 一条弹簧 `t`（见 `_coverAnim`），所以改成把错位切进 `t` 的两个区间。这样
/// 信息栏和封面始终锁在同一条弹簧上，不会重新出现「各走各的曲线」的散乱感。
///
/// 区间取成相互重叠但不同起止，就能在两个方向上都自动满足「先走后进」：
///
/// ```
/// t: 0 ───────────────────────────────────────── 1
///    │        歌词模式                 封面模式   │
///    ├── 小信息离场 [0, 0.45] ──┤
///                    ├──────── 大信息入场 [0.35, 1] ────┤
/// ```
///
/// - `t` 从 0 升到 1（歌词→封面）：小信息先在 [0, 0.45] 让位，大信息后在
///   [0.35, 1] 落位。
/// - `t` 从 1 降到 0（封面→歌词）：同样两个区间反着走，于是变成大信息先让位、
///   小信息后落位。对称性是免费的，不需要按方向分支。
class AppleMusicInfoStagger {
  const AppleMusicInfoStagger._();

  /// 离场用的加速曲线（AMLL 的 `--info-timing-func-in`）。
  static const easeIn = Cubic(0.5, 0, 0.75, 0);

  /// 入场用的减速曲线（AMLL 的 `--info-timing-func-out`）。
  static const easeOut = Cubic(0.25, 1, 0.5, 1);

  /// 位移量占屏幕高度的比例，对应 CSS 里的 25vh。
  static const shiftRatio = 0.25;

  /// 小信息（歌词模式那块）让位的区间上界。
  static const smallOutEnd = 0.45;

  /// 大信息（封面模式那块）入场的区间下界。
  static const bigInStart = 0.35;

  /// 歌词模式那块信息的「在场度」：1 = 完全就位，0 = 已让位。
  static double smallPresence(double t) =>
      easeIn.transform((1.0 - (t / smallOutEnd).clamp(0.0, 1.0)).clamp(0.0, 1.0));

  /// 封面模式那块信息的「在场度」。
  static double bigPresence(double t) => easeOut.transform(
      ((t - bigInStart) / (1.0 - bigInStart)).clamp(0.0, 1.0));

  /// 歌词模式那块信息的纵向位移（像素）。让位时向**下**，故非负。
  static double smallOffsetY(double t, double screenHeight) =>
      (1.0 - smallPresence(t)) * screenHeight * shiftRatio;

  /// 封面模式那块信息的纵向位移（像素）。入场前在**上**方，故非正。
  static double bigOffsetY(double t, double screenHeight) =>
      -(1.0 - bigPresence(t)) * screenHeight * shiftRatio;
}
