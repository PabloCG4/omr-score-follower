import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:score_follower_poc/omr/omr_structural_document.dart';
import 'package:score_follower_poc/score/omr_structural_to_score_document.dart';
import 'package:score_follower_poc/score/score_timeline_mapper.dart';

void main() {
  test('omrStructuralToScoreDocument maps pages, anchors, and chromagram', () {
    final structural = buildMultiPageStructuralDocument();
    final scoreDocument = omrStructuralToScoreDocument(
      structural: structural,
      scoreId: 'persisted:7',
    );

    expect(scoreDocument.scoreId, 'persisted:7');
    expect(scoreDocument.displayTitle, 'Two Page Fixture');
    expect(scoreDocument.sampleRateHz, 22050.0);
    expect(scoreDocument.hopLengthSamples, 512);
    expect(scoreDocument.referenceFrameCount, 4);
    expect(scoreDocument.pages, hasLength(2));
    expect(scoreDocument.pages[0].aspectRatio, closeTo(960 / 540, 1e-9));
    expect(scoreDocument.pages[1].aspectRatio, closeTo(960 / 540, 1e-9));
    expect(scoreDocument.pages[0].assetPath, isEmpty);
    expect(scoreDocument.anchors, hasLength(4));
    expect(scoreDocument.anchors[2].pageIndex, 1);
    expect(scoreDocument.anchors[2].yNorm, 0.72);
    expect(
      scoreDocument.referenceChromagramRowMajor.length,
      4 * omrPitchClassCount,
    );
    expect(scoreDocument.referenceChromagramRowMajor[0], 1.0);
  });

  test(
    'tap-seek on page 1 with multi-page anchors does not map back to page 0',
    () {
      final scoreDocument = omrStructuralToScoreDocument(
        structural: buildMultiPageStructuralDocument(),
        scoreId: 'persisted:7',
      );
      const mapper = ScoreTimelineMapper();

      final frameIndex = mapper.mapTapToFrameIndex(
        document: scoreDocument,
        pageIndex: 1,
        xNorm: 0.40,
        yNorm: 0.72,
      );
      final pose = mapper.mapFrameIndex(scoreDocument, frameIndex);

      expect(frameIndex, greaterThanOrEqualTo(2.0));
      expect(pose.pageIndex, 1);
      expect(pose.yNorm, closeTo(0.72, 1e-9));
    },
  );
}

OmrStructuralDocument buildMultiPageStructuralDocument() {
  const frameCount = 4;
  final energies = Float32List(frameCount * omrPitchClassCount);
  energies[0] = 1.0;
  energies[omrPitchClassCount] = 0.9;
  energies[2 * omrPitchClassCount] = 0.8;
  energies[3 * omrPitchClassCount] = 0.7;

  final rawBytes = Uint8List(energies.length * 4);
  final byteData = ByteData.sublistView(rawBytes);
  for (var floatIndex = 0; floatIndex < energies.length; floatIndex++) {
    byteData.setFloat32(floatIndex * 4, energies[floatIndex], Endian.little);
  }

  return OmrStructuralDocument.fromJson(<String, dynamic>{
    'schemaVersion': omrStructuralDocumentSchemaVersion,
    'documentId': 'multi-page-fixture',
    'displayTitle': 'Two Page Fixture',
    'sampleRateHz': 22050.0,
    'hopLengthSamples': 512,
    'referenceFrameCount': frameCount,
    'pages': [
      <String, dynamic>{
        'pageIndex': 0,
        'widthPx': 960,
        'heightPx': 540,
      },
      <String, dynamic>{
        'pageIndex': 1,
        'widthPx': 960,
        'heightPx': 540,
      },
    ],
    'anchors': [
      <String, dynamic>{
        'frameIndex': 0.0,
        'pageIndex': 0,
        'xNorm': 0.10,
        'yNorm': 0.30,
        'measureNumber': 1,
      },
      <String, dynamic>{
        'frameIndex': 1.0,
        'pageIndex': 0,
        'xNorm': 0.50,
        'yNorm': 0.30,
        'measureNumber': 2,
      },
      <String, dynamic>{
        'frameIndex': 2.0,
        'pageIndex': 1,
        'xNorm': 0.20,
        'yNorm': 0.72,
        'measureNumber': 3,
      },
      <String, dynamic>{
        'frameIndex': 3.0,
        'pageIndex': 1,
        'xNorm': 0.60,
        'yNorm': 0.72,
        'measureNumber': 4,
      },
    ],
    'referenceChromagram': <String, dynamic>{
      'encoding': omrChromagramEncodingF32LeRowMajor,
      'pitchClassCount': omrPitchClassCount,
      'frameCount': frameCount,
      'dataBase64': base64Encode(rawBytes),
    },
  });
}
