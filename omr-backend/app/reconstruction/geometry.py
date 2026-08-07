"""Bounding-box geometry helpers for OMR reconstruction."""

from __future__ import annotations

from app.vision.detections import RawDetection


def bbox_center(bbox_xyxy: tuple[float, float, float, float]) -> tuple[float, float]:
    x1, y1, x2, y2 = bbox_xyxy
    return ((x1 + x2) * 0.5, (y1 + y2) * 0.5)


def bbox_width(bbox_xyxy: tuple[float, float, float, float]) -> float:
    return max(0.0, bbox_xyxy[2] - bbox_xyxy[0])


def bbox_height(bbox_xyxy: tuple[float, float, float, float]) -> float:
    return max(0.0, bbox_xyxy[3] - bbox_xyxy[1])


def expand_bbox(
    bbox_xyxy: tuple[float, float, float, float],
    *,
    expand_x: float = 0.0,
    expand_y: float = 0.0,
) -> tuple[float, float, float, float]:
    x1, y1, x2, y2 = bbox_xyxy
    return (x1 - expand_x, y1 - expand_y, x2 + expand_x, y2 + expand_y)


def horizontal_gap(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
) -> float:
    """Positive gap when `left` is entirely to the left of `right`; else <= 0."""
    return right[0] - left[2]


def iou(
    a: tuple[float, float, float, float],
    b: tuple[float, float, float, float],
) -> float:
    ix1 = max(a[0], b[0])
    iy1 = max(a[1], b[1])
    ix2 = min(a[2], b[2])
    iy2 = min(a[3], b[3])
    inter_w = max(0.0, ix2 - ix1)
    inter_h = max(0.0, iy2 - iy1)
    inter = inter_w * inter_h
    if inter <= 0.0:
        return 0.0
    area_a = bbox_width(a) * bbox_height(a)
    area_b = bbox_width(b) * bbox_height(b)
    union = area_a + area_b - inter
    if union <= 0.0:
        return 0.0
    return inter / union


def boxes_overlap_y(
    a: tuple[float, float, float, float],
    b: tuple[float, float, float, float],
) -> bool:
    return a[1] < b[3] and b[1] < a[3]


def detection_center(detection: RawDetection) -> tuple[float, float]:
    return bbox_center(detection.bbox_xyxy)
