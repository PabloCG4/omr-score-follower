"""Stable DeepScores-style class taxonomy for OMR detections (placeholder IDs).

Class IDs are fixed so Phase C.3 can map symbols without renumbering.
"""

from __future__ import annotations

# Ordered list: index == class_id.
OMR_CLASS_NAMES: list[str] = [
    "noteheadBlack",
    "noteheadHalf",
    "noteheadWhole",
    "stem",
    "beam",
    "flag8thUp",
    "flag8thDown",
    "restQuarter",
    "restHalf",
    "restWhole",
    "clefG",
    "clefF",
    "clefC",
    "accidentalSharp",
    "accidentalFlat",
    "accidentalNatural",
    "timeSigCommon",
    "barline",
    "ledgerLine",
    "augmentationDot",
]


def build_category_mapping() -> dict[str, str]:
    """SAHI category_mapping: category id string -> category name."""
    return {str(index): name for index, name in enumerate(OMR_CLASS_NAMES)}


def class_name_for_id(class_id: int) -> str:
    if 0 <= class_id < len(OMR_CLASS_NAMES):
        return OMR_CLASS_NAMES[class_id]
    return f"unknown_{class_id}"
