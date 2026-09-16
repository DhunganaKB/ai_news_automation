# ===========================================================================
# AI-news event-driven pipeline — task runner.
# Run `make` (or `make help`) to see targets.
# ===========================================================================
SHELL := /bin/bash
INFRA := infra
INGEST := ingestion
# Python for local helpers (override: `make fetch-local PYTHON=/path/to/python`).
PYTHON ?= python3

.DEFAULT_GOAL := help

.PHONY: help setup setup-ingestion wif secret deploy deploy-fetcher scheduler \
        trigger test news fetch-local lint logs teardown

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- one-time bootstrap -----------------------------------------------------
setup: ## Base pipeline: buckets, SAs, topic, processor, subscription, notification
	cd $(INFRA) && bash deploy_all.sh

setup-ingestion: ## Cloud ingestion: secret + news-fetcher + daily Cloud Scheduler
	cd $(INFRA) && bash setup_ingestion.sh

wif: ## Set up Workload Identity Federation for GitHub Actions (needs GITHUB_REPO in 00_config.sh)
	cd $(INFRA) && bash 13_setup_wif.sh

secret: ## Create/refresh the Tavily key in Secret Manager (from .env)
	cd $(INFRA) && bash 10_secret_manager.sh

# --- deploys (also done by GitHub Actions) ---------------------------------
deploy: ## Deploy the processor service (services/raw-file-processor)
	cd $(INFRA) && bash 05_deploy_cloud_run.sh

deploy-fetcher: ## Deploy the news-fetcher service (services/news-fetcher)
	cd $(INFRA) && bash 11_deploy_news_fetcher.sh

scheduler: ## Create/update the daily Cloud Scheduler job
	cd $(INFRA) && bash 12_cloud_scheduler.sh

# --- run / test -------------------------------------------------------------
trigger: ## Run the daily fetch NOW via Cloud Scheduler (cloud path)
	cd $(INFRA) && source ./00_config.sh && \
	  gcloud scheduler jobs run $$SCHEDULER_JOB --project=$$PROJECT_ID --location=$$REGION

test: ## End-to-end smoke test (uploads a sample file, checks destination bucket)
	cd $(INFRA) && bash 99_test.sh

news: ## Local fetch + push to source bucket (manual/offline path)
	bash $(INGEST)/fetch_and_push_news.sh && echo "Pushed. See ingestion/logs/ for details."

fetch-local: ## Fetch AI news to ./data only (no upload) — quick check of the fetcher
	mkdir -p data && $(PYTHON) $(INGEST)/fetch_ai_news.py data/ai_news_preview.json

lint: ## Run the same lint CI runs (ruff)
	ruff check .

logs: ## Tail recent processor logs
	cd $(INFRA) && source ./00_config.sh && \
	  gcloud run services logs read $$RUN_SERVICE --project=$$PROJECT_ID --region=$$REGION --limit=30

teardown: ## Delete cloud resources this project created (keeps buckets)
	cd $(INFRA) && bash teardown.sh
