import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:score_follower_poc/omr/score_local_file_store.dart';
import 'package:score_follower_poc/persistence/database/app_database.dart';
import 'package:score_follower_poc/persistence/repositories/score_document_repository.dart';
import 'package:score_follower_poc/score/score_library_controller.dart';
import 'package:score_follower_poc/score/score_visual_document.dart';
import 'package:score_follower_poc/score/score_visual_document_loader.dart';

void main() {
  late Directory temporaryDocumentsRoot;
  late AppDatabase database;
  late ScoreDocumentRepository scoreDocumentRepository;
  late ScoreLocalFileStore fileStore;
  late ScoreVisualDocumentLoader loader;

  setUp(() async {
    temporaryDocumentsRoot =
        await Directory.systemTemp.createTemp('score_visual_docs_');
    database = AppDatabase(NativeDatabase.memory());
    scoreDocumentRepository = ScoreDocumentRepository(database);
    fileStore = ScoreLocalFileStore(
      applicationDocumentsDirectoryResolver: () async => temporaryDocumentsRoot,
    );
    loader = ScoreVisualDocumentLoader(
      scoreDocumentRepository: scoreDocumentRepository,
      fileStore: fileStore,
      openAssetPdf: (assetPath) async {
        fail('openAssetPdf should not be called in resolveLocation tests.');
      },
      openFilePdf: (filePath) async {
        fail('openFilePdf should not be called in resolveLocation tests.');
      },
    );
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDocumentsRoot.exists()) {
      await temporaryDocumentsRoot.delete(recursive: true);
    }
  });

  test('resolveLocation maps demo id to bundled score.pdf asset', () async {
    final location = await loader.resolveLocation(demoScorePreferenceId);

    expect(location.scoreId, demoScorePreferenceId);
    expect(location.displayTitle, 'Demo: C - G - Am - F');
    expect(
      location.source,
      isA<AssetPdfSource>().having(
        (source) => source.assetPath,
        'assetPath',
        ScoreVisualDocumentLoader.demoPdfAssetPath,
      ),
    );
  });

  test(
    'resolveLocation maps persisted id to absolute original.pdf path',
    () async {
      final writtenRelativePath = await fileStore.writeOriginalPdf(
        documentId: 'persisted-doc-42',
        pdfBytes: const <int>[0x25, 0x50, 0x44, 0x46],
      );
      final persisted = await scoreDocumentRepository.insert(
        title: 'Imported Sonata',
        originalPdfLocalPath: writtenRelativePath,
        structuralDataLocalPath: path.join(
          'scores',
          'persisted-doc-42',
          'structural.json',
        ),
      );

      final preferenceId =
          ScoreLibraryController.preferenceIdForPersistedDocument(persisted.id);
      final location = await loader.resolveLocation(preferenceId);

      expect(location.scoreId, preferenceId);
      expect(location.displayTitle, 'Imported Sonata');
      expect(location.source, isA<FilePdfSource>());
      final fileSource = location.source as FilePdfSource;
      expect(
        fileSource.absoluteFilePath,
        path.join(temporaryDocumentsRoot.path, writtenRelativePath),
      );
      expect(File(fileSource.absoluteFilePath).existsSync(), isTrue);
    },
  );

  test('resolveLocation fails when persisted PDF file is missing', () async {
    final persisted = await scoreDocumentRepository.insert(
      title: 'Missing File Score',
      originalPdfLocalPath: path.join('scores', 'gone', 'original.pdf'),
      structuralDataLocalPath: path.join('scores', 'gone', 'structural.json'),
    );
    final preferenceId =
        ScoreLibraryController.preferenceIdForPersistedDocument(persisted.id);

    expect(
      () => loader.resolveLocation(preferenceId),
      throwsA(isA<ScoreVisualDocumentException>()),
    );
  });
}
