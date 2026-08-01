/// CJK 判定。
///
/// JS 侧用的是 `/^[\p{Unified_Ideograph}ࠀ-鿼]+$/u`。Dart 的正则不支持
/// `\p{...}` Unicode 属性转义，因此改为等价的码点区间判断。
///
/// `Unified_Ideograph` 覆盖 CJK 统一表意文字及其扩展区，
/// `ࠀ-鿼` 是原实现额外并入的一段（会顺带涵盖日文假名等），
/// 这里保持一致，不做收窄，以免改变分词与强调判定的行为。
library;

const List<List<int>> _cjkRanges = <List<int>>[
  // 原实现显式并入的区间：ࠀ-鿼
  <int>[0x0800, 0x9FFC],
  // Unified_Ideograph 中超出上面范围的部分
  <int>[0x9FFD, 0x9FFF], // CJK 统一表意文字尾部（Unicode 13+ 扩展到 9FFF）
  <int>[0x3400, 0x4DBF], // 扩展 A（已被 0800-9FFC 覆盖，保留以示完整）
  <int>[0xFA0E, 0xFA0F],
  <int>[0xFA11, 0xFA11],
  <int>[0xFA13, 0xFA14],
  <int>[0xFA1F, 0xFA1F],
  <int>[0xFA21, 0xFA21],
  <int>[0xFA23, 0xFA24],
  <int>[0xFA27, 0xFA29],
  <int>[0x20000, 0x2A6DF], // 扩展 B
  <int>[0x2A700, 0x2B739], // 扩展 C
  <int>[0x2B740, 0x2B81D], // 扩展 D
  <int>[0x2B820, 0x2CEA1], // 扩展 E
  <int>[0x2CEB0, 0x2EBE0], // 扩展 F
  <int>[0x2EBF0, 0x2EE5D], // 扩展 I
  <int>[0x30000, 0x3134A], // 扩展 G
  <int>[0x31350, 0x323AF], // 扩展 H
];

bool _isCjkRune(int rune) {
  for (final range in _cjkRanges) {
    if (rune >= range[0] && rune <= range[1]) return true;
  }
  return false;
}

/// 字符串是否**全部**由 CJK 字符组成（空串返回 false，与 JS 侧 `+` 量词一致）。
bool isCJK(String text) {
  if (text.isEmpty) return false;
  for (final rune in text.runes) {
    if (!_isCjkRune(rune)) return false;
  }
  return true;
}
