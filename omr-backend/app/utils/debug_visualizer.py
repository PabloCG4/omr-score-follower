"""Debug overlays for reconstructed OMR note events on page images."""

from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

from PIL import Image, ImageDraw

from app.reconstruction.document_synthesizer import frames_per_quarter
from app.schemas.omr_structural import OmrStructuralDocument

PITCH_CLASS_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")


def midi_to_pitch_name(midi: int) -> str:
    """Convert MIDI note number to scientific pitch name (e.g. 64 -> E4)."""
    if midi < 0 or midi > 127:
        raise ValueError(f"MIDI pitch out of range: {midi}")
    pitch_class = midi % 12
    octave = (midi // 12) - 1
    return f"{PITCH_CLASS_NAMES[pitch_class]}{octave}"


def duration_frames_to_quarters(duration_frames: float) -> float:
    """Convert schema durationFrames back to quarter-note units at 120 BPM."""
    return float(duration_frames) / frames_per_quarter()


def format_note_label(midi_pitch: int, duration_frames: float) -> str:
    quarters = duration_frames_to_quarters(duration_frames)
    # Trim trailing zeros for readability (0.25 stays 0.25; 1.0 -> 1).
    duration_text = f"{quarters:g}"
    return f"{midi_to_pitch_name(midi_pitch)}, {duration_text}"


def annotate_reconstruction(
    image: Image.Image | Path,
    document: OmrStructuralDocument,
    notehead_boxes_xyxy: Sequence[tuple[float, float, float, float]],
    *,
    output_path: Path | None = None,
) -> Image.Image:
    """Draw pitch/duration labels over notehead boxes using document noteEvents.

    ``notehead_boxes_xyxy`` must align 1:1 with ``document.note_events`` because
    the schema stores normalized centers, not original detection bboxes.
    """
    note_events = document.note_events or []
    if len(notehead_boxes_xyxy) != len(note_events):
        raise ValueError(
            "notehead_boxes_xyxy length must equal noteEvents length "
            f"({len(notehead_boxes_xyxy)} != {len(note_events)})."
        )

    canvas = _load_rgb_image(image).copy()
    drawer = ImageDraw.Draw(canvas)
    label_fill = (220, 40, 40)
    box_outline = (30, 120, 220)

    for event, bbox in zip(note_events, notehead_boxes_xyxy, strict=True):
        x1, y1, x2, y2 = bbox
        drawer.rectangle((x1, y1, x2, y2), outline=box_outline, width=2)
        label = format_note_label(event.midi_pitch, event.duration_frames)
        text_x = x1
        text_y = max(0.0, y1 - 14.0)
        drawer.text((text_x, text_y), label, fill=label_fill)

    if output_path is not None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(output_path)

    return canvas


def _load_rgb_image(image: Image.Image | Path) -> Image.Image:
    if isinstance(image, Image.Image):
        return image.convert("RGB")
    return Image.open(image).convert("RGB")
