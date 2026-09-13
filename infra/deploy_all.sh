#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Runs the whole setup in the correct order. Each step is idempotent, so it is
# safe to re-run. Order matters: topic must exist before IAM/notification,
# Cloud Run must exist before the push subscription.
bash 01_enable_apis.sh
bash 04_create_topic.sh                 # topic first (IAM in step 03 references it)
bash 02_create_buckets.sh
bash 03_service_accounts_and_iam.sh
bash 05_deploy_cloud_run.sh
bash 06_create_push_subscription.sh
bash 07_create_gcs_notification.sh      # connect the trigger LAST

echo
echo "=========================================================="
echo " Pipeline is live. Test it with:  bash 99_test.sh"
echo "=========================================================="
