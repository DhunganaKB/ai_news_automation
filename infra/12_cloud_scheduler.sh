#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# --- 1. Scheduler's invoker service account --------------------------------
if ! gcloud iam service-accounts describe "$SCHEDULER_SA_EMAIL" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SCHEDULER_SA" \
    --project="$PROJECT_ID" --display-name="Cloud Scheduler -> news-fetcher invoker"
fi

FETCHER_URL="$(cat .fetcher_url 2>/dev/null || gcloud run services describe "$FETCHER_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')"

# Allow the scheduler SA to invoke the private fetcher service.
gcloud run services add-iam-policy-binding "$FETCHER_SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" \
  --member="serviceAccount:${SCHEDULER_SA_EMAIL}" \
  --role="roles/run.invoker"

# --- 2. Daily HTTP scheduler job (OIDC-authenticated) ----------------------
COMMON=(--project="$PROJECT_ID" --location="$REGION"
        --schedule="$SCHEDULE_CRON" --time-zone="$SCHEDULE_TZ"
        --uri="$FETCHER_URL" --http-method=POST
        --oidc-service-account-email="$SCHEDULER_SA_EMAIL"
        --oidc-token-audience="$FETCHER_URL")

if gcloud scheduler jobs describe "$SCHEDULER_JOB" --project="$PROJECT_ID" --location="$REGION" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$SCHEDULER_JOB" "${COMMON[@]}"
  echo "Scheduler job ${SCHEDULER_JOB} updated."
else
  gcloud scheduler jobs create http "$SCHEDULER_JOB" "${COMMON[@]}"
  echo "Scheduler job ${SCHEDULER_JOB} created (${SCHEDULE_CRON} ${SCHEDULE_TZ})."
fi

echo "Trigger it now to test:  gcloud scheduler jobs run ${SCHEDULER_JOB} --location=${REGION}"
