#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# --- 1. Create the two service accounts (idempotent) ------------------------
create_sa () {
  local NAME="$1" DISPLAY="$2"
  if gcloud iam service-accounts describe "${NAME}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
    echo "SA ${NAME} already exists — skipping."
  else
    gcloud iam service-accounts create "$NAME" \
      --project="$PROJECT_ID" --display-name="$DISPLAY"
  fi
}
create_sa "$RUN_SA"  "Cloud Run runtime for raw-file-processor"
create_sa "$PUSH_SA" "Pub/Sub push identity -> Cloud Run"

# --- 2. Cloud Run runtime SA: read SOURCE, write DESTINATION ----------------
gcloud storage buckets add-iam-policy-binding "gs://${SOURCE_BUCKET}" \
  --member="serviceAccount:${RUN_SA_EMAIL}" --role="roles/storage.objectViewer"

gcloud storage buckets add-iam-policy-binding "gs://${DEST_BUCKET}" \
  --member="serviceAccount:${RUN_SA_EMAIL}" --role="roles/storage.objectAdmin"

# --- 3. Let Cloud Storage publish notifications to the topic ----------------
# The GCS service agent must be a Pub/Sub publisher on our topic.
GCS_SA="$(gcloud storage service-agent --project="$PROJECT_ID")"
gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
  --project="$PROJECT_ID" \
  --member="serviceAccount:${GCS_SA}" \
  --role="roles/pubsub.publisher" || true

# --- 4. Let Pub/Sub mint OIDC tokens for the push SA ------------------------
# The Pub/Sub service agent needs tokenCreator to sign push auth tokens.
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
gcloud iam service-accounts add-iam-policy-binding "$PUSH_SA_EMAIL" \
  --project="$PROJECT_ID" \
  --member="serviceAccount:${PUBSUB_SA}" \
  --role="roles/iam.serviceAccountTokenCreator"

echo "Service accounts + IAM configured."
echo "NOTE: run.invoker for the push SA is granted in 05_deploy_cloud_run.sh,"
echo "      because it must be bound to the concrete Cloud Run service."
