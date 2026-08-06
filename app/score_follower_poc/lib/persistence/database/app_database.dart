import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database for offline instrument, preference, and score metadata.
@DriftDatabase(tables: [Instruments, UserPreferencesRows, ScoreDocuments])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  @override
  int get schemaVersion => 1;

  /// Default seed instrument id after first-boot transaction (Piano).
  static const int defaultInstrumentId = 1;

  /// Singleton preferences row id.
  static const int preferencesRowId = 1;

  static QueryExecutor openConnection() {
    return driftDatabase(name: 'score_follower_poc');
  }

  /// Inserts the default Piano instrument and singleton preferences in one
  /// transaction when the database is empty (first launch).
  Future<void> seedIfEmpty() async {
    await transaction(() async {
      final instrumentCount = await instruments.count().getSingle();
      if (instrumentCount > 0) {
        return;
      }

      final now = DateTime.now().toUtc();
      final insertedInstrumentId = await into(instruments).insert(
        InstrumentsCompanion.insert(
          name: 'Piano',
          baseFrequencyHz: const Value(440.0),
          transpositionSemitones: const Value(0),
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      );

      await into(userPreferencesRows).insert(
        UserPreferencesRowsCompanion.insert(
          id: const Value(preferencesRowId),
          trackingMode: 'rubato',
          activeInstrumentId: insertedInstrumentId,
          strictConfidenceThreshold: const Value(0.55),
          scoreId: const Value('demo_four_chords'),
          updatedAtUtc: now,
        ),
      );
    });
  }
}
