import 'score_document.dart';
import 'timeline_anchor.dart';

/// Maps a fractional reference chromagram frame index onto a
/// [ScoreCursorPose] via binary search over the document's sorted
/// [TimelineAnchor]s and linear interpolation between neighbors.
final class ScoreTimelineMapper {
  const ScoreTimelineMapper();

  ScoreCursorPose mapFrameIndex(ScoreDocument document, double frameIndex) {
    final anchors = document.anchors;
    if (anchors.isEmpty) {
      return ScoreCursorPose.origin;
    }

    if (frameIndex <= anchors.first.frameIndex) {
      final first = anchors.first;
      return ScoreCursorPose(
        pageIndex: first.pageIndex,
        xNorm: first.xNorm,
        yNorm: first.yNorm,
      );
    }
    if (frameIndex >= anchors.last.frameIndex) {
      final last = anchors.last;
      return ScoreCursorPose(
        pageIndex: last.pageIndex,
        xNorm: last.xNorm,
        yNorm: last.yNorm,
      );
    }

    final rightIndex = _lowerBound(anchors, frameIndex);
    final left = anchors[rightIndex - 1];
    final right = anchors[rightIndex];

    // Cross-page segments: never draw a cursor mid-air between pages.
    // Snap onto the destination page and interpolate only within that page's
    // arrival segment (from the destination page's first coordinate).
    if (left.pageIndex != right.pageIndex) {
      return ScoreCursorPose(
        pageIndex: right.pageIndex,
        xNorm: right.xNorm,
        yNorm: right.yNorm,
      );
    }

    final span = right.frameIndex - left.frameIndex;
    final fraction = span <= 0.0 ? 0.0 : (frameIndex - left.frameIndex) / span;
    return ScoreCursorPose(
      pageIndex: left.pageIndex,
      xNorm: left.xNorm + (right.xNorm - left.xNorm) * fraction,
      yNorm: left.yNorm + (right.yNorm - left.yNorm) * fraction,
    );
  }

  /// Smallest index `i` such that `anchors[i].frameIndex >= frameIndex`.
  /// Caller guarantees `frameIndex` is strictly inside `(first, last)`.
  int _lowerBound(List<TimelineAnchor> anchors, double frameIndex) {
    var low = 0;
    var high = anchors.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (anchors[mid].frameIndex < frameIndex) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
