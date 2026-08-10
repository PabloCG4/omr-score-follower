import 'package:pdfrx/pdfrx.dart';

/// Where the practice-screen PDF bytes are loaded from.
sealed class ScorePdfSource {
  const ScorePdfSource();
}

/// Bundled Flutter asset (demo pack).
final class AssetPdfSource extends ScorePdfSource {
  const AssetPdfSource(this.assetPath);

  final String assetPath;
}

/// Absolute filesystem path to a persisted `original.pdf`.
final class FilePdfSource extends ScorePdfSource {
  const FilePdfSource(this.absoluteFilePath);

  final String absoluteFilePath;
}

/// One page of a [ScoreVisualDocument] for letterboxed layout.
final class ScoreVisualPage {
  const ScoreVisualPage({
    required this.pageIndex,
    required this.aspectRatio,
  });

  /// Zero-based page index within the PDF.
  final int pageIndex;

  /// Page width / height in PDF points (rotated).
  final double aspectRatio;
}

/// Practice-screen visual score: original PDF plus per-page aspect ratios.
///
/// Owns [pdfDocument]; callers must [dispose] when finished.
final class ScoreVisualDocument {
  ScoreVisualDocument({
    required this.scoreId,
    required this.displayTitle,
    required this.pdfSource,
    required this.pdfDocument,
    required this.pages,
  });

  final String scoreId;
  final String displayTitle;
  final ScorePdfSource pdfSource;
  final PdfDocument pdfDocument;
  final List<ScoreVisualPage> pages;

  int get pageCount => pages.length;

  Future<void> dispose() => pdfDocument.dispose();
}

/// Typed failure when a practice PDF cannot be resolved or opened.
final class ScoreVisualDocumentException implements Exception {
  ScoreVisualDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}
