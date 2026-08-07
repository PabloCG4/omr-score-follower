"""Application error hierarchy mapped to structured HTTP JSON responses."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class AppError(Exception):
    """Base application error with a stable machine-readable code."""

    code: str
    message: str
    http_status: int = 500

    def __str__(self) -> str:
        return f"{self.code}: {self.message}"


class ValidationAppError(AppError):
    """Client input failed validation (empty file, oversize, bad fields)."""

    def __init__(self, message: str) -> None:
        super().__init__(code="validation_error", message=message, http_status=400)


class UnsupportedMediaAppError(AppError):
    """Uploaded content is not an accepted PDF."""

    def __init__(self, message: str) -> None:
        super().__init__(
            code="unsupported_media_type",
            message=message,
            http_status=415,
        )


class ProcessingAppError(AppError):
    """OMR processing failed after a valid upload was accepted."""

    def __init__(self, message: str) -> None:
        super().__init__(code="processing_error", message=message, http_status=422)
