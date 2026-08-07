"""SAHI DetectionModel adapter for DinoV2OmrDetector."""

from __future__ import annotations

from typing import Any

import numpy as np
import torch
import torch.nn.functional as functional
from sahi.models.base import DetectionModel
from sahi.prediction import ObjectPrediction
from sahi.utils.compatibility import fix_full_shape_list, fix_shift_amount_list
from torchvision.transforms.functional import normalize

from app.vision.category_taxonomy import OMR_CLASS_NAMES, build_category_mapping
from app.vision.dino_detector import DinoV2OmrDetector

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


class DinoV2SahiDetectionModel(DetectionModel):
    """Wraps DinoV2OmrDetector so SAHI can slice, NMS, and remap boxes."""

    def __init__(
        self,
        *args: object,
        backbone: torch.nn.Module | None = None,
        prefer_dinov2_hub: bool = True,
        **kwargs: object,
    ) -> None:
        existing_packages = getattr(self, "required_packages", None) or []
        self.required_packages = [*list(existing_packages), "torch", "torchvision"]
        self.injected_backbone = backbone
        self.prefer_dinov2_hub = prefer_dinov2_hub
        super().__init__(*args, **kwargs)  # type: ignore[misc, arg-type]

    def load_model(self) -> None:
        from app.vision.dino_detector import build_backbone

        input_size = self.image_size if self.image_size is not None else 518
        if self.injected_backbone is not None:
            backbone = self.injected_backbone
        else:
            backbone = build_backbone(prefer_dinov2_hub=self.prefer_dinov2_hub)

        detector = DinoV2OmrDetector(
            backbone=backbone,
            num_classes=len(OMR_CLASS_NAMES),
            input_size=input_size,
        )
        detector.load_weights_if_available(self.model_path)
        self.set_model(detector)

    def set_model(self, model: Any, **kwargs: Any) -> None:
        if not isinstance(model, DinoV2OmrDetector):
            raise TypeError(
                f"Expected DinoV2OmrDetector, got {type(model).__name__}."
            )
        model.eval()
        self.model = model.to(self.device)
        if self.category_mapping is None:
            self.category_mapping = build_category_mapping()
        if self.image_size is None:
            self.image_size = model.input_size

    def perform_inference(self, image: np.ndarray) -> None:
        if self.model is None:
            raise RuntimeError("Model is not loaded; call load_model() first.")
        if image.ndim != 3 or image.shape[2] != 3:
            raise ValueError(
                f"Expected RGB HWC image, got shape {image.shape}."
            )

        image_height, image_width = int(image.shape[0]), int(image.shape[1])
        input_size = int(self.image_size or self.model.input_size)

        tensor = torch.from_numpy(np.ascontiguousarray(image)).float()
        tensor = tensor.permute(2, 0, 1).unsqueeze(0) / 255.0
        tensor = functional.interpolate(
            tensor,
            size=(input_size, input_size),
            mode="bilinear",
            align_corners=False,
        )
        tensor = normalize(tensor, mean=list(IMAGENET_MEAN), std=list(IMAGENET_STD))
        tensor = tensor.to(self.device)

        with torch.inference_mode():
            class_logits, box_offsets = self.model(tensor)
            boxes, scores, labels = self.model.decode_predictions(
                class_logits,
                box_offsets,
                image_height=input_size,
                image_width=input_size,
                confidence_threshold=self.confidence_threshold,
            )

        # Map decoded boxes from model input space back to the original slice.
        scale_x = image_width / float(input_size)
        scale_y = image_height / float(input_size)
        if boxes.numel() > 0:
            boxes = boxes.clone()
            boxes[:, 0] *= scale_x
            boxes[:, 2] *= scale_x
            boxes[:, 1] *= scale_y
            boxes[:, 3] *= scale_y

        self._original_predictions = [
            {
                "boxes": boxes,
                "scores": scores,
                "labels": labels,
            }
        ]
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

            boxes = image_predictions["boxes"]
            scores = image_predictions["scores"]
            labels = image_predictions["labels"]

            if hasattr(boxes, "detach"):
                boxes_np = boxes.detach().cpu().numpy()
                scores_np = scores.detach().cpu().numpy()
                labels_np = labels.detach().cpu().numpy()
            else:
                boxes_np = np.asarray(boxes)
                scores_np = np.asarray(scores)
                labels_np = np.asarray(labels)

            object_prediction_list: list[ObjectPrediction] = []
            for index in range(len(boxes_np)):
                category_id = int(labels_np[index])
                category_name = self.category_mapping.get(
                    str(category_id),
                    f"unknown_{category_id}",
                )
                bbox = boxes_np[index].tolist()
                # Skip degenerate boxes that SAHI would reject.
                if bbox[2] <= bbox[0] or bbox[3] <= bbox[1]:
                    continue
                object_prediction_list.append(
                    ObjectPrediction(
                        bbox=bbox,
                        category_id=category_id,
                        category_name=category_name,
                        score=float(scores_np[index]),
                        shift_amount=shift_amount,
                        full_shape=full_shape,
                    )
                )
            object_prediction_list_per_image.append(object_prediction_list)

        self._object_prediction_list_per_image = object_prediction_list_per_image
