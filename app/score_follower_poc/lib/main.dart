// Phase 5.5.3 entry: open local SQLite, wire score library, show config UI.
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'omr/omr_api_client.dart';
import 'omr/omr_score_ingestion_service.dart';
import 'omr/score_local_file_store.dart';
import 'persistence/app_database_provider.dart';
import 'persistence/repositories/score_document_repository.dart';
import 'persistence/repositories/user_preferences_repository.dart';
import 'score/score_library_controller.dart';
import 'ui/initial_config_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final database = await AppDatabaseProvider.initialize();

  final scoreDocumentRepository = ScoreDocumentRepository(database);
  final preferencesRepository = UserPreferencesRepository(database);
  final apiClient = OmrApiClient();
  final ingestionService = OmrScoreIngestionService(
    apiClient: apiClient,
    fileStore: ScoreLocalFileStore(),
    scoreDocumentRepository: scoreDocumentRepository,
  );
  final scoreLibraryController = ScoreLibraryController(
    ingestionService: ingestionService,
    scoreDocumentRepository: scoreDocumentRepository,
    preferencesRepository: preferencesRepository,
  );
  await scoreLibraryController.loadSelectionFromPreferences();

  runApp(
    ScoreFollowerPocApp(
      scoreLibraryController: scoreLibraryController,
    ),
  );
}

class ScoreFollowerPocApp extends StatelessWidget {
  const ScoreFollowerPocApp({
    super.key,
    required this.scoreLibraryController,
  });

  final ScoreLibraryController scoreLibraryController;

  @override
  Widget build(BuildContext context) {
    return ScoreLibraryScope(
      controller: scoreLibraryController,
      child: MaterialApp(
        title: 'Score Follower',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const InitialConfigScreen(),
      ),
    );
  }
}
