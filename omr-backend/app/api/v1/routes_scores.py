"""Score upload routes compatible with the Flutter OmrApiClient contract."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.config import Settings, get_settings
from app.core.errors import ValidationAppError
from app.schemas.omr_structural import OmrStructuralDocument
from app.services.omr_processor import OmrProcessor, get_omr_processor
from app.services.temp_storage import TempPdfStorage

LOGGER = logging.getLogger(__name__)

router = APIRouter(tags=["omr-scores"])


@router.post(
    "/v1/omr/scores",
    response_model=OmrStructuralDocument,
    response_model_by_alias=True,
    summary="Process a PDF score into an OmrStructuralDocument",
)
async def upload_score_pdf(
    file: UploadFile = File(description="PDF score file"),
    title: str | None = Form(default=None),
    settings: Settings = Depends(get_settings),
    processor: OmrProcessor = Depends(get_omr_processor),
) -> OmrStructuralDocument:
    """Accept multipart field `file` (+ optional `title`) and return schema v1 JSON.

    Temporary PDF storage is always removed, including when processing fails.
    """
    if file.filename is None or not str(file.filename).strip():
        raise ValidationAppError("Multipart field 'file' must include a filename.")

    async with TempPdfStorage(
        file,
        max_upload_bytes=settings.max_upload_bytes,
        original_filename=file.filename,
    ) as pdf_path:
        LOGGER.info("Starting OMR processing for %s", pdf_path.name)
        document = await processor.process(pdf_path, title=title)
        LOGGER.info(
            "OMR processing complete documentId=%s title=%s",
            document.document_id,
            document.display_title,
        )
        return document
