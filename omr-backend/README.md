# Stateless OMR (Optical Music Recognition) HTTP API for the Score Follower TFM.
#
# The Flutter client uploads a PDF via multipart form field `file` (optional
# `title`) to POST /v1/omr/scores and receives an OmrStructuralDocument JSON
# (schemaVersion 1). This service does not persist scores; the mobile app owns
# Drift / local filesystem storage.
#
# Phase 5.5.3.C.1 ships MockOmrProcessor on the HTTP route.
# Phase 5.5.3.C.2 adds VisionDetectionService (DINOv2 + SAHI) under app/vision/;
# C.3 will wire it into a real OmrProcessor (HTTP still uses the mock for now).

## Setup

```bash
cd omr-backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
# source .venv/bin/activate
pip install -r requirements.txt
```

## Run

From the `omr-backend` directory (so the `app` package resolves):

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- OpenAPI UI: http://127.0.0.1:8000/docs
- Health: `GET http://127.0.0.1:8000/health`

## Example upload

```bash
curl -F "file=@sample.pdf" -F "title=Test Score" http://127.0.0.1:8000/v1/omr/scores
```

Point the Flutter `OmrApiConfig.baseUrl` at `http://127.0.0.1:8000` for local integration.

## Configuration

Environment variables (prefix `OMR_`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `OMR_MAX_UPLOAD_BYTES` | 52428800 (50 MiB) | Reject larger uploads |
| `OMR_MOCK_INFERENCE_DELAY_SECONDS` | 2.0 | Simulated processing latency |
| `OMR_LOG_LEVEL` | INFO | Logging verbosity |
| `OMR_VISION_RASTER_DPI` | 200 | PDF page raster DPI (PyMuPDF) |
| `OMR_VISION_MAX_PAGES` | 50 | Reject PDFs with more pages |
| `OMR_VISION_SLICE_HEIGHT` / `WIDTH` | 512 | SAHI slice size |
| `OMR_VISION_OVERLAP_RATIO` | 0.2 | SAHI slice overlap |
| `OMR_VISION_CONFIDENCE_THRESHOLD` | 0.25 | Drop low-score detections |
| `OMR_VISION_DEVICE` | cpu | Torch device (`cpu` / `cuda:0`) |
| `OMR_VISION_WEIGHTS_PATH` | (unset) | Optional DeepScores `.pt`; random weights if missing |
| `OMR_VISION_INPUT_SIZE` | 518 | Model input side (multiple of 14 for DINOv2) |

## Tests

```bash
cd omr-backend
pytest -q
```
