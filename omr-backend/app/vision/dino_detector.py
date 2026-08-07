"""DINOv2 backbone + lightweight object-detection head for OMR symbols."""

from __future__ import annotations

import logging
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as functional

from app.vision.category_taxonomy import OMR_CLASS_NAMES

LOGGER = logging.getLogger(__name__)

DINOV2_EMBED_DIM = 384  # dinov2_vits14
DINOV2_PATCH_SIZE = 14
NECK_CHANNELS = 256


class TinyRandomBackbone(nn.Module):
    """Lightweight CNN stand-in used for tests and offline DINOv2 fallback.

    Produces a feature map with the same channel count as DINOv2 ViT-S/14.
    """

    def __init__(self, embed_dim: int = DINOV2_EMBED_DIM) -> None:
        super().__init__()
        self.embed_dim = embed_dim
        self.stem = nn.Sequential(
            nn.Conv2d(3, 64, kernel_size=7, stride=2, padding=3),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, 128, kernel_size=3, stride=2, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(128, embed_dim, kernel_size=3, stride=2, padding=1),
            nn.ReLU(inplace=True),
        )

    def forward(self, images: torch.Tensor) -> torch.Tensor:
        return self.stem(images)


class DinoV2TokenBackbone(nn.Module):
    """Wrap a DINOv2 (or compatible) encoder that returns patch tokens."""

    def __init__(self, encoder: nn.Module, embed_dim: int, patch_size: int) -> None:
        super().__init__()
        self.encoder = encoder
        self.embed_dim = embed_dim
        self.patch_size = patch_size

    def forward(self, images: torch.Tensor) -> torch.Tensor:
        # DINOv2 forward_features returns dict with x_norm_patchtokens, or a tensor.
        output = None
        if hasattr(self.encoder, "forward_features"):
            features = self.encoder.forward_features(images)
            if isinstance(features, dict):
                tokens = features.get("x_norm_patchtokens")
                if tokens is None:
                    tokens = features.get("x_prenorm")
                    if tokens is not None and tokens.dim() == 3:
                        tokens = tokens[:, 1:, :]
                output = tokens
            elif isinstance(features, torch.Tensor):
                output = features[:, 1:, :] if features.dim() == 3 else features
        if output is None:
            raw = self.encoder(images)
            if isinstance(raw, dict):
                output = raw.get("x_norm_patchtokens", next(iter(raw.values())))
            else:
                output = raw
                if output.dim() == 3 and output.shape[1] > 1:
                    # Drop CLS if present (heuristic: square number of patches).
                    patch_count = output.shape[1] - 1
                    side = int(patch_count**0.5)
                    if side * side == patch_count:
                        output = output[:, 1:, :]

        if output.dim() != 3:
            raise RuntimeError(
                f"Unexpected backbone output shape {tuple(output.shape)}; "
                "expected (B, N, C)."
            )

        batch_size, token_count, channels = output.shape
        grid = int(token_count**0.5)
        if grid * grid != token_count:
            raise RuntimeError(
                f"Patch token count {token_count} is not a perfect square."
            )
        return output.transpose(1, 2).reshape(batch_size, channels, grid, grid)


def build_backbone(*, prefer_dinov2_hub: bool = True) -> nn.Module:
    """Build DINOv2 ViT-S/14 when possible; otherwise a tiny random CNN."""
    if prefer_dinov2_hub:
        try:
            encoder = torch.hub.load(
                "facebookresearch/dinov2",
                "dinov2_vits14",
                pretrained=False,
                verbose=False,
            )
            LOGGER.info("Loaded DINOv2 ViT-S/14 architecture from torch.hub (random weights).")
            return DinoV2TokenBackbone(
                encoder=encoder,
                embed_dim=DINOV2_EMBED_DIM,
                patch_size=DINOV2_PATCH_SIZE,
            )
        except Exception as error:  # noqa: BLE001 - offline / hub unavailable
            LOGGER.warning(
                "DINOv2 hub load failed (%s); falling back to TinyRandomBackbone.",
                error,
            )
    return TinyRandomBackbone(embed_dim=DINOV2_EMBED_DIM)


class DetectionHead(nn.Module):
    """Sibling conv towers for class logits and box regression (anchor-free)."""

    def __init__(self, in_channels: int, num_classes: int) -> None:
        super().__init__()
        self.cls_tower = nn.Sequential(
            nn.Conv2d(in_channels, in_channels, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(in_channels, num_classes, kernel_size=3, padding=1),
        )
        self.box_tower = nn.Sequential(
            nn.Conv2d(in_channels, in_channels, kernel_size=3, padding=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(in_channels, 4, kernel_size=3, padding=1),
        )

    def forward(self, features: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        return self.cls_tower(features), self.box_tower(features)


class DinoV2OmrDetector(nn.Module):
    """DINOv2 (or stub) backbone + neck + detection head for OMR symbols."""

    def __init__(
        self,
        *,
        backbone: nn.Module | None = None,
        num_classes: int | None = None,
        input_size: int = 518,
    ) -> None:
        super().__init__()
        self.num_classes = num_classes if num_classes is not None else len(OMR_CLASS_NAMES)
        self.input_size = input_size
        self.backbone = backbone if backbone is not None else build_backbone()
        backbone_channels = getattr(self.backbone, "embed_dim", DINOV2_EMBED_DIM)
        self.neck = nn.Conv2d(backbone_channels, NECK_CHANNELS, kernel_size=1)
        self.head = DetectionHead(NECK_CHANNELS, self.num_classes)

    def forward(self, images: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        features = self.backbone(images)
        features = self.neck(features)
        return self.head(features)

    def decode_predictions(
        self,
        class_logits: torch.Tensor,
        box_offsets: torch.Tensor,
        *,
        image_height: int,
        image_width: int,
        confidence_threshold: float,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """Decode dense maps into xyxy boxes, scores, and labels (CPU tensors)."""
        # class_logits: (1, C, H, W), box_offsets: (1, 4, H, W)
        probabilities = functional.softmax(class_logits[0], dim=0)
        scores, labels = probabilities.max(dim=0)
        grid_height, grid_width = scores.shape
        device = scores.device

        y_coords = torch.linspace(0.5, grid_height - 0.5, grid_height, device=device)
        x_coords = torch.linspace(0.5, grid_width - 0.5, grid_width, device=device)
        grid_y, grid_x = torch.meshgrid(y_coords, x_coords, indexing="ij")

        stride_y = image_height / grid_height
        stride_x = image_width / grid_width
        center_x = grid_x * stride_x
        center_y = grid_y * stride_y

        # Offsets: (tx, ty, tw, th) with sigmoid sizes relative to cell stride.
        tx = box_offsets[0, 0]
        ty = box_offsets[0, 1]
        tw = box_offsets[0, 2].sigmoid()
        th = box_offsets[0, 3].sigmoid()
        width = (tw * stride_x * 4.0).clamp(min=1.0)
        height = (th * stride_y * 4.0).clamp(min=1.0)
        center_x = center_x + tx.tanh() * stride_x
        center_y = center_y + ty.tanh() * stride_y

        x1 = (center_x - width / 2).clamp(0, image_width)
        y1 = (center_y - height / 2).clamp(0, image_height)
        x2 = (center_x + width / 2).clamp(0, image_width)
        y2 = (center_y + height / 2).clamp(0, image_height)

        mask = scores >= confidence_threshold
        if not mask.any():
            empty = torch.zeros((0, 4), dtype=torch.float32)
            return empty, torch.zeros((0,), dtype=torch.float32), torch.zeros((0,), dtype=torch.int64)

        boxes = torch.stack([x1[mask], y1[mask], x2[mask], y2[mask]], dim=-1).cpu()
        return boxes, scores[mask].cpu(), labels[mask].cpu().to(torch.int64)

    def load_weights_if_available(self, weights_path: str | Path | None) -> None:
        if weights_path is None:
            LOGGER.warning(
                "No OMR vision weights path configured; using randomly initialized "
                "detector weights (pipeline will run but detections are not meaningful)."
            )
            return
        path = Path(weights_path)
        if not path.is_file():
            LOGGER.warning(
                "Vision weights file not found at %s; using randomly initialized weights.",
                path,
            )
            return
        state = torch.load(path, map_location="cpu", weights_only=True)
        if isinstance(state, dict) and "state_dict" in state:
            state = state["state_dict"]
        missing, unexpected = self.load_state_dict(state, strict=False)
        LOGGER.info(
            "Loaded vision weights from %s (missing=%s unexpected=%s).",
            path,
            len(missing),
            len(unexpected),
        )
