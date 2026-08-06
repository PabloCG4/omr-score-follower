import 'package:flutter/foundation.dart';

import 'database/app_database.dart';

/// Process-wide [AppDatabase] handle opened once at startup.
final class AppDatabaseProvider {
  AppDatabaseProvider._();

  static AppDatabase? sharedDatabase;

  /// Opens SQLite (via drift_flutter) and runs the first-boot seed transaction.
  static Future<AppDatabase> initialize() async {
    if (sharedDatabase != null) {
      return sharedDatabase!;
    }
    final database = AppDatabase();
    await database.seedIfEmpty();
    sharedDatabase = database;
    return database;
  }

  static AppDatabase get requireDatabase {
    final database = sharedDatabase;
    if (database == null) {
      throw StateError(
        'AppDatabaseProvider.initialize() must complete before accessing the database.',
      );
    }
    return database;
  }

  @visibleForTesting
  static Future<void> resetForTests() async {
    await sharedDatabase?.close();
    sharedDatabase = null;
  }
}
