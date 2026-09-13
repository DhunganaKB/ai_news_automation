#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# APIs required by the whole pipeline.
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  pubsub.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --project="$PROJECT_ID"

echo "APIs enabled."
