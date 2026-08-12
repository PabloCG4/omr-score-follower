"""Chronological sorting, chord grouping, and onset accumulation."""

from __future__ import annotations

from dataclasses import dataclass

from app.reconstruction.pitch_estimator import PitchedNotehead, pitch_noteheads_in_system
from app.reconstruction.rhythm_estimator import (
    REST_QUARTERS,
    estimate_notehead_duration_quarters,
    estimate_rest_duration_quarters,
)
from app.reconstruction.staff_system import StaffSystem

CHORD_X_TOLERANCE_INTERLINES = 0.6


@dataclass(frozen=True, slots=True)
class ReconstructedNote:
    page_index: int
    x_center: float
    y_center: float
    midi_pitch: int
    duration_quarters: float
    staff_system_id: int
    onset_quarters: float


@dataclass(frozen=True, slots=True)
class TimelineRest:
    page_index: int
    x_center: float
    y_center: float
    duration_quarters: float
    staff_system_id: int
    onset_quarters: float


def build_timeline_for_system(
    system: StaffSystem,
) -> tuple[list[ReconstructedNote], list[TimelineRest]]:
    pitched = pitch_noteheads_in_system(system)
    s = system.geometry.interline_px

    events: list[tuple[float, str, object]] = []
    for note in pitched:
        duration = estimate_notehead_duration_quarters(note.detection, system)
        events.append((note.x_center, "note", (note, duration)))

    for detection in system.detections:
        if detection.class_name not in REST_QUARTERS:
            continue
        cx = (detection.bbox_xyxy[0] + detection.bbox_xyxy[2]) * 0.5
        cy = (detection.bbox_xyxy[1] + detection.bbox_xyxy[3]) * 0.5
        duration = estimate_rest_duration_quarters(detection)
        events.append((cx, "rest", (detection, cx, cy, duration)))

    events.sort(key=lambda item: (item[0], 0 if item[1] == "note" else 1))

    notes_out: list[ReconstructedNote] = []
    rests_out: list[TimelineRest] = []
    time_quarters = 0.0
    index = 0
    while index < len(events):
        x0, kind, payload = events[index]
        if kind == "rest":
            _detection, cx, cy, duration = payload  # type: ignore[misc]
            rests_out.append(
                TimelineRest(
                    page_index=system.geometry.page_index,
                    x_center=float(cx),
                    y_center=float(cy),
                    duration_quarters=float(duration),
                    staff_system_id=system.system_id,
                    onset_quarters=time_quarters,
                )
            )
            time_quarters += float(duration)
            index += 1
            continue

        chord: list[tuple[PitchedNotehead, float]] = []
        while index < len(events):
            x_i, kind_i, payload_i = events[index]
            if kind_i != "note":
                break
            if chord and abs(x_i - x0) >= CHORD_X_TOLERANCE_INTERLINES * s:
                break
            note_i, duration_i = payload_i  # type: ignore[misc]
            chord.append((note_i, float(duration_i)))
            index += 1

        max_duration = max(duration for _, duration in chord)
        for note_i, duration_i in chord:
            notes_out.append(
                ReconstructedNote(
                    page_index=system.geometry.page_index,
                    x_center=note_i.x_center,
                    y_center=note_i.y_center,
                    midi_pitch=note_i.midi_pitch,
                    duration_quarters=duration_i,
                    staff_system_id=system.system_id,
                    onset_quarters=time_quarters,
                )
            )
        time_quarters += max_duration

    return notes_out, rests_out


def build_full_timeline(systems: list[StaffSystem]) -> list[ReconstructedNote]:
    """Build a global note timeline across systems.

    Independent systems are concatenated top-to-bottom (sequential). Systems
    that share a [StaffSystem.grand_staff_group_id] (Treble+Bass grand staff)
    share one local onset clock so both staves advance concurrently.
    """
    all_notes: list[ReconstructedNote] = []
    global_time = 0.0
    ordered = sorted(
        systems,
        key=lambda system: (
            system.geometry.page_index,
            system.geometry.line_y[2],
            system.system_id,
        ),
    )

    index = 0
    while index < len(ordered):
        system = ordered[index]
        group_id = system.grand_staff_group_id
        if group_id is not None:
            # Consume every member of this grand-staff group in page order.
            span = 0
            while index + span < len(ordered) and ordered[
                index + span
            ].grand_staff_group_id == group_id:
                span += 1
            pair = ordered[index : index + span]
            notes, span_end = _concurrent_notes_for_systems(pair, global_time)
            all_notes.extend(notes)
            global_time += span_end
            index += span
            continue

        notes, rests = build_timeline_for_system(system)
        note_end = max(
            (note.onset_quarters + note.duration_quarters for note in notes),
            default=0.0,
        )
        rest_end = max(
            (rest.onset_quarters + rest.duration_quarters for rest in rests),
            default=0.0,
        )
        for note in notes:
            all_notes.append(
                ReconstructedNote(
                    page_index=note.page_index,
                    x_center=note.x_center,
                    y_center=note.y_center,
                    midi_pitch=note.midi_pitch,
                    duration_quarters=note.duration_quarters,
                    staff_system_id=note.staff_system_id,
                    onset_quarters=global_time + note.onset_quarters,
                )
            )
        global_time += max(note_end, rest_end)
        index += 1

    return all_notes


def _concurrent_notes_for_systems(
    systems: list[StaffSystem],
    global_time: float,
) -> tuple[list[ReconstructedNote], float]:
    """Offset each system timeline by [global_time]; advance by max duration."""
    merged: list[ReconstructedNote] = []
    span_end = 0.0
    for system in systems:
        notes, rests = build_timeline_for_system(system)
        note_end = max(
            (note.onset_quarters + note.duration_quarters for note in notes),
            default=0.0,
        )
        rest_end = max(
            (rest.onset_quarters + rest.duration_quarters for rest in rests),
            default=0.0,
        )
        span_end = max(span_end, note_end, rest_end)
        for note in notes:
            merged.append(
                ReconstructedNote(
                    page_index=note.page_index,
                    x_center=note.x_center,
                    y_center=note.y_center,
                    midi_pitch=note.midi_pitch,
                    duration_quarters=note.duration_quarters,
                    staff_system_id=note.staff_system_id,
                    onset_quarters=global_time + note.onset_quarters,
                )
            )
    return merged, span_end
