import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_follower_bridge/score_follower_bridge.dart';
import 'package:score_follower_poc/score/score_document.dart';
import 'package:score_follower_poc/score/score_page.dart';
import 'package:score_follower_poc/score/timeline_anchor.dart';
import 'package:score_follower_poc/score/tracking_document_guards.dart';

void main() {
  test('assertTrackingDocumentReady accepts matching non-empty chromagram', () {
    final document = buildReadyDocument(scoreId: 'persisted:1', frameCount: 2);
    expect(
      () => assertTrackingDocumentReady(
        document,
        expectedScoreId: 'persisted:1',
      ),
      returnsNormally,
    );
  });

  test('assertTrackingDocumentReady rejects score id mismatch', () {
    final document = buildReadyDocument(scoreId: 'persisted:2', frameCount: 2);
    expect(
      () => assertTrackingDocumentReady(
        document,
        expectedScoreId: 'persisted:1',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('assertTrackingDocumentReady rejects empty referenceFrameCount', () {
    final document = ScoreDocument(
      scoreId: 'persisted:1',
      displayTitle: 'Empty',
      sampleRateHz: 22050.0,
      hopLengthSamples: 512,
      pages: const [
        ScorePage(pageIndex: 0, assetPath: '', aspectRatio: 1.0),
      ],
      anchors: const [
        TimelineAnchor(
          frameIndex: 0.0,
          pageIndex: 0,
          xNorm: 0.1,
          yNorm: 0.2,
          measureNumber: 1,
        ),
      ],
      referenceChromagramRowMajor: Float32List(0),
      referenceFrameCount: 0,
    );
    expect(
      () => assertTrackingDocumentReady(
        document,
        expectedScoreId: 'persisted:1',
      ),
      throwsA(isA<StateError>()),
    );
  });
}

ScoreDocument buildReadyDocument({
  required String scoreId,
  required int frameCount,
}) {
  return ScoreDocument(
    scoreId: scoreId,
    displayTitle: 'Ready',
    sampleRateHz: 22050.0,
    hopLengthSamples: 512,
    pages: const [
      ScorePage(pageIndex: 0, assetPath: '', aspectRatio: 1.0),
    ],
    anchors: const [
      TimelineAnchor(
        frameIndex: 0.0,
        pageIndex: 0,
        xNorm: 0.1,
        yNorm: 0.2,
        measureNumber: 1,
      ),
      TimelineAnchor(
        frameIndex: 1.0,
        pageIndex: 0,
        xNorm: 0.5,
        yNorm: 0.2,
        measureNumber: 2,
      ),
    ],
    referenceChromagramRowMajor:
        Float32List(frameCount * scoreFollowerPitchClassCount),
    referenceFrameCount: frameCount,
  );
}
