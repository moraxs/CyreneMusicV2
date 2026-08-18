class SonnetStaffNote {
  const SonnetStaffNote({
    required this.pitch,
    required this.staffStep,
    required this.beats,
    this.accidental,
  });

  final String pitch; // 'C#5' | 'D5' | 'E5' | 'F5'
  final int staffStep;
  final double beats;
  final String? accidental; // 'sharp'
}

const List<SonnetStaffNote> laFoliaStaffNotes = [
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 1.0),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 1.5),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 0.5),
  SonnetStaffNote(pitch: 'C#5', staffStep: 5, beats: 1.0, accidental: 'sharp'),
  SonnetStaffNote(pitch: 'C#5', staffStep: 5, beats: 1.0, accidental: 'sharp'),
  SonnetStaffNote(pitch: 'C#5', staffStep: 5, beats: 1.0, accidental: 'sharp'),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 1.0),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 1.5),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 0.5),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 1.0),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 1.0),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 1.0),
  SonnetStaffNote(pitch: 'F5', staffStep: 8, beats: 1.0),
  SonnetStaffNote(pitch: 'F5', staffStep: 8, beats: 1.5),
  SonnetStaffNote(pitch: 'F5', staffStep: 8, beats: 0.5),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 1.0),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 1.0),
  SonnetStaffNote(pitch: 'E5', staffStep: 7, beats: 1.0),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 1.0),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 1.5),
  SonnetStaffNote(pitch: 'C#5', staffStep: 5, beats: 0.5, accidental: 'sharp'),
  SonnetStaffNote(pitch: 'D5', staffStep: 6, beats: 3.0),
];

const double laFoliaTotalBeats = 24.0;
const double laFoliaCycleSeconds = 8.0;
