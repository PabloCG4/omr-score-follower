import 'dart:convert';
import 'dart:typed_data';

/// Supported major version of the OMR structural JSON contract.
const int omrStructuralDocumentSchemaVersion = 1;

/// Pitch-class count in the reference chromagram (C .. B).
const int omrPitchClassCount = 12;

/// Encoding tag for little-endian row-major float32 chromagram payloads.
const String omrChromagramEncodingF32LeRowMajor = 'f32le_row_major';

/// Thrown when an OMR structural JSON document fails contract validation.
final class OmrStructuralDocumentFormatException implements Exception {
  OmrStructuralDocumentFormatException(this.message);

  final String message;

  @override
  String toString() => 'OmrStructuralDocumentFormatException: $message';
}

/// One page's geometry for page-normalized cursor mapping.
final class OmrStructuralPage {
  const OmrStructuralPage({
    required this.pageIndex,
    required this.widthPx,
    required this.heightPx,
  });

  final int pageIndex;
  final int widthPx;
  final int heightPx;

  double get aspectRatio => widthPx / heightPx;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pageIndex': pageIndex,
      'widthPx': widthPx,
      'heightPx': heightPx,
    };
  }

  factory OmrStructuralPage.fromJson(Map<String, dynamic> json) {
    return OmrStructuralPage(
      pageIndex: _requireInt(json, 'pageIndex'),
      widthPx: _requireInt(json, 'widthPx'),
      heightPx: _requireInt(json, 'heightPx'),
    );
  }
}

/// Frame → page-normalized cursor anchor (same semantics as demo timeline_map).
final class OmrStructuralAnchor {
  const OmrStructuralAnchor({
    required this.frameIndex,
    required this.pageIndex,
    required this.xNorm,
    required this.yNorm,
    required this.measureNumber,
  });

  final double frameIndex;
  final int pageIndex;
  final double xNorm;
  final double yNorm;
  final int measureNumber;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'frameIndex': frameIndex,
      'pageIndex': pageIndex,
      'xNorm': xNorm,
      'yNorm': yNorm,
      'measureNumber': measureNumber,
    };
  }

  factory OmrStructuralAnchor.fromJson(Map<String, dynamic> json) {
    return OmrStructuralAnchor(
      frameIndex: _requireDouble(json, 'frameIndex'),
      pageIndex: _requireInt(json, 'pageIndex'),
      xNorm: _requireDouble(json, 'xNorm'),
      yNorm: _requireDouble(json, 'yNorm'),
      measureNumber: _requireInt(json, 'measureNumber'),
    );
  }
}

/// Optional symbolic note onset for future UX / Strict mode (not used by DTW yet).
final class OmrStructuralNoteEvent {
  const OmrStructuralNoteEvent({
    required this.midiPitch,
    required this.onsetFrame,
    required this.durationFrames,
    this.pageIndex,
    this.xNorm,
    this.yNorm,
  });

  final int midiPitch;
  final double onsetFrame;
  final double durationFrames;
  final int? pageIndex;
  final double? xNorm;
  final double? yNorm;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'midiPitch': midiPitch,
      'onsetFrame': onsetFrame,
      'durationFrames': durationFrames,
      if (pageIndex != null) 'pageIndex': pageIndex,
      if (xNorm != null) 'xNorm': xNorm,
      if (yNorm != null) 'yNorm': yNorm,
    };
  }

  factory OmrStructuralNoteEvent.fromJson(Map<String, dynamic> json) {
    return OmrStructuralNoteEvent(
      midiPitch: _requireInt(json, 'midiPitch'),
      onsetFrame: _requireDouble(json, 'onsetFrame'),
      durationFrames: _requireDouble(json, 'durationFrames'),
      pageIndex: json.containsKey('pageIndex') ? _requireInt(json, 'pageIndex') : null,
      xNorm: json.containsKey('xNorm') ? _requireDouble(json, 'xNorm') : null,
      yNorm: json.containsKey('yNorm') ? _requireDouble(json, 'yNorm') : null,
    );
  }
}

/// Reference chromagram payload consumed by [ScoreFollowerEngine.loadReferenceChromagram].
final class OmrReferenceChromagram {
  const OmrReferenceChromagram({
    required this.encoding,
    required this.pitchClassCount,
    required this.frameCount,
    required this.dataBase64,
    required this.decodedRowMajor,
  });

  final String encoding;
  final int pitchClassCount;
  final int frameCount;
  final String dataBase64;

  /// Decoded little-endian float32 row-major energies (`frameCount * 12`).
  final Float32List decodedRowMajor;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'encoding': encoding,
      'pitchClassCount': pitchClassCount,
      'frameCount': frameCount,
      'dataBase64': dataBase64,
    };
  }

  factory OmrReferenceChromagram.fromJson(Map<String, dynamic> json) {
    final encoding = _requireString(json, 'encoding');
    final pitchClassCount = _requireInt(json, 'pitchClassCount');
    final frameCount = _requireInt(json, 'frameCount');
    final dataBase64 = _requireString(json, 'dataBase64');

    if (encoding != omrChromagramEncodingF32LeRowMajor) {
      throw OmrStructuralDocumentFormatException(
        'referenceChromagram.encoding must be "$omrChromagramEncodingF32LeRowMajor".',
      );
    }
    if (pitchClassCount != omrPitchClassCount) {
      throw OmrStructuralDocumentFormatException(
        'referenceChromagram.pitchClassCount must be $omrPitchClassCount.',
      );
    }
    if (frameCount <= 0) {
      throw OmrStructuralDocumentFormatException(
        'referenceChromagram.frameCount must be positive.',
      );
    }

    final Uint8List rawBytes;
    try {
      rawBytes = base64Decode(dataBase64);
    } on FormatException catch (error) {
      throw OmrStructuralDocumentFormatException(
        'referenceChromagram.dataBase64 is not valid Base64: $error',
      );
    }

    final expectedByteLength = frameCount * omrPitchClassCount * 4;
    if (rawBytes.length != expectedByteLength) {
      throw OmrStructuralDocumentFormatException(
        'referenceChromagram.dataBase64 decodes to ${rawBytes.length} bytes; '
        'expected $expectedByteLength (frameCount * 12 * 4).',
      );
    }

    final byteData = ByteData.sublistView(rawBytes);
    final decoded = Float32List(frameCount * omrPitchClassCount);
    for (var floatIndex = 0; floatIndex < decoded.length; floatIndex++) {
      decoded[floatIndex] = byteData.getFloat32(floatIndex * 4, Endian.little);
    }

    return OmrReferenceChromagram(
      encoding: encoding,
      pitchClassCount: pitchClassCount,
      frameCount: frameCount,
      dataBase64: dataBase64,
      decodedRowMajor: decoded,
    );
  }
}

/// Production OMR structural document (schemaVersion 1).
///
/// Consolidates demo manifest + timeline_map + reference chromagram into one
/// JSON file written to [PersistedScoreDocument.structuralDataLocalPath].
final class OmrStructuralDocument {
  const OmrStructuralDocument({
    required this.schemaVersion,
    required this.displayTitle,
    required this.sampleRateHz,
    required this.hopLengthSamples,
    required this.referenceFrameCount,
    required this.pages,
    required this.anchors,
    required this.referenceChromagram,
    this.documentId,
    this.noteEvents = const <OmrStructuralNoteEvent>[],
  });

  final int schemaVersion;
  final String? documentId;
  final String displayTitle;
  final double sampleRateHz;
  final int hopLengthSamples;
  final int referenceFrameCount;
  final List<OmrStructuralPage> pages;
  final List<OmrStructuralAnchor> anchors;
  final OmrReferenceChromagram referenceChromagram;
  final List<OmrStructuralNoteEvent> noteEvents;

  /// Parses and validates a decoded JSON object.
  factory OmrStructuralDocument.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _requireInt(json, 'schemaVersion');
    if (schemaVersion != omrStructuralDocumentSchemaVersion) {
      throw OmrStructuralDocumentFormatException(
        'Unsupported schemaVersion $schemaVersion; '
        'expected $omrStructuralDocumentSchemaVersion.',
      );
    }

    final documentId = json.containsKey('documentId')
        ? _requireString(json, 'documentId')
        : null;
    final displayTitle = _requireString(json, 'displayTitle');
    final sampleRateHz = _requireDouble(json, 'sampleRateHz');
    final hopLengthSamples = _requireInt(json, 'hopLengthSamples');
    final referenceFrameCount = _requireInt(json, 'referenceFrameCount');

    final pagesJson = _requireList(json, 'pages');
    final pages = <OmrStructuralPage>[
      for (final entry in pagesJson)
        OmrStructuralPage.fromJson(_requireObject(entry, 'pages[]')),
    ];

    final anchorsJson = _requireList(json, 'anchors');
    final anchors = <OmrStructuralAnchor>[
      for (final entry in anchorsJson)
        OmrStructuralAnchor.fromJson(_requireObject(entry, 'anchors[]')),
    ];

    final chromagramJson = _requireObject(
      json['referenceChromagram'],
      'referenceChromagram',
    );
    final referenceChromagram = OmrReferenceChromagram.fromJson(chromagramJson);

    final noteEvents = <OmrStructuralNoteEvent>[];
    if (json.containsKey('noteEvents')) {
      final noteEventsJson = _requireList(json, 'noteEvents');
      for (final entry in noteEventsJson) {
        noteEvents.add(
          OmrStructuralNoteEvent.fromJson(_requireObject(entry, 'noteEvents[]')),
        );
      }
    }

    final document = OmrStructuralDocument(
      schemaVersion: schemaVersion,
      documentId: documentId,
      displayTitle: displayTitle,
      sampleRateHz: sampleRateHz,
      hopLengthSamples: hopLengthSamples,
      referenceFrameCount: referenceFrameCount,
      pages: List<OmrStructuralPage>.unmodifiable(pages),
      anchors: List<OmrStructuralAnchor>.unmodifiable(anchors),
      referenceChromagram: referenceChromagram,
      noteEvents: List<OmrStructuralNoteEvent>.unmodifiable(noteEvents),
    );
    document.validate();
    return document;
  }

  /// Parses UTF-8 JSON text into a validated document.
  factory OmrStructuralDocument.parseJsonString(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw OmrStructuralDocumentFormatException(
        'Structural JSON is not valid JSON: $error',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw OmrStructuralDocumentFormatException(
        'Structural JSON root must be an object.',
      );
    }
    return OmrStructuralDocument.fromJson(decoded);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      if (documentId != null) 'documentId': documentId,
      'displayTitle': displayTitle,
      'sampleRateHz': sampleRateHz,
      'hopLengthSamples': hopLengthSamples,
      'referenceFrameCount': referenceFrameCount,
      'pages': [for (final page in pages) page.toJson()],
      'anchors': [for (final anchor in anchors) anchor.toJson()],
      'referenceChromagram': referenceChromagram.toJson(),
      if (noteEvents.isNotEmpty)
        'noteEvents': [for (final event in noteEvents) event.toJson()],
    };
  }

  /// Encodes this document as pretty-printed JSON for local persistence.
  String toPrettyJsonString() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  /// Enforces invariants required by a future filesystem score loader / DTW path.
  void validate() {
    if (displayTitle.trim().isEmpty) {
      throw OmrStructuralDocumentFormatException('displayTitle must be non-empty.');
    }
    if (!(sampleRateHz > 0.0) || !sampleRateHz.isFinite) {
      throw OmrStructuralDocumentFormatException('sampleRateHz must be finite and positive.');
    }
    if (hopLengthSamples <= 0) {
      throw OmrStructuralDocumentFormatException('hopLengthSamples must be positive.');
    }
    if (referenceFrameCount <= 0) {
      throw OmrStructuralDocumentFormatException('referenceFrameCount must be positive.');
    }
    if (pages.isEmpty) {
      throw OmrStructuralDocumentFormatException('pages must be non-empty.');
    }
    if (anchors.isEmpty) {
      throw OmrStructuralDocumentFormatException('anchors must be non-empty.');
    }
    if (referenceChromagram.frameCount != referenceFrameCount) {
      throw OmrStructuralDocumentFormatException(
        'referenceChromagram.frameCount (${referenceChromagram.frameCount}) '
        'must equal referenceFrameCount ($referenceFrameCount).',
      );
    }

    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      if (page.pageIndex != index) {
        throw OmrStructuralDocumentFormatException(
          'pages must be contiguous from 0; expected pageIndex $index, '
          'got ${page.pageIndex}.',
        );
      }
      if (page.widthPx <= 0 || page.heightPx <= 0) {
        throw OmrStructuralDocumentFormatException(
          'page $index widthPx/heightPx must be positive.',
        );
      }
    }

    final pageCount = pages.length;
    for (var index = 0; index < anchors.length; index++) {
      final anchor = anchors[index];
      if (anchor.pageIndex < 0 || anchor.pageIndex >= pageCount) {
        throw OmrStructuralDocumentFormatException(
          'anchors[$index].pageIndex ${anchor.pageIndex} is out of range '
          '[0, $pageCount).',
        );
      }
      if (anchor.xNorm < 0.0 || anchor.xNorm > 1.0 ||
          anchor.yNorm < 0.0 || anchor.yNorm > 1.0) {
        throw OmrStructuralDocumentFormatException(
          'anchors[$index] xNorm/yNorm must be in [0, 1].',
        );
      }
      if (!anchor.frameIndex.isFinite) {
        throw OmrStructuralDocumentFormatException(
          'anchors[$index].frameIndex must be finite.',
        );
      }
      if (index > 0 && anchor.frameIndex < anchors[index - 1].frameIndex) {
        throw OmrStructuralDocumentFormatException(
          'anchors must be sorted by frameIndex ascending (violation at index $index).',
        );
      }
    }

    final anchorsByPage = <int, List<OmrStructuralAnchor>>{};
    for (final anchor in anchors) {
      anchorsByPage.putIfAbsent(anchor.pageIndex, () => <OmrStructuralAnchor>[]).add(anchor);
    }
    for (final entry in anchorsByPage.entries) {
      final pageAnchors = entry.value;
      for (var index = 1; index < pageAnchors.length; index++) {
        final previous = pageAnchors[index - 1];
        final current = pageAnchors[index];
        if (current.xNorm + 1e-9 < previous.xNorm &&
            (current.yNorm - previous.yNorm).abs() <= 1e-4) {
          throw OmrStructuralDocumentFormatException(
            'page ${entry.key}: within a system, xNorm must be non-decreasing '
            'with frameIndex (violation at frame ${current.frameIndex}).',
          );
        }
      }
    }

    for (var index = 0; index < noteEvents.length; index++) {
      final event = noteEvents[index];
      if (event.midiPitch < 0 || event.midiPitch > 127) {
        throw OmrStructuralDocumentFormatException(
          'noteEvents[$index].midiPitch must be in 0..127.',
        );
      }
      if (!(event.onsetFrame >= 0.0) || !event.onsetFrame.isFinite) {
        throw OmrStructuralDocumentFormatException(
          'noteEvents[$index].onsetFrame must be finite and non-negative.',
        );
      }
      if (!(event.durationFrames > 0.0) || !event.durationFrames.isFinite) {
        throw OmrStructuralDocumentFormatException(
          'noteEvents[$index].durationFrames must be finite and positive.',
        );
      }
      if (event.pageIndex != null &&
          (event.pageIndex! < 0 || event.pageIndex! >= pageCount)) {
        throw OmrStructuralDocumentFormatException(
          'noteEvents[$index].pageIndex is out of range.',
        );
      }
      if (event.xNorm != null && (event.xNorm! < 0.0 || event.xNorm! > 1.0)) {
        throw OmrStructuralDocumentFormatException(
          'noteEvents[$index].xNorm must be in [0, 1].',
        );
      }
      if (event.yNorm != null && (event.yNorm! < 0.0 || event.yNorm! > 1.0)) {
        throw OmrStructuralDocumentFormatException(
          'noteEvents[$index].yNorm must be in [0, 1].',
        );
      }
    }
  }
}

int _requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw OmrStructuralDocumentFormatException('"$key" must be an integer.');
}

double _requireDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) {
    return value.toDouble();
  }
  throw OmrStructuralDocumentFormatException('"$key" must be a number.');
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw OmrStructuralDocumentFormatException('"$key" must be a non-empty string.');
}

List<dynamic> _requireList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is List<dynamic>) {
    return value;
  }
  throw OmrStructuralDocumentFormatException('"$key" must be an array.');
}

Map<String, dynamic> _requireObject(Object? value, String label) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw OmrStructuralDocumentFormatException('"$label" must be an object.');
}
