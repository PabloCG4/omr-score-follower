import '../config/tracking_mode.dart';

/// Persisted user session preferences restored across app launches.
final class UserPreferences {
  const UserPreferences({
    required this.trackingMode,
    required this.activeInstrumentId,
    this.strictConfidenceThreshold = 0.55,
    this.scoreId = 'demo_four_chords',
  });

  final TrackingMode trackingMode;
  final int activeInstrumentId;
  final double strictConfidenceThreshold;
  final String scoreId;

  UserPreferences copyWith({
    TrackingMode? trackingMode,
    int? activeInstrumentId,
    double? strictConfidenceThreshold,
    String? scoreId,
  }) {
    return UserPreferences(
      trackingMode: trackingMode ?? this.trackingMode,
      activeInstrumentId: activeInstrumentId ?? this.activeInstrumentId,
      strictConfidenceThreshold:
          strictConfidenceThreshold ?? this.strictConfidenceThreshold,
      scoreId: scoreId ?? this.scoreId,
    );
  }
}
