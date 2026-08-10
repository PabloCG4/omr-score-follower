"""Tests for VisionOmrProcessor production wiring without loading weights."""

from __future__ import annotations

from pathlib import Path

import pytest

from app.core.config import Settings
from app.core.errors import ProcessingAppError
from app.schemas.omr_structural import OmrStructuralDocument
from app.services.omr_processor import VisionOmrProcessor
from app.vision.category_taxonomy import OMR_CLASS_NAMES
from app.vision.deepscores_categories import (
    alias_to_reconstruction_class_name,
    load_deepscores_category_names,
    validate_category_count_against_num_classes,
)
from app.vision.detections import PageImage, RawDetection
import numpy as np


def detection(
    class_name: str,
    bbox: tuple[float, float, float, float],
) -> RawDetection:
    return RawDetection(
        page_index=0,
        bbox_xyxy=bbox,
        class_id=OMR_CLASS_NAMES.index(class_name)
        if class_name in OMR_CLASS_NAMES
        else 0,
        class_name=class_name,
        confidence=0.95,
    )


class StubVisionService:
    def __init__(self, detections: list[RawDetection]) -> None:
        self.detections = detections

    def detect_pages(self, pages: list[PageImage]) -> list[RawDetection]:
        return list(self.detections)


class StubRasterizer:
    def render(self, pdf_path: Path) -> list[PageImage]:
        image = np.zeros((360, 640, 3), dtype=np.uint8)
        return [
            PageImage(
                page_index=0,
                image_rgb=image,
                width_px=640,
                height_px=360,
            )
        ]


@pytest.mark.asyncio
async def test_vision_processor_empty_detections_raises(
    tmp_path: Path,
) -> None:
    pdf_path = tmp_path / "empty.pdf"
    pdf_path.write_bytes(b"%PDF-1.4\n%%EOF\n")
    processor = VisionOmrProcessor(
        settings=Settings(vision_warmup_on_startup=False, vision_weights_path=None),
        vision_service=StubVisionService([]),  # type: ignore[arg-type]
        rasterizer=StubRasterizer(),  # type: ignore[arg-type]
    )
    with pytest.raises(ProcessingAppError, match="no symbol detections"):
        await processor.process(pdf_path, title="Empty")


@pytest.mark.asyncio
async def test_vision_processor_stub_detections_reconstruct(
    tmp_path: Path,
) -> None:
    pdf_path = tmp_path / "score.pdf"
    pdf_path.write_bytes(b"%PDF-1.4\n%%EOF\n")
    detections = [
        detection("staff", (40.0, 100.0, 560.0, 200.0)),
        detection("clefG", (50.0, 110.0, 95.0, 190.0)),
        detection("noteheadBlack", (200.0, 190.0, 220.0, 210.0)),
    ]
    processor = VisionOmrProcessor(
        settings=Settings(vision_warmup_on_startup=False, vision_weights_path=None),
        vision_service=StubVisionService(detections),  # type: ignore[arg-type]
        rasterizer=StubRasterizer(),  # type: ignore[arg-type]
    )
    document = await processor.process(pdf_path, title="Stub Score")
    assert isinstance(document, OmrStructuralDocument)
    assert document.display_title == "Stub Score"
    assert document.note_events is not None
    assert len(document.note_events) == 1
    assert document.note_events[0].midi_pitch == 64


def test_deepscores_category_count_matches_faster_rcnn() -> None:
    names = load_deepscores_category_names()
    assert len(names) == 149
    validate_category_count_against_num_classes(names, 150)
    assert alias_to_reconstruction_class_name("noteheadBlackOnLine") == "noteheadBlack"
    assert alias_to_reconstruction_class_name("keySharp") == "accidentalSharp"
    assert alias_to_reconstruction_class_name("legerLine") == "ledgerLine"


def test_faster_rcnn_loads_real_checkpoint_if_present() -> None:
    weights = Path("weights/omr_deepscores_best_50epoch.pt")
    if not weights.is_file():
        pytest.skip("DeepScores Faster R-CNN weights not present")

    from app.vision.fasterrcnn_sahi_model import FasterRcnnSahiDetectionModel

    model = FasterRcnnSahiDetectionModel(
        model_path=str(weights),
        confidence_threshold=0.5,
        device="cpu",
        load_at_init=True,
    )
    assert model.model is not None
    assert model.num_categories == 149
