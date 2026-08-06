import 'dart:math' as math;

/// Pitch-class labels in chromatic order (C = 0).
const List<String> chromaticNoteNames = <String>[
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Concert A4 reference used when splitting fractional offset into A4 Hz.
const double concertA4FrequencyHz = 440.0;

/// Result of mapping a detected F0 against a user-selected reference note.
final class AcousticTuningMeasurement {
  const AcousticTuningMeasurement({
    required this.baseFrequencyHz,
    required this.transpositionSemitones,
    required this.detectedFrequencyHz,
    required this.expectedFrequencyHz,
    required this.offsetSemitones,
  });

  /// Instrument A4 after removing whole-semitone transposition.
  final double baseFrequencyHz;

  /// Whole-semitone written-to-concert transposition.
  final int transpositionSemitones;

  /// Measured fundamental frequency.
  final double detectedFrequencyHz;

  /// Expected frequency of the selected reference note at A440.
  final double expectedFrequencyHz;

  /// Continuous offset in semitones: `12 * log2(f0 / fExpected)`.
  final double offsetSemitones;
}

/// MIDI note number for [pitchClass] (0=C … 11=B) in [octave] (scientific).
int midiNoteNumber({required int pitchClass, required int octave}) {
  if (pitchClass < 0 || pitchClass > 11) {
    throw ArgumentError.value(pitchClass, 'pitchClass', 'Must be in 0..11.');
  }
  return (octave + 1) * 12 + pitchClass;
}

/// Equal-temperament frequency of a MIDI note at concert A4 = 440 Hz.
double frequencyHzForMidiNote(int midiNoteNumber) {
  return concertA4FrequencyHz *
      math.pow(2.0, (midiNoteNumber - 69) / 12.0).toDouble();
}

/// Expected frequency of the wizard reference note at A440.
double expectedFrequencyHzForReferenceNote({
  required int pitchClass,
  required int octave,
}) {
  return frequencyHzForMidiNote(
    midiNoteNumber(pitchClass: pitchClass, octave: octave),
  );
}

/// Splits a detected F0 into integer transposition + fine A4 Hz, relative to
/// the selected reference note (defaults to C4 when pitchClass=0, octave=4).
AcousticTuningMeasurement mapDetectedFrequencyToTuning({
  required double detectedFrequencyHz,
  required int referencePitchClass,
  required int referenceOctave,
}) {
  if (!(detectedFrequencyHz > 0.0) || !detectedFrequencyHz.isFinite) {
    throw ArgumentError.value(
      detectedFrequencyHz,
      'detectedFrequencyHz',
      'Must be a positive finite frequency.',
    );
  }

  final expectedFrequencyHz = expectedFrequencyHzForReferenceNote(
    pitchClass: referencePitchClass,
    octave: referenceOctave,
  );
  final offsetSemitones =
      12.0 * (math.log(detectedFrequencyHz / expectedFrequencyHz) / math.ln2);
  final transpositionSemitones = offsetSemitones.round();
  final fractionalSemitones = offsetSemitones - transpositionSemitones;
  final baseFrequencyHz = concertA4FrequencyHz *
      math.pow(2.0, fractionalSemitones / 12.0).toDouble();

  return AcousticTuningMeasurement(
    baseFrequencyHz: baseFrequencyHz,
    transpositionSemitones: transpositionSemitones,
    detectedFrequencyHz: detectedFrequencyHz,
    expectedFrequencyHz: expectedFrequencyHz,
    offsetSemitones: offsetSemitones,
  );
}

/// Nearest note name + cents deviation for a live frequency readout.
({String noteName, int octave, double cents}) nearestNoteLabel(
  double frequencyHz,
) {
  final midiContinuous =
      69.0 + 12.0 * (math.log(frequencyHz / concertA4FrequencyHz) / math.ln2);
  final midiRounded = midiContinuous.round();
  final pitchClass = ((midiRounded % 12) + 12) % 12;
  final octave = (midiRounded ~/ 12) - 1;
  final cents = (midiContinuous - midiRounded) * 100.0;
  return (
    noteName: chromaticNoteNames[pitchClass],
    octave: octave,
    cents: cents,
  );
}
