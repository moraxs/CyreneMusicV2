/// 歌词展示样式（对应 Next.js LyricDisplayStyle）。
enum LyricDisplayStyle {
  scroll('scroll'),
  roulette('roulette'),
  singleLine('singleLine');

  const LyricDisplayStyle(this.wireName);

  final String wireName;

  static LyricDisplayStyle fromWireName(String value) =>
      LyricDisplayStyle.values.firstWhere(
        (style) => style.wireName == value,
        orElse: () => LyricDisplayStyle.scroll,
      );
}

/// 单行歌词入场动画（对应 Next.js SingleLineAnimation）。
enum SingleLineAnimation {
  slideUp('slideUp'),
  fade('fade'),
  zoom('zoom'),
  blur('blur');

  const SingleLineAnimation(this.wireName);

  final String wireName;

  static SingleLineAnimation fromWireName(String value) =>
      SingleLineAnimation.values.firstWhere(
        (animation) => animation.wireName == value,
        orElse: () => SingleLineAnimation.slideUp,
      );
}

/// 播放器背景类型（对应 Next.js PlayerBgType）。
enum PlayerBgType {
  webgl('webgl'),
  image('image'),
  wallpaper('wallpaper');

  const PlayerBgType(this.wireName);

  final String wireName;

  static PlayerBgType fromWireName(String value) =>
      PlayerBgType.values.firstWhere(
        (type) => type.wireName == value,
        orElse: () => PlayerBgType.webgl,
      );
}
