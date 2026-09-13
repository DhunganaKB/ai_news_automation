# ===========================================================================
# AI-news event-driven pipeline — task runner.
# Run `make` (or `make help`) to see targets.
# ===========================================================================
SHELL := /bin/bash
INFRA := infra
INGEST := ingestion

.DEFAULT_GOAL := help

.PHONY: help setup deploy test news fetch-local logs install-cron teardown

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## One-time: create ALL cloud resources (APIs, buckets, SAs, topic, Cloud Run, sub, notification)
	cd $(INFRA) && bash deploy_all.sh

deploy: ## Redeploy just the Cloud Run service (after editing services/raw-file-processor/)
	cd $(INFRA) && bash 05_deploy_cloud_run.sh

test: ## End-to-end smoke test (uploads a sample file, checks destination bucket)
	cd $(INFRA) && bash 99_test.sh

news: ## Fetch AI news now and push to the source bucket (manual run of the cron job)
	bash $(INGEST)/fetch_and_push_news.sh && echo "Pushed. See ingestion/logs/ for details."

fetch-local: ## Fetch AI news to ./data only (no upload) — quick check of the fetcher
	mkdir -p data && /opt/anaconda3/envs/mcp/bin/python $(INGEST)/fetch_ai_news.py data/ai_news_preview.json

logs: ## Tail recent Cloud Run logs
	cd $(INFRA) && source ./00_config.sh && \
	  gcloud run services logs read $$RUN_SERVICE --project=$$PROJECT_ID --region=$$REGION --limit=30

install-cron: ## Print the cron line to install (copy into `crontab -e`)
	@echo "Add this line via 'crontab -e':"
	@grep -E '^0 7' $(INGEST)/crontab.example

teardown: ## Delete all cloud resources this project created (keeps buckets)
	cd $(INFRA) && bash teardown.sh
