# AI News Event-Driven Pipeline

A serverless pipeline that collects **AI news daily** and processes it through Google Cloud, fully event-driven:

> **internet (AI news)** → **cron (your Mac)** → **GCS source bucket** → **Pub/Sub** → **Cloud Run** → **GCS destination bucket**

- **Project:** `deve-487713`  **Region:** `us-central1`
- No servers to babysit: a file landing in the source bucket is the only thing that triggers work.

---

## 1. Architecture

```
  YOUR MAC                                GOOGLE CLOUD (deve-487713 / us-central1)
  ┌─────────────────────────┐
  │ Tavily API / Google News │  (internet)
  │      ↓ fetch_ai_news.py  │
  │  data/ai_news_*.json     │
  └──────────┬──────────────┘
             │  cron: daily 07:00 — fetch_and_push_news.sh
             ▼
  ┌──────────────────────────┐   OBJECT_FINALIZE notification
  │ Bucket 1 (SOURCE)         │──────────────┐
  │ source_raw_123456         │              ▼
  │   incoming/…              │      ┌────────────────────┐
  └──────────────────────────┘      │ Pub/Sub topic       │
                                     │ source-file-landed  │
                                     └────────┬───────────┘
                                              │ push subscription (OIDC auth)
                                              │ source-file-landed-push
                                              ▼
                                     ┌──────────────────────┐
                                     │ Cloud Run service     │
                                     │ raw-file-processor    │
                                     │  • download source obj│
                                     │  • process_data()     │
                                     │  • upload result      │
                                     └────────┬──────────────┘
                                              ▼
                                     ┌──────────────────────────┐
                                     │ Bucket 2 (DESTINATION)    │
                                     │ destination_raw_123456    │
                                     │   processed/…             │
                                     └──────────────────────────┘
```

### Component names (all defined once in `infra/00_config.sh`)

| Role                          | Name                            |
|-------------------------------|---------------------------------|
| GCP project / region          | `deve-487713` / `us-central1`   |
| Source bucket (bucket 1)      | `source_raw_123456` → `incoming/` |
| Destination bucket (bucket 2) | `destination_raw_123456` → `processed/` |
| Pub/Sub topic                 | `source-file-landed`            |
| Pub/Sub push subscription     | `source-file-landed-push`       |
| Cloud Run service             | `raw-file-processor`            |
| Cloud Run runtime SA          | `raw-processor-sa@…`            |
| Pub/Sub push identity SA      | `pubsub-push-sa@…`              |
| Local news fetcher            | `ingestion/fetch_ai_news.py`    |
| Local cron uploader           | `ingestion/fetch_and_push_news.sh` |

---

## 2. Repository layout

```
.
├── Makefile                      # one-command tasks: make setup | deploy | news | test
├── README.md
├── .env.example                  # copy to .env; holds TAVILY_API_KEY
├── .gitignore                    # keeps .env, data/, logs/ out of git
│
├── ingestion/                    # runs on YOUR Mac (the cron side)
│   ├── fetch_ai_news.py          #   fetch AI news (Tavily → RSS fallback) → JSON
│   ├── fetch_and_push_news.sh    #   cron entrypoint: fetch → upload to source bucket
│   ├── push_to_gcs.sh            #   legacy: sync a local data/ folder instead
│   └── crontab.example           #   the daily cron line to install
│
├── services/                     # runs in GOOGLE CLOUD
│   └── raw-file-processor/       #   the Cloud Run service
│       ├── main.py               #     Flask: parse Pub/Sub push → process → write
│       ├── requirements.txt
│       ├── Dockerfile
│       └── .gcloudignore
│
├── infra/                        # one-time GCP setup (idempotent scripts)
│   ├── 00_config.sh              #   ALL names/vars live here
│   ├── 01_enable_apis.sh
│   ├── 02_create_buckets.sh
│   ├── 03_service_accounts_and_iam.sh
│   ├── 04_create_topic.sh
│   ├── 05_deploy_cloud_run.sh
│   ├── 06_create_push_subscription.sh
│   ├── 07_create_gcs_notification.sh
│   ├── deploy_all.sh             #   runs 01→07 in the correct order
│   ├── 99_test.sh                #   end-to-end smoke test
│   └── teardown.sh
│
└── data/                         # local scratch (gitignored) — generated JSON lands here
```

---

## 3. News fetcher (`ingestion/fetch_ai_news.py`)

- **Primary source: Tavily** (`TAVILY_API_KEY` in `.env`) — relevance-scored news, real article URLs, content snippets.
- **Fallback: Google News RSS** — used automatically per-query if Tavily is missing or errors, so the job never comes back empty.
- Stdlib only → runs in the `mcp` conda env with nothing to install.
- Output: a single JSON collection, e.g. `data/ai_news_2026-09-12.json`:
  ```json
  {
    "collection": "ai_news",
    "fetched_at": "2026-09-12T07:00:00Z",
    "date": "2026-09-12",
    "primary_provider": "tavily",
    "count": 41,
    "items": [ { "title": "...", "link": "...", "source": "...", "snippet": "...", "score": 0.88 } ]
  }
  ```
- Edit the `QUERIES` list at the top of the script to change what topics are pulled.

## 4. Processing logic (where your real code goes)

Open `services/raw-file-processor/main.py` → `process_data(object_name, raw_bytes)`.
It returns `(bytes_to_write, output_object_name)`. Today it demos a CSV transform and passes other files through. **Replace the body with your real transformation** (e.g. enrich/filter the news JSON) — the plumbing (download, upload, Pub/Sub ack/retry) stays the same. Redeploy with `make deploy`.

---

## 5. Quick start (using the Makefile)

```bash
make            # list all targets

# --- one-time cloud setup (creates every resource; idempotent) ---
make setup

# --- verify end-to-end ---
make test       # uploads a sample file, checks the destination bucket + logs

# --- run the news job by hand (before scheduling it) ---
make news       # fetch AI news now and push to the source bucket

# --- schedule it daily ---
make install-cron   # prints the cron line; paste it into `crontab -e`
```

### Setup order (what `make setup` runs, if you prefer step-by-step)

```bash
cd infra
bash 01_enable_apis.sh              # Run, Build, Pub/Sub, Storage, IAM
bash 04_create_topic.sh            # topic: source-file-landed
bash 02_create_buckets.sh          # source_raw_123456 + destination_raw_123456
bash 03_service_accounts_and_iam.sh# 2 SAs + IAM bindings
bash 05_deploy_cloud_run.sh        # build image + deploy raw-file-processor
bash 06_create_push_subscription.sh# subscription → Cloud Run (OIDC)
bash 07_create_gcs_notification.sh # LAST: arms the trigger
```
On the first `05`, if `gcloud` offers to create an Artifact Registry repo, answer **Y**.

---

## 6. Schedule the daily cron

1. Ensure `.env` has your `TAVILY_API_KEY` (copy from `.env.example`).
2. Run once by hand: `make news` (check `ingestion/logs/`).
3. Confirm paths in `ingestion/fetch_and_push_news.sh`:
   - `MCP_PYTHON=/opt/anaconda3/envs/mcp/bin/python`
   - `GCLOUD` = output of `which gcloud`
4. Install the schedule:
   ```bash
   crontab -e
   # paste (daily at 07:00):
   0 7 * * * /Users/kamaldhungana/Documents/Coding/pubsub/part1/ingestion/fetch_and_push_news.sh
   ```
5. **macOS only:** give cron Full Disk Access — System Settings → Privacy & Security → Full Disk Access → add `/usr/sbin/cron`.

Logs from each run land in `ingestion/logs/`.

---

## 7. Pushing to a Git repo & deploying from it

The repo is self-contained and safe to push (`.env` is gitignored).

```bash
git init && git add . && git commit -m "AI news pub/sub pipeline"
# create a remote (GitHub CLI):  gh repo create <name> --private --source=. --push
```

**Deploy is code-driven:** `make deploy` runs `gcloud run deploy --source services/raw-file-processor`, which uses Cloud Build to build the container and roll it out. So on any machine with `gcloud` + this repo, a deploy is just:
```bash
make deploy
```
> Want fully automated deploys on `git push`? Add a Cloud Build trigger or a GitHub Actions workflow that runs `make deploy`. Ask and I'll add one — it needs a Workload Identity / service-account binding to your repo.

---

## 8. Conda note
The `mcp` conda env is used **locally** by the fetcher (`fetch_ai_news.py`). Cloud Run builds its own Python container in the cloud, so it needs nothing from conda. The cron script calls the env's interpreter directly (`/opt/anaconda3/envs/mcp/bin/python`) — no `conda activate` needed.

## 9. Teardown
```bash
make teardown                 # removes service, subscription, topic, notification, SAs
cd infra && bash teardown.sh --delete-buckets   # also empties + deletes both buckets
```

## 10. Troubleshooting
| Symptom | Likely cause / fix |
|---|---|
| File uploaded but nothing in `processed/` | `make logs` — read Cloud Run output. |
| `403` in Cloud Run logs | IAM still propagating (wait 1–2 min) or `raw-processor-sa` missing bucket roles — re-run `03_…`. |
| Pub/Sub redelivering forever | Cloud Run returning non-2xx; code returns 500 only on real errors — fix the error in logs. |
| Nothing publishes on upload | Notification not armed — re-run `07_…`; confirm files go under `incoming/`. |
| Fetcher returns 0 items / falls back | Check `errors` field in the JSON; verify `TAVILY_API_KEY`. RSS fallback should still populate. |
| cron does nothing on macOS | Full Disk Access not granted to `/usr/sbin/cron`, or wrong `MCP_PYTHON`/`GCLOUD` path. |
