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
#
# IMPORTANT: the Cloud Storage service agent is created ON DEMAND. Contrary to
# its help text, `gcloud storage service-agent` only PRINTS the email — it does
# not actually provision the agent. The agent is created as a side effect of a
# GET to the Storage JSON API serviceAccount endpoint, so we call that first.
# Without this, the IAM binding fails with "Service account ... does not exist".
GCS_SA="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"

echo "Provisioning the Cloud Storage service agent (${GCS_SA})..."
curl -s -o /dev/null -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://storage.googleapis.com/storage/v1/projects/${PROJECT_ID}/serviceAccount"

# Grant publisher. Retry a few times for IAM propagation; on the last try we let
# the real error through (unsuppressed) so `set -e` stops with a useful message.
granted=false
for attempt in 1 2 3 4 5; do
  if gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
       --project="$PROJECT_ID" \
       --member="serviceAccount:${GCS_SA}" \
       --role="roles/pubsub.publisher" >/dev/null 2>&1; then
    granted=true
    break
  fi
  echo "  waiting for the service agent to become bindable (attempt ${attempt}/5)..."
  sleep 5
done
if [ "$granted" != "true" ]; then
  echo "Publisher grant still failing — showing the full error:" >&2
  gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:${GCS_SA}" \
    --role="roles/pubsub.publisher"   # unsuppressed; set -e exits on failure
fi
echo "Granted pubsub.publisher to ${GCS_SA} on ${TOPIC}."

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
