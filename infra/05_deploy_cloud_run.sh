#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# Deploy from source: Cloud Build builds the container (using cloud_run/Dockerfile),
# pushes it to Artifact Registry, and deploys it to Cloud Run automatically.
gcloud run deploy "$RUN_SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --source="../services/raw-file-processor" \
  --service-account="$RUN_SA_EMAIL" \
  --no-allow-unauthenticated \
  --set-env-vars="DEST_BUCKET=${DEST_BUCKET},PROCESSED_PREFIX=${PROCESSED_PREFIX}"

# Grant the push SA permission to INVOKE this service (private -> OIDC only).
gcloud run services add-iam-policy-binding "$RUN_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" \
  --member="serviceAccount:${PUSH_SA_EMAIL}" \
  --role="roles/run.invoker"

RUN_URL="$(gcloud run services describe "$RUN_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"
echo "Cloud Run deployed at: ${RUN_URL}"
echo "$RUN_URL" > .run_url    # cached for the next script
