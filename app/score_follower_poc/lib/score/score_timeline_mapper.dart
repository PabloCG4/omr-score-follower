import 'score_document.dart';
import 'timeline_anchor.dart';

/// Maps a fractional reference chromagram frame index onto a
/// [ScoreCursorPose] via binary search over the document's sorted
/// [TimelineAnchor]s and linear interpolation between neighbors.
/// Also provides the inverse: tap coordinates to a frame index.
final class ScoreTimelineMapper {
  const ScoreTimelineMapper();

  /// Absolute yNorm difference below which two anchors are treated as the
  /// same staff/system when grouping for reverse mapping.
  static const double systemYNormEpsilon = 1e-4;

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

    final rightIndex = lowerBoundByFrameIndex(anchors, frameIndex);
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

  /// Inverse of [mapFrameIndex] for a tap on [pageIndex] at page-normalized
  /// coordinates. Selects the closest staff/system by yNorm, then inverse-
  /// lerps along that system's xNorm-ordered anchors.
  double mapTapToFrameIndex({
    required ScoreDocument document,
    required int pageIndex,
    required double xNorm,
    required double yNorm,
  }) {
    final anchors = document.anchors;
    if (anchors.isEmpty) {
      return 0.0;
    }

    final clampedX = xNorm.clamp(0.0, 1.0);
    final clampedY = yNorm.clamp(0.0, 1.0);

    final pageAnchors = <TimelineAnchor>[
      for (final anchor in anchors)
        if (anchor.pageIndex == pageIndex) anchor,
    ];
    if (pageAnchors.isEmpty) {
      return anchors.first.frameIndex;
    }

    final systemAnchors = selectClosestSystemAnchors(pageAnchors, clampedY);
    if (systemAnchors.isEmpty) {
      return pageAnchors.first.frameIndex;
    }

    systemAnchors.sort((left, right) => left.xNorm.compareTo(right.xNorm));

    if (clampedX <= systemAnchors.first.xNorm) {
      return systemAnchors.first.frameIndex;
    }
    if (clampedX >= systemAnchors.last.xNorm) {
      return systemAnchors.last.frameIndex;
    }

    final rightIndex = lowerBoundByXNorm(systemAnchors, clampedX);
    final left = systemAnchors[rightIndex - 1];
    final right = systemAnchors[rightIndex];
    final span = right.xNorm - left.xNorm;
    final fraction = span <= 0.0 ? 0.0 : (clampedX - left.xNorm) / span;
    final frameIndex = left.frameIndex + fraction * (right.frameIndex - left.frameIndex);

    final minFrame = anchors.first.frameIndex;
    final maxFrame = anchors.last.frameIndex;
    return frameIndex.clamp(minFrame, maxFrame);
  }

  /// Groups [pageAnchors] into systems by unique yNorm (within
  /// [systemYNormEpsilon]), then returns the group whose representative
  /// yNorm is closest to [tapYNorm].
  List<TimelineAnchor> selectClosestSystemAnchors(
    List<TimelineAnchor> pageAnchors,
    double tapYNorm,
  ) {
    final systems = <List<TimelineAnchor>>[];
    for (final anchor in pageAnchors) {
      var assigned = false;
      for (final system in systems) {
        if ((system.first.yNorm - anchor.yNorm).abs() <= systemYNormEpsilon) {
          system.add(anchor);
          assigned = true;
          break;
        }
      }
      if (!assigned) {
        systems.add(<TimelineAnchor>[anchor]);
      }
    }

    List<TimelineAnchor> closest = systems.first;
    var closestDistance = (closest.first.yNorm - tapYNorm).abs();
    for (var index = 1; index < systems.length; index++) {
      final distance = (systems[index].first.yNorm - tapYNorm).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = systems[index];
      }
    }
    return List<TimelineAnchor>.from(closest);
  }

  /// Smallest index `i` such that `anchors[i].frameIndex >= frameIndex`.
  int lowerBoundByFrameIndex(List<TimelineAnchor> anchors, double frameIndex) {
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

  /// Smallest index `i` such that `anchors[i].xNorm >= xNorm`.
  /// Caller guarantees [xNorm] is strictly inside `(first.xNorm, last.xNorm)`.
  int lowerBoundByXNorm(List<TimelineAnchor> anchors, double xNorm) {
    var low = 0;
    var high = anchors.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (anchors[mid].xNorm < xNorm) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
