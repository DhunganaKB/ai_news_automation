#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# push_to_gcs.sh  —  runs on YOUR Mac, once an hour, from cron.
#
# It syncs the local data/ folder up to gs://source_raw_123456/incoming/.
# `gcloud storage rsync` uploads only NEW or CHANGED files, so each run
# triggers the pipeline for genuinely new data only (no re-processing of
# unchanged files). We do NOT pass --delete-unmatched-destination-objects,
# so files already in the bucket are never removed.
# ---------------------------------------------------------------------------
set -euo pipefail

# --- Settings (keep in sync with deploy/00_config.sh) -----------------------
SOURCE_BUCKET="source_raw_123456"
INCOMING_PREFIX="incoming/"
LOCAL_DATA_DIR="/Users/kamaldhungana/Documents/Coding/pubsub/part1/data"

# cron runs with a minimal PATH, so point at the gcloud binary explicitly.
# Find yours once with:  which gcloud
GCLOUD="/usr/local/bin/gcloud"          # <-- edit if `which gcloud` differs
[ -x "$GCLOUD" ] || GCLOUD="$(command -v gcloud)"

LOG_DIR="$(dirname "$0")/logs"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/push_$(date +%Y%m%d).log"

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') push_to_gcs start ==="
  "$GCLOUD" storage rsync "$LOCAL_DATA_DIR" \
      "gs://${SOURCE_BUCKET}/${INCOMING_PREFIX}" \
      --recursive
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') push_to_gcs done ==="
} >> "$LOG" 2>&1
