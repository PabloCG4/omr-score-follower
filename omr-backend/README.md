# Stateless OMR (Optical Music Recognition) HTTP API for the Score Follower TFM.
#
# The Flutter client uploads a PDF via multipart form field `file` (optional
# `title`) to POST /v1/omr/scores and receives an OmrStructuralDocument JSON
# (schemaVersion 1). This service does not persist scores; the mobile app owns
# Drift / local filesystem storage.
#
# Production pipeline (Phase 5.5.3.C finalization):
# VisionOmrProcessor (singleton) → Faster R-CNN + SAHI → StructuralReconstructionService
# → OmrStructuralDocument. MockOmrProcessor is test-only via dependency overrides.

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

Place trained DeepScores Faster R-CNN weights at:

`weights/omr_deepscores_best_50epoch.pt`

(or set `OMR_VISION_WEIGHTS_PATH` to an absolute path).

## Run

From the `omr-backend` directory (so the `app` package and relative weights path resolve):

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

On startup the process warms up the Faster R-CNN weights on a worker thread
(`OMR_VISION_WARMUP_ON_STARTUP=true` by default) so the first upload is not a cold start.
Heavy inference always runs under `asyncio.to_thread` and does not block the event loop.

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
| `OMR_MOCK_INFERENCE_DELAY_SECONDS` | 2.0 | Mock processor delay (tests only) |
| `OMR_LOG_LEVEL` | INFO | Logging verbosity |
| `OMR_VISION_RASTER_DPI` | 200 | PDF page raster DPI (PyMuPDF) |
| `OMR_VISION_MAX_PAGES` | 50 | Reject PDFs with more pages |
| `OMR_VISION_SLICE_HEIGHT` / `WIDTH` | 512 | SAHI slice size |
| `OMR_VISION_OVERLAP_RATIO` | 0.2 | SAHI slice overlap |
| `OMR_VISION_CONFIDENCE_THRESHOLD` | 0.25 | Drop low-score detections |
| `OMR_VISION_DEVICE` | cpu | Torch device (`cpu` / `cuda:0`) |
| `OMR_VISION_WEIGHTS_PATH` | `weights/omr_deepscores_best_50epoch.pt` | Faster R-CNN DeepScores checkpoint |
| `OMR_VISION_INPUT_SIZE` | 800 | TorchVision transform size hint |
| `OMR_VISION_WARMUP_ON_STARTUP` | true | Load weights during app lifespan |

If the category name order in training differs from
`app/vision/data/deepscores_categories.json`, replace that JSON with the exact
training list (must contain 149 foreground names).

## Tests

```bash
cd omr-backend
pytest -q
```

HTTP upload tests override the DI dependency with `MockOmrProcessor` and disable warmup
so CI does not load the neural network.
