import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_follower_poc/score/score_document.dart';
import 'package:score_follower_poc/score/score_page.dart';
import 'package:score_follower_poc/score/score_timeline_mapper.dart';
import 'package:score_follower_poc/score/timeline_anchor.dart';

void main() {
  const mapper = ScoreTimelineMapper();

  test('empty middle page bridges frames instead of returning frame 0', () {
    final document = buildSparseThreePageDocument();

    final frameIndex = mapper.mapTapToFrameIndex(
      document: document,
      pageIndex: 1,
      xNorm: 0.5,
      yNorm: 0.4,
    );

    expect(frameIndex, greaterThan(0.0));
    expect(frameIndex, lessThan(document.anchors.last.frameIndex));
    expect(frameIndex, closeTo(50.0, 1e-6));
  });

  test('single-anchor systems still interpolate via page x-order', () {
    final document = ScoreDocument(
      scoreId: 'single-anchor-systems',
      displayTitle: 'Single Anchor Systems',
      sampleRateHz: 22050.0,
      hopLengthSamples: 512,
      pages: const [
        ScorePage(pageIndex: 0, assetPath: '', aspectRatio: 16 / 9),
      ],
      anchors: const [
        TimelineAnchor(
          frameIndex: 0.0,
          pageIndex: 0,
          xNorm: 0.10,
          yNorm: 0.301,
          measureNumber: 1,
        ),
        TimelineAnchor(
          frameIndex: 40.0,
          pageIndex: 0,
          xNorm: 0.40,
          yNorm: 0.302,
          measureNumber: 2,
        ),
        TimelineAnchor(
          frameIndex: 80.0,
          pageIndex: 0,
          xNorm: 0.70,
          yNorm: 0.299,
          measureNumber: 3,
        ),
      ],
      referenceChromagramRowMajor: Float32List(3 * 12),
      referenceFrameCount: 3,
    );

    final frameIndex = mapper.mapTapToFrameIndex(
      document: document,
      pageIndex: 0,
      xNorm: 0.55,
      yNorm: 0.30,
    );

    expect(frameIndex, greaterThan(40.0));
    expect(frameIndex, lessThan(80.0));
  });

  test('tap on page 1 with page anchors keeps pose on page 1', () {
    final document = buildDenseTwoPageDocument();

    final frameIndex = mapper.mapTapToFrameIndex(
      document: document,
      pageIndex: 1,
      xNorm: 0.40,
      yNorm: 0.55,
    );
    final pose = mapper.mapFrameIndex(document, frameIndex);

    expect(pose.pageIndex, 1);
    expect(frameIndex, greaterThanOrEqualTo(20.0));
  });
}

ScoreDocument buildSparseThreePageDocument() {
  return ScoreDocument(
    scoreId: 'sparse-three-page',
    displayTitle: 'Sparse Three Page',
    sampleRateHz: 22050.0,
    hopLengthSamples: 512,
    pages: const [
      ScorePage(pageIndex: 0, assetPath: '', aspectRatio: 16 / 9),
      ScorePage(pageIndex: 1, assetPath: '', aspectRatio: 16 / 9),
      ScorePage(pageIndex: 2, assetPath: '', aspectRatio: 16 / 9),
    ],
    anchors: const [
      TimelineAnchor(
        frameIndex: 0.0,
        pageIndex: 0,
        xNorm: 0.1,
        yNorm: 0.4,
        measureNumber: 1,
      ),
      TimelineAnchor(
        frameIndex: 100.0,
        pageIndex: 2,
        xNorm: 0.9,
        yNorm: 0.4,
        measureNumber: 2,
      ),
    ],
    referenceChromagramRowMajor: Float32List(2 * 12),
    referenceFrameCount: 2,
  );
}

ScoreDocument buildDenseTwoPageDocument() {
  return ScoreDocument(
    scoreId: 'dense-two-page',
    displayTitle: 'Dense Two Page',
    sampleRateHz: 22050.0,
    hopLengthSamples: 512,
    pages: const [
      ScorePage(pageIndex: 0, assetPath: '', aspectRatio: 16 / 9),
      ScorePage(pageIndex: 1, assetPath: '', aspectRatio: 16 / 9),
    ],
    anchors: const [
      TimelineAnchor(
        frameIndex: 0.0,
        pageIndex: 0,
        xNorm: 0.1,
        yNorm: 0.3,
        measureNumber: 1,
      ),
      TimelineAnchor(
        frameIndex: 10.0,
        pageIndex: 0,
        xNorm: 0.6,
        yNorm: 0.3,
        measureNumber: 2,
      ),
      TimelineAnchor(
        frameIndex: 20.0,
        pageIndex: 1,
        xNorm: 0.2,
        yNorm: 0.55,
        measureNumber: 3,
      ),
      TimelineAnchor(
        frameIndex: 40.0,
        pageIndex: 1,
        xNorm: 0.7,
        yNorm: 0.55,
        measureNumber: 4,
      ),
    ],
    referenceChromagramRowMajor: Float32List(4 * 12),
    referenceFrameCount: 4,
  );
}
