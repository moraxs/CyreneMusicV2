/// Fixed timing offset used by the original lyric renderer.
///
/// Parsed lyric timestamps are shifted forward by this duration. Playback
/// lookups receive the same shift, while lyric taps convert back to playback
/// time. Keep this invariant shared by every lyric presentation.
const Duration lyricIntroDelay = Duration(seconds: 4);

Duration lyricLookupPosition(Duration playbackPosition) =>
    playbackPosition + lyricIntroDelay;

Duration playbackPositionForLyric(Duration lyricPosition) {
  final position = lyricPosition - lyricIntroDelay;
  return position < Duration.zero ? Duration.zero : position;
}
