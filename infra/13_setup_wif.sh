#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ./00_config.sh

# Sets up keyless auth so GitHub Actions can deploy to GCP with NO stored key.
# Run this AFTER you have created the GitHub repo and set GITHUB_REPO in
# 00_config.sh (format: owner/repo).

if [ -z "${GITHUB_REPO:-}" ]; then
  echo "ERROR: GITHUB_REPO is not set. Provide it as owner/repo, e.g." >&2
  echo "       GITHUB_REPO=your-org/your-repo make wif" >&2
  echo "   (or set it in infra/00_config.sh)" >&2
  exit 1
fi
OWNER="${GITHUB_REPO%%/*}"

# --- 1. Deployer service account -------------------------------------------
if ! gcloud iam service-accounts describe "$DEPLOYER_SA_EMAIL" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$DEPLOYER_SA" \
    --project="$PROJECT_ID" --display-name="GitHub Actions deployer"
fi

# Roles needed to build (Cloud Build) and deploy Cloud Run from source.
for ROLE in \
  roles/run.admin \
  roles/iam.serviceAccountUser \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.writer \
  roles/storage.admin ; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${DEPLOYER_SA_EMAIL}" --role="$ROLE" \
    --condition=None >/dev/null
done
echo "Granted deploy roles to ${DEPLOYER_SA_EMAIL}."

# --- 2. Workload Identity Pool + GitHub OIDC provider ----------------------
if ! gcloud iam workload-identity-pools describe "$WIF_POOL" \
      --project="$PROJECT_ID" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$WIF_POOL" \
    --project="$PROJECT_ID" --location=global --display-name="GitHub Actions pool"
fi

if ! gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
      --project="$PROJECT_ID" --location=global --workload-identity-pool="$WIF_POOL" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
    --project="$PROJECT_ID" --location=global --workload-identity-pool="$WIF_POOL" \
    --display-name="GitHub OIDC" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner=='${OWNER}'"
fi

# --- 3. Let ONLY this repo impersonate the deployer SA ----------------------
gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_REPO}"

WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"

cat <<EOF

============================================================================
 WIF is ready. Add these GitHub repository VARIABLES (Settings ->
 Secrets and variables -> Actions -> Variables), used by .github/workflows:

   GCP_WORKLOAD_IDENTITY_PROVIDER = ${WIF_PROVIDER_RESOURCE}
   GCP_DEPLOYER_SA                = ${DEPLOYER_SA_EMAIL}
   GCP_PROJECT_ID                 = ${PROJECT_ID}
   GCP_REGION                     = ${REGION}
============================================================================
EOF
