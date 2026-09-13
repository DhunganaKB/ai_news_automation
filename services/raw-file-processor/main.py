"""
raw-file-processor  —  Cloud Run service.

Triggered by a Pub/Sub PUSH subscription that is fed by a Cloud Storage
notification on the SOURCE bucket (source_raw_123456).

Flow for every new object that lands in the source bucket:
    1. Pub/Sub delivers an HTTP POST (push envelope) to this service.
    2. We read which bucket/object triggered it (from the message attributes).
    3. Download that object from the SOURCE bucket.
    4. Process it  (see process_data() -- replace with your real logic).
    5. Upload the result to the DESTINATION bucket (destination_raw_123456).

Return codes matter for Pub/Sub:
    2xx  -> message is ACKed (success, will not be redelivered).
    non-2xx -> message is NACKed (Pub/Sub retries later).
Anything we cannot recover from (bad payload, object we intentionally skip)
returns 2xx so Pub/Sub does not retry forever.
"""

import base64
import json
import os
import csv
import io
import datetime

from flask import Flask, request
from google.cloud import storage

app = Flask(__name__)

# ---- Configuration (injected as env vars at deploy time) --------------------
DEST_BUCKET = os.environ.get("DEST_BUCKET", "destination_raw_123456")
PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/")

storage_client = storage.Client()


# ---------------------------------------------------------------------------
# YOUR BUSINESS LOGIC LIVES HERE.
# Input : raw bytes of the object + its name.
# Output: (bytes to write, output_object_name).
# Replace the body with whatever transformation you actually need.
# ---------------------------------------------------------------------------
def process_data(object_name: str, raw_bytes: bytes) -> tuple[bytes, str]:
    processed_at = datetime.datetime.utcnow().isoformat() + "Z"

    # Example transformation: for CSV files, append a "processed_at" column.
    if object_name.lower().endswith(".csv"):
        text = raw_bytes.decode("utf-8", errors="replace")
        reader = csv.reader(io.StringIO(text))
        rows = list(reader)
        out = io.StringIO()
        writer = csv.writer(out)
        for i, row in enumerate(rows):
            if i == 0:
                writer.writerow(row + ["processed_at"])
            else:
                writer.writerow(row + [processed_at])
        result = out.getvalue().encode("utf-8")
    else:
        # Non-CSV: pass the bytes through unchanged (placeholder).
        result = raw_bytes

    # Output name: strip any leading "incoming/" and drop it under PROCESSED_PREFIX.
    base = object_name.split("/")[-1]
    output_name = f"{PROCESSED_PREFIX}{base}"
    return result, output_name


@app.route("/", methods=["POST"])
def handle_pubsub_push():
    envelope = request.get_json(silent=True)
    if not envelope or "message" not in envelope:
        # Malformed -> ACK so Pub/Sub stops retrying a message we can never parse.
        print("ERROR: no Pub/Sub message in request body")
        return ("Bad Request: no Pub/Sub message", 204)

    message = envelope["message"]
    attributes = message.get("attributes", {}) or {}

    # Cloud Storage notifications put these in the message attributes.
    event_type = attributes.get("eventType", "")
    source_bucket = attributes.get("bucketId", "")
    object_name = attributes.get("objectId", "")

    # Only react to newly finalized (written) objects.
    if event_type and event_type != "OBJECT_FINALIZE":
        print(f"SKIP: ignoring event {event_type} for {object_name}")
        return ("", 204)

    # Ignore "folder" placeholder objects and our own outputs, just in case.
    if not object_name or object_name.endswith("/"):
        print(f"SKIP: not a file object: {object_name!r}")
        return ("", 204)
    if object_name.startswith(PROCESSED_PREFIX):
        print(f"SKIP: already-processed object: {object_name}")
        return ("", 204)

    print(f"PROCESS: gs://{source_bucket}/{object_name}")

    try:
        # 1. Download from source bucket.
        src_blob = storage_client.bucket(source_bucket).blob(object_name)
        raw_bytes = src_blob.download_as_bytes()

        # 2. Process.
        result_bytes, output_name = process_data(object_name, raw_bytes)

        # 3. Upload to destination bucket.
        dst_blob = storage_client.bucket(DEST_BUCKET).blob(output_name)
        dst_blob.upload_from_string(result_bytes)

        print(f"DONE: wrote gs://{DEST_BUCKET}/{output_name} "
              f"({len(result_bytes)} bytes)")
        return ("", 204)

    except Exception as exc:  # noqa: BLE001
        # Return 500 so Pub/Sub retries (transient errors, e.g. IAM propagation).
        print(f"ERROR processing {object_name}: {exc}")
        return (f"error: {exc}", 500)


@app.route("/", methods=["GET"])
def health():
    return ("raw-file-processor is alive", 200)


if __name__ == "__main__":
    # Local dev only. In Cloud Run, gunicorn serves the app (see Dockerfile).
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
