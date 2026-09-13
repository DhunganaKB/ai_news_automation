#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# Wire the SOURCE bucket to publish an OBJECT_FINALIZE notification to the topic.
# We scope it to the INCOMING_PREFIX so only files under "incoming/" trigger the job.
#
# This is the last wire connected: after this runs, any new object in
# gs://SOURCE_BUCKET/incoming/ publishes to the topic -> push subscription ->
# Cloud Run.

EXISTING="$(gcloud storage buckets notifications list "gs://${SOURCE_BUCKET}" 2>/dev/null | grep -c "$TOPIC" || true)"
if [ "$EXISTING" != "0" ]; then
  echo "A notification to topic ${TOPIC} already exists on gs://${SOURCE_BUCKET} — skipping."
else
  gcloud storage buckets notifications create "gs://${SOURCE_BUCKET}" \
    --topic="$TOPIC" \
    --event-types="OBJECT_FINALIZE" \
    --object-prefix="$INCOMING_PREFIX" \
    --payload-format="json"
  echo "Notification created: gs://${SOURCE_BUCKET}/${INCOMING_PREFIX}* -> ${TOPIC}"
fi
