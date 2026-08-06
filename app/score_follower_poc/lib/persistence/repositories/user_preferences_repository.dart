import 'package:drift/drift.dart';

import '../../config/tracking_mode.dart';
import '../../domain/user_preferences.dart';
import '../database/app_database.dart';

/// Loads and persists the singleton [UserPreferences] row.
final class UserPreferencesRepository {
  UserPreferencesRepository(this.database);

  final AppDatabase database;

  /// Returns existing preferences, or recreates defaults if the singleton
  /// row is missing (should only happen if the DB was manually corrupted).
  Future<UserPreferences> loadOrCreateDefaults() async {
    final existing = await (database.select(database.userPreferencesRows)
          ..where((table) => table.id.equals(AppDatabase.preferencesRowId)))
        .getSingleOrNull();
    if (existing != null) {
      return mapRow(existing);
    }

    await database.seedIfEmpty();
    final seeded = await (database.select(database.userPreferencesRows)
          ..where((table) => table.id.equals(AppDatabase.preferencesRowId)))
        .getSingle();
    return mapRow(seeded);
  }

  Future<void> save(UserPreferences preferences) async {
    final now = DateTime.now().toUtc();
    await database.into(database.userPreferencesRows).insertOnConflictUpdate(
          UserPreferencesRowsCompanion.insert(
            id: const Value(AppDatabase.preferencesRowId),
            trackingMode: preferences.trackingMode.name,
            activeInstrumentId: preferences.activeInstrumentId,
            strictConfidenceThreshold: Value(preferences.strictConfidenceThreshold),
            scoreId: Value(preferences.scoreId),
            updatedAtUtc: now,
          ),
        );
  }

  UserPreferences mapRow(UserPreferencesRow row) {
    return UserPreferences(
      trackingMode: parseTrackingMode(row.trackingMode),
      activeInstrumentId: row.activeInstrumentId,
      strictConfidenceThreshold: row.strictConfidenceThreshold,
      scoreId: row.scoreId,
    );
  }

  TrackingMode parseTrackingMode(String rawValue) {
    for (final mode in TrackingMode.values) {
      if (mode.name == rawValue) {
        return mode;
      }
    }
    return TrackingMode.rubato;
  }
}
