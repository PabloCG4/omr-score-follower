import 'package:score_follower_bridge/score_follower_bridge.dart';

import 'score_document.dart';

/// Guards FFI injection: session id match and non-empty reference chroma.
///
/// Used by [FollowingSessionController] before [ScoreFollowerEngine.loadReferenceChromagram]
/// so DTW never runs against an unloaded or mismatched reference.
void assertTrackingDocumentReady(
  ScoreDocument document, {
  required String expectedScoreId,
}) {
  if (document.scoreId != expectedScoreId) {
    throw StateError(
      'Loaded score id "${document.scoreId}" does not match the session '
      'score id "$expectedScoreId".',
    );
  }
  if (document.referenceFrameCount <= 0) {
    throw StateError(
      'Score "${document.scoreId}" has an empty reference chromagram '
      '(referenceFrameCount=${document.referenceFrameCount}).',
    );
  }
  final expectedLength =
      document.referenceFrameCount * scoreFollowerPitchClassCount;
  if (document.referenceChromagramRowMajor.length != expectedLength) {
    throw StateError(
      'Score "${document.scoreId}" chromagram length '
      '(${document.referenceChromagramRowMajor.length}) must equal '
      'referenceFrameCount * $scoreFollowerPitchClassCount ($expectedLength).',
    );
  }
}
