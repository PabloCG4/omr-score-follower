/// Phase 5.5.3 OMR network, structural document, and local persistence layer.
///
/// Upload UI and ingestion write PDF + structural JSON. Tracking loads those
/// artifacts through [ScoreDocumentLoader] / [ScoreVisualDocumentLoader].
library;

export 'omr_api_client.dart';
export 'omr_api_config.dart';
export 'omr_api_exceptions.dart';
export 'omr_score_ingestion_service.dart';
export 'omr_structural_document.dart';
export 'score_local_file_store.dart';
