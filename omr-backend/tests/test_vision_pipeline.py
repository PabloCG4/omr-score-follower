"""Tests for Phase 5.5.3.C.2 vision inference pipeline."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pymupdf
import pytest

from app.core.config import Settings
from app.vision.category_taxonomy import OMR_CLASS_NAMES, build_category_mapping
from app.vision.detections import RawDetection
from app.vision.dino_detector import TinyRandomBackbone
from app.vision.pdf_rasterizer import PdfPageRasterizer
from app.vision.sahi_dino_model import DinoV2SahiDetectionModel
from app.vision.vision_detection_service import VisionDetectionService


def create_blank_pdf(path: Path, *, page_count: int = 1) -> Path:
    document = pymupdf.open()
    for _ in range(page_count):
        document.new_page(width=200, height=280)
    document.save(path)
    document.close()
    return path


@pytest.fixture()
def blank_pdf(tmp_path: Path) -> Path:
    return create_blank_pdf(tmp_path / "blank.pdf")


def test_pdf_page_rasterizer_returns_rgb_pages(blank_pdf: Path) -> None:
    rasterizer = PdfPageRasterizer(dpi=72.0, max_pages=5)
    pages = rasterizer.render(blank_pdf)

    assert len(pages) == 1
    page = pages[0]
    assert page.page_index == 0
    assert isinstance(page.image_rgb, np.ndarray)
    assert page.image_rgb.dtype == np.uint8
    assert page.image_rgb.ndim == 3
    assert page.image_rgb.shape[2] == 3
    assert page.width_px == page.image_rgb.shape[1]
    assert page.height_px == page.image_rgb.shape[0]


def test_dino_sahi_detection_model_with_stub_backbone() -> None:
    backbone = TinyRandomBackbone()
    model = DinoV2SahiDetectionModel(
        model_path=None,
        confidence_threshold=0.01,
        device="cpu",
        category_mapping=build_category_mapping(),
        image_size=112,
        load_at_init=True,
        backbone=backbone,
        prefer_dinov2_hub=False,
    )

    image = np.zeros((128, 128, 3), dtype=np.uint8)
    image[40:80, 40:80] = 255
    model.perform_inference(image)
    model._create_object_prediction_list_from_original_predictions(
        shift_amount_list=[[0, 0]],
        full_shape_list=[[128, 128]],
    )

    assert model._object_prediction_list_per_image is not None
    assert isinstance(model._object_prediction_list_per_image, list)
    # Random head may yield zero or more boxes; structure must be valid.
    for prediction in model._object_prediction_list_per_image[0]:
        assert prediction.category.id >= 0
        assert prediction.category.name in OMR_CLASS_NAMES or prediction.category.name.startswith(
            "unknown_"
        )
        assert 0.0 <= prediction.score.value <= 1.0


def test_vision_detection_service_detect_pdf_returns_raw_detections(
    blank_pdf: Path,
    tmp_path: Path,
) -> None:
    settings = Settings(
        vision_raster_dpi=72.0,
        vision_slice_height=64,
        vision_slice_width=64,
        vision_overlap_ratio=0.2,
        vision_confidence_threshold=0.99,
        vision_device="cpu",
        vision_weights_path=None,
        vision_input_size=112,
        vision_max_pages=5,
    )
    backbone = TinyRandomBackbone()
    detection_model = DinoV2SahiDetectionModel(
        model_path=None,
        confidence_threshold=settings.vision_confidence_threshold,
        device=settings.vision_device,
        category_mapping=build_category_mapping(),
        image_size=settings.vision_input_size,
        load_at_init=True,
        backbone=backbone,
        prefer_dinov2_hub=False,
    )
    service = VisionDetectionService(
        settings=settings,
        detection_model=detection_model,
        prefer_dinov2_hub=False,
    )

    scratch_before = {path.name for path in tmp_path.iterdir()}
    detections = service.detect_pdf(blank_pdf)
    scratch_after = {path.name for path in tmp_path.iterdir()}

    assert isinstance(detections, list)
    for item in detections:
        assert isinstance(item, RawDetection)
        assert item.page_index == 0
        assert len(item.bbox_xyxy) == 4
        assert item.bbox_xyxy[2] >= item.bbox_xyxy[0]
        assert item.bbox_xyxy[3] >= item.bbox_xyxy[1]
        assert isinstance(item.class_name, str)
        assert 0.0 <= item.confidence <= 1.0

    # Rasterization is in-memory; no scratch page images under the PDF temp dir.
    assert scratch_after == scratch_before
