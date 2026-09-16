#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Sets up the cloud-native daily ingestion (secret -> fetcher -> scheduler).
# Assumes the base pipeline (deploy_all.sh: buckets, topic, subscription,
# processor, notification) already exists. Fail-fast: stops on any error.
run_step () {
  echo; echo "──────── $1 ────────"
  bash "$1" || { echo "❌ HALTED at $1"; exit 1; }
}

run_step 10_secret_manager.sh
run_step 11_deploy_news_fetcher.sh
run_step 12_cloud_scheduler.sh

echo
echo "=========================================================="
echo " Daily ingestion is live. Test it end-to-end with:"
echo "   gcloud scheduler jobs run daily-news-fetch --location=us-central1"
echo "=========================================================="
