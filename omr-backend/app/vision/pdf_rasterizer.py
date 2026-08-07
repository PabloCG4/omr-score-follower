"""PDF → high-resolution RGB page images via PyMuPDF."""

from __future__ import annotations

import logging
from pathlib import Path

import numpy as np
import pymupdf

from app.core.errors import ProcessingAppError, ValidationAppError
from app.vision.detections import PageImage

LOGGER = logging.getLogger(__name__)


class PdfPageRasterizer:
    """Rasterize each PDF page to an in-memory RGB numpy array."""

    def __init__(self, *, dpi: float = 200.0, max_pages: int = 50) -> None:
        if dpi <= 0:
            raise ValueError("dpi must be positive.")
        if max_pages < 1:
            raise ValueError("max_pages must be at least 1.")
        self.dpi = dpi
        self.max_pages = max_pages

    def render(self, pdf_path: Path) -> list[PageImage]:
        if not pdf_path.is_file():
            raise ValidationAppError(f"PDF path does not exist: {pdf_path}")

        try:
            document = pymupdf.open(pdf_path)
        except Exception as error:  # noqa: BLE001 - surface as processing failure
            raise ProcessingAppError(f"Failed to open PDF: {error}") from error

        try:
            if document.page_count == 0:
                raise ValidationAppError("PDF contains no pages.")
            if document.page_count > self.max_pages:
                raise ValidationAppError(
                    f"PDF has {document.page_count} pages; maximum allowed is "
                    f"{self.max_pages}."
                )

            zoom = self.dpi / 72.0
            matrix = pymupdf.Matrix(zoom, zoom)
            pages: list[PageImage] = []

            for page_index in range(document.page_count):
                page = document.load_page(page_index)
                pixmap = page.get_pixmap(matrix=matrix, alpha=False)
                image_rgb = np.frombuffer(pixmap.samples, dtype=np.uint8).reshape(
                    pixmap.height,
                    pixmap.width,
                    3,
                ).copy()
                pages.append(
                    PageImage(
                        page_index=page_index,
                        image_rgb=image_rgb,
                        width_px=pixmap.width,
                        height_px=pixmap.height,
                    )
                )
                LOGGER.debug(
                    "Rasterized page %s (%sx%s) at %.1f DPI",
                    page_index,
                    pixmap.width,
                    pixmap.height,
                    self.dpi,
                )

            return pages
        finally:
            document.close()
