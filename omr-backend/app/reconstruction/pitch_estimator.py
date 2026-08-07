"""Pitch estimation from notehead Y relative to staff geometry."""

from __future__ import annotations

from dataclasses import dataclass

from app.reconstruction.geometry import detection_center, horizontal_gap
from app.reconstruction.staff_system import StaffGeometry, StaffSystem
from app.vision.detections import RawDetection

# Bottom-line MIDI for each clef (half_spaces == 0).
CLEF_BOTTOM_LINE_MIDI: dict[str, int] = {
    "G": 64,  # E4
    "F": 43,  # G2
    "C": 53,  # F3
}

# Natural letter cycle starting at bottom-line letter for each clef.
# Index advances with half_spaces; octave bumps when wrapping past B.
CLEF_BOTTOM_LETTER_INDEX: dict[str, int] = {
    "G": 2,  # E
    "F": 4,  # G
    "C": 3,  # F
}

LETTER_NAMES = ("C", "D", "E", "F", "G", "A", "B")
LETTER_TO_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

NOTEHEAD_CLASSES = frozenset({"noteheadBlack", "noteheadHalf", "noteheadWhole"})
ACCIDENTAL_DELTA = {
    "accidentalSharp": 1,
    "accidentalFlat": -1,
    "accidentalNatural": 0,
}


@dataclass(frozen=True, slots=True)
class PitchedNotehead:
    detection: RawDetection
    midi_pitch: int
    x_center: float
    y_center: float


def half_spaces_from_bottom(y_note: float, geometry: StaffGeometry) -> int:
    y_bottom = geometry.line_y[4]
    s = geometry.interline_px
    if s <= 0.0:
        raise ValueError("interline_px must be positive.")
    return int(round(2.0 * (y_bottom - y_note) / s))


def diatonic_midi_from_half_spaces(
    half_spaces: int,
    *,
    clef_kind: str,
) -> tuple[int, str]:
    """Return (natural MIDI, letter name) for a staff step under the active clef."""
    bottom_midi = CLEF_BOTTOM_LINE_MIDI[clef_kind]
    letter_index = CLEF_BOTTOM_LETTER_INDEX[clef_kind]
    bottom_letter = LETTER_NAMES[letter_index]
    bottom_pc = LETTER_TO_PC[bottom_letter]
    octave_index = (bottom_midi - bottom_pc) // 12

    idx = letter_index
    oct_index = octave_index
    if half_spaces >= 0:
        for _ in range(half_spaces):
            idx = (idx + 1) % 7
            if idx == 0:
                oct_index += 1
    else:
        for _ in range(-half_spaces):
            if idx == 0:
                oct_index -= 1
            idx = (idx - 1) % 7

    letter = LETTER_NAMES[idx]
    midi = LETTER_TO_PC[letter] + 12 * oct_index
    return midi, letter


def estimate_key_signature_alterations(
    system: StaffSystem,
) -> dict[str, int]:
    """Map letter -> semitone delta from sharps/flats immediately right of the clef."""
    geometry = system.geometry
    s = geometry.interline_px
    clef_x = geometry.clef_center_x

    # First structural marker after the clef.
    markers = [
        d
        for d in system.detections
        if d.class_name in NOTEHEAD_CLASSES
        or d.class_name in {"timeSigCommon", "barline"}
    ]
    first_marker_x = min(
        (detection_center(d)[0] for d in markers),
        default=float("inf"),
    )

    alterations: dict[str, int] = {}
    accidentals = [
        d
        for d in system.detections
        if d.class_name in {"accidentalSharp", "accidentalFlat"}
    ]
    accidentals.sort(key=lambda d: detection_center(d)[0])

    # Order of adding sharps / flats in key signatures.
    sharp_order = ["F", "C", "G", "D", "A", "E", "B"]
    flat_order = ["B", "E", "A", "D", "G", "C", "F"]

    sharp_count = 0
    flat_count = 0
    for accidental in accidentals:
        ax, _ = detection_center(accidental)
        if ax <= clef_x:
            continue
        if ax >= first_marker_x:
            break
        # Must sit near the staff vertically.
        if abs(detection_center(accidental)[1] - geometry.line_y[2]) > 3.5 * s:
            continue
        if accidental.class_name == "accidentalSharp":
            if sharp_count < len(sharp_order):
                alterations[sharp_order[sharp_count]] = 1
                sharp_count += 1
        elif accidental.class_name == "accidentalFlat":
            if flat_count < len(flat_order):
                alterations[flat_order[flat_count]] = -1
                flat_count += 1
    return alterations


def find_local_accidental(
    notehead: RawDetection,
    system: StaffSystem,
) -> str | None:
    s = system.geometry.interline_px
    nx, ny = detection_center(notehead)
    best: RawDetection | None = None
    best_key: tuple[float, float] | None = None

    for accidental in system.detections:
        if accidental.class_name not in ACCIDENTAL_DELTA:
            continue
        if accidental.bbox_xyxy[2] >= notehead.bbox_xyxy[0]:
            continue
        gap = horizontal_gap(accidental.bbox_xyxy, notehead.bbox_xyxy)
        if gap < 0.0 or gap >= 2.5 * s:
            continue
        ay = detection_center(accidental)[1]
        if abs(ay - ny) >= 0.75 * s:
            continue
        key = (gap, abs(ay - ny))
        if best_key is None or key < best_key:
            best = accidental
            best_key = key

    return None if best is None else best.class_name


def estimate_midi_for_notehead(
    notehead: RawDetection,
    system: StaffSystem,
    key_alterations: dict[str, int] | None = None,
) -> int:
    geometry = system.geometry
    _, y_n = detection_center(notehead)
    half_spaces = half_spaces_from_bottom(y_n, geometry)
    natural_midi, letter = diatonic_midi_from_half_spaces(
        half_spaces, clef_kind=geometry.clef_kind
    )

    local = find_local_accidental(notehead, system)
    if local is not None:
        if local == "accidentalNatural":
            midi = natural_midi
        else:
            midi = natural_midi + ACCIDENTAL_DELTA[local]
    else:
        delta = 0 if key_alterations is None else key_alterations.get(letter, 0)
        midi = natural_midi + delta

    return max(0, min(127, midi))


def pitch_noteheads_in_system(system: StaffSystem) -> list[PitchedNotehead]:
    key_alterations = estimate_key_signature_alterations(system)
    pitched: list[PitchedNotehead] = []
    for detection in system.detections:
        if detection.class_name not in NOTEHEAD_CLASSES:
            continue
        cx, cy = detection_center(detection)
        midi = estimate_midi_for_notehead(detection, system, key_alterations)
        pitched.append(
            PitchedNotehead(
                detection=detection,
                midi_pitch=midi,
                x_center=cx,
                y_center=cy,
            )
        )
    return pitched
