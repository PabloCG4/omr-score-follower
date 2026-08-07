"""Smoke tests for the reconstruction debug visualizer."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from app.schemas.omr_structural import OmrStructuralDocument
from app.utils.debug_visualizer import (
    annotate_reconstruction,
    format_note_label,
    midi_to_pitch_name,
)
from app.reconstruction.document_synthesizer import frames_per_quarter


def test_midi_to_pitch_name_e4() -> None:
    assert midi_to_pitch_name(64) == "E4"
    assert format_note_label(64, 0.25 * frames_per_quarter()) == "E4, 0.25"


def test_annotate_reconstruction_draws_on_blank_image(tmp_path: Path) -> None:
    width, height = 320, 240
    blank = Image.new("RGB", (width, height), color=(255, 255, 255))
    document = OmrStructuralDocument.model_validate(
        {
            "schemaVersion": 1,
            "documentId": "viz-test",
            "displayTitle": "Visualizer Smoke",
            "sampleRateHz": 22050.0,
            "hopLengthSamples": 512,
            "referenceFrameCount": 2,
            "pages": [{"pageIndex": 0, "widthPx": width, "heightPx": height}],
            "anchors": [
                {
                    "frameIndex": 0.0,
                    "pageIndex": 0,
                    "xNorm": 0.1,
                    "yNorm": 0.5,
                    "measureNumber": 1,
                },
                {
                    "frameIndex": 1.0,
                    "pageIndex": 0,
                    "xNorm": 0.9,
                    "yNorm": 0.5,
                    "measureNumber": 2,
                },
            ],
            "referenceChromagram": {
                "encoding": "f32le_row_major",
                "pitchClassCount": 12,
                "frameCount": 2,
                "dataBase64": (
                    # 2 frames * 12 floats; minimal valid payload via zeros with C energy
                    __import__("base64").b64encode(
                        __import__("struct").pack("<24f", *([1.0] + [0.0] * 11) * 2)
                    ).decode("ascii")
                ),
            },
            "noteEvents": [
                {
                    "midiPitch": 64,
                    "onsetFrame": 0.0,
                    "durationFrames": 0.25 * frames_per_quarter(),
                    "pageIndex": 0,
                    "xNorm": 0.5,
                    "yNorm": 0.5,
                }
            ],
        }
    )
    box = (100.0, 100.0, 140.0, 130.0)
    output_path = tmp_path / "annotated.png"
    annotated = annotate_reconstruction(
        blank,
        document,
        [box],
        output_path=output_path,
    )

    assert annotated.size == (width, height)
    assert output_path.is_file()
    # Outline is drawn on the box border; interior may remain blank.
    border_sample = annotated.getpixel((100, 110))
    assert border_sample != (255, 255, 255)
