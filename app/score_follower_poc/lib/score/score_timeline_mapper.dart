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
  ///
  /// 3% of page height tolerates OMR float noise so same-staff anchors
  /// group for horizontal interpolation.
  static const double systemYNormEpsilon = 0.03;

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
      return bridgeFrameAcrossEmptyPage(
        anchors: anchors,
        pageIndex: pageIndex,
        xNorm: clampedX,
      );
    }

    final systemAnchors = selectClosestSystemAnchors(pageAnchors, clampedY);
    final List<TimelineAnchor> lerpAnchors;
    if (systemAnchors.length >= 2) {
      lerpAnchors = List<TimelineAnchor>.from(systemAnchors)
        ..sort((left, right) => left.xNorm.compareTo(right.xNorm));
    } else {
      // Single-anchor systems cannot interpolate in x; use page reading order.
      lerpAnchors = List<TimelineAnchor>.from(pageAnchors)
        ..sort((left, right) => left.xNorm.compareTo(right.xNorm));
    }

    return interpolateFrameByXNorm(
      lerpAnchors: lerpAnchors,
      xNorm: clampedX,
      documentAnchors: anchors,
    );
  }

  /// When [pageIndex] has no anchors, lerp between the previous page's last
  /// and the next page's first anchor by [xNorm].
  double bridgeFrameAcrossEmptyPage({
    required List<TimelineAnchor> anchors,
    required int pageIndex,
    required double xNorm,
  }) {
    TimelineAnchor? previous;
    TimelineAnchor? following;
    for (final anchor in anchors) {
      if (anchor.pageIndex < pageIndex) {
        previous = anchor;
      } else if (anchor.pageIndex > pageIndex) {
        following = anchor;
        break;
      }
    }

    if (previous != null && following != null) {
      final spanX = following.xNorm - previous.xNorm;
      final fraction = spanX.abs() <= 1e-9
          ? xNorm
          : ((xNorm - previous.xNorm) / spanX).clamp(0.0, 1.0);
      final frameIndex = previous.frameIndex +
          fraction * (following.frameIndex - previous.frameIndex);
      return frameIndex.clamp(anchors.first.frameIndex, anchors.last.frameIndex);
    }
    if (following != null) {
      return following.frameIndex;
    }
    if (previous != null) {
      return previous.frameIndex;
    }
    return anchors.first.frameIndex;
  }

  /// Inverse-lerps [xNorm] along [lerpAnchors] sorted by xNorm.
  double interpolateFrameByXNorm({
    required List<TimelineAnchor> lerpAnchors,
    required double xNorm,
    required List<TimelineAnchor> documentAnchors,
  }) {
    if (lerpAnchors.isEmpty) {
      return documentAnchors.first.frameIndex;
    }
    if (lerpAnchors.length == 1) {
      return lerpAnchors.first.frameIndex;
    }

    if (xNorm <= lerpAnchors.first.xNorm) {
      return lerpAnchors.first.frameIndex;
    }
    if (xNorm >= lerpAnchors.last.xNorm) {
      return lerpAnchors.last.frameIndex;
    }

    final rightIndex = lowerBoundByXNorm(lerpAnchors, xNorm);
    final left = lerpAnchors[rightIndex - 1];
    final right = lerpAnchors[rightIndex];
    final span = right.xNorm - left.xNorm;
    final fraction = span <= 0.0 ? 0.0 : (xNorm - left.xNorm) / span;
    final frameIndex =
        left.frameIndex + fraction * (right.frameIndex - left.frameIndex);

    final minFrame = documentAnchors.first.frameIndex;
    final maxFrame = documentAnchors.last.frameIndex;
    return frameIndex.clamp(minFrame, maxFrame);
  }

  /// Groups [pageAnchors] into systems by unique yNorm (within
  /// [systemYNormEpsilon]), then returns the group whose representative
  /// yNorm is closest to [tapYNorm].
  List<TimelineAnchor> selectClosestSystemAnchors(
    List<TimelineAnchor> pageAnchors,
    double tapYNorm,
  ) {
    if (pageAnchors.isEmpty) {
      return const <TimelineAnchor>[];
    }

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
