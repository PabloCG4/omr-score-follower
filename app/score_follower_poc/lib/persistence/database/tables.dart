import 'package:drift/drift.dart';

/// User-configured instruments (tuning reference + transposition).
@DataClassName('InstrumentRow')
class Instruments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 128)();
  RealColumn get baseFrequencyHz => real().withDefault(const Constant(440.0))();
  IntColumn get transpositionSemitones => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();
}

/// Singleton preferences row (`id` is always 1).
@DataClassName('UserPreferencesRow')
class UserPreferencesRows extends Table {
  IntColumn get id => integer()();
  TextColumn get trackingMode => text()();
  IntColumn get activeInstrumentId => integer().references(Instruments, #id)();
  RealColumn get strictConfidenceThreshold =>
      real().withDefault(const Constant(0.55))();
  TextColumn get scoreId => text().withDefault(const Constant('demo_four_chords'))();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Future score pack metadata. Population via PDF/API is out of scope for
/// Phase 5.5.1; this table exists so later phases can insert without a migration.
@DataClassName('ScoreDocumentRow')
class ScoreDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 256)();
  /// Relative to the application documents directory (never absolute).
  TextColumn get originalPdfLocalPath => text()();
  /// Relative path to OMR structural JSON (schema v1); see docs/omr_structural_document.schema.v1.json.
  TextColumn get structuralDataLocalPath => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();
}
