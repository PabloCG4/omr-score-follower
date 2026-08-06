/// Domain entity for a user-configured performance instrument.
final class Instrument {
  const Instrument({
    required this.id,
    required this.name,
    required this.baseFrequencyHz,
    required this.transpositionSemitones,
  });

  final int id;
  final String name;

  /// Concert pitch reference A4 in Hertz (typically 440).
  final double baseFrequencyHz;

  /// Written-pitch to concert-pitch offset in semitones
  /// (e.g. Bb clarinet is -2).
  final int transpositionSemitones;

  Instrument copyWith({
    int? id,
    String? name,
    double? baseFrequencyHz,
    int? transpositionSemitones,
  }) {
    return Instrument(
      id: id ?? this.id,
      name: name ?? this.name,
      baseFrequencyHz: baseFrequencyHz ?? this.baseFrequencyHz,
      transpositionSemitones: transpositionSemitones ?? this.transpositionSemitones,
    );
  }
}
