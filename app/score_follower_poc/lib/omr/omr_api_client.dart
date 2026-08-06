import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'omr_api_config.dart';
import 'omr_api_exceptions.dart';
import 'omr_structural_document.dart';

/// Port used by [OmrScoreIngestionService] so production HTTP and test fakes
/// share one upload contract.
abstract interface class OmrScoreUploadClient {
  Future<OmrStructuralDocument> uploadScorePdf({
    required File pdfFile,
    String? displayTitle,
  });
}

/// Production HTTP client for uploading a local PDF to the external OMR API
/// and receiving a validated [OmrStructuralDocument].
///
/// Does not write disk or SQLite; [OmrScoreIngestionService] owns persistence.
final class OmrApiClient implements OmrScoreUploadClient {
  OmrApiClient({
    OmrApiConfig? config,
    http.Client? httpClient,
  })  : config = config ?? const OmrApiConfig(),
        httpClient = httpClient ?? http.Client(),
        ownsHttpClient = httpClient == null;

  final OmrApiConfig config;
  final http.Client httpClient;
  final bool ownsHttpClient;

  /// Uploads [pdfFile] as `multipart/form-data` field `file`, optionally with
  /// form field `title`, and returns a validated structural document.
  @override
  Future<OmrStructuralDocument> uploadScorePdf({
    required File pdfFile,
    String? displayTitle,
  }) async {
    if (!await pdfFile.exists()) {
      throw OmrApiNetworkException(
        'PDF file does not exist: ${pdfFile.path}',
      );
    }

    final fileLength = await pdfFile.length();
    if (fileLength <= 0) {
      throw OmrApiNetworkException('PDF file is empty: ${pdfFile.path}');
    }

    final request = http.MultipartRequest('POST', config.uploadUri);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        pdfFile.path,
        filename: _fileNameFromPath(pdfFile.path),
      ),
    );
    final trimmedTitle = displayTitle?.trim();
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      request.fields['title'] = trimmedTitle;
    }

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await httpClient
          .send(request)
          .timeout(config.connectTimeout + config.receiveTimeout);
    } on TimeoutException {
      throw const OmrApiTimeoutException(
        'OMR upload timed out waiting for a response.',
      );
    } on SocketException catch (error) {
      throw OmrApiNetworkException(
        'Network failure while uploading PDF: ${error.message}',
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw OmrApiNetworkException(
        'HTTP client failure while uploading PDF: ${error.message}',
        cause: error,
      );
    } on IOException catch (error) {
      throw OmrApiNetworkException(
        'I/O failure while uploading PDF: $error',
        cause: error,
      );
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(streamedResponse)
          .timeout(config.receiveTimeout);
    } on TimeoutException {
      throw const OmrApiTimeoutException(
        'OMR upload timed out while reading the response body.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OmrApiHttpException(
        statusCode: response.statusCode,
        message:
            'OMR API returned HTTP ${response.statusCode} for ${config.uploadUri}.',
        responseBody: _truncateBody(response.body),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw OmrApiMalformedResponseException(
        'OMR API response is not valid JSON.',
        cause: error,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const OmrApiMalformedResponseException(
        'OMR API response root must be a JSON object.',
      );
    }

    try {
      return OmrStructuralDocument.fromJson(decoded);
    } on OmrStructuralDocumentFormatException catch (error) {
      throw OmrApiMalformedResponseException(
        'OMR API JSON failed structural validation: ${error.message}',
        cause: error,
      );
    }
  }

  /// Releases the underlying [http.Client] when this client created it.
  void dispose() {
    if (ownsHttpClient) {
      httpClient.close();
    }
  }

  static String _fileNameFromPath(String path) {
    final separatorIndex = path.replaceAll('\\', '/').lastIndexOf('/');
    if (separatorIndex < 0 || separatorIndex + 1 >= path.length) {
      return 'score.pdf';
    }
    return path.substring(separatorIndex + 1);
  }

  static String? _truncateBody(String body) {
    if (body.isEmpty) {
      return null;
    }
    const maxLength = 2048;
    if (body.length <= maxLength) {
      return body;
    }
    return '${body.substring(0, maxLength)}…';
  }
}
