"""
news-fetcher  —  Cloud Run service (FastAPI).

Triggered daily by Cloud Scheduler (an authenticated HTTP POST). On each call it:
    1. Reads the Tavily API key from the environment (injected from Secret
       Manager at deploy time via --set-secrets).
    2. Fetches category-tagged AI news (news_source.build_collection).
    3. Uploads the collection as JSON to gs://SOURCE_BUCKET/incoming/,
       which fires the existing Pub/Sub -> raw-file-processor pipeline.

This replaces the old local cron + local Python fetch: the whole ingestion now
runs in the cloud on a schedule.
"""

import datetime
import json
import os

from fastapi import FastAPI, Response
from fastapi.concurrency import run_in_threadpool
from google.cloud import storage

import news_source

app = FastAPI(title="news-fetcher")

SOURCE_BUCKET = os.environ.get("SOURCE_BUCKET", "source_raw_123456")
INCOMING_PREFIX = os.environ.get("INCOMING_PREFIX", "incoming/")
# Injected from Secret Manager at deploy time (--set-secrets). May be empty,
# in which case news_source falls back to Google News RSS.
TAVILY_API_KEY = os.environ.get("TAVILY_API_KEY") or None

_storage_client = None


def storage_client() -> storage.Client:
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client


def _fetch_and_upload() -> dict:
    collection = news_source.build_collection(TAVILY_API_KEY)
    date_str = collection.get("date") or \
        datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    object_name = f"{INCOMING_PREFIX}ai_news_{date_str}.json"

    payload = json.dumps(collection, ensure_ascii=False, indent=2).encode("utf-8")
    blob = storage_client().bucket(SOURCE_BUCKET).blob(object_name)
    blob.upload_from_string(payload, content_type="application/json")

    return {
        "uploaded": f"gs://{SOURCE_BUCKET}/{object_name}",
        "count": collection.get("count", 0),
        "category_counts": collection.get("category_counts", {}),
        "provider": collection.get("primary_provider"),
        "errors": collection.get("errors", []),
    }


@app.post("/")
async def run_fetch():
    print("FETCH: starting daily AI-news fetch")
    try:
        result = await run_in_threadpool(_fetch_and_upload)
        print(f"DONE: {result['uploaded']} ({result['count']} items)")
        return result
    except Exception as exc:  # noqa: BLE001
        # 500 so Cloud Scheduler records the failure and retries per its policy.
        print(f"ERROR during fetch: {exc}")
        return Response(content=f"error: {exc}", status_code=500)


@app.get("/")
async def health():
    return {"status": "ok", "service": "news-fetcher"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0",
                port=int(os.environ.get("PORT", 8080)))
