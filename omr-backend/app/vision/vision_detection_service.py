"""Orchestrates PDF rasterization and SAHI sliced detection."""

from __future__ import annotations

import logging
from pathlib import Path

from sahi.models.base import DetectionModel
from sahi.predict import get_sliced_prediction

from app.core.config import Settings, get_settings
from app.core.errors import ProcessingAppError, ValidationAppError
from app.vision.category_taxonomy import build_category_mapping
from app.vision.deepscores_categories import alias_to_reconstruction_class_name
from app.vision.detections import PageImage, RawDetection
from app.vision.fasterrcnn_sahi_model import FasterRcnnSahiDetectionModel
from app.vision.pdf_rasterizer import PdfPageRasterizer
from app.vision.sahi_dino_model import DinoV2SahiDetectionModel

LOGGER = logging.getLogger(__name__)


class VisionDetectionService:
    """PDF → page rasters → SAHI slices → raw page-space detections."""

    def __init__(
        self,
        *,
        settings: Settings | None = None,
        rasterizer: PdfPageRasterizer | None = None,
        detection_model: DetectionModel | None = None,
        prefer_dinov2_hub: bool = True,
    ) -> None:
        self.settings = settings if settings is not None else get_settings()
        self.rasterizer = rasterizer or PdfPageRasterizer(
            dpi=self.settings.vision_raster_dpi,
            max_pages=self.settings.vision_max_pages,
        )
        self.prefer_dinov2_hub = prefer_dinov2_hub
        self.detection_model = detection_model
        if self.detection_model is None:
            self.detection_model = self._build_detection_model()

    def _build_detection_model(self) -> DetectionModel:
        weights_path = self.settings.resolved_vision_weights_path()
        if weights_path is not None and weights_path.is_file():
            LOGGER.info("Building Faster R-CNN SAHI model from %s", weights_path)
            return FasterRcnnSahiDetectionModel(
                model_path=str(weights_path),
                confidence_threshold=self.settings.vision_confidence_threshold,
                device=self.settings.vision_device,
                image_size=self.settings.vision_input_size,
                load_at_init=True,
            )

        LOGGER.warning(
            "Vision weights missing at configured path; falling back to DINOv2 stub detector."
        )
        return DinoV2SahiDetectionModel(
            model_path=None,
            confidence_threshold=self.settings.vision_confidence_threshold,
            device=self.settings.vision_device,
            category_mapping=build_category_mapping(),
            image_size=self.settings.vision_input_size,
            load_at_init=True,
            prefer_dinov2_hub=self.prefer_dinov2_hub,
        )

    def detect_pdf(self, pdf_path: Path) -> list[RawDetection]:
        """Rasterize a PDF then run sliced inference on every page."""
        try:
            pages = self.rasterizer.render(pdf_path)
        except (ValidationAppError, ProcessingAppError):
            raise
        except Exception as error:  # noqa: BLE001
            raise ProcessingAppError(f"PDF rasterization failed: {error}") from error

        if not pages:
            raise ValidationAppError("PDF produced no rasterized pages.")
        return self.detect_pages(pages)

    def detect_pages(self, pages: list[PageImage]) -> list[RawDetection]:
        """Run sliced inference on pre-rasterized page images."""
        if not pages:
            raise ValidationAppError("No page images provided for detection.")

        assert self.detection_model is not None
        detections: list[RawDetection] = []

        for page in pages:
            try:
                result = get_sliced_prediction(
                    page.image_rgb,
                    self.detection_model,
                    slice_height=self.settings.vision_slice_height,
                    slice_width=self.settings.vision_slice_width,
                    overlap_height_ratio=self.settings.vision_overlap_ratio,
                    overlap_width_ratio=self.settings.vision_overlap_ratio,
                    verbose=0,
                    perform_standard_pred=False,
                )
            except Exception as error:  # noqa: BLE001
                raise ProcessingAppError(
                    f"Vision inference failed on page {page.page_index}: {error}"
                ) from error

            for object_prediction in result.object_prediction_list:
                bbox = object_prediction.bbox
                if bbox is None:
                    continue
                x1 = float(bbox.minx)
                y1 = float(bbox.miny)
                x2 = float(bbox.maxx)
                y2 = float(bbox.maxy)
                class_id = int(object_prediction.category.id)
                raw_name = str(object_prediction.category.name)
                detections.append(
                    RawDetection(
                        page_index=page.page_index,
                        bbox_xyxy=(x1, y1, x2, y2),
                        class_id=class_id,
                        class_name=alias_to_reconstruction_class_name(raw_name),
                        confidence=float(object_prediction.score.value),
                    )
                )

            LOGGER.info(
                "Page %s: %s detections after SAHI NMS",
                page.page_index,
                sum(1 for item in detections if item.page_index == page.page_index),
            )

        return detections
