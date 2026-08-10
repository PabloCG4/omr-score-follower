"""Rhythm estimation from notehead class and spatial modifiers."""

from __future__ import annotations

from app.reconstruction.geometry import (
    boxes_overlap_y,
    detection_center,
    expand_bbox,
    horizontal_gap,
    iou,
)
from app.reconstruction.staff_system import StaffSystem
from app.vision.detections import RawDetection

NOTEHEAD_BASE_QUARTERS: dict[str, float] = {
    "noteheadWhole": 4.0,
    "noteheadHalf": 2.0,
    "noteheadBlack": 1.0,
}

REST_QUARTERS: dict[str, float] = {
    "restWhole": 4.0,
    "restHalf": 2.0,
    "restQuarter": 1.0,
    "rest8th": 0.5,
    "rest16th": 0.25,
    "rest32nd": 0.125,
    "rest64th": 0.0625,
    "rest128th": 0.03125,
    "restDoubleWhole": 8.0,
}

FLAG_DURATION_QUARTERS: dict[str, float] = {
    "flag8thUp": 0.5,
    "flag8thDown": 0.5,
    "flag16thUp": 0.25,
    "flag16thDown": 0.25,
    "flag32ndUp": 0.125,
    "flag32ndDown": 0.125,
    "flag64thUp": 0.0625,
    "flag64thDown": 0.0625,
    "flag128thUp": 0.03125,
    "flag128thDown": 0.03125,
}


def estimate_notehead_duration_quarters(
    notehead: RawDetection,
    system: StaffSystem,
) -> float:
    base = NOTEHEAD_BASE_QUARTERS.get(notehead.class_name)
    if base is None:
        raise ValueError(f"Not a notehead class: {notehead.class_name}")

    s = system.geometry.interline_px
    duration = base

    if notehead.class_name == "noteheadBlack":
        flag_duration = _matching_flag_duration(notehead, system, s)
        beam_duration = _matching_beam_duration(notehead, system, s)
        candidates = [duration]
        if flag_duration is not None:
            candidates.append(flag_duration)
        if beam_duration is not None:
            candidates.append(beam_duration)
        # Conflict policy: smaller (more specific) duration wins.
        duration = min(candidates)

    if _has_augmentation_dot(notehead, system, s):
        duration *= 1.5

    return duration


def estimate_rest_duration_quarters(rest: RawDetection) -> float:
    duration = REST_QUARTERS.get(rest.class_name)
    if duration is None:
        raise ValueError(f"Not a rest class: {rest.class_name}")
    return duration


def _matching_flag_duration(
    notehead: RawDetection,
    system: StaffSystem,
    interline: float,
) -> float | None:
    stem = _find_stem(notehead, system, interline)
    best: float | None = None
    for detection in system.detections:
        flag_duration = FLAG_DURATION_QUARTERS.get(detection.class_name)
        if flag_duration is None:
            continue
        matched = False
        if stem is not None:
            expanded_stem = expand_bbox(
                stem.bbox_xyxy, expand_x=0.35 * interline, expand_y=0.35 * interline
            )
            if iou(detection.bbox_xyxy, expanded_stem) > 0.0:
                matched = True
            else:
                # Flag near the stem tip (top or bottom of stem).
                fx, fy = detection_center(detection)
                sx = detection_center(stem)[0]
                if abs(fx - sx) <= 1.25 * interline and (
                    abs(fy - stem.bbox_xyxy[1]) <= 1.25 * interline
                    or abs(fy - stem.bbox_xyxy[3]) <= 1.25 * interline
                ):
                    matched = True
        if not matched:
            nx, ny = detection_center(notehead)
            fx, fy = detection_center(detection)
            if abs(fx - nx) <= 1.5 * interline and (
                abs(fy - notehead.bbox_xyxy[1]) <= 1.5 * interline
                or abs(fy - notehead.bbox_xyxy[3]) <= 1.5 * interline
            ):
                matched = True
        if matched:
            best = flag_duration if best is None else min(best, flag_duration)
    return best


def _matching_beam_duration(
    notehead: RawDetection,
    system: StaffSystem,
    interline: float,
) -> float | None:
    nx, _ = detection_center(notehead)
    for detection in system.detections:
        if detection.class_name != "beam":
            continue
        if detection.bbox_xyxy[0] <= nx <= detection.bbox_xyxy[2]:
            stem = _find_stem(notehead, system, interline)
            if stem is None:
                return 0.5
            by = detection_center(detection)[1]
            sy1, sy2 = stem.bbox_xyxy[1], stem.bbox_xyxy[3]
            if sy1 - interline <= by <= sy2 + interline:
                return 0.5
    return None


def _find_stem(
    notehead: RawDetection,
    system: StaffSystem,
    interline: float,
) -> RawDetection | None:
    expanded = expand_bbox(notehead.bbox_xyxy, expand_x=1.5 * interline)
    best: RawDetection | None = None
    best_iou = 0.0
    nx, _ = detection_center(notehead)
    for detection in system.detections:
        if detection.class_name != "stem":
            continue
        overlap = iou(expanded, detection.bbox_xyxy)
        if overlap > best_iou:
            best = detection
            best_iou = overlap
            continue
        sx, _ = detection_center(detection)
        if abs(sx - nx) <= 0.8 * interline and boxes_overlap_y(
            notehead.bbox_xyxy, detection.bbox_xyxy
        ):
            if best is None:
                best = detection
    return best


def _has_augmentation_dot(
    notehead: RawDetection,
    system: StaffSystem,
    interline: float,
) -> bool:
    _, ny = detection_center(notehead)
    for detection in system.detections:
        if detection.class_name != "augmentationDot":
            continue
        gap = horizontal_gap(notehead.bbox_xyxy, detection.bbox_xyxy)
        if gap < 0.0 or gap >= 1.2 * interline:
            continue
        dy = abs(detection_center(detection)[1] - ny)
        if dy < 0.5 * interline:
            return True
    return False
