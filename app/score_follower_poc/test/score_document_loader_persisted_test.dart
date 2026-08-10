import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:score_follower_poc/omr/omr_structural_document.dart';
import 'package:score_follower_poc/omr/score_local_file_store.dart';
import 'package:score_follower_poc/persistence/database/app_database.dart';
import 'package:score_follower_poc/persistence/repositories/score_document_repository.dart';
import 'package:score_follower_poc/score/score_document_loader.dart';
import 'package:score_follower_poc/score/score_library_controller.dart';

void main() {
  late Directory temporaryDocumentsRoot;
  late AppDatabase database;
  late ScoreDocumentRepository scoreDocumentRepository;
  late ScoreLocalFileStore fileStore;
  late ScoreDocumentLoader loader;

  setUp(() async {
    temporaryDocumentsRoot =
        await Directory.systemTemp.createTemp('score_doc_loader_');
    database = AppDatabase(NativeDatabase.memory());
    scoreDocumentRepository = ScoreDocumentRepository(database);
    fileStore = ScoreLocalFileStore(
      applicationDocumentsDirectoryResolver: () async => temporaryDocumentsRoot,
    );
    loader = ScoreDocumentLoader(
      scoreDocumentRepository: scoreDocumentRepository,
      fileStore: fileStore,
    );
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDocumentsRoot.exists()) {
      await temporaryDocumentsRoot.delete(recursive: true);
    }
  });

  test(
    'loadFromPersistedStructural reads structural.json and adapts ScoreDocument',
    () async {
      final structural = buildPersistedStructuralFixture();
      final jsonRelativePath = await fileStore.writeStructuralJson(
        documentId: 'persisted-doc-99',
        jsonText: structural.toPrettyJsonString(),
      );
      final pdfRelativePath = await fileStore.writeOriginalPdf(
        documentId: 'persisted-doc-99',
        pdfBytes: const <int>[0x25, 0x50, 0x44, 0x46],
      );
      final persisted = await scoreDocumentRepository.insert(
        title: structural.displayTitle,
        originalPdfLocalPath: pdfRelativePath,
        structuralDataLocalPath: jsonRelativePath,
      );

      final preferenceId =
          ScoreLibraryController.preferenceIdForPersistedDocument(persisted.id);
      final scoreDocument = await loader.loadForScoreId(preferenceId);

      expect(scoreDocument.scoreId, preferenceId);
      expect(scoreDocument.displayTitle, 'Persisted Loader Fixture');
      expect(scoreDocument.pages, hasLength(1));
      expect(scoreDocument.anchors, hasLength(2));
      expect(
        scoreDocument.referenceChromagramRowMajor.length,
        2 * omrPitchClassCount,
      );
      expect(scoreDocument.referenceFrameCount, greaterThan(0));
      expect(
        scoreDocument.referenceChromagramRowMajor,
        orderedEquals(structural.referenceChromagram.decodedRowMajor),
      );

      final absoluteJson = await fileStore.resolveAbsoluteFile(jsonRelativePath);
      expect(absoluteJson.path, contains(path.join('scores', 'persisted-doc-99')));
      expect(await absoluteJson.exists(), isTrue);
    },
  );

  test('loadFromPersistedStructural fails when structural file is missing',
      () async {
    final persisted = await scoreDocumentRepository.insert(
      title: 'Missing Structural',
      originalPdfLocalPath: path.join('scores', 'gone', 'original.pdf'),
      structuralDataLocalPath: path.join('scores', 'gone', 'structural.json'),
    );
    final preferenceId =
        ScoreLibraryController.preferenceIdForPersistedDocument(persisted.id);

    expect(
      () => loader.loadForScoreId(preferenceId),
      throwsA(isA<ScoreDocumentLoadException>()),
    );
  });
}

OmrStructuralDocument buildPersistedStructuralFixture() {
  const frameCount = 2;
  final energies = Float32List(frameCount * omrPitchClassCount);
  energies[0] = 1.0;
  energies[omrPitchClassCount] = 0.5;

  final rawBytes = Uint8List(energies.length * 4);
  final byteData = ByteData.sublistView(rawBytes);
  for (var floatIndex = 0; floatIndex < energies.length; floatIndex++) {
    byteData.setFloat32(floatIndex * 4, energies[floatIndex], Endian.little);
  }

  return OmrStructuralDocument.fromJson(<String, dynamic>{
    'schemaVersion': omrStructuralDocumentSchemaVersion,
    'documentId': 'persisted-doc-99',
    'displayTitle': 'Persisted Loader Fixture',
    'sampleRateHz': 22050.0,
    'hopLengthSamples': 512,
    'referenceFrameCount': frameCount,
    'pages': [
      <String, dynamic>{
        'pageIndex': 0,
        'widthPx': 800,
        'heightPx': 600,
      },
    ],
    'anchors': [
      <String, dynamic>{
        'frameIndex': 0.0,
        'pageIndex': 0,
        'xNorm': 0.1,
        'yNorm': 0.4,
        'measureNumber': 1,
      },
      <String, dynamic>{
        'frameIndex': 1.0,
        'pageIndex': 0,
        'xNorm': 0.6,
        'yNorm': 0.4,
        'measureNumber': 2,
      },
    ],
    'referenceChromagram': <String, dynamic>{
      'encoding': omrChromagramEncodingF32LeRowMajor,
      'pitchClassCount': omrPitchClassCount,
      'frameCount': frameCount,
      'dataBase64': base64Encode(rawBytes),
    },
  });
}
