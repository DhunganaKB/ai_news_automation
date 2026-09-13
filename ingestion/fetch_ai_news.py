#!/usr/bin/env python3
"""
fetch_ai_news.py  —  fetch AI-related news from the internet, write a JSON
collection to disk.

Sources (in priority order):
  1. Tavily Search API  (if TAVILY_API_KEY is set) — relevance-scored news with
     real article URLs and content snippets. Preferred.
  2. Google News RSS    — free, no key. Used as a fallback if Tavily is missing
     or fails, so the cron job never comes back empty.

Stdlib only (urllib + xml), so it runs in the `mcp` conda env with nothing to
install. The Tavily key is read from the project .env (never printed).

Usage:
    python fetch_ai_news.py OUTPUT_PATH.json
If OUTPUT_PATH is omitted, prints the JSON to stdout.
"""

import json
import os
import sys
import datetime
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

# --- Which AI topics to pull. Edit freely. ---------------------------------
QUERIES = [
    "artificial intelligence",
    "machine learning",
    "generative AI",
    "large language models",
    "AI regulation and policy",
]
WHEN_DAYS = 1                     # last day's news (matches a daily cron)
MAX_PER_QUERY = 20                # Tavily results per query
HL, GL, CEID = "en-US", "US", "US:en"
USER_AGENT = "Mozilla/5.0 (ai-news-fetcher)"
TIMEOUT = 30
ENV_PATH = os.path.join(os.path.dirname(__file__), "..", ".env")


# --------------------------------------------------------------------------
# .env loader (tiny; avoids a python-dotenv dependency)
# --------------------------------------------------------------------------
def load_env_var(name: str) -> str | None:
    if os.environ.get(name):
        return os.environ[name]
    try:
        with open(ENV_PATH, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == name:
                    return v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return None


# --------------------------------------------------------------------------
# Source 1: Tavily
# --------------------------------------------------------------------------
def fetch_tavily(query: str, api_key: str) -> list[dict]:
    body = json.dumps({
        "query": query,
        "topic": "news",
        "days": WHEN_DAYS,
        "max_results": MAX_PER_QUERY,
        "search_depth": "basic",
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.tavily.com/search",
        data=body,
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        data = json.loads(resp.read())
    items = []
    for r in data.get("results", []):
        url = (r.get("url") or "").strip()
        items.append({
            "title": (r.get("title") or "").strip(),
            "link": url,
            "published": (r.get("published_date") or "").strip(),
            "source": urllib.parse.urlparse(url).netloc or None,
            "snippet": (r.get("content") or "").strip()[:500],
            "score": r.get("score"),
            "query": query,
            "provider": "tavily",
        })
    return items


# --------------------------------------------------------------------------
# Source 2: Google News RSS (fallback)
# --------------------------------------------------------------------------
def fetch_rss(query: str) -> list[dict]:
    q = urllib.parse.quote_plus(f"{query} when:{WHEN_DAYS}d")
    url = (f"https://news.google.com/rss/search?q={q}"
           f"&hl={HL}&gl={GL}&ceid={CEID}")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        root = ET.fromstring(resp.read())
    items = []
    for it in root.findall(".//item"):
        src = it.find("{*}source")
        items.append({
            "title": (it.findtext("title") or "").strip(),
            "link": (it.findtext("link") or "").strip(),
            "published": (it.findtext("pubDate") or "").strip(),
            "source": (src.text.strip() if src is not None and src.text else None),
            "snippet": None,
            "score": None,
            "query": query,
            "provider": "google_news_rss",
        })
    return items


def main() -> int:
    now = datetime.datetime.now(datetime.timezone.utc)
    api_key = load_env_var("TAVILY_API_KEY")
    provider = "tavily" if api_key else "google_news_rss"

    all_items: list[dict] = []
    errors: list[str] = []

    for q in QUERIES:
        try:
            if api_key:
                got = fetch_tavily(q, api_key)
                # If Tavily returns nothing for a query, backfill with RSS.
                if not got:
                    got = fetch_rss(q)
                all_items.extend(got)
            else:
                all_items.extend(fetch_rss(q))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{provider}:{q}: {exc}")
            # Hard fallback to RSS for this query if Tavily errored.
            if api_key:
                try:
                    all_items.extend(fetch_rss(q))
                except Exception as exc2:  # noqa: BLE001
                    errors.append(f"rss_fallback:{q}: {exc2}")

    # De-duplicate by link (fall back to title). Keep highest score on collision.
    best: dict[str, dict] = {}
    for item in all_items:
        key = item["link"] or item["title"]
        if not key:
            continue
        prev = best.get(key)
        if prev is None or (item.get("score") or 0) > (prev.get("score") or 0):
            best[key] = item
    deduped = sorted(best.values(),
                     key=lambda x: (x.get("score") or 0), reverse=True)

    collection = {
        "collection": "ai_news",
        "fetched_at": now.isoformat().replace("+00:00", "Z"),
        "date": now.date().isoformat(),
        "primary_provider": provider,
        "queries": QUERIES,
        "window_days": WHEN_DAYS,
        "count": len(deduped),
        "errors": errors,
        "items": deduped,
    }

    payload = json.dumps(collection, ensure_ascii=False, indent=2)
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8") as fh:
            fh.write(payload)
        print(f"Wrote {len(deduped)} items to {sys.argv[1]} "
              f"(provider={provider}, errors={len(errors)})")
    else:
        print(payload)

    return 0 if deduped else 1


if __name__ == "__main__":
    sys.exit(main())
