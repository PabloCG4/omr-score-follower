import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import '../domain/persisted_score_document.dart';
import '../omr/omr_api_exceptions.dart';
import '../omr/omr_score_ingestion_service.dart';
import '../persistence/repositories/score_document_repository.dart';
import '../persistence/repositories/user_preferences_repository.dart';

/// Bundled demo pack id stored in [UserPreferences.scoreId].
const String demoScorePreferenceId = 'demo_four_chords';

/// Prefix for preference ids that refer to a Drift [PersistedScoreDocument].
const String persistedScorePreferencePrefix = 'persisted:';

/// In-flight PDF → OMR job shown in the library before the Drift row exists.
final class PendingScoreIngestion {
  const PendingScoreIngestion({
    required this.localId,
    required this.displayTitle,
    required this.startedAtUtc,
  });

  final String localId;
  final String displayTitle;
  final DateTime startedAtUtc;
}

/// App-scoped score library: pending ingestions, Ready selection, and prefs.
///
/// Survives navigation away from [InitialConfigScreen]. Pending jobs are
/// in-memory only (lost on process death); Ready rows live in SQLite.
final class ScoreLibraryController extends ChangeNotifier {
  ScoreLibraryController({
    required this.ingestionService,
    required this.scoreDocumentRepository,
    required this.preferencesRepository,
  });

  final OmrScoreIngestionService ingestionService;
  final ScoreDocumentRepository scoreDocumentRepository;
  final UserPreferencesRepository preferencesRepository;

  List<PendingScoreIngestion> pendingIngestions = const [];
  String selectedScoreId = demoScorePreferenceId;
  String? lastUserFacingError;
  bool isBusySelecting = false;

  Stream<List<PersistedScoreDocument>> watchReadyScores() {
    return scoreDocumentRepository.watchAll();
  }

  /// Loads [UserPreferences.scoreId] into [selectedScoreId].
  Future<void> loadSelectionFromPreferences() async {
    final preferences = await preferencesRepository.loadOrCreateDefaults();
    selectedScoreId = preferences.scoreId;
    notifyListeners();
  }

  static String preferenceIdForPersistedDocument(int documentId) {
    return '$persistedScorePreferencePrefix$documentId';
  }

  static int? tryParsePersistedDocumentId(String scoreId) {
    if (!scoreId.startsWith(persistedScorePreferencePrefix)) {
      return null;
    }
    return int.tryParse(
      scoreId.substring(persistedScorePreferencePrefix.length),
    );
  }

  static bool isDemoScoreId(String scoreId) {
    return scoreId == demoScorePreferenceId;
  }

  /// Human title for the summary chip given the current preference id and
  /// the latest Ready list from Drift.
  String resolveSelectedScoreTitle(List<PersistedScoreDocument> readyScores) {
    if (isDemoScoreId(selectedScoreId)) {
      return 'Demo: C - G - Am - F';
    }
    final documentId = tryParsePersistedDocumentId(selectedScoreId);
    if (documentId == null) {
      return selectedScoreId;
    }
    for (final document in readyScores) {
      if (document.id == documentId) {
        return document.title;
      }
    }
    return 'Ingested score #$documentId';
  }

  /// Starts a non-blocking OMR ingest. Adds a Pending row immediately.
  Future<void> enqueuePdfImport(File pdfFile) async {
    final displayTitle = _titleFromPdfPath(pdfFile.path);
    final localId =
        'pending-${DateTime.now().toUtc().microsecondsSinceEpoch}-${pendingIngestions.length}';
    final pending = PendingScoreIngestion(
      localId: localId,
      displayTitle: displayTitle,
      startedAtUtc: DateTime.now().toUtc(),
    );

    pendingIngestions = [...pendingIngestions, pending];
    lastUserFacingError = null;
    notifyListeners();

    try {
      final result = await ingestionService.ingestPdfScore(
        pdfFile: pdfFile,
        displayTitle: displayTitle,
      );
      await selectPersistedScore(result.persistedDocument);
    } catch (error) {
      lastUserFacingError = mapIngestionErrorToUserMessage(error);
      notifyListeners();
    } finally {
      pendingIngestions = [
        for (final item in pendingIngestions)
          if (item.localId != localId) item,
      ];
      notifyListeners();
    }
  }

  Future<void> selectDemoScore() async {
    await _persistScoreId(demoScorePreferenceId);
  }

  Future<void> selectPersistedScore(PersistedScoreDocument document) async {
    await _persistScoreId(preferenceIdForPersistedDocument(document.id));
  }

  Future<void> _persistScoreId(String scoreId) async {
    isBusySelecting = true;
    notifyListeners();
    try {
      final preferences = await preferencesRepository.loadOrCreateDefaults();
      await preferencesRepository.save(
        preferences.copyWith(scoreId: scoreId),
      );
      selectedScoreId = scoreId;
    } finally {
      isBusySelecting = false;
      notifyListeners();
    }
  }

  /// Consumes [lastUserFacingError] after the UI has shown it.
  void clearLastUserFacingError() {
    if (lastUserFacingError == null) {
      return;
    }
    lastUserFacingError = null;
    notifyListeners();
  }

  static String mapIngestionErrorToUserMessage(Object error) {
    if (error is OmrApiTimeoutException) {
      return 'Score processing timed out. The OMR service took too long — '
          'try again with a shorter PDF or check your connection.';
    }
    if (error is OmrApiNetworkException) {
      return 'Could not reach the score processing service. '
          'Check your network connection and try again.';
    }
    if (error is OmrApiHttpException) {
      return 'The score processing service rejected the upload '
          '(HTTP ${error.statusCode}). Try again later.';
    }
    if (error is OmrApiMalformedResponseException) {
      return 'The processing service returned an invalid score document. '
          'The PDF may be unsupported or the server misconfigured.';
    }
    return 'Score import failed. Please try again.';
  }

  static String _titleFromPdfPath(String pdfPath) {
    final baseName = path.basename(pdfPath);
    if (baseName.toLowerCase().endsWith('.pdf') && baseName.length > 4) {
      return baseName.substring(0, baseName.length - 4);
    }
    return baseName.isEmpty ? 'Imported score' : baseName;
  }
}

/// Provides the app-scoped [ScoreLibraryController] below [MaterialApp].
final class ScoreLibraryScope extends InheritedNotifier<ScoreLibraryController> {
  const ScoreLibraryScope({
    super.key,
    required ScoreLibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  static ScoreLibraryController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ScoreLibraryScope>();
    if (scope == null || scope.notifier == null) {
      throw StateError(
        'ScoreLibraryScope.of() requires a ScoreLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }

  static ScoreLibraryController read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<ScoreLibraryScope>();
    if (scope == null || scope.notifier == null) {
      throw StateError(
        'ScoreLibraryScope.read() requires a ScoreLibraryScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
