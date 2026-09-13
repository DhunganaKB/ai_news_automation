#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# Create the two buckets (idempotent: ignore "already exists" errors).
for BUCKET in "$SOURCE_BUCKET" "$DEST_BUCKET"; do
  if gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1; then
    echo "Bucket gs://${BUCKET} already exists — skipping."
  else
    gcloud storage buckets create "gs://${BUCKET}" \
      --project="$PROJECT_ID" \
      --location="$REGION" \
      --uniform-bucket-level-access
    echo "Created gs://${BUCKET}"
  fi
done
