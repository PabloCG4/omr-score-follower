import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../omr/omr_structural_document.dart';
import '../omr/score_local_file_store.dart';
import '../persistence/repositories/score_document_repository.dart';
import 'omr_structural_to_score_document.dart';
import 'score_document.dart';
import 'score_library_controller.dart';
import 'score_page.dart';
import 'timeline_anchor.dart';

/// Typed failure when a tracking [ScoreDocument] cannot be resolved or opened.
final class ScoreDocumentLoadException implements Exception {
  ScoreDocumentLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Loads a [ScoreDocument] for the active preference id: bundled demo assets
/// or a persisted OMR `structural.json` on disk.
final class ScoreDocumentLoader {
  ScoreDocumentLoader({
    AssetBundle? assetBundle,
    this.scoreDocumentRepository,
    this.fileStore,
  }) : assetBundle = assetBundle ?? rootBundle;

  final AssetBundle assetBundle;
  final ScoreDocumentRepository? scoreDocumentRepository;
  final ScoreLocalFileStore? fileStore;

  /// Asset directory prefix for a given score id.
  static String assetPrefix(String scoreId) => 'assets/scores/$scoreId';

  /// Resolves [scoreId] to a tracking document (demo pack or structural JSON).
  Future<ScoreDocument> loadForScoreId(String scoreId) async {
    if (ScoreLibraryController.isDemoScoreId(scoreId)) {
      return loadFromAssets(demoScorePreferenceId);
    }
    return loadFromPersistedStructural(scoreId);
  }

  Future<ScoreDocument> loadFromAssets(String scoreId) async {
    final prefix = assetPrefix(scoreId);
    final manifestJson =
        jsonDecode(await assetBundle.loadString('$prefix/manifest.json'))
            as Map<String, dynamic>;
    final timelineJson =
        jsonDecode(await assetBundle.loadString('$prefix/timeline_map.json'))
            as Map<String, dynamic>;

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
      for (final entry in anchorsJson)
        TimelineAnchor.fromJson(entry as Map<String, dynamic>),
    ];

    final chromagramByteData =
        await assetBundle.load('$prefix/reference_chromagram.f32');
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

  /// Loads Drift metadata, reads `structural.json`, and adapts to [ScoreDocument].
  Future<ScoreDocument> loadFromPersistedStructural(String scoreId) async {
    final repository = scoreDocumentRepository;
    final store = fileStore;
    if (repository == null || store == null) {
      throw ScoreDocumentLoadException(
        'Persisted score loading requires a score repository and file store.',
      );
    }

    final documentId =
        ScoreLibraryController.tryParsePersistedDocumentId(scoreId);
    if (documentId == null) {
      throw ScoreDocumentLoadException(
        'Unknown score id "$scoreId". Select a Ready score or the demo pack.',
      );
    }

    final row = await repository.getById(documentId);
    if (row == null) {
      throw ScoreDocumentLoadException(
        'Score #$documentId was not found in the local library.',
      );
    }

    final structuralFile = await store.resolveAbsoluteFile(
      row.structuralDataLocalPath,
    );
    if (!await structuralFile.exists()) {
      throw ScoreDocumentLoadException(
        'Structural JSON is missing for "${row.title}" '
        '(${structuralFile.path}). Re-import the score.',
      );
    }

    final String jsonText;
    try {
      jsonText = await structuralFile.readAsString();
    } on FileSystemException catch (error) {
      throw ScoreDocumentLoadException(
        'Could not read structural JSON for "${row.title}": $error',
      );
    }

    final OmrStructuralDocument structural;
    try {
      structural = OmrStructuralDocument.parseJsonString(jsonText);
    } on OmrStructuralDocumentFormatException catch (error) {
      throw ScoreDocumentLoadException(
        'Invalid structural JSON for "${row.title}": ${error.message}',
      );
    }

    return omrStructuralToScoreDocument(
      structural: structural,
      scoreId: scoreId,
    );
  }
}
