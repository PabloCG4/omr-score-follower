/// Operational practice mode for a tracking session.
enum TrackingMode {
  /// Halts reference advance in the native ODTW engine when confidence is
  /// below the configured threshold; cursor waits for the correct pitch.
  strict,

  /// Default Online DTW behavior: follows tempo variation and recovers.
  rubato,

  /// Cursor advances at the score's authored frame rate in Dart; native
  /// alignment still runs in the background for confidence / scoring.
  fixedTempo,
}

extension TrackingModeLabel on TrackingMode {
  String get displayLabel {
    switch (this) {
      case TrackingMode.strict:
        return 'Strict';
      case TrackingMode.rubato:
        return 'Rubato';
      case TrackingMode.fixedTempo:
        return 'Fixed Tempo';
    }
  }

  String get description {
    switch (this) {
      case TrackingMode.strict:
        return 'Cursor waits when the wrong note is played.';
      case TrackingMode.rubato:
        return 'Follows your tempo and recovers from mistakes.';
      case TrackingMode.fixedTempo:
        return 'Cursor advances at the score tempo regardless of playing.';
    }
  }
}
