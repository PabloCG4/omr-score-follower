"""Orchestrates PDF rasterization and SAHI sliced DINOv2 detection."""

from __future__ import annotations

import logging
from pathlib import Path

from sahi.predict import get_sliced_prediction

from app.core.config import Settings, get_settings
from app.core.errors import ProcessingAppError, ValidationAppError
from app.vision.category_taxonomy import build_category_mapping, class_name_for_id
from app.vision.detections import RawDetection
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
        detection_model: DinoV2SahiDetectionModel | None = None,
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

    def _build_detection_model(self) -> DinoV2SahiDetectionModel:
        return DinoV2SahiDetectionModel(
            model_path=self.settings.vision_weights_path,
            confidence_threshold=self.settings.vision_confidence_threshold,
            device=self.settings.vision_device,
            category_mapping=build_category_mapping(),
            image_size=self.settings.vision_input_size,
            load_at_init=True,
            prefer_dinov2_hub=self.prefer_dinov2_hub,
        )

    def detect_pdf(self, pdf_path: Path) -> list[RawDetection]:
        """Run sliced inference on every page and return flat raw detections.

        Sync CPU/GPU work; FastAPI callers should wrap with asyncio.to_thread.
        """
        try:
            pages = self.rasterizer.render(pdf_path)
        except (ValidationAppError, ProcessingAppError):
            raise
        except Exception as error:  # noqa: BLE001
            raise ProcessingAppError(f"PDF rasterization failed: {error}") from error

        if not pages:
            raise ValidationAppError("PDF produced no rasterized pages.")

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
                # SAHI BBox exposes minx, miny, maxx, maxy after shift remap.
                x1 = float(bbox.minx)
                y1 = float(bbox.miny)
                x2 = float(bbox.maxx)
                y2 = float(bbox.maxy)
                class_id = int(object_prediction.category.id)
                detections.append(
                    RawDetection(
                        page_index=page.page_index,
                        bbox_xyxy=(x1, y1, x2, y2),
                        class_id=class_id,
                        class_name=class_name_for_id(class_id),
                        confidence=float(object_prediction.score.value),
                    )
                )

            LOGGER.info(
                "Page %s: %s detections after SAHI NMS",
                page.page_index,
                sum(1 for item in detections if item.page_index == page.page_index),
            )

        return detections
