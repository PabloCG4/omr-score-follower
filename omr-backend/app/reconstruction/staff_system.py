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

ASSIGN_MAX_DISTANCE_INTERLINES = 3.5

# Maximum gap (in interline units) between the bottom of an upper staff and the
# top of a lower staff for a Treble+Bass pair to count as one grand staff.
GRAND_STAFF_MAX_GAP_INTERLINES = 10.0


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
    """One staff of notation with optional grand-staff pairing metadata.

    Independent staves (e.g. ensemble parts sharing the same clef) remain
    separate systems. Only a Treble-above-Bass pair may share
    [grand_staff_group_id] for concurrent timeline alignment.
    """

    system_id: int
    geometry: StaffGeometry
    detections: list[RawDetection] = field(default_factory=list)
    grand_staff_group_id: int | None = None


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
    """Build staff systems from staff boxes (preferred) or one system per clef.

    Single-instrument tracking policy: never collapse ensemble staves into one
    system. Grand-staff Treble+Bass pairs are linked via [grand_staff_group_id]
    after assembly for concurrent timeline use only.
    """
    by_page: dict[int, list[RawDetection]] = {}
    for detection in detections:
        by_page.setdefault(detection.page_index, []).append(detection)

    systems: list[StaffSystem] = []
    next_id = 0
    next_group_id = 0
    for page_index in sorted(by_page.keys()):
        page_detections = by_page[page_index]
        page_systems = _assemble_page(page_index, page_detections, next_id)
        next_group_id = link_grand_staff_pairs(page_systems, next_group_id)
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

    # One StaffSystem per clef. Nearby same-clef ensemble parts must not
    # collapse into a single system (former leftmost-clef grouping).
    systems: list[StaffSystem] = []
    for offset, clef in enumerate(clefs):
        kind = CLEF_CLASS_TO_KIND[clef.class_name]
        line_y, interline = build_line_y_from_clef(clef.bbox_xyxy, kind)
        cx, _ = detection_center(clef)
        geometry = StaffGeometry(
            page_index=page_index,
            line_y=line_y,
            interline_px=interline,
            clef_kind=kind,
            clef_center_x=cx,
        )
        systems.append(StaffSystem(system_id=start_id + offset, geometry=geometry))
    return systems


def link_grand_staff_pairs(
    systems: list[StaffSystem],
    next_group_id: int = 0,
) -> int:
    """Link adjacent Treble-above-Bass systems as grand-staff pairs.

    Only the semantic combination upper clef G + lower clef F within a vertical
    gap threshold receives a shared [grand_staff_group_id]. Ensemble staves
    (G+G, F+F, inverted F above G, C-clefs) remain independent.

    Returns the next free group id for subsequent pages.
    """
    if len(systems) < 2:
        return next_group_id

    ordered = sorted(
        systems,
        key=lambda system: (system.geometry.line_y[2], system.system_id),
    )
    index = 0
    group_id = next_group_id
    while index < len(ordered) - 1:
        upper = ordered[index]
        lower = ordered[index + 1]
        if (
            upper.grand_staff_group_id is None
            and lower.grand_staff_group_id is None
            and upper.geometry.clef_kind == "G"
            and lower.geometry.clef_kind == "F"
            and _grand_staff_vertical_gap_ok(upper, lower)
        ):
            upper.grand_staff_group_id = group_id
            lower.grand_staff_group_id = group_id
            group_id += 1
            index += 2
            continue
        index += 1
    return group_id


def _grand_staff_vertical_gap_ok(upper: StaffSystem, lower: StaffSystem) -> bool:
    """True when the lower staff sits immediately under the upper staff."""
    gap = lower.geometry.line_y[0] - upper.geometry.line_y[4]
    if gap < -1e-3:
        return False
    reference_interline = max(
        upper.geometry.interline_px,
        lower.geometry.interline_px,
        1e-6,
    )
    return gap <= GRAND_STAFF_MAX_GAP_INTERLINES * reference_interline


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
