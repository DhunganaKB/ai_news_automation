#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Runs the whole setup in the correct order. Each step is idempotent, so it is
# safe to re-run. Order matters: topic must exist before IAM/notification,
# Cloud Run must exist before the push subscription.
#
# FAIL-FAST: if any step exits non-zero, we STOP immediately and do NOT proceed
# to later steps (which could otherwise leave a half-configured pipeline).
run_step () {
  local script="$1"
  echo
  echo "──────────────────────── $script ────────────────────────"
  if ! bash "$script"; then
    echo
    echo "❌ SETUP HALTED: '$script' failed (see the error above)."
    echo "   Nothing after this step was run. Fix the cause, then re-run"
    echo "   'make setup' — every step is idempotent, so completed steps are skipped."
    exit 1
  fi
}

run_step 01_enable_apis.sh
run_step 04_create_topic.sh                 # topic first (IAM in step 03 references it)
run_step 02_create_buckets.sh
run_step 03_service_accounts_and_iam.sh
run_step 05_deploy_cloud_run.sh
run_step 06_create_push_subscription.sh
run_step 07_create_gcs_notification.sh      # connect the trigger LAST

echo
echo "=========================================================="
echo " Pipeline is live. Test it with:  make test"
echo "=========================================================="
