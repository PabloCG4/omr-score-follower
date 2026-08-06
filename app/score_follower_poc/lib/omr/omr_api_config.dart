/// Configuration for the external OMR processing HTTP API.
final class OmrApiConfig {
  const OmrApiConfig({
    this.baseUrl = defaultBaseUrl,
    this.processPath = defaultProcessPath,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 300),
  });

  /// Placeholder host used until a real backend URL is injected by the host app.
  static const String defaultBaseUrl = 'https://api.example.com';

  /// Multipart upload endpoint path (appended to [baseUrl]).
  static const String defaultProcessPath = '/v1/omr/scores';

  /// Origin without a trailing slash (e.g. `https://api.example.com`).
  final String baseUrl;

  /// Path beginning with `/` for `POST` multipart PDF upload.
  final String processPath;

  /// Upper bound for establishing the TCP/TLS connection.
  final Duration connectTimeout;

  /// Upper bound for waiting on the OMR response body (heavy multi-page jobs).
  final Duration receiveTimeout;

  /// Absolute URL for the score-upload endpoint.
  Uri get uploadUri {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath =
        processPath.startsWith('/') ? processPath : '/$processPath';
    return Uri.parse('$normalizedBase$normalizedPath');
  }
}
