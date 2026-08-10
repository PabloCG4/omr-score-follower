"""DeepScores category loading and aliasing into reconstruction class names."""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from pathlib import Path

LOGGER = logging.getLogger(__name__)

DATA_DIR = Path(__file__).resolve().parent / "data"
DEFAULT_CATEGORIES_PATH = DATA_DIR / "deepscores_categories.json"

# Map DeepScores / training label names onto reconstruction taxonomy names.
DEEPSCORES_TO_RECONSTRUCTION_ALIASES: dict[str, str] = {
    "noteheadBlackOnLine": "noteheadBlack",
    "noteheadBlackInSpace": "noteheadBlack",
    "noteheadBlack": "noteheadBlack",
    "noteheadHalfOnLine": "noteheadHalf",
    "noteheadHalfInSpace": "noteheadHalf",
    "noteheadHalf": "noteheadHalf",
    "noteheadWholeOnLine": "noteheadWhole",
    "noteheadWholeInSpace": "noteheadWhole",
    "noteheadWhole": "noteheadWhole",
    "keySharp": "accidentalSharp",
    "keyFlat": "accidentalFlat",
    "keyNatural": "accidentalNatural",
    "legerLine": "ledgerLine",
    "ledgerLine": "ledgerLine",
    "clefCAlto": "clefC",
    "clefCTenor": "clefC",
    "clefC": "clefC",
}


@lru_cache
def load_deepscores_category_names(
    categories_path: str | None = None,
) -> tuple[str, ...]:
    """Load ordered foreground class names (index 0 == torchvision label 1)."""
    path = Path(categories_path) if categories_path else DEFAULT_CATEGORIES_PATH
    if not path.is_file():
        raise FileNotFoundError(f"DeepScores category file not found: {path}")
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list) or not all(isinstance(item, str) for item in raw):
        raise ValueError(f"Category file must be a JSON list of strings: {path}")
    names = tuple(str(item) for item in raw)
    if not names:
        raise ValueError(f"Category file is empty: {path}")
    return names


def build_torchvision_category_mapping(
    category_names: tuple[str, ...] | list[str] | None = None,
) -> dict[str, str]:
    """SAHI mapping: torchvision label id string -> DeepScores class name.

    Label 0 is background and is omitted. Foreground labels are 1..N.
    """
    names = category_names if category_names is not None else load_deepscores_category_names()
    return {str(index + 1): name for index, name in enumerate(names)}


def alias_to_reconstruction_class_name(deep_scores_name: str) -> str:
    """Map a DeepScores label name to the C.3 reconstruction taxonomy name."""
    if deep_scores_name in DEEPSCORES_TO_RECONSTRUCTION_ALIASES:
        return DEEPSCORES_TO_RECONSTRUCTION_ALIASES[deep_scores_name]
    return deep_scores_name


def validate_category_count_against_num_classes(
    category_names: tuple[str, ...] | list[str],
    num_classes_including_background: int,
) -> None:
    expected = num_classes_including_background - 1
    actual = len(category_names)
    if actual != expected:
        raise ValueError(
            f"DeepScores category count {actual} does not match model "
            f"foreground classes {expected} (num_classes={num_classes_including_background})."
        )
