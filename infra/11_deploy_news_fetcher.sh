#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# --- 1. Runtime service account for the fetcher + its IAM -------------------
if ! gcloud iam service-accounts describe "$FETCHER_SA_EMAIL" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$FETCHER_SA" \
    --project="$PROJECT_ID" --display-name="news-fetcher runtime"
fi

# Read the Tavily secret ...
gcloud secrets add-iam-policy-binding "$SECRET_TAVILY" \
  --project="$PROJECT_ID" \
  --member="serviceAccount:${FETCHER_SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"

# ... and write the fetched JSON into the SOURCE bucket.
gcloud storage buckets add-iam-policy-binding "gs://${SOURCE_BUCKET}" \
  --member="serviceAccount:${FETCHER_SA_EMAIL}" --role="roles/storage.objectAdmin"

# --- 2. Deploy the fetcher (secret injected as an env var) ------------------
# This is also what the GitHub Actions deploy workflow runs.
gcloud run deploy "$FETCHER_SERVICE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --source="../services/news-fetcher" \
  --service-account="$FETCHER_SA_EMAIL" \
  --no-allow-unauthenticated \
  --set-env-vars="SOURCE_BUCKET=${SOURCE_BUCKET},INCOMING_PREFIX=${INCOMING_PREFIX}" \
  --set-secrets="TAVILY_API_KEY=${SECRET_TAVILY}:latest"

FETCHER_URL="$(gcloud run services describe "$FETCHER_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"
echo "$FETCHER_URL" > .fetcher_url
echo "news-fetcher deployed at: ${FETCHER_URL}"
