import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'score_document.dart';
import 'score_page.dart';
import 'timeline_anchor.dart';

/// Loads a [ScoreDocument] from the Flutter asset bundle under
/// `assets/scores/<scoreId>/`.
final class ScoreDocumentLoader {
  ScoreDocumentLoader({AssetBundle? assetBundle})
      : assetBundle = assetBundle ?? rootBundle;

  final AssetBundle assetBundle;

  /// Asset directory prefix for a given score id.
  static String assetPrefix(String scoreId) => 'assets/scores/$scoreId';

  Future<ScoreDocument> loadFromAssets(String scoreId) async {
    final prefix = assetPrefix(scoreId);
    final manifestJson =
        jsonDecode(await assetBundle.loadString('$prefix/manifest.json')) as Map<String, dynamic>;
    final timelineJson =
        jsonDecode(await assetBundle.loadString('$prefix/timeline_map.json')) as Map<String, dynamic>;

    final sampleRateHz = (manifestJson['sampleRateHz'] as num).toDouble();
    final hopLengthSamples = manifestJson['hopLengthSamples'] as int;
    final referenceFrameCount = manifestJson['referenceFrameCount'] as int;
    final displayTitle = (manifestJson['displayTitle'] as String?) ?? scoreId;

    final pagesJson = manifestJson['pages'] as List<dynamic>;
    final pages = <ScorePage>[
      for (final entry in pagesJson)
        ScorePage(
          pageIndex: (entry as Map<String, dynamic>)['pageIndex'] as int,
          assetPath: '$prefix/${entry['assetPath'] as String}',
          aspectRatio: (entry['aspectRatio'] as num).toDouble(),
        ),
    ];

    final anchorsJson = timelineJson['anchors'] as List<dynamic>;
    final anchors = <TimelineAnchor>[
      for (final entry in anchorsJson) TimelineAnchor.fromJson(entry as Map<String, dynamic>),
    ];

    final chromagramByteData = await assetBundle.load('$prefix/reference_chromagram.f32');
    if (chromagramByteData.lengthInBytes % 4 != 0) {
      throw FormatException(
        'reference_chromagram.f32 for "$scoreId" has length '
        '${chromagramByteData.lengthInBytes}, which is not a multiple of 4.',
      );
    }
    final floatCount = chromagramByteData.lengthInBytes ~/ 4;
    final referenceChromagramRowMajor = Float32List(floatCount);
    for (var index = 0; index < floatCount; index++) {
      referenceChromagramRowMajor[index] =
          chromagramByteData.getFloat32(index * 4, Endian.little);
    }

    final document = ScoreDocument(
      scoreId: scoreId,
      displayTitle: displayTitle,
      sampleRateHz: sampleRateHz,
      hopLengthSamples: hopLengthSamples,
      pages: List<ScorePage>.unmodifiable(pages),
      anchors: List<TimelineAnchor>.unmodifiable(anchors),
      referenceChromagramRowMajor: referenceChromagramRowMajor,
      referenceFrameCount: referenceFrameCount,
    );
    document.validate();
    return document;
  }
}
