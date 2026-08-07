"""OMR processing abstraction, mock, and vision-backed implementation."""

from __future__ import annotations

import asyncio
import base64
import logging
import struct
import uuid
from pathlib import Path
from typing import Protocol

from app.core.config import Settings, get_settings
from app.core.errors import ProcessingAppError, ValidationAppError
from app.reconstruction.document_synthesizer import page_sizes_from_page_images
from app.reconstruction.structural_reconstruction_service import (
    StructuralReconstructionService,
)
from app.schemas.omr_structural import OmrStructuralDocument
from app.vision.pdf_rasterizer import PdfPageRasterizer
from app.vision.vision_detection_service import VisionDetectionService

LOGGER = logging.getLogger(__name__)

PITCH_CLASS_COUNT = 12


class OmrProcessor(Protocol):
    """Replaceable OMR pipeline."""

    async def process(
        self,
        pdf_path: Path,
        *,
        title: str | None,
    ) -> OmrStructuralDocument:
        """Analyze a local PDF and return a schema-v1 structural document."""


class MockOmrProcessor:
    """Simulates multi-second inference and returns a valid dummy document."""

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()

    async def process(
        self,
        pdf_path: Path,
        *,
        title: str | None,
    ) -> OmrStructuralDocument:
        delay_seconds = self.settings.mock_inference_delay_seconds
        LOGGER.info(
            "Mock OMR processing %s (delay=%.2fs)",
            pdf_path.name,
            delay_seconds,
        )
        await asyncio.sleep(delay_seconds)

        display_title = _resolve_display_title(title, pdf_path)
        frame_count = 2
        chromagram_bytes = _build_dummy_chromagram_bytes(frame_count)

        document = OmrStructuralDocument.model_validate(
            {
                "schemaVersion": 1,
                "documentId": str(uuid.uuid4()),
                "displayTitle": display_title,
                "sampleRateHz": 22050.0,
                "hopLengthSamples": 512,
                "referenceFrameCount": frame_count,
                "pages": [
                    {
                        "pageIndex": 0,
                        "widthPx": 960,
                        "heightPx": 540,
                    }
                ],
                "anchors": [
                    {
                        "frameIndex": 0.0,
                        "pageIndex": 0,
                        "xNorm": 0.12,
                        "yNorm": 0.42,
                        "measureNumber": 1,
                    },
                    {
                        "frameIndex": 1.0,
                        "pageIndex": 0,
                        "xNorm": 0.34,
                        "yNorm": 0.42,
                        "measureNumber": 2,
                    },
                ],
                "referenceChromagram": {
                    "encoding": "f32le_row_major",
                    "pitchClassCount": PITCH_CLASS_COUNT,
                    "frameCount": frame_count,
                    "dataBase64": base64.b64encode(chromagram_bytes).decode("ascii"),
                },
            }
        )
        return document


class VisionOmrProcessor:
    """Runs DINOv2+SAHI vision then structural reconstruction."""

    def __init__(
        self,
        settings: Settings | None = None,
        *,
        vision_service: VisionDetectionService | None = None,
        reconstruction_service: StructuralReconstructionService | None = None,
        rasterizer: PdfPageRasterizer | None = None,
        prefer_dinov2_hub: bool = True,
    ) -> None:
        self.settings = settings or get_settings()
        self.prefer_dinov2_hub = prefer_dinov2_hub
        self.vision_service = vision_service
        self.reconstruction_service = (
            reconstruction_service or StructuralReconstructionService()
        )
        self.rasterizer = rasterizer or PdfPageRasterizer(
            dpi=self.settings.vision_raster_dpi,
            max_pages=self.settings.vision_max_pages,
        )

    def _ensure_vision_service(self) -> VisionDetectionService:
        if self.vision_service is None:
            self.vision_service = VisionDetectionService(
                settings=self.settings,
                rasterizer=self.rasterizer,
                prefer_dinov2_hub=self.prefer_dinov2_hub,
            )
        return self.vision_service

    async def process(
        self,
        pdf_path: Path,
        *,
        title: str | None,
    ) -> OmrStructuralDocument:
        LOGGER.info("Vision OMR processing %s", pdf_path.name)

        def run_pipeline() -> OmrStructuralDocument:
            page_images = self.rasterizer.render(pdf_path)
            if not page_images:
                raise ProcessingAppError("PDF produced no rasterized pages.")
            detections = self._ensure_vision_service().detect_pages(page_images)
            if not detections:
                raise ProcessingAppError(
                    "Vision pipeline returned no symbol detections."
                )
            return self.reconstruction_service.reconstruct(
                detections,
                page_sizes_from_page_images(page_images),
                title=title,
                pdf_path=pdf_path,
            )

        try:
            return await asyncio.to_thread(run_pipeline)
        except (ProcessingAppError, ValidationAppError):
            raise
        except Exception as error:  # noqa: BLE001
            raise ProcessingAppError(f"OMR pipeline failed: {error}") from error


def get_omr_processor() -> OmrProcessor:
    """FastAPI dependency that returns the live vision-backed OMR processor."""
    return VisionOmrProcessor()


def _resolve_display_title(title: str | None, pdf_path: Path) -> str:
    if title is not None and title.strip():
        return title.strip()
    stem = pdf_path.stem.strip()
    if stem:
        return stem
    return "Untitled score"


def _build_dummy_chromagram_bytes(frame_count: int) -> bytes:
    """Encode frame_count * 12 little-endian float32 energies."""
    values: list[float] = []
    for frame_index in range(frame_count):
        for pitch_class in range(PITCH_CLASS_COUNT):
            if pitch_class == 0:
                values.append(1.0 if frame_index == 0 else 0.8)
            else:
                values.append(0.0)
    return struct.pack(f"<{len(values)}f", *values)
