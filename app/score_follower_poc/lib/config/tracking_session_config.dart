import 'tracking_mode.dart';

/// Immutable configuration injected from [InitialConfigScreen] into
/// [TrackingScreen]. Expandable later with instrument / tuning fields
/// without changing the navigation seam.
final class TrackingSessionConfig {
  const TrackingSessionConfig({
    required this.trackingMode,
    this.scoreId = 'demo_four_chords',
    // Aligned with the ConfidenceBar amber/green boundary so Strict (and the
    // native poor-match advance cap) freeze on yellow as well as red.
    this.strictConfidenceThreshold = 0.55,
  });

  final TrackingMode trackingMode;
  final String scoreId;

  /// Confidence below which Strict mode freezes reference advance in C++.
  final double strictConfidenceThreshold;
}
