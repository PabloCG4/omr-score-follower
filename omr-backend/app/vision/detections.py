"""Raw detection types produced by the vision pipeline (pre music-theory)."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RawDetection:
    """One symbol hypothesis in full-page image coordinates."""

    page_index: int
    bbox_xyxy: tuple[float, float, float, float]
    class_id: int
    class_name: str
    confidence: float


@dataclass(frozen=True, slots=True)
class PageImage:
    """One rasterized PDF page ready for sliced inference."""

    page_index: int
    image_rgb: object  # numpy.ndarray[H, W, 3] uint8
    width_px: int
    height_px: int
