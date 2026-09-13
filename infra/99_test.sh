#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# End-to-end smoke test: upload one sample CSV, then look for the output.
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"
SAMPLE="${TMP}/sample_${STAMP}.csv"
printf 'id,name,value\n1,alpha,100\n2,beta,200\n' > "$SAMPLE"

echo "Uploading test file to gs://${SOURCE_BUCKET}/${INCOMING_PREFIX}..."
gcloud storage cp "$SAMPLE" "gs://${SOURCE_BUCKET}/${INCOMING_PREFIX}"

echo "Waiting 20s for Pub/Sub -> Cloud Run to process..."
sleep 20

echo "Objects now in destination bucket:"
gcloud storage ls "gs://${DEST_BUCKET}/${PROCESSED_PREFIX}" || true

echo
echo "Recent Cloud Run logs:"
gcloud run services logs read "$RUN_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" --limit=20 || true

rm -rf "$TMP"
