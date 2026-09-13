#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Central config for the whole pipeline. Every other script sources this file:
#     source ./00_config.sh
# Edit values here in ONE place; nothing else hardcodes names.
# ---------------------------------------------------------------------------

# --- GCP project / location -------------------------------------------------
export PROJECT_ID="deve-487713"
export REGION="us-central1"
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

# --- Buckets ----------------------------------------------------------------
export SOURCE_BUCKET="source_raw_123456"          # cron job pushes files here
export DEST_BUCKET="destination_raw_123456"       # Cloud Run writes results here
export INCOMING_PREFIX="incoming/"                 # local files land under this "folder"
export PROCESSED_PREFIX="processed/"               # Cloud Run outputs under this "folder"

# --- Pub/Sub ----------------------------------------------------------------
export TOPIC="source-file-landed"                  # GCS notifications publish here
export PUSH_SUBSCRIPTION="source-file-landed-push" # push subscription -> Cloud Run

# --- Cloud Run --------------------------------------------------------------
export RUN_SERVICE="raw-file-processor"

# --- Service accounts -------------------------------------------------------
# Runtime identity of the Cloud Run service (reads source, writes destination):
export RUN_SA="raw-processor-sa"
export RUN_SA_EMAIL="${RUN_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
# Identity Pub/Sub uses to authenticate its push calls into Cloud Run:
export PUSH_SA="pubsub-push-sa"
export PUSH_SA_EMAIL="${PUSH_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

# --- Local source folder for the cron uploader ------------------------------
export LOCAL_DATA_DIR="/Users/kamaldhungana/Documents/Coding/pubsub/part1/data"

echo "Config loaded: project=$PROJECT_ID region=$REGION"
