import 'package:drift/drift.dart';

import '../../domain/instrument.dart';
import '../database/app_database.dart';

/// CRUD for [Instrument] rows. Maps Drift companions to domain entities.
final class InstrumentRepository {
  InstrumentRepository(this.database);

  final AppDatabase database;

  /// True for the seeded Piano row that must never be removed.
  static bool isProtectedDefaultInstrument(int instrumentId) {
    return instrumentId == AppDatabase.defaultInstrumentId;
  }

  Future<List<Instrument>> listAll() async {
    final rows = await (database.select(database.instruments)
          ..orderBy([(table) => OrderingTerm.asc(table.name)]))
        .get();
    return rows.map(mapRow).toList(growable: false);
  }

  Future<Instrument?> getById(int instrumentId) async {
    final row = await (database.select(database.instruments)
          ..where((table) => table.id.equals(instrumentId)))
        .getSingleOrNull();
    return row == null ? null : mapRow(row);
  }

  /// Inserts a new instrument when [instrument.id] is less than or equal to
  /// zero; otherwise updates the existing row.
  Future<Instrument> upsert(Instrument instrument) async {
    final now = DateTime.now().toUtc();
    if (instrument.id <= 0) {
      final insertedId = await database.into(database.instruments).insert(
            InstrumentsCompanion.insert(
              name: instrument.name.trim(),
              baseFrequencyHz: Value(instrument.baseFrequencyHz),
              transpositionSemitones: Value(instrument.transpositionSemitones),
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      return Instrument(
        id: insertedId,
        name: instrument.name.trim(),
        baseFrequencyHz: instrument.baseFrequencyHz,
        transpositionSemitones: instrument.transpositionSemitones,
      );
    }

    await (database.update(database.instruments)
          ..where((table) => table.id.equals(instrument.id)))
        .write(
      InstrumentsCompanion(
        name: Value(instrument.name.trim()),
        baseFrequencyHz: Value(instrument.baseFrequencyHz),
        transpositionSemitones: Value(instrument.transpositionSemitones),
        updatedAtUtc: Value(now),
      ),
    );
    return instrument;
  }

  /// Deletes [instrumentId] unless it is the seeded default Piano.
  /// If the deleted instrument was active, preferences are reassigned to the
  /// default instrument inside the same transaction.
  Future<void> deleteInstrument(int instrumentId) async {
    if (isProtectedDefaultInstrument(instrumentId)) {
      throw StateError('The default Piano instrument cannot be deleted.');
    }

    await database.transaction(() async {
      final preferences = await (database.select(database.userPreferencesRows)
            ..where((table) => table.id.equals(AppDatabase.preferencesRowId)))
          .getSingleOrNull();

      if (preferences != null && preferences.activeInstrumentId == instrumentId) {
        await (database.update(database.userPreferencesRows)
              ..where((table) => table.id.equals(AppDatabase.preferencesRowId)))
            .write(
          UserPreferencesRowsCompanion(
            activeInstrumentId: const Value(AppDatabase.defaultInstrumentId),
            updatedAtUtc: Value(DateTime.now().toUtc()),
          ),
        );
      }

      final deletedCount = await (database.delete(database.instruments)
            ..where((table) => table.id.equals(instrumentId)))
          .go();
      if (deletedCount == 0) {
        throw StateError('Instrument id=$instrumentId was not found.');
      }
    });
  }

  Instrument mapRow(InstrumentRow row) {
    return Instrument(
      id: row.id,
      name: row.name,
      baseFrequencyHz: row.baseFrequencyHz,
      transpositionSemitones: row.transpositionSemitones,
    );
  }
}
