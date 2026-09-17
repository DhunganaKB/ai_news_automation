"""Unit tests for the processor's pure rendering logic (render.py)."""

import json

import render


def _collection():
    return {
        "collection": "ai_news",
        "date": "2026-09-17",
        "primary_provider": "tavily",
        "category_order": ["Software Development", "Research"],
        "items": [
            {"title": "A", "link": "http://x/a", "category": "Software Development", "score": 0.9},
            {"title": "B", "link": "http://x/b", "category": "Software Development", "score": 0.7},
            {"title": "C", "link": "http://x/c", "category": "Research", "score": 0.8},
        ],
    }


def test_process_data_json_makes_html():
    raw = json.dumps(_collection()).encode()
    out_bytes, out_name = render.process_data("incoming/ai_news_2026-09-17.json", raw)
    assert out_name == "processed/ai_news_2026-09-17.html"
    html = out_bytes.decode()
    assert "<!DOCTYPE html>" in html
    # One tab per category plus the "All" tab.
    assert 'data-cat="Software Development"' in html
    assert 'data-cat="Research"' in html


def test_top_n_cap_per_category(monkeypatch):
    monkeypatch.setattr(render, "MAX_PER_CATEGORY", 1)
    coll = _collection()
    html = render.render_news_html(coll, coll["date"])
    # Software Development had 2 items; capped to 1 story card there.
    assert html.count('class="card ') == 2  # 1 per category, 2 categories


def test_html_is_escaped():
    coll = {
        "date": "2026-09-17",
        "category_order": ["Research"],
        "items": [{"title": "<script>alert(1)</script>", "link": "http://x",
                   "category": "Research", "score": 0.5}],
    }
    html = render.render_news_html(coll, coll["date"])
    assert "<script>alert(1)</script>" not in html
    assert "&lt;script&gt;" in html


def test_non_json_passthrough():
    out_bytes, out_name = render.process_data("incoming/photo.png", b"rawbytes")
    assert out_bytes == b"rawbytes"
    assert out_name == "processed/photo.png"
