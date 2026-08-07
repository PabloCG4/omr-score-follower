"""Staff geometry assembly and symbol-to-staff assignment."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Literal

from app.reconstruction.geometry import (
    bbox_center,
    bbox_height,
    detection_center,
    iou,
)
from app.vision.detections import RawDetection

LOGGER = logging.getLogger(__name__)

ClefKind = Literal["G", "F", "C"]

CLEF_CLASS_TO_KIND: dict[str, ClefKind] = {
    "clefG": "G",
    "clefF": "F",
    "clefC": "C",
}

SYSTEM_SPLIT_CLEF_GAP_FACTOR = 1.75
ASSIGN_MAX_DISTANCE_INTERLINES = 3.5


@dataclass(frozen=True, slots=True)
class StaffGeometry:
    """Virtual five-line staff in image coordinates (Y increases downward)."""

    page_index: int
    line_y: tuple[float, float, float, float, float]
    interline_px: float
    clef_kind: ClefKind
    clef_center_x: float


@dataclass(slots=True)
class StaffSystem:
    system_id: int
    geometry: StaffGeometry
    detections: list[RawDetection] = field(default_factory=list)


def build_line_y_from_staff_bbox(
    staff_bbox: tuple[float, float, float, float],
) -> tuple[tuple[float, float, float, float, float], float]:
    top = float(staff_bbox[1])
    bottom = float(staff_bbox[3])
    if bottom <= top:
        raise ValueError("Staff bbox height must be positive.")
    interline = (bottom - top) / 4.0
    line_y = (
        top,
        top + interline,
        top + 2.0 * interline,
        top + 3.0 * interline,
        bottom,
    )
    return line_y, interline


def build_line_y_from_clef(
    clef_bbox: tuple[float, float, float, float],
    clef_kind: ClefKind,
) -> tuple[tuple[float, float, float, float, float], float]:
    """Fallback when no staff box exists: place lines from clef height/center."""
    height = bbox_height(clef_bbox)
    if height <= 0.0:
        raise ValueError("Clef bbox height must be positive.")
    interline = height / 4.0
    _, clef_cy = bbox_center(clef_bbox)

    if clef_kind == "G":
        # Second line from bottom (index 3) is the G4 reference line.
        ref_y = clef_cy
        line_y3 = ref_y
        line_y = (
            line_y3 - 3.0 * interline,
            line_y3 - 2.0 * interline,
            line_y3 - 1.0 * interline,
            line_y3,
            line_y3 + 1.0 * interline,
        )
    elif clef_kind == "F":
        # Second line from top (index 1) is F3.
        line_y1 = clef_cy
        line_y = (
            line_y1 - 1.0 * interline,
            line_y1,
            line_y1 + 1.0 * interline,
            line_y1 + 2.0 * interline,
            line_y1 + 3.0 * interline,
        )
    else:
        # Alto C-clef: middle line is C4.
        line_y2 = clef_cy
        line_y = (
            line_y2 - 2.0 * interline,
            line_y2 - 1.0 * interline,
            line_y2,
            line_y2 + 1.0 * interline,
            line_y2 + 2.0 * interline,
        )
    return line_y, interline


def assemble_staff_systems(detections: list[RawDetection]) -> list[StaffSystem]:
    """Build staff systems from staff boxes (preferred) or clef clustering."""
    by_page: dict[int, list[RawDetection]] = {}
    for detection in detections:
        by_page.setdefault(detection.page_index, []).append(detection)

    systems: list[StaffSystem] = []
    next_id = 0
    for page_index in sorted(by_page.keys()):
        page_detections = by_page[page_index]
        page_systems = _assemble_page(page_index, page_detections, next_id)
        systems.extend(page_systems)
        next_id += len(page_systems)

    assign_detections_to_systems(systems, detections)
    return systems


def _assemble_page(
    page_index: int,
    page_detections: list[RawDetection],
    start_id: int,
) -> list[StaffSystem]:
    staff_boxes = [d for d in page_detections if d.class_name == "staff"]
    staff_boxes.sort(key=lambda d: detection_center(d)[1])

    if staff_boxes:
        systems: list[StaffSystem] = []
        for offset, staff in enumerate(staff_boxes):
            line_y, interline = build_line_y_from_staff_bbox(staff.bbox_xyxy)
            clef_kind, clef_x = _resolve_clef_for_staff(
                page_detections, line_y, interline
            )
            geometry = StaffGeometry(
                page_index=page_index,
                line_y=line_y,
                interline_px=interline,
                clef_kind=clef_kind,
                clef_center_x=clef_x,
            )
            systems.append(
                StaffSystem(system_id=start_id + offset, geometry=geometry)
            )
        return systems

    clefs = [d for d in page_detections if d.class_name in CLEF_CLASS_TO_KIND]
    clefs.sort(key=lambda d: (detection_center(d)[1], detection_center(d)[0]))
    if not clefs:
        LOGGER.warning(
            "Page %s has no staff or clef detections; cannot assemble systems.",
            page_index,
        )
        return []

    heights = [bbox_height(c.bbox_xyxy) for c in clefs]
    median_height = sorted(heights)[len(heights) // 2]
    gap_threshold = SYSTEM_SPLIT_CLEF_GAP_FACTOR * median_height

    groups: list[list[RawDetection]] = [[clefs[0]]]
    for clef in clefs[1:]:
        prev_y = detection_center(groups[-1][-1])[1]
        cur_y = detection_center(clef)[1]
        if cur_y - prev_y > gap_threshold:
            groups.append([clef])
        else:
            groups[-1].append(clef)

    systems = []
    for offset, group in enumerate(groups):
        primary = min(group, key=lambda d: detection_center(d)[0])
        kind = CLEF_CLASS_TO_KIND[primary.class_name]
        line_y, interline = build_line_y_from_clef(primary.bbox_xyxy, kind)
        cx, _ = detection_center(primary)
        geometry = StaffGeometry(
            page_index=page_index,
            line_y=line_y,
            interline_px=interline,
            clef_kind=kind,
            clef_center_x=cx,
        )
        systems.append(StaffSystem(system_id=start_id + offset, geometry=geometry))
    return systems


def _resolve_clef_for_staff(
    page_detections: list[RawDetection],
    line_y: tuple[float, float, float, float, float],
    interline: float,
) -> tuple[ClefKind, float]:
    mid_y = line_y[2]
    band_top = line_y[0] - 2.0 * interline
    band_bottom = line_y[4] + 2.0 * interline
    candidates = [
        d
        for d in page_detections
        if d.class_name in CLEF_CLASS_TO_KIND
        and band_top <= detection_center(d)[1] <= band_bottom
    ]
    if not candidates:
        return "G", 0.0
    primary = min(
        candidates,
        key=lambda d: (abs(detection_center(d)[1] - mid_y), detection_center(d)[0]),
    )
    cx, _ = detection_center(primary)
    return CLEF_CLASS_TO_KIND[primary.class_name], cx


def assign_detections_to_systems(
    systems: list[StaffSystem],
    detections: list[RawDetection],
) -> None:
    for system in systems:
        system.detections.clear()

    for detection in detections:
        if detection.class_name == "staff":
            continue
        best: StaffSystem | None = None
        best_distance = float("inf")
        best_iou = -1.0
        for system in systems:
            if system.geometry.page_index != detection.page_index:
                continue
            mid_y = system.geometry.line_y[2]
            s = system.geometry.interline_px
            _, cy = detection_center(detection)
            distance = abs(cy - mid_y)
            max_distance = ASSIGN_MAX_DISTANCE_INTERLINES * s
            if distance > max_distance:
                continue
            x1, _, x2, _ = detection.bbox_xyxy
            band_box = (
                x1,
                system.geometry.line_y[0] - 2.0 * s,
                x2,
                system.geometry.line_y[4] + 2.0 * s,
            )
            overlap = iou(detection.bbox_xyxy, band_box)
            if distance < best_distance - 1e-6 or (
                abs(distance - best_distance) <= 1e-6 and overlap > best_iou
            ):
                best = system
                best_distance = distance
                best_iou = overlap

        if best is not None:
            best.detections.append(detection)
