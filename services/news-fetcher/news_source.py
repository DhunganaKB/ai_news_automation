"""
news_source.py  —  category-aware AI news fetcher (pure logic, no I/O side effects).

Canonical fetch logic for the cloud `news-fetcher` service. Given a Tavily API
key (or None), it returns a ready-to-serialise "collection" dict identical in
shape to what the processor expects.

Keep the CATEGORIES here in sync with ingestion/fetch_ai_news.py (the local
preview copy).
"""

import datetime
import json
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

# --- The 5 categories and their search queries. -----------------------------
CATEGORIES: dict[str, list[str]] = {
    "Software Development": [
        "AI coding assistant OR AI code generation developer tools",
        "AI agents for software engineering OR programming",
    ],
    "Model Development": [
        "new large language model release OR foundation model",
        "LLM training OR fine-tuning OR model architecture",
    ],
    "Economic Impact": [
        "AI impact on jobs OR labor market OR economy",
        "AI investment OR funding OR market valuation",
    ],
    "Big Tech": [
        "OpenAI OR Anthropic OR Google DeepMind OR Microsoft OR Meta OR Nvidia AI announcement",
        "big technology company artificial intelligence strategy",
    ],
    "Research": [
        "AI research breakthrough OR new paper OR study",
        "machine learning research university OR arxiv",
    ],
}

WHEN_DAYS = 2
MAX_PER_QUERY = 12
HL, GL, CEID = "en-US", "US", "US:en"
USER_AGENT = "Mozilla/5.0 (ai-news-fetcher)"
TIMEOUT = 30


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


def build_collection(api_key: str | None) -> dict:
    """Fetch every category and return the collection dict."""
    now = datetime.datetime.now(datetime.timezone.utc)
    provider = "tavily" if api_key else "google_news_rss"

    all_items: list[dict] = []
    errors: list[str] = []

    for category, queries in CATEGORIES.items():
        for q in queries:
            got: list[dict] = []
            try:
                got = fetch_tavily(q, api_key) if api_key else fetch_rss(q)
                if api_key and not got:
                    got = fetch_rss(q)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{provider}:{category}:{q}: {exc}")
                if api_key:
                    try:
                        got = fetch_rss(q)
                    except Exception as exc2:  # noqa: BLE001
                        errors.append(f"rss_fallback:{category}:{q}: {exc2}")
            for it in got:
                it["category"] = category
            all_items.extend(got)

    # De-duplicate by link; keep the highest-scoring copy (that fixes its category).
    best: dict[str, dict] = {}
    for item in all_items:
        key = item["link"] or item["title"]
        if not key:
            continue
        prev = best.get(key)
        if prev is None or (item.get("score") or 0) > (prev.get("score") or 0):
            best[key] = item
    deduped = list(best.values())

    order = list(CATEGORIES.keys())
    counts = {c: sum(1 for it in deduped if it.get("category") == c) for c in order}

    return {
        "collection": "ai_news",
        "fetched_at": now.isoformat().replace("+00:00", "Z"),
        "date": now.date().isoformat(),
        "primary_provider": provider,
        "category_order": order,
        "category_counts": counts,
        "window_days": WHEN_DAYS,
        "count": len(deduped),
        "errors": errors,
        "items": deduped,
    }
