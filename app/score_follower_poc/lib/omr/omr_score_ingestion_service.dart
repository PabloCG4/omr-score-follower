import 'dart:io';
import 'dart:math';

import '../domain/persisted_score_document.dart';
import '../persistence/repositories/score_document_repository.dart';
import 'omr_api_client.dart';
import 'omr_structural_document.dart';
import 'score_local_file_store.dart';

/// Result of a successful PDF → OMR API → local persistence pipeline.
final class OmrScoreIngestionResult {
  const OmrScoreIngestionResult({
    required this.persistedDocument,
    required this.structuralDocument,
  });

  final PersistedScoreDocument persistedDocument;
  final OmrStructuralDocument structuralDocument;
}

/// Orchestrates OMR upload, local PDF/JSON persistence, and Drift insertion.
///
/// Callers (future UI) supply a local PDF [File]; this service does not open
/// a file picker. Tracking still uses the asset demo pack until a later phase
/// wires [PersistedScoreDocument] into [ScoreDocumentLoader].
final class OmrScoreIngestionService {
  OmrScoreIngestionService({
    required this.apiClient,
    required this.fileStore,
    required this.scoreDocumentRepository,
    Random? random,
  }) : random = random ?? Random.secure();

  final OmrScoreUploadClient apiClient;
  final ScoreLocalFileStore fileStore;
  final ScoreDocumentRepository scoreDocumentRepository;
  final Random random;

  /// Uploads [pdfFile], writes artifacts under `scores/<id>/`, and inserts a
  /// [PersistedScoreDocument] row with relative paths.
  Future<OmrScoreIngestionResult> ingestPdfScore({
    required File pdfFile,
    String? displayTitle,
  }) async {
    final structuralDocument = await apiClient.uploadScorePdf(
      pdfFile: pdfFile,
      displayTitle: displayTitle,
    );

    final folderId = resolveFolderDocumentId(structuralDocument);
    final title = (displayTitle?.trim().isNotEmpty == true)
        ? displayTitle!.trim()
        : structuralDocument.displayTitle.trim();

    final pdfBytes = await pdfFile.readAsBytes();
    String? writtenPdfRelativePath;
    String? writtenJsonRelativePath;

    try {
      writtenPdfRelativePath = await fileStore.writeOriginalPdf(
        documentId: folderId,
        pdfBytes: pdfBytes,
      );
      writtenJsonRelativePath = await fileStore.writeStructuralJson(
        documentId: folderId,
        jsonText: structuralDocument.toPrettyJsonString(),
      );

      final persisted = await scoreDocumentRepository.insert(
        title: title,
        originalPdfLocalPath: writtenPdfRelativePath,
        structuralDataLocalPath: writtenJsonRelativePath,
      );

      return OmrScoreIngestionResult(
        persistedDocument: persisted,
        structuralDocument: structuralDocument,
      );
    } catch (error) {
      // Avoid orphan folders without a DB row (and vice versa after insert fail).
      await fileStore.deleteScoreDirectory(folderId);
      rethrow;
    }
  }

  /// Prefers backend [OmrStructuralDocument.documentId]; otherwise generates a UUID.
  String resolveFolderDocumentId(OmrStructuralDocument document) {
    final backendId = document.documentId?.trim();
    if (backendId != null && backendId.isNotEmpty) {
      return ScoreLocalFileStore.sanitizeDocumentId(backendId);
    }
    return generateUuidV4();
  }

  /// RFC 4122 version-4 UUID without an extra package dependency.
  String generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final encoded = bytes.map(hex).join();
    return '${encoded.substring(0, 8)}-'
        '${encoded.substring(8, 12)}-'
        '${encoded.substring(12, 16)}-'
        '${encoded.substring(16, 20)}-'
        '${encoded.substring(20, 32)}';
  }
}
