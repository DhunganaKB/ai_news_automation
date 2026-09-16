# AI News Event-Driven Pipeline

A serverless, **cloud-native** pipeline that collects **AI news daily**, categorises it into five topics, and renders a professional, tabbed **HTML digest** — fully event-driven and deployed by CI/CD.

> **Cloud Scheduler** → **news-fetcher** (Cloud Run) → **GCS source bucket** → **Pub/Sub** → **raw-file-processor** (Cloud Run) → **GCS destination bucket** (`ai_news_{date}.html`)

- **Daily trigger:** Cloud Scheduler — no local cron required.
- **Secrets:** the Tavily API key lives in **Secret Manager**, never in code or the repo.
- **Deploys:** **GitHub Actions** with **Workload Identity Federation** (keyless) — on **push to `main`** or a **`v*` tag from any branch**.
- **Linting:** runs on **every branch push** and pull request.

> **Configuration:** every resource name — including your **GCP project ID** — is set in one place: [`infra/00_config.sh`](infra/00_config.sh). This README uses `YOUR_PROJECT_ID` as a placeholder; set your real value there. See **[app_run.html](app_run.html)** for the full step-by-step run guide.

---

## 1. Architecture

```
  ┌───────────────────────┐
  │ Cloud Scheduler        │  daily-news-fetch @ 07:00
  │ (daily HTTP trigger)   │
  └───────────┬───────────┘
              │ OIDC-authenticated POST
              ▼
  ┌───────────────────────┐     reads Tavily key
  │ Cloud Run: news-fetcher│◀────  Secret Manager: tavily-api-key
  │  fetch categorised news│
  └───────────┬───────────┘
              │ uploads ai_news_{date}.json
              ▼
  ┌───────────────────────┐   OBJECT_FINALIZE notification
  │ SOURCE bucket          │──────────────┐
  │   incoming/…           │              ▼
  └───────────────────────┘      ┌────────────────────┐
                                  │ Pub/Sub topic       │
                                  │ source-file-landed  │
                                  └────────┬───────────┘
                                           │ push subscription (OIDC)
                                           ▼
                                  ┌────────────────────────┐
                                  │ Cloud Run:              │
                                  │ raw-file-processor      │
                                  │  JSON → tabbed HTML      │
                                  └────────┬───────────────┘
                                           ▼
                                  ┌────────────────────────┐
                                  │ DESTINATION bucket      │
                                  │   processed/            │
                                  │     ai_news_{date}.html │
                                  └────────────────────────┘

  CI/CD:  push to main OR tag v*  ──(GitHub Actions + WIF, keyless)──▶  gcloud run deploy (both services)
          push to any branch      ──▶  ruff + shellcheck lint
```

### Component names (all defined in `infra/00_config.sh`)

| Role | Name |
|------|------|
| GCP project / region | `YOUR_PROJECT_ID` / `us-central1` |
| Source bucket | `source_raw_123456` → `incoming/` |
| Destination bucket | `destination_raw_123456` → `processed/` |
| Pub/Sub topic | `source-file-landed` |
| Pub/Sub push subscription | `source-file-landed-push` |
| Cloud Run — fetcher | `news-fetcher` |
| Cloud Run — processor | `raw-file-processor` |
| Cloud Scheduler job | `daily-news-fetch` |
| Secret (Tavily key) | `tavily-api-key` |
| SA — fetcher runtime | `news-fetcher-sa` |
| SA — processor runtime | `raw-processor-sa` |
| SA — Pub/Sub push identity | `pubsub-push-sa` |
| SA — Scheduler invoker | `scheduler-invoker-sa` |
| SA — GitHub Actions deployer (WIF) | `github-deployer-sa` |

(Service-account emails are `<name>@YOUR_PROJECT_ID.iam.gserviceaccount.com`.)

---

## 2. Repository layout

```
.
├── Makefile                       # task runner: make help
├── README.md
├── app_run.html                   # full run guide (open in a browser)
├── ruff.toml                      # lint config (used by CI and `make lint`)
├── .env.example                   # copy to .env; holds TAVILY_API_KEY (gitignored)
├── .gitignore                     # keeps .env, data/, logs/ out of git
│
├── .github/workflows/
│   ├── lint.yml                   # ruff + shellcheck on every branch push / PR
│   └── deploy.yml                 # deploy both services on main push or v* tag (WIF)
│
├── services/                      # runs in Google Cloud (deployed by CI)
│   ├── news-fetcher/              #   fetches categorised AI news → source bucket
│   │   ├── main.py                #     FastAPI: Scheduler POST → fetch → upload JSON
│   │   ├── news_source.py         #     category-tagged Tavily/RSS fetch logic
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── raw-file-processor/        #   renders the HTML digest
│       ├── main.py                #     FastAPI: Pub/Sub push → JSON → tabbed HTML
│       ├── requirements.txt
│       └── Dockerfile
│
├── infra/                         # one-time bootstrap (idempotent, fail-fast)
│   ├── 00_config.sh               #   ALL names/vars live here (set YOUR_PROJECT_ID)
│   ├── 01_enable_apis.sh … 07_create_gcs_notification.sh
│   ├── deploy_all.sh              #   base pipeline: buckets, topic, processor, sub, notify
│   ├── 10_secret_manager.sh       #   store Tavily key in Secret Manager
│   ├── 11_deploy_news_fetcher.sh  #   fetcher SA + IAM + deploy fetcher
│   ├── 12_cloud_scheduler.sh      #   daily Cloud Scheduler job (OIDC)
│   ├── 13_setup_wif.sh            #   Workload Identity Federation for GitHub Actions
│   ├── setup_ingestion.sh         #   runs 10 → 11 → 12
│   ├── 99_test.sh                 #   end-to-end smoke test
│   └── teardown.sh
│
├── ingestion/                     # OPTIONAL local/offline path (legacy)
│   ├── fetch_ai_news.py           #   local preview copy of the fetch logic
│   ├── fetch_and_push_news.sh     #   local cron entrypoint (superseded by Scheduler)
│   └── crontab.example
│
└── data/                          # local scratch (gitignored)
```

---

## 3. What the services do

### `news-fetcher` (ingestion)
Runs **category-specific Tavily searches** across five topics and tags every article with its category:

| Category | Audience |
|----------|----------|
| Software Development | engineers & builders |
| Model Development | ML practitioners |
| Economic Impact | business & policy |
| Big Tech | industry watchers |
| Research | researchers & academics |

- **Primary source:** Tavily (key injected from Secret Manager). **Fallback:** Google News RSS per query, so a category is never empty.
- De-duplicates by link, keeping each article in its **highest-relevance** category.
- Uploads one JSON collection to `gs://<source-bucket>/incoming/ai_news_{date}.json`, which fires the pipeline.
- Edit the `CATEGORIES` map in [`services/news-fetcher/news_source.py`](services/news-fetcher/news_source.py) to change topics/queries.

### `raw-file-processor` (rendering)
Parses the JSON and renders a **self-contained, tabbed HTML digest** — one clickable tab per category (plus "All"), the **top 5 stories per category** by relevance, each a highlighted card with a title link, source, date, and snippet. Output: `gs://<destination-bucket>/processed/ai_news_{date}.html` (served as `text/html`).

- Change the per-category cap via the `MAX_PER_CATEGORY` env var (default `5`).
- The digest layout lives in `render_news_html()` in [`services/raw-file-processor/main.py`](services/raw-file-processor/main.py).

---

## 4. First-time setup

> Prerequisite: `gcloud` installed and authenticated, and `YOUR_PROJECT_ID` set in `infra/00_config.sh`.

```bash
# 1. Base pipeline: buckets, topic, processor, push subscription, notification
make setup

# 2. Cloud ingestion: Secret Manager + news-fetcher + daily Cloud Scheduler
make setup-ingestion

# 3. Test the whole thing now (don't wait for 07:00):
make trigger        # runs Cloud Scheduler → fetch → pipeline → HTML digest
```

`make setup-ingestion` reads your Tavily key from `.env` into Secret Manager (idempotent), deploys the fetcher, and creates the daily scheduler job.

---

## 5. CI/CD with GitHub Actions (keyless)

Deploys use **Workload Identity Federation** — GitHub gets short-lived tokens scoped to your repo; **no service-account key is ever stored**.

**One-time, after creating the GitHub repo:**
```bash
# set GITHUB_REPO="owner/repo" in infra/00_config.sh, then:
make wif
```
`make wif` prints two values. Add them as **repository variables** (Settings → Secrets and variables → Actions → **Variables**):

| Variable | Value |
|----------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | printed by `make wif` |
| `GCP_DEPLOYER_SA` | `github-deployer-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com` |
| `GCP_PROJECT_ID` | your GCP project ID |
| `GCP_REGION` | e.g. `us-central1` |

> `deploy.yml` reads the project ID and region from these variables — nothing is hardcoded in the workflow.

**Deploy — two ways** (both run [`deploy.yml`](.github/workflows/deploy.yml), deploying both services):

| Trigger | How |
|---------|-----|
| Merge / push to `main` | normal PR merge or push |
| Tag `v*` from **any** branch | `git tag v1.0.0 && git push origin v1.0.0` |

**Linting** ([`lint.yml`](.github/workflows/lint.yml)) runs `ruff` + `shellcheck` on every branch push and PR. Run it locally first:
```bash
make lint
```

---

## 6. Common commands

```bash
make                 # list all targets
make trigger         # run the daily fetch now (cloud path)
make deploy          # redeploy the processor
make deploy-fetcher  # redeploy the fetcher
make test            # end-to-end smoke test
make logs            # tail processor logs
make lint            # ruff check
make teardown        # delete cloud resources (keeps buckets)
```

---

## 7. Security & secrets

- The Tavily key is stored **only** in Secret Manager (`tavily-api-key`) and injected into the fetcher at deploy time via `--set-secrets`. Your local `.env` is **gitignored** and never pushed.
- Both Cloud Run services are deployed `--no-allow-unauthenticated` (private). Only their designated callers can invoke them: Pub/Sub (via `pubsub-push-sa`) for the processor, Cloud Scheduler (via `scheduler-invoker-sa`) for the fetcher.
- GitHub Actions authenticates via WIF, restricted to your repository — no long-lived credentials.

---

## 8. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| No `ai_news_{date}.html` in the destination bucket | `make logs` — read the processor's Cloud Run output. |
| Scheduler ran but no JSON in `incoming/` | Check the `news-fetcher` logs; verify it can read the secret and write the source bucket. |
| `403` in Cloud Run logs | IAM still propagating (wait 1–2 min) or a runtime SA is missing a role — re-run the relevant `infra` script. |
| Pub/Sub redelivering forever | Processor returning non-2xx; it returns 500 only on real errors — fix the error in the logs. |
| Fetcher returns 0 items | Check the `errors` field in the JSON and the Tavily secret; the RSS fallback should still populate. |
| First CI deploy fails on build/permissions | Ensure `make setup-ingestion` ran once (creates `news-fetcher-sa`) and that `make wif` granted the deployer roles. |
| GitHub Actions auth fails | Confirm `GITHUB_REPO` in `00_config.sh` matches the real repo and the two repo variables are set. |

---

## 9. Teardown
```bash
make teardown                                   # service, subscription, topic, notification, SAs
cd infra && bash teardown.sh --delete-buckets   # also empties + deletes both buckets
```
