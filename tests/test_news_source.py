"""Unit tests for the fetcher's pure collection-building logic (news_source.py)."""

import news_source


def test_build_collection_tags_and_dedupes(monkeypatch):
    # Replace the network fetch with a canned result so the test is offline.
    def fake_tavily(query, api_key):
        # Same link returned for every query -> should dedupe to one item,
        # keeping the highest score (and its category).
        return [{"title": "Dup", "link": "http://x/dup", "score": 0.5,
                 "source": "x", "snippet": "", "published": ""}]

    monkeypatch.setattr(news_source, "fetch_tavily", fake_tavily)

    coll = news_source.build_collection(api_key="fake-key")

    assert coll["collection"] == "ai_news"
    assert coll["primary_provider"] == "tavily"
    assert coll["category_order"] == list(news_source.CATEGORIES.keys())
    # The identical link collapses to a single deduped item.
    assert coll["count"] == 1
    assert coll["items"][0]["category"] in news_source.CATEGORIES


def test_rss_fallback_when_no_key(monkeypatch):
    def fake_rss(query):
        return [{"title": query, "link": f"http://x/{query}", "score": None,
                 "source": None, "snippet": None, "published": ""}]

    monkeypatch.setattr(news_source, "fetch_rss", fake_rss)

    coll = news_source.build_collection(api_key=None)

    assert coll["primary_provider"] == "google_news_rss"
    assert coll["count"] > 0
