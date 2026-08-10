import 'dart:typed_data';

import '../omr/omr_structural_document.dart';
import 'score_document.dart';
import 'score_page.dart';
import 'timeline_anchor.dart';

/// Maps a validated [OmrStructuralDocument] onto the runtime [ScoreDocument]
/// used by [ScoreTimelineMapper] and [ScoreFollowerEngine.loadReferenceChromagram].
///
/// Anchors and page aspect ratios remain Dart-owned. Only the reference
/// chromagram floats cross the existing FFI boundary; note events are left on
/// the structural model and are not transferred to C++.
ScoreDocument omrStructuralToScoreDocument({
  required OmrStructuralDocument structural,
  required String scoreId,
}) {
  structural.validate();

  final pages = <ScorePage>[
    for (final page in structural.pages)
      ScorePage(
        pageIndex: page.pageIndex,
        // Practice rendering uses the PDF visual path; asset path is unused.
        assetPath: '',
        aspectRatio: page.aspectRatio,
      ),
  ];

  final anchors = <TimelineAnchor>[
    for (final anchor in structural.anchors)
      TimelineAnchor(
        frameIndex: anchor.frameIndex,
        pageIndex: anchor.pageIndex,
        xNorm: anchor.xNorm,
        yNorm: anchor.yNorm,
        measureNumber: anchor.measureNumber,
      ),
  ];

  final document = ScoreDocument(
    scoreId: scoreId,
    displayTitle: structural.displayTitle,
    sampleRateHz: structural.sampleRateHz,
    hopLengthSamples: structural.hopLengthSamples,
    pages: List<ScorePage>.unmodifiable(pages),
    anchors: List<TimelineAnchor>.unmodifiable(anchors),
    referenceChromagramRowMajor: Float32List.fromList(
      structural.referenceChromagram.decodedRowMajor,
    ),
    referenceFrameCount: structural.referenceFrameCount,
  );
  document.validate();
  return document;
}
