"""Tests for PDF upload, mock processing, and temp-file cleanup."""

from __future__ import annotations

import io
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.main import create_app
from app.services.omr_processor import MockOmrProcessor
from app.services.temp_storage import TempPdfStorage


@pytest.fixture
def test_settings(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Settings:
    get_settings.cache_clear()
    monkeypatch.setenv("OMR_MOCK_INFERENCE_DELAY_SECONDS", "0")
    monkeypatch.setenv("OMR_MAX_UPLOAD_BYTES", str(2 * 1024 * 1024))
    settings = get_settings()
    yield settings
    get_settings.cache_clear()


@pytest.fixture
def client(test_settings: Settings) -> TestClient:
    app = create_app(test_settings)
    with TestClient(app) as test_client:
        yield test_client


def build_minimal_pdf_bytes() -> bytes:
    """Return a tiny byte buffer that starts with PDF magic (not a full PDF)."""
    return b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"


def test_health(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_upload_score_returns_schema_v1_document(client: TestClient) -> None:
    pdf_bytes = build_minimal_pdf_bytes()
    response = client.post(
        "/v1/omr/scores",
        files={"file": ("mock_score.pdf", io.BytesIO(pdf_bytes), "application/pdf")},
        data={"title": "Mock Four Chords"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["schemaVersion"] == 1
    assert body["displayTitle"] == "Mock Four Chords"
    assert body["sampleRateHz"] == 22050.0
    assert body["hopLengthSamples"] == 512
    assert body["referenceFrameCount"] == 2
    assert body["referenceChromagram"]["encoding"] == "f32le_row_major"
    assert body["referenceChromagram"]["pitchClassCount"] == 12
    assert body["referenceChromagram"]["frameCount"] == 2
    assert len(body["pages"]) == 1
    assert len(body["anchors"]) == 2
    assert body["documentId"]


def test_upload_rejects_non_pdf_extension(client: TestClient) -> None:
    response = client.post(
        "/v1/omr/scores",
        files={"file": ("notes.txt", io.BytesIO(b"not a pdf"), "text/plain")},
    )
    assert response.status_code == 415
    payload = response.json()
    assert payload["error"]["code"] == "unsupported_media_type"


def test_upload_rejects_missing_pdf_magic(client: TestClient) -> None:
    response = client.post(
        "/v1/omr/scores",
        files={"file": ("fake.pdf", io.BytesIO(b"HELLO WORLD"), "application/pdf")},
    )
    assert response.status_code == 415
    assert response.json()["error"]["code"] == "unsupported_media_type"


@pytest.mark.asyncio
async def test_temp_storage_deletes_directory_after_context(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from fastapi import UploadFile

    created_directories: list[Path] = []
    original_mkdtemp = __import__("tempfile").mkdtemp

    def tracking_mkdtemp(*args: object, **kwargs: object) -> str:
        directory = Path(original_mkdtemp(*args, **kwargs))
        created_directories.append(directory)
        return str(directory)

    monkeypatch.setattr("app.services.temp_storage.tempfile.mkdtemp", tracking_mkdtemp)

    upload = UploadFile(
        filename="cleanup.pdf",
        file=io.BytesIO(build_minimal_pdf_bytes()),
    )
    async with TempPdfStorage(upload, max_upload_bytes=1024 * 1024) as pdf_path:
        assert pdf_path.exists()
        assert created_directories
        tracked = created_directories[0]
        assert tracked.exists()

    assert created_directories
    assert not created_directories[0].exists()


@pytest.mark.asyncio
async def test_temp_storage_cleans_up_when_validation_fails() -> None:
    from fastapi import UploadFile

    from app.core.errors import UnsupportedMediaAppError

    upload = UploadFile(
        filename="bad.pdf",
        file=io.BytesIO(b"NOTPDF"),
    )
    with pytest.raises(UnsupportedMediaAppError):
        async with TempPdfStorage(upload, max_upload_bytes=1024 * 1024):
            pass


@pytest.mark.asyncio
async def test_mock_processor_builds_valid_document(tmp_path: Path) -> None:
    pdf_path = tmp_path / "demo.pdf"
    pdf_path.write_bytes(build_minimal_pdf_bytes())
    processor = MockOmrProcessor(
        Settings(mock_inference_delay_seconds=0.0),
    )
    document = await processor.process(pdf_path, title=None)
    assert document.schema_version == 1
    assert document.display_title == "demo"
    assert document.reference_frame_count == 2
