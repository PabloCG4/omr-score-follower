"""SAHI DetectionModel adapter for TorchVision Faster R-CNN DeepScores weights."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np
import torch
from sahi.models.base import DetectionModel
from sahi.prediction import ObjectPrediction
from sahi.utils.compatibility import fix_full_shape_list, fix_shift_amount_list
from torchvision.models.detection import fasterrcnn_resnet50_fpn

from app.core.errors import ProcessingAppError
from app.vision.deepscores_categories import (
    build_torchvision_category_mapping,
    load_deepscores_category_names,
    validate_category_count_against_num_classes,
)

LOGGER = logging.getLogger(__name__)

FASTER_RCNN_NUM_CLASSES = 150


class FasterRcnnSahiDetectionModel(DetectionModel):
    """Wraps a DeepScores-trained Faster R-CNN for SAHI sliced inference."""

    def __init__(
        self,
        *args: object,
        categories_path: str | None = None,
        num_classes: int = FASTER_RCNN_NUM_CLASSES,
        **kwargs: object,
    ) -> None:
        existing_packages = getattr(self, "required_packages", None) or []
        self.required_packages = [*list(existing_packages), "torch", "torchvision"]
        self.categories_path = categories_path
        self.num_classes = num_classes
        super().__init__(*args, **kwargs)  # type: ignore[misc, arg-type]

    def load_model(self) -> None:
        if self.model_path is None:
            raise ProcessingAppError(
                "Faster R-CNN requires OMR_VISION_WEIGHTS_PATH to point to a .pt file."
            )
        weights_path = Path(self.model_path)
        if not weights_path.is_file():
            raise ProcessingAppError(
                f"Faster R-CNN weights file not found: {weights_path}"
            )

        category_names = load_deepscores_category_names(self.categories_path)
        validate_category_count_against_num_classes(category_names, self.num_classes)

        model = fasterrcnn_resnet50_fpn(weights=None, num_classes=self.num_classes)
        state = torch.load(weights_path, map_location="cpu", weights_only=False)
        if isinstance(state, dict) and "state_dict" in state:
            state = state["state_dict"]
        missing, unexpected = model.load_state_dict(state, strict=True)
        LOGGER.info(
            "Loaded Faster R-CNN weights from %s (missing=%s unexpected=%s).",
            weights_path,
            len(missing),
            len(unexpected),
        )
        self.category_mapping = build_torchvision_category_mapping(category_names)
        self.set_model(model)

    def set_model(self, model: Any, **kwargs: Any) -> None:
        model.eval()
        self.model = model.to(self.device)
        if self.category_mapping is None:
            self.category_mapping = build_torchvision_category_mapping()

    def perform_inference(self, image: np.ndarray) -> None:
        if self.model is None:
            raise RuntimeError("Model is not loaded; call load_model() first.")
        if image.ndim != 3 or image.shape[2] != 3:
            raise ValueError(f"Expected RGB HWC image, got shape {image.shape}.")

        if self.image_size is not None:
            min_shape, max_shape = min(image.shape[:2]), max(image.shape[:2])
            scaled = self.image_size * min_shape / max_shape
            self.model.transform.min_size = (scaled,)
            self.model.transform.max_size = scaled

        image_tensor = torch.from_numpy(np.ascontiguousarray(image)).float()
        image_tensor = image_tensor.permute(2, 0, 1) / 255.0
        image_tensor = image_tensor.to(self.device)

        with torch.inference_mode():
            prediction_result = self.model([image_tensor])

        self._original_predictions = prediction_result
        self._original_shapes = [image.shape]

    @property
    def num_categories(self) -> int:
        assert self.category_mapping is not None
        return len(self.category_mapping)

    @property
    def has_mask(self) -> bool:
        return False

    @property
    def category_names(self) -> list[str]:
        assert self.category_mapping is not None
        return list(self.category_mapping.values())

    def _create_object_prediction_list_from_original_predictions(
        self,
        shift_amount_list: list[list[int | float]] | None = [[0, 0]],
        full_shape_list: list[list[int | float]] | None = None,
    ) -> None:
        assert self._original_predictions is not None
        assert self.category_mapping is not None

        shift_amount_list = fix_shift_amount_list(shift_amount_list)
        full_shape_list = fix_full_shape_list(full_shape_list)

        object_prediction_list_per_image: list[list[ObjectPrediction]] = []
        for image_index, image_predictions in enumerate(self._original_predictions):
            shift_amount = shift_amount_list[image_index]
            full_shape = (
                None if full_shape_list is None else full_shape_list[image_index]
            )

            scores = image_predictions["scores"].detach().cpu().numpy()
            selected = np.where(scores > self.confidence_threshold)[0]
            boxes = image_predictions["boxes"][selected].detach().cpu().numpy()
            labels = image_predictions["labels"][selected].detach().cpu().numpy()
            selected_scores = scores[selected]

            object_prediction_list: list[ObjectPrediction] = []
            for index in range(len(boxes)):
                category_id = int(labels[index])
                category_name = self.category_mapping.get(
                    str(category_id),
                    f"unknown_{category_id}",
                )
                bbox = boxes[index].tolist()
                if bbox[2] <= bbox[0] or bbox[3] <= bbox[1]:
                    continue
                object_prediction_list.append(
                    ObjectPrediction(
                        bbox=bbox,
                        category_id=category_id,
                        category_name=category_name,
                        score=float(selected_scores[index]),
                        shift_amount=shift_amount,
                        full_shape=full_shape,
                    )
                )
            object_prediction_list_per_image.append(object_prediction_list)

        self._object_prediction_list_per_image = object_prediction_list_per_image
