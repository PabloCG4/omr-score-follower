/// Typed failures from [OmrApiClient] so callers can branch without parsing
/// raw [http] exceptions.
sealed class OmrApiException implements Exception {
  const OmrApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// DNS / socket / connection refused / TLS failures before a response arrives.
final class OmrApiNetworkException extends OmrApiException {
  const OmrApiNetworkException(super.message, {this.cause});

  final Object? cause;
}

/// Request exceeded [OmrApiConfig.connectTimeout] or [OmrApiConfig.receiveTimeout].
final class OmrApiTimeoutException extends OmrApiException {
  const OmrApiTimeoutException(super.message);
}

/// Non-success HTTP status from the OMR backend.
final class OmrApiHttpException extends OmrApiException {
  const OmrApiHttpException({
    required this.statusCode,
    required String message,
    this.responseBody,
  }) : super(message);

  final int statusCode;
  final String? responseBody;
}

/// Response body was not valid JSON or failed [OmrStructuralDocument] validation.
final class OmrApiMalformedResponseException extends OmrApiException {
  const OmrApiMalformedResponseException(super.message, {this.cause});

  final Object? cause;
}
