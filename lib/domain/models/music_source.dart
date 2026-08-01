enum MusicSource {
  netease,
  qq,
  kugou,
  kuwo,
  apple,
  spotify,
  qishui,
  local;

  String get wireName => name;

  static MusicSource fromWireName(String value) =>
      MusicSource.values.firstWhere(
        (source) => source.wireName == value,
        orElse: () => MusicSource.netease,
      );
}
