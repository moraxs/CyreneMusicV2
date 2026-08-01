class MusicApiConfiguration {
  const MusicApiConfiguration({
    this.baseUrl = 'https://music.nekofun.top',
    this.audioQuality = 'exhigh',
  });

  final String baseUrl;
  final String audioQuality;

  Uri endpoint(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');
}
