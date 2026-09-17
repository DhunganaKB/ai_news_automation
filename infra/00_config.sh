#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Central config for the whole pipeline. Every other script sources this file:
#     source ./00_config.sh
#
# NOTHING account-specific is hardcoded here:
#   - PROJECT_ID / REGION come from your active `gcloud` config (or env override).
#   - Paths are derived from this file's location.
#   - Every resource name can be overridden by exporting it before sourcing.
# ---------------------------------------------------------------------------

# --- GCP project / location (from gcloud config, or export to override) -----
export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-$(gcloud config get-value run/region 2>/dev/null)}"
case "$REGION" in ""|"(unset)") REGION="us-central1" ;; esac   # default if unset
export REGION

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "ERROR: no GCP project configured. Run:" >&2
  echo "       gcloud config set project YOUR_PROJECT_ID" >&2
  echo "   (or: export PROJECT_ID=... before running)" >&2
  return 1 2>/dev/null || exit 1
fi
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)"

# --- Repo paths (derived, not hardcoded) ------------------------------------
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LOCAL_DATA_DIR="${REPO_ROOT}/data"

# --- Buckets ----------------------------------------------------------------
export SOURCE_BUCKET="${SOURCE_BUCKET:-source_raw_123456}"       # ingestion writes here
export DEST_BUCKET="${DEST_BUCKET:-destination_raw_123456}"      # processor writes here
export INCOMING_PREFIX="${INCOMING_PREFIX:-incoming/}"
export PROCESSED_PREFIX="${PROCESSED_PREFIX:-processed/}"

# --- Pub/Sub ----------------------------------------------------------------
export TOPIC="${TOPIC:-source-file-landed}"
export PUSH_SUBSCRIPTION="${PUSH_SUBSCRIPTION:-source-file-landed-push}"

# --- Cloud Run --------------------------------------------------------------
export RUN_SERVICE="${RUN_SERVICE:-raw-file-processor}"          # JSON -> HTML digest
export FETCHER_SERVICE="${FETCHER_SERVICE:-news-fetcher}"        # fetch news -> source bucket

# --- Secret Manager ---------------------------------------------------------
export SECRET_TAVILY="${SECRET_TAVILY:-tavily-api-key}"

# --- Cloud Scheduler (daily trigger for the fetcher) ------------------------
export SCHEDULER_JOB="${SCHEDULER_JOB:-daily-news-fetch}"
export SCHEDULE_CRON="${SCHEDULE_CRON:-0 7 * * *}"
export SCHEDULE_TZ="${SCHEDULE_TZ:-America/New_York}"

# --- Workload Identity Federation (GitHub Actions -> GCP, keyless) ----------
export WIF_POOL="${WIF_POOL:-github-pool}"
export WIF_PROVIDER="${WIF_PROVIDER:-github-provider}"
# Auto-derived from the git 'origin' remote as owner/repo (override by exporting
# GITHUB_REPO). Nothing hardcoded — it reads whatever remote your repo points at.
export GITHUB_REPO="${GITHUB_REPO:-$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null | sed -E 's#(git@|https://)github\.com[:/]##; s#\.git$##')}"

# --- Service accounts (names derived from the values above) -----------------
export RUN_SA="${RUN_SA:-raw-processor-sa}"
export RUN_SA_EMAIL="${RUN_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
export PUSH_SA="${PUSH_SA:-pubsub-push-sa}"
export PUSH_SA_EMAIL="${PUSH_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
export FETCHER_SA="${FETCHER_SA:-news-fetcher-sa}"
export FETCHER_SA_EMAIL="${FETCHER_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
export SCHEDULER_SA="${SCHEDULER_SA:-scheduler-invoker-sa}"
export SCHEDULER_SA_EMAIL="${SCHEDULER_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
export DEPLOYER_SA="${DEPLOYER_SA:-github-deployer-sa}"
export DEPLOYER_SA_EMAIL="${DEPLOYER_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Config loaded: project=$PROJECT_ID region=$REGION"
