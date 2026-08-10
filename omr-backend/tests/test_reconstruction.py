"""Unit and integration tests for Phase 5.5.3.C.3 structural reconstruction."""

from __future__ import annotations

from app.reconstruction.document_synthesizer import PageSize, frames_per_quarter
from app.reconstruction.pitch_estimator import (
    estimate_midi_for_notehead,
    half_spaces_from_bottom,
)
from app.reconstruction.rhythm_estimator import estimate_notehead_duration_quarters
from app.reconstruction.staff_system import (
    StaffGeometry,
    StaffSystem,
    assemble_staff_systems,
    build_line_y_from_staff_bbox,
)
from app.reconstruction.structural_reconstruction_service import (
    StructuralReconstructionService,
)
from app.schemas.omr_structural import OmrStructuralDocument
from app.vision.category_taxonomy import OMR_CLASS_NAMES
from app.vision.detections import RawDetection

# Locked validation fixtures (Phase C.3 validation strategy).
STAFF_BBOX = (40.0, 100.0, 560.0, 200.0)
CLEF_G_BBOX = (50.0, 110.0, 95.0, 190.0)
NOTEHEAD_E4_BBOX = (200.0, 190.0, 220.0, 210.0)  # center y=200 on bottom line
RHYTHM_NOTEHEAD_BBOX = (200.0, 150.0, 220.0, 170.0)
RHYTHM_STEM_BBOX = (214.0, 100.0, 226.0, 168.0)
RHYTHM_FLAG16_BBOX = (214.0, 100.0, 236.0, 128.0)


def detection(
    class_name: str,
    bbox: tuple[float, float, float, float],
    *,
    page_index: int = 0,
    confidence: float = 0.9,
) -> RawDetection:
    class_id = OMR_CLASS_NAMES.index(class_name)
    return RawDetection(
        page_index=page_index,
        bbox_xyxy=bbox,
        class_id=class_id,
        class_name=class_name,
        confidence=confidence,
    )


def locked_staff_geometry() -> StaffGeometry:
    """Staff Y 100→200 → interline 25, lines at 100/125/150/175/200."""
    line_y, interline = build_line_y_from_staff_bbox(STAFF_BBOX)
    return StaffGeometry(
        page_index=0,
        line_y=line_y,
        interline_px=interline,
        clef_kind="G",
        clef_center_x=72.5,
    )


def treble_staff_geometry() -> StaffGeometry:
    # Lines at y=100,120,140,160,180 → interline 20
    line_y, interline = build_line_y_from_staff_bbox((50.0, 100.0, 500.0, 180.0))
    return StaffGeometry(
        page_index=0,
        line_y=line_y,
        interline_px=interline,
        clef_kind="G",
        clef_center_x=70.0,
    )


def test_pitch_bottom_line_e4_midi_64() -> None:
    """Locked pitch fixture: staff 100–200, notehead on bottom line → MIDI 64."""
    detections = [
        detection("staff", STAFF_BBOX),
        detection("clefG", CLEF_G_BBOX),
        detection("noteheadBlack", NOTEHEAD_E4_BBOX),
    ]
    systems = assemble_staff_systems(detections)
    assert len(systems) == 1
    system = systems[0]
    assert system.geometry.clef_kind == "G"
    assert system.geometry.line_y[4] == 200.0
    assert system.geometry.interline_px == 25.0

    noteheads = [d for d in system.detections if d.class_name == "noteheadBlack"]
    assert len(noteheads) == 1
    assert estimate_midi_for_notehead(noteheads[0], system) == 64


def test_rhythm_flag16th_high_iou_duration_0_25() -> None:
    """Locked rhythm fixture: black head + stem + flag16thUp → 0.25 quarters."""
    geometry = locked_staff_geometry()
    note = detection("noteheadBlack", RHYTHM_NOTEHEAD_BBOX)
    stem = detection("stem", RHYTHM_STEM_BBOX)
    flag = detection("flag16thUp", RHYTHM_FLAG16_BBOX)
    system = StaffSystem(
        system_id=0,
        geometry=geometry,
        detections=[note, stem, flag],
    )
    assert estimate_notehead_duration_quarters(note, system) == 0.25


def test_reconstruction_output_passes_model_validate() -> None:
    """Synthetic detections → reconstruct → explicit Pydantic re-validation."""
    # E4 notehead with stem/flag placed for high IoU (16th) on the locked staff.
    stem_bbox = (214.0, 130.0, 226.0, 208.0)
    flag_bbox = (214.0, 130.0, 236.0, 158.0)
    detections = [
        detection("staff", STAFF_BBOX),
        detection("clefG", CLEF_G_BBOX),
        detection("noteheadBlack", NOTEHEAD_E4_BBOX),
        detection("stem", stem_bbox),
        detection("flag16thUp", flag_bbox),
        detection("barline", (480.0, 95.0, 488.0, 205.0)),
    ]
    pages = [PageSize(page_index=0, width_px=640, height_px=360)]
    document = StructuralReconstructionService().reconstruct(
        detections,
        pages,
        title="Validation Score",
        pdf_path=None,
    )

    revalidated = OmrStructuralDocument.model_validate(
        document.model_dump(by_alias=True)
    )
    assert revalidated.schema_version == 1
    assert revalidated.note_events is not None
    assert len(revalidated.note_events) == 1
    event = revalidated.note_events[0]
    assert event.midi_pitch == 64
    duration_quarters = event.duration_frames / frames_per_quarter()
    assert abs(duration_quarters - 0.25) < 1e-6
    assert (
        revalidated.reference_chromagram.frame_count
        == revalidated.reference_frame_count
    )
    assert len(revalidated.anchors) >= 1
    frame_indices = [anchor.frame_index for anchor in revalidated.anchors]
    assert frame_indices == sorted(frame_indices)


def test_multi_page_anchors_have_increasing_frames_on_later_pages() -> None:
    """Notes on page 1 must produce page-1 anchors that are not collapsed to frame 0."""
    from app.reconstruction.document_synthesizer import (
        _build_anchors,
        _interpolate_frame_at_x,
        frames_per_quarter,
    )
    from app.reconstruction.timeline_builder import ReconstructedNote

    fpq = frames_per_quarter()
    notes = [
        ReconstructedNote(
            page_index=0,
            x_center=120.0,
            y_center=150.0,
            midi_pitch=64,
            duration_quarters=1.0,
            staff_system_id=0,
            onset_quarters=0.0,
        ),
        ReconstructedNote(
            page_index=0,
            x_center=300.0,
            y_center=150.0,
            midi_pitch=67,
            duration_quarters=1.0,
            staff_system_id=0,
            onset_quarters=1.0,
        ),
        ReconstructedNote(
            page_index=1,
            x_center=140.0,
            y_center=160.0,
            midi_pitch=69,
            duration_quarters=1.0,
            staff_system_id=1,
            onset_quarters=2.0,
        ),
        ReconstructedNote(
            page_index=1,
            x_center=320.0,
            y_center=160.0,
            midi_pitch=71,
            duration_quarters=1.0,
            staff_system_id=1,
            onset_quarters=3.0,
        ),
    ]
    pages = [
        PageSize(page_index=0, width_px=640, height_px=360),
        PageSize(page_index=1, width_px=640, height_px=360),
    ]

    # Barline on page 1 with no page-local notes must not resolve to frame 0.
    # (Simulate empty page notes for page 2 index that has notes on page 1.)
    fallback = _interpolate_frame_at_x(notes, page_index=2, x_position=200.0, frames_per_quarter_value=fpq)
    assert fallback > 0.0

    frame_count = max(1, int((3.0 + 1.0) * fpq))
    anchors = _build_anchors(
        detections=[],
        systems=[],
        notes=notes,
        pages=pages,
        frame_count=frame_count,
        frames_per_quarter_value=fpq,
    )
    page1_anchors = [a for a in anchors if int(a["pageIndex"]) == 1]
    assert len(page1_anchors) >= 2
    page1_frames = [float(a["frameIndex"]) for a in page1_anchors]
    assert min(page1_frames) > 0.0
    assert page1_frames == sorted(page1_frames)
    all_frames = [float(a["frameIndex"]) for a in anchors]
    assert all_frames == sorted(all_frames)


def test_half_spaces_and_treble_pitches() -> None:
    geometry = treble_staff_geometry()
    # Bottom line E4
    assert half_spaces_from_bottom(180.0, geometry) == 0
    # Second line from bottom = G4
    assert half_spaces_from_bottom(160.0, geometry) == 2
    # Top line F5
    assert half_spaces_from_bottom(100.0, geometry) == 8

    system = StaffSystem(system_id=0, geometry=geometry, detections=[])
    e4 = detection("noteheadBlack", (200.0, 170.0, 220.0, 190.0))
    g4 = detection("noteheadBlack", (240.0, 150.0, 260.0, 170.0))
    system.detections = [e4, g4]
    assert estimate_midi_for_notehead(e4, system) == 64
    assert estimate_midi_for_notehead(g4, system) == 67


def test_local_sharp_raises_pitch() -> None:
    geometry = treble_staff_geometry()
    note = detection("noteheadBlack", (220.0, 150.0, 240.0, 170.0))  # G4
    sharp = detection("accidentalSharp", (200.0, 148.0, 212.0, 172.0))
    system = StaffSystem(system_id=0, geometry=geometry, detections=[sharp, note])
    assert estimate_midi_for_notehead(note, system) == 68  # G#4


def test_rhythm_flag_and_dot() -> None:
    geometry = treble_staff_geometry()
    note = detection("noteheadBlack", (200.0, 150.0, 220.0, 170.0))
    stem = detection("stem", (218.0, 90.0, 224.0, 160.0))
    flag = detection("flag8thUp", (224.0, 90.0, 240.0, 120.0))
    system = StaffSystem(
        system_id=0, geometry=geometry, detections=[note, stem, flag]
    )
    assert estimate_notehead_duration_quarters(note, system) == 0.5

    dotted = detection("noteheadBlack", (300.0, 150.0, 320.0, 170.0))
    dot = detection("augmentationDot", (322.0, 155.0, 330.0, 165.0))
    system2 = StaffSystem(system_id=0, geometry=geometry, detections=[dotted, dot])
    assert estimate_notehead_duration_quarters(dotted, system2) == 1.5

    half = detection("noteheadHalf", (400.0, 150.0, 420.0, 170.0))
    half_dot = detection("augmentationDot", (422.0, 155.0, 430.0, 165.0))
    system3 = StaffSystem(system_id=0, geometry=geometry, detections=[half, half_dot])
    assert estimate_notehead_duration_quarters(half, system3) == 3.0


def test_staff_assembly_from_two_staff_boxes() -> None:
    staff_top = detection("staff", (40.0, 80.0, 500.0, 160.0))
    staff_bottom = detection("staff", (40.0, 280.0, 500.0, 360.0))
    clef_top = detection("clefG", (50.0, 90.0, 90.0, 150.0))
    clef_bottom = detection("clefF", (50.0, 290.0, 90.0, 350.0))
    note_top = detection("noteheadBlack", (200.0, 110.0, 220.0, 130.0))
    note_bottom = detection("noteheadBlack", (200.0, 310.0, 220.0, 330.0))

    systems = assemble_staff_systems(
        [staff_top, staff_bottom, clef_top, clef_bottom, note_top, note_bottom]
    )
    assert len(systems) == 2
    assert systems[0].geometry.clef_kind == "G"
    assert systems[1].geometry.clef_kind == "F"
    assert any(d.class_name == "noteheadBlack" for d in systems[0].detections)
    assert any(d.class_name == "noteheadBlack" for d in systems[1].detections)


def test_reconstruction_service_builds_valid_document() -> None:
    staff = detection("staff", (40.0, 100.0, 600.0, 180.0))
    clef = detection("clefG", (50.0, 110.0, 90.0, 170.0))
    # G4 on second line from bottom (y=160)
    note = detection("noteheadBlack", (200.0, 150.0, 220.0, 170.0))
    stem = detection("stem", (218.0, 100.0, 224.0, 160.0))
    flag = detection("flag8thUp", (224.0, 100.0, 240.0, 130.0))
    barline = detection("barline", (400.0, 95.0, 408.0, 185.0))

    detections = [staff, clef, note, stem, flag, barline]
    pages = [PageSize(page_index=0, width_px=640, height_px=360)]
    service = StructuralReconstructionService()
    document = service.reconstruct(
        detections, pages, title="Unit Score", pdf_path=None
    )

    assert document.schema_version == 1
    assert document.display_title == "Unit Score"
    assert document.note_events is not None
    assert len(document.note_events) == 1
    assert document.note_events[0].midi_pitch == 67
    assert document.reference_chromagram.frame_count == document.reference_frame_count
    assert document.reference_frame_count >= 1
    assert len(document.anchors) >= 1
