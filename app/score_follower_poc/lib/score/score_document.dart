import 'dart:typed_data';

import 'package:score_follower_bridge/score_follower_bridge.dart';

import 'score_page.dart';
import 'timeline_anchor.dart';

/// Immutable, asset-backed description of a score the follower can track:
/// visual pages, a sorted timeline map from reference-frame index to
/// page-normalized coordinates, and the reference chromagram the DSP engine
/// aligns against.
final class ScoreDocument {
  const ScoreDocument({
    required this.scoreId,
    required this.sampleRateHz,
    required this.hopLengthSamples,
    required this.pages,
    required this.anchors,
    required this.referenceChromagramRowMajor,
    required this.referenceFrameCount,
  });

  final String scoreId;
  final double sampleRateHz;
  final int hopLengthSamples;
  final List<ScorePage> pages;

  /// Sorted by [TimelineAnchor.frameIndex] ascending. Required by
  /// [ScoreTimelineMapper].
  final List<TimelineAnchor> anchors;

  /// Flat row-major pitch-class energies,
  /// `referenceFrameCount * scoreFollowerPitchClassCount` floats.
  final Float32List referenceChromagramRowMajor;

  final int referenceFrameCount;

  /// Converts the packed float32 chromagram into the [List]<[double]> form
  /// expected by [ScoreFollowerEngine.loadReferenceChromagram].
  List<double> get referenceChromagramAsDoubles {
    return List<double>.generate(
      referenceChromagramRowMajor.length,
      (index) => referenceChromagramRowMajor[index].toDouble(),
      growable: false,
    );
  }

  /// Sanity-checks invariants the loader and mapper rely on. Throws
  /// [ArgumentError] on violation.
  void validate() {
    if (pages.isEmpty) {
      throw ArgumentError('ScoreDocument "$scoreId" has no pages.');
    }
    if (anchors.isEmpty) {
      throw ArgumentError('ScoreDocument "$scoreId" has no timeline anchors.');
    }
    final expectedLength = referenceFrameCount * scoreFollowerPitchClassCount;
    if (referenceChromagramRowMajor.length != expectedLength) {
      throw ArgumentError(
        'ScoreDocument "$scoreId" chromagram length '
        '(${referenceChromagramRowMajor.length}) must equal '
        'referenceFrameCount * $scoreFollowerPitchClassCount ($expectedLength).',
      );
    }
    for (var index = 1; index < anchors.length; index++) {
      if (anchors[index].frameIndex < anchors[index - 1].frameIndex) {
        throw ArgumentError(
          'ScoreDocument "$scoreId" timeline anchors must be sorted by '
          'frameIndex ascending (violation at index $index).',
        );
      }
    }
  }
}

/// Page-normalized cursor pose produced by [ScoreTimelineMapper].
final class ScoreCursorPose {
  const ScoreCursorPose({
    required this.pageIndex,
    required this.xNorm,
    required this.yNorm,
  });

  final int pageIndex;
  final double xNorm;
  final double yNorm;

  static const origin = ScoreCursorPose(pageIndex: 0, xNorm: 0.0, yNorm: 0.0);

  @override
  bool operator ==(Object other) {
    return other is ScoreCursorPose &&
        other.pageIndex == pageIndex &&
        other.xNorm == xNorm &&
        other.yNorm == yNorm;
  }

  @override
  int get hashCode => Object.hash(pageIndex, xNorm, yNorm);
}
