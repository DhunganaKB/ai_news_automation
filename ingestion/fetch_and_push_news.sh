#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fetch_and_push_news.sh  —  runs on YOUR Mac, once a day, from cron.
#
#   1. Fetches AI news from the internet (fetch_ai_news.py, run in conda env mcp).
#   2. Writes a dated JSON collection locally (data/ai_news_YYYY-MM-DD.json).
#   3. Uploads it to gs://source_raw_123456/incoming/, which fires the
#      Pub/Sub -> Cloud Run pipeline exactly like any other new object.
#
# Everything is logged to local_uploader/logs/.
# ---------------------------------------------------------------------------
set -euo pipefail

# --- Settings (keep in sync with deploy/00_config.sh) -----------------------
SOURCE_BUCKET="source_raw_123456"
INCOMING_PREFIX="incoming/"
PROJECT_DIR="/Users/kamaldhungana/Documents/Coding/pubsub/part1"
DATA_DIR="${PROJECT_DIR}/data"

# conda env mcp Python (found via `conda env list`). cron has a bare PATH, so
# we call the interpreter by absolute path — no `conda activate` needed.
MCP_PYTHON="/opt/anaconda3/envs/mcp/bin/python"

# gcloud absolute path (cron's PATH is minimal). Verify with `which gcloud`.
GCLOUD="$(command -v gcloud || echo /usr/local/bin/gcloud)"

# --- Paths ------------------------------------------------------------------
DATE="$(date +%Y-%m-%d)"
OUT_FILE="${DATA_DIR}/ai_news_${DATE}.json"
LOG_DIR="${PROJECT_DIR}/ingestion/logs"
mkdir -p "$DATA_DIR" "$LOG_DIR"
LOG="${LOG_DIR}/news_$(date +%Y%m%d).log"

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') fetch_and_push_news start ==="

  # 1 + 2: fetch news and write JSON collection.
  "$MCP_PYTHON" "${PROJECT_DIR}/ingestion/fetch_ai_news.py" "$OUT_FILE"

  # 3: upload to the source bucket (triggers the pipeline).
  "$GCLOUD" storage cp "$OUT_FILE" "gs://${SOURCE_BUCKET}/${INCOMING_PREFIX}"

  echo "Uploaded gs://${SOURCE_BUCKET}/${INCOMING_PREFIX}$(basename "$OUT_FILE")"
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') fetch_and_push_news done ==="
} >> "$LOG" 2>&1
