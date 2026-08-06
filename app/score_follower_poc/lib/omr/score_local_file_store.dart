import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Writes ingested score artifacts under the application documents directory
/// and returns paths **relative** to that root for Drift persistence.
final class ScoreLocalFileStore {
  ScoreLocalFileStore({
    Future<Directory> Function()? applicationDocumentsDirectoryResolver,
  }) : applicationDocumentsDirectoryResolver =
            applicationDocumentsDirectoryResolver ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() applicationDocumentsDirectoryResolver;

  static const String scoresDirectoryName = 'scores';
  static const String originalPdfFileName = 'original.pdf';
  static const String structuralJsonFileName = 'structural.json';

  /// Absolute path to the application documents directory.
  Future<Directory> resolveDocumentsRoot() {
    return applicationDocumentsDirectoryResolver();
  }

  /// Creates `scores/<documentId>/` under the documents root if missing.
  Future<Directory> ensureScoreDirectory(String documentId) async {
    final sanitizedId = sanitizeDocumentId(documentId);
    final documentsRoot = await resolveDocumentsRoot();
    final scoreDirectory = Directory(
      path.join(documentsRoot.path, scoresDirectoryName, sanitizedId),
    );
    if (!await scoreDirectory.exists()) {
      await scoreDirectory.create(recursive: true);
    }
    return scoreDirectory;
  }

  /// Writes PDF bytes and returns the relative path stored in SQLite.
  Future<String> writeOriginalPdf({
    required String documentId,
    required List<int> pdfBytes,
  }) async {
    final scoreDirectory = await ensureScoreDirectory(documentId);
    final absolutePath = path.join(scoreDirectory.path, originalPdfFileName);
    await File(absolutePath).writeAsBytes(pdfBytes, flush: true);
    return relativeScorePath(documentId, originalPdfFileName);
  }

  /// Writes structural JSON UTF-8 text and returns the relative SQLite path.
  Future<String> writeStructuralJson({
    required String documentId,
    required String jsonText,
  }) async {
    final scoreDirectory = await ensureScoreDirectory(documentId);
    final absolutePath = path.join(scoreDirectory.path, structuralJsonFileName);
    await File(absolutePath).writeAsString(jsonText, flush: true);
    return relativeScorePath(documentId, structuralJsonFileName);
  }

  /// Best-effort recursive delete of `scores/<documentId>/`.
  Future<void> deleteScoreDirectory(String documentId) async {
    final sanitizedId = sanitizeDocumentId(documentId);
    final documentsRoot = await resolveDocumentsRoot();
    final scoreDirectory = Directory(
      path.join(documentsRoot.path, scoresDirectoryName, sanitizedId),
    );
    if (await scoreDirectory.exists()) {
      await scoreDirectory.delete(recursive: true);
    }
  }

  /// Resolves a DB-relative path to an absolute [File].
  Future<File> resolveAbsoluteFile(String relativePath) async {
    final documentsRoot = await resolveDocumentsRoot();
    return File(path.join(documentsRoot.path, relativePath));
  }

  static String relativeScorePath(String documentId, String fileName) {
    final sanitizedId = sanitizeDocumentId(documentId);
    return path.join(scoresDirectoryName, sanitizedId, fileName);
  }

  /// Rejects path separators so document ids cannot escape the scores folder.
  static String sanitizeDocumentId(String documentId) {
    final trimmed = documentId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('documentId must be non-empty.');
    }
    if (trimmed.contains('/') ||
        trimmed.contains('\\') ||
        trimmed.contains('..')) {
      throw ArgumentError(
        'documentId must not contain path separators or "..": "$documentId".',
      );
    }
    return trimmed;
  }
}
