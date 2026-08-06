import 'tracking_mode.dart';

/// Immutable configuration injected from [InitialConfigScreen] into
/// [TrackingScreen]. Expandable later with calibration hooks without
/// changing the navigation seam.
final class TrackingSessionConfig {
  const TrackingSessionConfig({
    required this.trackingMode,
    this.scoreId = 'demo_four_chords',
    // Aligned with the ConfidenceBar amber/green boundary so Strict (and the
    // native poor-match advance cap) freeze on yellow as well as red.
    this.strictConfidenceThreshold = 0.55,
    this.instrumentId = 1,
    this.baseFrequencyHz = 440.0,
    this.transpositionSemitones = 0,
  });

  final TrackingMode trackingMode;
  final String scoreId;

  /// Confidence below which Strict mode freezes reference advance in C++.
  final double strictConfidenceThreshold;

  /// Persisted [Instrument] primary key selected on the config screen.
  final int instrumentId;

  /// Concert A reference in Hertz for the active instrument.
  final double baseFrequencyHz;

  /// Written-to-concert transposition in semitones for the active instrument.
  final int transpositionSemitones;
}
