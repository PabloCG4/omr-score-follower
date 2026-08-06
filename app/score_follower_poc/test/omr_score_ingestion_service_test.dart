import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:score_follower_poc/omr/omr_api_client.dart';
import 'package:score_follower_poc/omr/omr_score_ingestion_service.dart';
import 'package:score_follower_poc/omr/omr_structural_document.dart';
import 'package:score_follower_poc/omr/score_local_file_store.dart';
import 'package:score_follower_poc/persistence/database/app_database.dart';
import 'package:score_follower_poc/persistence/repositories/score_document_repository.dart';

void main() {
  late Directory temporaryDocumentsRoot;
  late Directory temporaryWorkRoot;
  late AppDatabase database;
  late ScoreDocumentRepository scoreDocumentRepository;
  late ScoreLocalFileStore fileStore;
  late FakeOmrApiClient fakeApiClient;
  late OmrScoreIngestionService ingestionService;

  setUp(() async {
    temporaryDocumentsRoot =
        await Directory.systemTemp.createTemp('omr_ingest_docs_');
    temporaryWorkRoot =
        await Directory.systemTemp.createTemp('omr_ingest_work_');

    database = AppDatabase(NativeDatabase.memory());
    scoreDocumentRepository = ScoreDocumentRepository(database);
    fileStore = ScoreLocalFileStore(
      applicationDocumentsDirectoryResolver: () async => temporaryDocumentsRoot,
    );
    fakeApiClient = FakeOmrApiClient(
      documentToReturn: buildDummyStructuralDocument(),
    );
    ingestionService = OmrScoreIngestionService(
      apiClient: fakeApiClient,
      fileStore: fileStore,
      scoreDocumentRepository: scoreDocumentRepository,
    );
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDocumentsRoot.exists()) {
      await temporaryDocumentsRoot.delete(recursive: true);
    }
    if (await temporaryWorkRoot.exists()) {
      await temporaryWorkRoot.delete(recursive: true);
    }
  });

  test(
    'ingestPdfScore writes local PDF/JSON and inserts a score_documents row',
    () async {
      const fakePdfBytes = <int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34];
      final fakePdfFile = File(
        path.join(temporaryWorkRoot.path, 'mock_score.pdf'),
      );
      await fakePdfFile.writeAsBytes(fakePdfBytes, flush: true);

      final result = await ingestionService.ingestPdfScore(
        pdfFile: fakePdfFile,
        displayTitle: 'Ingested Mock Score',
      );

      expect(fakeApiClient.uploadCallCount, 1);
      expect(fakeApiClient.lastUploadedPdfPath, fakePdfFile.path);
      expect(fakeApiClient.lastDisplayTitle, 'Ingested Mock Score');

      expect(result.persistedDocument.title, 'Ingested Mock Score');
      expect(result.persistedDocument.id, greaterThan(0));
      expect(
        result.persistedDocument.originalPdfLocalPath,
        path.join('scores', 'mock-doc-001', 'original.pdf'),
      );
      expect(
        result.persistedDocument.structuralDataLocalPath,
        path.join('scores', 'mock-doc-001', 'structural.json'),
      );

      final absolutePdf = await fileStore.resolveAbsoluteFile(
        result.persistedDocument.originalPdfLocalPath,
      );
      final absoluteJson = await fileStore.resolveAbsoluteFile(
        result.persistedDocument.structuralDataLocalPath,
      );

      expect(await absolutePdf.exists(), isTrue);
      expect(await absolutePdf.readAsBytes(), fakePdfBytes);
      expect(await absoluteJson.exists(), isTrue);

      final parsedStructural = OmrStructuralDocument.parseJsonString(
        await absoluteJson.readAsString(),
      );
      expect(parsedStructural.documentId, 'mock-doc-001');
      expect(parsedStructural.displayTitle, 'Mock Four Chords');
      expect(parsedStructural.referenceFrameCount, 2);
      expect(parsedStructural.pages, hasLength(1));
      expect(parsedStructural.anchors, hasLength(2));

      final rows = await scoreDocumentRepository.listAll();
      expect(rows, hasLength(1));
      expect(rows.single.id, result.persistedDocument.id);
      expect(rows.single.title, 'Ingested Mock Score');
      expect(
        rows.single.originalPdfLocalPath,
        result.persistedDocument.originalPdfLocalPath,
      );
      expect(
        rows.single.structuralDataLocalPath,
        result.persistedDocument.structuralDataLocalPath,
      );
    },
  );
}

/// Test double that returns a fixed [OmrStructuralDocument] without HTTP.
final class FakeOmrApiClient implements OmrScoreUploadClient {
  FakeOmrApiClient({required this.documentToReturn});

  final OmrStructuralDocument documentToReturn;
  int uploadCallCount = 0;
  String? lastUploadedPdfPath;
  String? lastDisplayTitle;

  @override
  Future<OmrStructuralDocument> uploadScorePdf({
    required File pdfFile,
    String? displayTitle,
  }) async {
    uploadCallCount += 1;
    lastUploadedPdfPath = pdfFile.path;
    lastDisplayTitle = displayTitle;
    return documentToReturn;
  }
}

OmrStructuralDocument buildDummyStructuralDocument() {
  const frameCount = 2;
  final energies = Float32List(frameCount * omrPitchClassCount);
  energies[0] = 1.0;
  energies[omrPitchClassCount] = 0.8;

  final rawBytes = Uint8List(energies.length * 4);
  final byteData = ByteData.sublistView(rawBytes);
  for (var floatIndex = 0; floatIndex < energies.length; floatIndex++) {
    byteData.setFloat32(floatIndex * 4, energies[floatIndex], Endian.little);
  }

  final chromagramJson = <String, dynamic>{
    'encoding': omrChromagramEncodingF32LeRowMajor,
    'pitchClassCount': omrPitchClassCount,
    'frameCount': frameCount,
    'dataBase64': base64Encode(rawBytes),
  };

  return OmrStructuralDocument.fromJson(<String, dynamic>{
    'schemaVersion': omrStructuralDocumentSchemaVersion,
    'documentId': 'mock-doc-001',
    'displayTitle': 'Mock Four Chords',
    'sampleRateHz': 22050.0,
    'hopLengthSamples': 512,
    'referenceFrameCount': frameCount,
    'pages': [
      <String, dynamic>{
        'pageIndex': 0,
        'widthPx': 960,
        'heightPx': 540,
      },
    ],
    'anchors': [
      <String, dynamic>{
        'frameIndex': 0.0,
        'pageIndex': 0,
        'xNorm': 0.12,
        'yNorm': 0.42,
        'measureNumber': 1,
      },
      <String, dynamic>{
        'frameIndex': 1.0,
        'pageIndex': 0,
        'xNorm': 0.34,
        'yNorm': 0.42,
        'measureNumber': 2,
      },
    ],
    'referenceChromagram': chromagramJson,
  });
}
