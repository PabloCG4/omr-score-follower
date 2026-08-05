import 'tracking_mode.dart';

/// Immutable configuration injected from [InitialConfigScreen] into
/// [TrackingScreen]. Expandable later with instrument / tuning fields
/// without changing the navigation seam.
final class TrackingSessionConfig {
  const TrackingSessionConfig({
    required this.trackingMode,
    this.scoreId = 'demo_four_chords',
    this.strictConfidenceThreshold = 0.35,
  });

  final TrackingMode trackingMode;
  final String scoreId;

  /// Confidence below which Strict mode freezes reference advance in C++.
  final double strictConfidenceThreshold;
}
