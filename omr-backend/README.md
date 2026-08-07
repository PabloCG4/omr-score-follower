# Stateless OMR (Optical Music Recognition) HTTP API for the Score Follower TFM.
#
# The Flutter client uploads a PDF via multipart form field `file` (optional
# `title`) to POST /v1/omr/scores and receives an OmrStructuralDocument JSON
# (schemaVersion 1). This service does not persist scores; the mobile app owns
# Drift / local filesystem storage.
#
# Phase 5.5.3.C.1 ships a MockOmrProcessor only (no DINOv2 / SAHI yet).

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

## Tests

```bash
cd omr-backend
pytest -q
```
