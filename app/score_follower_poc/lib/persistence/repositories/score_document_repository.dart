import 'package:drift/drift.dart';

import '../../domain/persisted_score_document.dart';
import '../database/app_database.dart';

/// Persistence API for [PersistedScoreDocument] metadata rows.
///
/// PDF upload and OMR processing live in `lib/omr/` ([OmrScoreIngestionService]).
/// The practice screen loads [originalPdfLocalPath] via [ScoreVisualDocumentLoader];
/// the DTW engine still uses the demo chromagram pack until D.2/D.3.
final class ScoreDocumentRepository {
  ScoreDocumentRepository(this.database);

  final AppDatabase database;

  Future<List<PersistedScoreDocument>> listAll() async {
    final rows = await (database.select(database.scoreDocuments)
          ..orderBy([(table) => OrderingTerm.asc(table.title)]))
        .get();
    return rows.map(mapRow).toList(growable: false);
  }

  /// Reactive stream of all persisted score metadata rows (title ascending).
  /// Emits on insert/update/delete so the score library UI can leave
  /// "Processing" and show "Ready" without a manual refresh.
  Stream<List<PersistedScoreDocument>> watchAll() {
    return (database.select(database.scoreDocuments)
          ..orderBy([(table) => OrderingTerm.asc(table.title)]))
        .watch()
        .map(
          (rows) => rows.map(mapRow).toList(growable: false),
        );
  }

  Future<PersistedScoreDocument?> getById(int documentId) async {
    final row = await (database.select(database.scoreDocuments)
          ..where((table) => table.id.equals(documentId)))
        .getSingleOrNull();
    return row == null ? null : mapRow(row);
  }

  /// Inserts metadata for a future ingested score pack.
  ///
  /// [originalPdfLocalPath] and [structuralDataLocalPath] must be paths
  /// relative to the application documents directory (never absolute).
  Future<PersistedScoreDocument> insert({
    required String title,
    required String originalPdfLocalPath,
    required String structuralDataLocalPath,
  }) async {
    final now = DateTime.now().toUtc();
    final insertedId = await database.into(database.scoreDocuments).insert(
          ScoreDocumentsCompanion.insert(
            title: title.trim(),
            originalPdfLocalPath: originalPdfLocalPath,
            structuralDataLocalPath: structuralDataLocalPath,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    return PersistedScoreDocument(
      id: insertedId,
      title: title.trim(),
      originalPdfLocalPath: originalPdfLocalPath,
      structuralDataLocalPath: structuralDataLocalPath,
    );
  }

  Future<void> deleteById(int documentId) async {
    await (database.delete(database.scoreDocuments)
          ..where((table) => table.id.equals(documentId)))
        .go();
  }

  PersistedScoreDocument mapRow(ScoreDocumentRow row) {
    return PersistedScoreDocument(
      id: row.id,
      title: row.title,
      originalPdfLocalPath: row.originalPdfLocalPath,
      structuralDataLocalPath: row.structuralDataLocalPath,
    );
  }
}
