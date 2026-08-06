/// Offline metadata row for a future ingested score pack.
///
/// Distinct from the in-memory tracking [ScoreDocument] under `lib/score/`.
/// Paths are stored relative to the application documents directory so they
/// remain valid across OS upgrades and reinstalls of the app sandbox root.
final class PersistedScoreDocument {
  const PersistedScoreDocument({
    required this.id,
    required this.title,
    required this.originalPdfLocalPath,
    required this.structuralDataLocalPath,
  });

  final int id;
  final String title;

  /// Relative path to the original PDF under the app documents directory.
  final String originalPdfLocalPath;

  /// Relative path to OMR structural JSON (`OmrStructuralDocument` schema v1).
  final String structuralDataLocalPath;
}
