#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# Create (or add a new version to) the Tavily key secret, reading the value from
# the local .env. The value is never echoed. Safe to re-run.
ENV_FILE="../.env"
KEY="$(grep -E '^TAVILY_API_KEY' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' ' || true)"
if [ -z "$KEY" ]; then
  echo "ERROR: TAVILY_API_KEY not found in $ENV_FILE" >&2
  exit 1
fi

if gcloud secrets describe "$SECRET_TAVILY" --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf '%s' "$KEY" | gcloud secrets versions add "$SECRET_TAVILY" \
    --data-file=- --project="$PROJECT_ID" >/dev/null
  echo "Secret ${SECRET_TAVILY}: added a new version."
else
  printf '%s' "$KEY" | gcloud secrets create "$SECRET_TAVILY" \
    --data-file=- --replication-policy=automatic --project="$PROJECT_ID" >/dev/null
  echo "Secret ${SECRET_TAVILY}: created."
fi
