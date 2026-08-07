"""Vision inference package (DINOv2 + SAHI). Phase 5.5.3.C.2."""

from app.vision.detections import PageImage, RawDetection
from app.vision.vision_detection_service import VisionDetectionService

__all__ = [
    "PageImage",
    "RawDetection",
    "VisionDetectionService",
]
