#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

RUN_URL="$(cat .run_url 2>/dev/null || gcloud run services describe "$RUN_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"

if gcloud pubsub subscriptions describe "$PUSH_SUBSCRIPTION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Subscription ${PUSH_SUBSCRIPTION} already exists — skipping."
else
  gcloud pubsub subscriptions create "$PUSH_SUBSCRIPTION" \
    --project="$PROJECT_ID" \
    --topic="$TOPIC" \
    --push-endpoint="$RUN_URL" \
    --push-auth-service-account="$PUSH_SA_EMAIL" \
    --ack-deadline=60 \
    --min-retry-delay=10s \
    --max-retry-delay=600s
  echo "Created push subscription ${PUSH_SUBSCRIPTION} -> ${RUN_URL}"
fi
