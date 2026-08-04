/// One discrete sample of the score timeline: a reference chromagram frame
/// index mapped to a page-normalized screen position. Anchors are sorted by
/// [frameIndex] ascending inside a [ScoreDocument]; continuous frame indices
/// are resolved by binary search plus linear interpolation between neighbors.
final class TimelineAnchor {
  const TimelineAnchor({
    required this.frameIndex,
    required this.pageIndex,
    required this.xNorm,
    required this.yNorm,
    required this.measureNumber,
  });

  /// Reference chromagram frame corresponding to this visual position.
  final double frameIndex;

  /// Page this anchor lives on (must match a [ScorePage.pageIndex]).
  final int pageIndex;

  /// Horizontal position in `[0, 1]` across the page width.
  final double xNorm;

  /// Vertical position in `[0, 1]` across the page height (typically a
  /// staff/system baseline).
  final double yNorm;

  /// Measure number for diagnostics and future UI (Phase 5.3+); unused by
  /// the cursor painter itself.
  final int measureNumber;

  factory TimelineAnchor.fromJson(Map<String, dynamic> json) {
    return TimelineAnchor(
      frameIndex: (json['frameIndex'] as num).toDouble(),
      pageIndex: json['pageIndex'] as int,
      xNorm: (json['xNorm'] as num).toDouble(),
      yNorm: (json['yNorm'] as num).toDouble(),
      measureNumber: json['measureNumber'] as int,
    );
  }
}
