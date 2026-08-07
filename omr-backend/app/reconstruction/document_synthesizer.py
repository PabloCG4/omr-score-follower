"""Serialize reconstructed notes into a schema-v1 OmrStructuralDocument."""

from __future__ import annotations

import base64
import math
import struct
import uuid
from dataclasses import dataclass

from app.reconstruction.geometry import detection_center
from app.reconstruction.staff_system import StaffSystem
from app.reconstruction.timeline_builder import ReconstructedNote
from app.schemas.omr_structural import OmrStructuralDocument
from app.vision.detections import PageImage, RawDetection

SAMPLE_RATE_HZ = 22050.0
HOP_LENGTH_SAMPLES = 512
SECONDS_PER_QUARTER = 0.5  # 120 BPM
PITCH_CLASS_COUNT = 12


@dataclass(frozen=True, slots=True)
class PageSize:
    page_index: int
    width_px: int
    height_px: int


def frames_per_quarter(
    *,
    sample_rate_hz: float = SAMPLE_RATE_HZ,
    hop_length_samples: int = HOP_LENGTH_SAMPLES,
    seconds_per_quarter: float = SECONDS_PER_QUARTER,
) -> float:
    return (sample_rate_hz / float(hop_length_samples)) * seconds_per_quarter


def synthesize_document(
    *,
    notes: list[ReconstructedNote],
    systems: list[StaffSystem],
    detections: list[RawDetection],
    pages: list[PageSize],
    display_title: str,
    document_id: str | None = None,
) -> OmrStructuralDocument:
    if not pages:
        raise ValueError("At least one page is required.")

    fpq = frames_per_quarter()
    note_events_payload: list[dict[str, object]] = []
    for note in notes:
        page = _page_for_index(pages, note.page_index)
        note_events_payload.append(
            {
                "midiPitch": note.midi_pitch,
                "onsetFrame": note.onset_quarters * fpq,
                "durationFrames": max(note.duration_quarters * fpq, 1e-3),
                "pageIndex": note.page_index,
                "xNorm": _clamp01(note.x_center / float(page.width_px)),
                "yNorm": _clamp01(note.y_center / float(page.height_px)),
            }
        )

    total_quarters = 0.0
    if notes:
        total_quarters = max(
            note.onset_quarters + note.duration_quarters for note in notes
        )
    frame_count = max(1, int(math.ceil(total_quarters * fpq)))

    chromagram_bytes = _synthesize_chromagram_bytes(notes, frame_count, fpq)
    anchors = _build_anchors(
        detections=detections,
        systems=systems,
        notes=notes,
        pages=pages,
        frame_count=frame_count,
        frames_per_quarter_value=fpq,
    )

    payload = {
        "schemaVersion": 1,
        "documentId": document_id or str(uuid.uuid4()),
        "displayTitle": display_title,
        "sampleRateHz": SAMPLE_RATE_HZ,
        "hopLengthSamples": HOP_LENGTH_SAMPLES,
        "referenceFrameCount": frame_count,
        "pages": [
            {
                "pageIndex": page.page_index,
                "widthPx": page.width_px,
                "heightPx": page.height_px,
            }
            for page in sorted(pages, key=lambda item: item.page_index)
        ],
        "anchors": anchors,
        "referenceChromagram": {
            "encoding": "f32le_row_major",
            "pitchClassCount": PITCH_CLASS_COUNT,
            "frameCount": frame_count,
            "dataBase64": base64.b64encode(chromagram_bytes).decode("ascii"),
        },
        "noteEvents": note_events_payload or None,
    }
    return OmrStructuralDocument.model_validate(payload)


def page_sizes_from_page_images(page_images: list[PageImage]) -> list[PageSize]:
    return [
        PageSize(
            page_index=page.page_index,
            width_px=page.width_px,
            height_px=page.height_px,
        )
        for page in page_images
    ]


def _synthesize_chromagram_bytes(
    notes: list[ReconstructedNote],
    frame_count: int,
    frames_per_quarter_value: float,
) -> bytes:
    frames = [[0.0] * PITCH_CLASS_COUNT for _ in range(frame_count)]
    for note in notes:
        start = int(math.floor(note.onset_quarters * frames_per_quarter_value))
        end = int(
            math.ceil(
                (note.onset_quarters + note.duration_quarters)
                * frames_per_quarter_value
            )
        )
        pitch_class = note.midi_pitch % PITCH_CLASS_COUNT
        for frame_index in range(max(0, start), min(frame_count, max(start + 1, end))):
            frames[frame_index][pitch_class] = 1.0

    # Ensure empty scores still have a valid chromagram frame.
    if not notes:
        frames[0][0] = 1.0

    for frame in frames:
        norm = math.sqrt(sum(value * value for value in frame))
        if norm > 0.0:
            for index in range(PITCH_CLASS_COUNT):
                frame[index] /= norm

    values: list[float] = [value for frame in frames for value in frame]
    return struct.pack(f"<{len(values)}f", *values)


def _build_anchors(
    *,
    detections: list[RawDetection],
    systems: list[StaffSystem],
    notes: list[ReconstructedNote],
    pages: list[PageSize],
    frame_count: int,
    frames_per_quarter_value: float,
) -> list[dict[str, object]]:
    system_by_page: dict[int, StaffSystem] = {}
    for system in systems:
        system_by_page.setdefault(system.geometry.page_index, system)

    barlines = [d for d in detections if d.class_name == "barline"]
    barlines.sort(
        key=lambda d: (d.page_index, detection_center(d)[0], detection_center(d)[1])
    )

    anchors: list[dict[str, object]] = []
    measure_number = 1

    # Always include frame 0.
    first_page = pages[0]
    first_system = system_by_page.get(first_page.page_index)
    y0 = (
        first_system.geometry.line_y[2]
        if first_system is not None
        else first_page.height_px * 0.5
    )
    anchors.append(
        {
            "frameIndex": 0.0,
            "pageIndex": first_page.page_index,
            "xNorm": 0.08,
            "yNorm": _clamp01(y0 / float(first_page.height_px)),
            "measureNumber": measure_number,
        }
    )

    for barline in barlines:
        page = _page_for_index(pages, barline.page_index)
        bx, by = detection_center(barline)
        frame_index = _interpolate_frame_at_x(
            notes, barline.page_index, bx, frames_per_quarter_value
        )
        measure_number += 1
        anchors.append(
            {
                "frameIndex": float(frame_index),
                "pageIndex": barline.page_index,
                "xNorm": _clamp01(bx / float(page.width_px)),
                "yNorm": _clamp01(by / float(page.height_px)),
                "measureNumber": measure_number,
            }
        )

    last_frame = float(max(frame_count - 1, 0))
    if anchors[-1]["frameIndex"] < last_frame:
        last_page = pages[-1]
        last_system = system_by_page.get(last_page.page_index)
        y_last = (
            last_system.geometry.line_y[2]
            if last_system is not None
            else last_page.height_px * 0.5
        )
        anchors.append(
            {
                "frameIndex": last_frame,
                "pageIndex": last_page.page_index,
                "xNorm": 0.92,
                "yNorm": _clamp01(y_last / float(last_page.height_px)),
                "measureNumber": measure_number + 1,
            }
        )

    # Ensure strictly non-decreasing frameIndex for schema validator.
    previous = float("-inf")
    normalized: list[dict[str, object]] = []
    for anchor in anchors:
        frame_index = float(anchor["frameIndex"])
        if frame_index < previous:
            frame_index = previous
        anchor = {**anchor, "frameIndex": frame_index}
        previous = frame_index
        normalized.append(anchor)
    return normalized


def _interpolate_frame_at_x(
    notes: list[ReconstructedNote],
    page_index: int,
    x_position: float,
    frames_per_quarter_value: float,
) -> float:
    page_notes = [note for note in notes if note.page_index == page_index]
    if not page_notes:
        return 0.0
    ordered = sorted(page_notes, key=lambda note: note.x_center)
    if x_position <= ordered[0].x_center:
        return ordered[0].onset_quarters * frames_per_quarter_value
    if x_position >= ordered[-1].x_center:
        last = ordered[-1]
        return (last.onset_quarters + last.duration_quarters) * frames_per_quarter_value
    for left, right in zip(ordered, ordered[1:]):
        if left.x_center <= x_position <= right.x_center:
            span = right.x_center - left.x_center
            if span <= 1e-6:
                return left.onset_quarters * frames_per_quarter_value
            ratio = (x_position - left.x_center) / span
            t = left.onset_quarters + ratio * (
                right.onset_quarters - left.onset_quarters
            )
            return t * frames_per_quarter_value
    return ordered[-1].onset_quarters * frames_per_quarter_value


def _page_for_index(pages: list[PageSize], page_index: int) -> PageSize:
    for page in pages:
        if page.page_index == page_index:
            return page
    raise ValueError(f"Missing page size for pageIndex={page_index}.")


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))
