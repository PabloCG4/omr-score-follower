import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

import '../omr/score_local_file_store.dart';
import '../persistence/repositories/score_document_repository.dart';
import 'score_library_controller.dart';
import 'score_visual_document.dart';

/// Opens the practice-viewport PDF for a preference score id.
///
/// Resolves the bundled demo PDF or a persisted `original.pdf`. Tracking
/// geometry and reference chromagrams are loaded separately by
/// [ScoreDocumentLoader].
final class ScoreVisualDocumentLoader {
  ScoreVisualDocumentLoader({
    required this.scoreDocumentRepository,
    required this.fileStore,
    Future<PdfDocument> Function(String assetPath)? openAssetPdf,
    Future<PdfDocument> Function(String filePath)? openFilePdf,
  })  : openAssetPdf = openAssetPdf ?? PdfDocument.openAsset,
        openFilePdf = openFilePdf ?? PdfDocument.openFile;

  final ScoreDocumentRepository scoreDocumentRepository;
  final ScoreLocalFileStore fileStore;
  final Future<PdfDocument> Function(String assetPath) openAssetPdf;
  final Future<PdfDocument> Function(String filePath) openFilePdf;

  static const String demoPdfAssetPath =
      'assets/scores/demo_four_chords/score.pdf';

  /// Resolves [scoreId] to an asset or absolute file path (no PDF decode).
  Future<ResolvedScorePdfLocation> resolveLocation(String scoreId) async {
    if (ScoreLibraryController.isDemoScoreId(scoreId)) {
      return const ResolvedScorePdfLocation(
        scoreId: demoScorePreferenceId,
        displayTitle: 'Demo: C - G - Am - F',
        source: AssetPdfSource(demoPdfAssetPath),
      );
    }

    final documentId = ScoreLibraryController.tryParsePersistedDocumentId(
      scoreId,
    );
    if (documentId == null) {
      throw ScoreVisualDocumentException(
        'Unknown score id "$scoreId". Select a Ready score or the demo pack.',
      );
    }

    final row = await scoreDocumentRepository.getById(documentId);
    if (row == null) {
      throw ScoreVisualDocumentException(
        'Score #$documentId was not found in the local library.',
      );
    }

    final pdfFile = await fileStore.resolveAbsoluteFile(
      row.originalPdfLocalPath,
    );
    if (!await pdfFile.exists()) {
      throw ScoreVisualDocumentException(
        'Original PDF is missing for "${row.title}" '
        '(${pdfFile.path}). Re-import the score.',
      );
    }

    return ResolvedScorePdfLocation(
      scoreId: scoreId,
      displayTitle: row.title,
      source: FilePdfSource(pdfFile.absolute.path),
    );
  }

  /// Resolves and opens the PDF for [scoreId].
  Future<ScoreVisualDocument> load(String scoreId) async {
    final location = await resolveLocation(scoreId);
    final PdfDocument pdfDocument;
    try {
      switch (location.source) {
        case AssetPdfSource(:final assetPath):
          pdfDocument = await openAssetPdf(assetPath);
        case FilePdfSource(:final absoluteFilePath):
          pdfDocument = await openFilePdf(absoluteFilePath);
      }
    } on FileSystemException catch (error) {
      throw ScoreVisualDocumentException(
        'Could not read PDF for "${location.displayTitle}": $error',
      );
    } catch (error) {
      throw ScoreVisualDocumentException(
        'Could not open PDF for "${location.displayTitle}": $error',
      );
    }

    if (pdfDocument.pages.isEmpty) {
      await pdfDocument.dispose();
      throw ScoreVisualDocumentException(
        'PDF for "${location.displayTitle}" has no pages.',
      );
    }

    final pages = <ScoreVisualPage>[
      for (var index = 0; index < pdfDocument.pages.length; index++)
        ScoreVisualPage(
          pageIndex: index,
          aspectRatio: _aspectRatioForPage(pdfDocument.pages[index]),
        ),
    ];

    return ScoreVisualDocument(
      scoreId: location.scoreId,
      displayTitle: location.displayTitle,
      pdfSource: location.source,
      pdfDocument: pdfDocument,
      pages: List<ScoreVisualPage>.unmodifiable(pages),
    );
  }

  static double _aspectRatioForPage(PdfPage page) {
    if (page.height <= 0) {
      return 1.0;
    }
    return page.width / page.height;
  }
}

/// Path resolution result before PDFium decode (unit-testable).
final class ResolvedScorePdfLocation {
  const ResolvedScorePdfLocation({
    required this.scoreId,
    required this.displayTitle,
    required this.source,
  });

  final String scoreId;
  final String displayTitle;
  final ScorePdfSource source;
}
