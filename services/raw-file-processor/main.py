"""
raw-file-processor  —  Cloud Run service (FastAPI).

Triggered by a Pub/Sub PUSH subscription fed by a Cloud Storage notification on
the SOURCE bucket. For every new object under incoming/ it downloads the object,
runs render.process_data() on it, and uploads the result to the DESTINATION
bucket. The pure logic lives in render.py (unit-tested); this file is just the
HTTP + Storage glue.

Return codes matter for Pub/Sub:
    2xx  -> ACK (success / intentionally skipped; not redelivered).
    non-2xx -> NACK (Pub/Sub retries later).
"""

import os

from fastapi import FastAPI, Request, Response
from fastapi.concurrency import run_in_threadpool
from google.cloud import storage

import render

app = FastAPI(title="raw-file-processor")

DEST_BUCKET = os.environ.get("DEST_BUCKET", "destination_raw_123456")
PROCESSED_PREFIX = render.PROCESSED_PREFIX

_storage_client = None


def storage_client() -> storage.Client:
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client


_CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".json": "application/json",
    ".csv": "text/csv",
}


def _download_process_upload(source_bucket: str, object_name: str) -> str:
    """Blocking GCS work; runs in a threadpool so the event loop stays free."""
    raw_bytes = storage_client().bucket(source_bucket).blob(object_name).download_as_bytes()
    result_bytes, output_name = render.process_data(object_name, raw_bytes)

    ext = os.path.splitext(output_name)[1].lower()
    content_type = _CONTENT_TYPES.get(ext)

    dst_blob = storage_client().bucket(DEST_BUCKET).blob(output_name)
    dst_blob.upload_from_string(result_bytes, content_type=content_type)
    return output_name


@app.post("/")
async def handle_pubsub_push(request: Request):
    try:
        envelope = await request.json()
    except Exception:  # noqa: BLE001
        envelope = None

    if not envelope or "message" not in envelope:
        print("ERROR: no Pub/Sub message in request body")
        return Response(status_code=204)

    attributes = (envelope["message"].get("attributes", {}) or {})
    event_type = attributes.get("eventType", "")
    source_bucket = attributes.get("bucketId", "")
    object_name = attributes.get("objectId", "")

    if event_type and event_type != "OBJECT_FINALIZE":
        print(f"SKIP: ignoring event {event_type} for {object_name}")
        return Response(status_code=204)
    if not object_name or object_name.endswith("/"):
        print(f"SKIP: not a file object: {object_name!r}")
        return Response(status_code=204)
    if object_name.startswith(PROCESSED_PREFIX):
        print(f"SKIP: already-processed object: {object_name}")
        return Response(status_code=204)

    print(f"PROCESS: gs://{source_bucket}/{object_name}")
    try:
        output_name = await run_in_threadpool(
            _download_process_upload, source_bucket, object_name)
        print(f"DONE: wrote gs://{DEST_BUCKET}/{output_name}")
        return Response(status_code=204)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR processing {object_name}: {exc}")
        return Response(content=f"error: {exc}", status_code=500)


@app.get("/")
async def health():
    return {"status": "ok", "service": "raw-file-processor"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0",
                port=int(os.environ.get("PORT", 8080)))
