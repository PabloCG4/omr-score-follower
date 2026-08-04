import 'package:score_follower_bridge/score_follower_bridge.dart';

/// Immutable snapshot of a DSP alignment poll, plus the wall-clock time it
/// was taken. Published through a [ValueNotifier] at ~30 Hz; only diagnostic
/// UI (and [CursorDisplayModel] via the session controller) should listen.
final class AlignmentSnapshot {
  const AlignmentSnapshot({
    required this.position,
    required this.polledAt,
  });

  final ScoreFollowerAlignmentPosition position;
  final DateTime polledAt;

  static final zero = AlignmentSnapshot(
    position: ScoreFollowerAlignmentPosition.zero,
    polledAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  double get referenceFrameIndex => position.referenceFrameIndex;
  double get alignmentConfidence => position.alignmentConfidence;
  double get cumulativeDistortionCost => position.cumulativeDistortionCost;
}
