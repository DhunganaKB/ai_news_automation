#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

if gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Topic ${TOPIC} already exists — skipping."
else
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT_ID"
  echo "Created topic ${TOPIC}"
fi
