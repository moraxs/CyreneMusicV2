/// Deterministic 32-bit integer pseudo-random hash functions matching Sonnet TS.
int hashSonnetSeed(String value) {
  var hash = 2166136261;
  for (var index = 0; index < value.length; index++) {
    hash ^= value.codeUnitAt(index);
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash;
}

/// Mixes a numeric seed with a salt to keep subsystems decorrelated.
int mixSonnetSeed(int seed, int salt) {
  final s = seed & 0xFFFFFFFF;
  return ((s ^ salt) * 2654435761) & 0xFFFFFFFF;
}

/// Deterministic 0..1 jitter per element index; seek-safe and rebuild-stable.
double sonnetHash01(int seed, int index, int salt) {
  final mixed = mixSonnetSeed(seed + ((index + 1) * 97), salt);
  return mixed / 4294967296.0;
}
