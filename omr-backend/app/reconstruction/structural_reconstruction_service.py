"""Orchestrates staff assembly, pitch/rhythm reconstruction, and document output."""

from __future__ import annotations

import logging
from pathlib import Path

from app.core.errors import ProcessingAppError, ValidationAppError
from app.reconstruction.document_synthesizer import (
    PageSize,
    page_sizes_from_page_images,
    synthesize_document,
)
from app.reconstruction.staff_system import assemble_staff_systems
from app.reconstruction.timeline_builder import build_full_timeline
from app.schemas.omr_structural import OmrStructuralDocument
from app.vision.detections import PageImage, RawDetection

LOGGER = logging.getLogger(__name__)


class StructuralReconstructionService:
    """Translate raw vision detections into a schema-v1 structural document."""

    def reconstruct(
        self,
        detections: list[RawDetection],
        pages: list[PageSize] | list[PageImage],
        *,
        title: str | None,
        pdf_path: Path | None = None,
    ) -> OmrStructuralDocument:
        page_sizes = self._normalize_pages(pages)
        if not page_sizes:
            raise ValidationAppError("Reconstruction requires at least one page.")

        systems = assemble_staff_systems(detections)
        if not systems:
            raise ProcessingAppError(
                "Unable to assemble staff systems from detections "
                "(no staff or clef symbols found)."
            )

        notes = build_full_timeline(systems)
        display_title = _resolve_display_title(title, pdf_path)
        LOGGER.info(
            "Reconstructed %s note events across %s staff systems",
            len(notes),
            len(systems),
        )
        return synthesize_document(
            notes=notes,
            systems=systems,
            detections=detections,
            pages=page_sizes,
            display_title=display_title,
        )

    def _normalize_pages(
        self, pages: list[PageSize] | list[PageImage]
    ) -> list[PageSize]:
        if not pages:
            return []
        first = pages[0]
        if isinstance(first, PageImage):
            return page_sizes_from_page_images(pages)  # type: ignore[arg-type]
        return list(pages)  # type: ignore[arg-type]


def _resolve_display_title(title: str | None, pdf_path: Path | None) -> str:
    if title is not None and title.strip():
        return title.strip()
    if pdf_path is not None:
        stem = pdf_path.stem.strip()
        if stem:
            return stem
    return "Untitled score"
