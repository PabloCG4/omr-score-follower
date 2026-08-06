import 'package:flutter_test/flutter_test.dart';

import 'package:score_follower_poc/score/score_library_controller.dart';

void main() {
  test('persisted score preference id round-trips', () {
    const documentId = 42;
    final preferenceId =
        ScoreLibraryController.preferenceIdForPersistedDocument(documentId);
    expect(preferenceId, 'persisted:42');
    expect(
      ScoreLibraryController.tryParsePersistedDocumentId(preferenceId),
      documentId,
    );
    expect(
      ScoreLibraryController.isDemoScoreId(demoScorePreferenceId),
      isTrue,
    );
  });
}
