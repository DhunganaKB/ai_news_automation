#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# Removes everything this project created. Use with care.
# Buckets are only emptied+deleted if you pass  --delete-buckets.

read -r -p "This deletes the Cloud Run service, subscription, topic, notification, and SAs. Continue? [y/N] " ans
[ "$ans" = "y" ] || { echo "Aborted."; exit 0; }

gcloud pubsub subscriptions delete "$PUSH_SUBSCRIPTION" --project="$PROJECT_ID" --quiet || true

# Delete GCS notifications pointing at our topic.
for ID in $(gcloud storage buckets notifications list "gs://${SOURCE_BUCKET}" 2>/dev/null \
             | grep -B1 "$TOPIC" | grep "notificationConfigs" | awk -F'/' '{print $NF}'); do
  gcloud storage buckets notifications delete "gs://${SOURCE_BUCKET}" --notification-id="$ID" --quiet || true
done

gcloud pubsub topics delete "$TOPIC" --project="$PROJECT_ID" --quiet || true
gcloud run services delete "$RUN_SERVICE" --project="$PROJECT_ID" --region="$REGION" --quiet || true
gcloud iam service-accounts delete "$RUN_SA_EMAIL" --project="$PROJECT_ID" --quiet || true
gcloud iam service-accounts delete "$PUSH_SA_EMAIL" --project="$PROJECT_ID" --quiet || true

if [ "${1:-}" = "--delete-buckets" ]; then
  gcloud storage rm --recursive "gs://${SOURCE_BUCKET}" --quiet || true
  gcloud storage rm --recursive "gs://${DEST_BUCKET}" --quiet || true
fi

echo "Teardown complete."
