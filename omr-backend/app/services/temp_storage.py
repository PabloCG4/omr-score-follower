"""Guaranteed-cleanup temporary storage for uploaded PDF bytes."""

from __future__ import annotations

import logging
import shutil
import tempfile
from pathlib import Path
from types import TracebackType

from fastapi import UploadFile

from app.core.errors import UnsupportedMediaAppError, ValidationAppError

LOGGER = logging.getLogger(__name__)

PDF_MAGIC = b"%PDF"
CHUNK_SIZE_BYTES = 1024 * 1024


class TempPdfStorage:
    """Async context manager that streams an upload to disk and always deletes it.

    Usage::

        async with TempPdfStorage(upload, max_bytes=...) as pdf_path:
            ...
        # pdf_path and its parent temp directory are gone
    """

    def __init__(
        self,
        upload: UploadFile,
        *,
        max_upload_bytes: int,
        original_filename: str | None = None,
    ) -> None:
        self.upload = upload
        self.max_upload_bytes = max_upload_bytes
        self.original_filename = original_filename or upload.filename or "upload.pdf"
        self.temp_directory: Path | None = None
        self.pdf_path: Path | None = None

    async def __aenter__(self) -> Path:
        self._validate_filename_extension(self.original_filename)

        self.temp_directory = Path(tempfile.mkdtemp(prefix="omr_upload_"))
        safe_name = Path(self.original_filename).name
        if not safe_name.lower().endswith(".pdf"):
            safe_name = f"{safe_name}.pdf"
        self.pdf_path = self.temp_directory / safe_name

        total_bytes = 0
        magic_buffer = bytearray()
        try:
            with self.pdf_path.open("wb") as output_file:
                while True:
                    chunk = await self.upload.read(CHUNK_SIZE_BYTES)
                    if not chunk:
                        break
                    total_bytes += len(chunk)
                    if total_bytes > self.max_upload_bytes:
                        raise ValidationAppError(
                            f"PDF exceeds maximum upload size of "
                            f"{self.max_upload_bytes} bytes."
                        )
                    if len(magic_buffer) < len(PDF_MAGIC):
                        remaining = len(PDF_MAGIC) - len(magic_buffer)
                        magic_buffer.extend(chunk[:remaining])
                    output_file.write(chunk)
        except Exception:
            await self._cleanup()
            raise

        if total_bytes == 0:
            await self._cleanup()
            raise ValidationAppError("Uploaded PDF is empty.")

        if bytes(magic_buffer[: len(PDF_MAGIC)]) != PDF_MAGIC:
            await self._cleanup()
            raise UnsupportedMediaAppError(
                "Uploaded file is not a PDF (missing %PDF header)."
            )

        LOGGER.info(
            "Stored upload %s (%s bytes) at %s",
            self.original_filename,
            total_bytes,
            self.pdf_path,
        )
        return self.pdf_path

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        await self._cleanup()

    async def _cleanup(self) -> None:
        directory = self.temp_directory
        self.pdf_path = None
        self.temp_directory = None
        if directory is None:
            return
        try:
            shutil.rmtree(directory, ignore_errors=False)
            LOGGER.debug("Removed temp upload directory %s", directory)
        except FileNotFoundError:
            return
        except OSError as error:
            LOGGER.warning("Failed to remove temp upload directory %s: %s", directory, error)

    @staticmethod
    def _validate_filename_extension(filename: str) -> None:
        lower_name = filename.lower()
        if not lower_name.endswith(".pdf"):
            raise UnsupportedMediaAppError(
                "Only PDF uploads are accepted (filename must end with .pdf)."
            )
