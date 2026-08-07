"""OMR processing abstraction and mock implementation (no vision models yet)."""

from __future__ import annotations

import asyncio
import base64
import logging
import struct
import uuid
from pathlib import Path
from typing import Protocol

from app.core.config import Settings, get_settings
from app.schemas.omr_structural import OmrStructuralDocument

LOGGER = logging.getLogger(__name__)

PITCH_CLASS_COUNT = 12


class OmrProcessor(Protocol):
    """Replaceable OMR pipeline; DINOv2/SAHI will implement this later."""

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


def get_omr_processor() -> OmrProcessor:
    """FastAPI dependency that returns the current OMR processor implementation."""
    return MockOmrProcessor()


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
