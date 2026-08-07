"""Pydantic models mirroring docs/omr_structural_document.schema.v1.json."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class OmrStructuralPage(BaseModel):
    """Page geometry for page-normalized cursor mapping."""

    model_config = ConfigDict(extra="forbid")

    page_index: int = Field(alias="pageIndex", ge=0)
    width_px: int = Field(alias="widthPx", gt=0)
    height_px: int = Field(alias="heightPx", gt=0)


class OmrStructuralAnchor(BaseModel):
    """Frame index mapped to a page-normalized cursor pose."""

    model_config = ConfigDict(extra="forbid")

    frame_index: float = Field(alias="frameIndex")
    page_index: int = Field(alias="pageIndex", ge=0)
    x_norm: float = Field(alias="xNorm", ge=0.0, le=1.0)
    y_norm: float = Field(alias="yNorm", ge=0.0, le=1.0)
    measure_number: int = Field(alias="measureNumber")


class OmrReferenceChromagram(BaseModel):
    """Little-endian row-major float32 chromagram payload (Base64)."""

    model_config = ConfigDict(extra="forbid")

    encoding: Literal["f32le_row_major"] = "f32le_row_major"
    pitch_class_count: Literal[12] = Field(default=12, alias="pitchClassCount")
    frame_count: int = Field(alias="frameCount", gt=0)
    data_base64: str = Field(alias="dataBase64", min_length=1)


class OmrStructuralNoteEvent(BaseModel):
    """Optional symbolic onset for future UX (not required by DTW today)."""

    model_config = ConfigDict(extra="forbid")

    midi_pitch: int = Field(alias="midiPitch", ge=0, le=127)
    onset_frame: float = Field(alias="onsetFrame", ge=0.0)
    duration_frames: float = Field(alias="durationFrames", gt=0.0)
    page_index: int | None = Field(default=None, alias="pageIndex", ge=0)
    x_norm: float | None = Field(default=None, alias="xNorm", ge=0.0, le=1.0)
    y_norm: float | None = Field(default=None, alias="yNorm", ge=0.0, le=1.0)


class OmrStructuralDocument(BaseModel):
    """Schema version 1 structural document returned to the Flutter client."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    schema_version: Literal[1] = Field(alias="schemaVersion")
    document_id: str | None = Field(default=None, alias="documentId", min_length=1, max_length=128)
    display_title: str = Field(alias="displayTitle", min_length=1, max_length=256)
    sample_rate_hz: float = Field(alias="sampleRateHz", gt=0.0)
    hop_length_samples: int = Field(alias="hopLengthSamples", gt=0)
    reference_frame_count: int = Field(alias="referenceFrameCount", gt=0)
    pages: list[OmrStructuralPage] = Field(min_length=1)
    anchors: list[OmrStructuralAnchor] = Field(min_length=1)
    reference_chromagram: OmrReferenceChromagram = Field(alias="referenceChromagram")
    note_events: list[OmrStructuralNoteEvent] | None = Field(default=None, alias="noteEvents")

    @field_validator("display_title")
    @classmethod
    def display_title_must_be_non_blank(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError("displayTitle must be non-empty.")
        return trimmed

    @model_validator(mode="after")
    def validate_cross_field_invariants(self) -> OmrStructuralDocument:
        if self.reference_chromagram.frame_count != self.reference_frame_count:
            raise ValueError(
                "referenceChromagram.frameCount must equal referenceFrameCount."
            )

        for index, page in enumerate(self.pages):
            if page.page_index != index:
                raise ValueError(
                    f"pages must be contiguous from 0; expected pageIndex {index}, "
                    f"got {page.page_index}."
                )

        page_count = len(self.pages)
        previous_frame_index = float("-inf")
        for index, anchor in enumerate(self.anchors):
            if anchor.page_index >= page_count:
                raise ValueError(
                    f"anchors[{index}].pageIndex is out of range [0, {page_count})."
                )
            if anchor.frame_index < previous_frame_index:
                raise ValueError("anchors must be sorted by frameIndex ascending.")
            previous_frame_index = anchor.frame_index

        return self
