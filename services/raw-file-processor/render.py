"""
render.py  —  pure rendering logic for raw-file-processor (no FastAPI, no GCS).

Kept dependency-free (standard library only) so it can be unit-tested directly.
main.py imports process_data() from here and handles the HTTP + Storage glue.
"""

import csv
import datetime
import html
import io
import os
import re
from email.utils import parsedate_to_datetime

PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/")
# Show at most this many stories per category (the highest-relevance ones).
MAX_PER_CATEGORY = int(os.environ.get("MAX_PER_CATEGORY", "5"))

CATEGORY_AUDIENCE = {
    "Software Development": "for engineers & builders",
    "Model Development": "for ML practitioners",
    "Economic Impact": "for business & policy",
    "Big Tech": "for industry watchers",
    "Research": "for researchers & academics",
}


def _pretty_date(raw: str) -> str:
    """Turn an RFC-822 / ISO date string into 'Sep 12, 2026'. Fallback: raw."""
    if not raw:
        return ""
    try:
        return parsedate_to_datetime(raw).strftime("%b %d, %Y")
    except (TypeError, ValueError):
        pass
    try:
        return datetime.datetime.fromisoformat(
            raw.replace("Z", "+00:00")).strftime("%b %d, %Y")
    except ValueError:
        return raw


def _digest_date(collection: dict, object_name: str) -> str:
    """Best-effort YYYY-MM-DD for the output filename/title."""
    if collection.get("date"):
        return str(collection["date"])
    m = re.search(r"(\d{4}-\d{2}-\d{2})", object_name)
    if m:
        return m.group(1)
    return datetime.datetime.now(datetime.timezone.utc).date().isoformat()


def _card_html(rank: int, it: dict) -> str:
    title = html.escape((it.get("title") or "Untitled").strip())
    link = html.escape((it.get("link") or "#").strip(), quote=True)
    source = html.escape((it.get("source") or "").strip())
    published = html.escape(_pretty_date(it.get("published") or ""))
    snippet = html.escape((it.get("snippet") or "").strip())

    score = it.get("score")
    score_badge, tier = "", "t-none"
    if isinstance(score, (int, float)):
        pct = round(float(score) * 100)
        tier = "t-high" if pct >= 80 else "t-mid" if pct >= 65 else "t-low"
        score_badge = f'<span class="score {tier}">{pct}% match</span>'

    meta_bits = []
    if source:
        meta_bits.append(f'<span class="src">{source}</span>')
    if published:
        meta_bits.append(f'<span class="date">{published}</span>')
    meta_row = ('<div class="metarow">' + "".join(meta_bits) + score_badge
                + "</div>") if (meta_bits or score_badge) else ""
    snippet_html = f'<p class="snippet">{snippet}</p>' if snippet else ""

    return f"""
        <article class="card {tier}">
          <div class="rank">{rank}</div>
          <div class="content">
            <a class="title" href="{link}" target="_blank" rel="noopener">{title}</a>
            {meta_row}
            {snippet_html}
            <a class="read" href="{link}" target="_blank" rel="noopener">Read article ↗</a>
          </div>
        </article>"""


def render_news_html(collection: dict, date_str: str) -> str:
    """Render the collection as a self-contained, categorised HTML page."""
    items = collection.get("items", []) or []

    order = collection.get("category_order")
    if not order:
        order, seen = [], set()
        for it in items:
            c = it.get("category") or "AI News"
            if c not in seen:
                seen.add(c)
                order.append(c)
        if not order:
            order = ["AI News"]

    grouped: dict[str, list[dict]] = {c: [] for c in order}
    for it in items:
        c = it.get("category") or order[0]
        grouped.setdefault(c, []).append(it)
        if c not in order:
            order.append(c)
    for c in grouped:
        grouped[c].sort(key=lambda x: (x.get("score") is not None,
                                       x.get("score") or 0), reverse=True)
        grouped[c] = grouped[c][:MAX_PER_CATEGORY]

    provider = html.escape(str(collection.get("primary_provider", "web")))
    fetched = _pretty_date(collection.get("fetched_at", "")) or date_str
    total = sum(len(v) for v in grouped.values())

    tabs = [f'<button class="tab active" data-cat="__all">All '
            f'<span class="n">{total}</span></button>']
    sections = []
    for cat in order:
        cards = grouped.get(cat, [])
        if not cards:
            continue
        cat_attr = html.escape(cat, quote=True)
        cat_txt = html.escape(cat)
        aud = html.escape(CATEGORY_AUDIENCE.get(cat, ""))
        tabs.append(f'<button class="tab" data-cat="{cat_attr}">{cat_txt} '
                    f'<span class="n">{len(cards)}</span></button>')
        cards_html = "\n".join(_card_html(i, it) for i, it in enumerate(cards, 1))
        aud_html = f'<span class="aud">{aud}</span>' if aud else ""
        sections.append(f"""
      <section class="cat-section" data-cat="{cat_attr}">
        <h2>{cat_txt} {aud_html}</h2>
        <p class="cnt">{len(cards)} stories</p>
        {cards_html}
      </section>""")

    tabs_html = "\n        ".join(tabs)
    body = "\n".join(sections) if sections else (
        '<p class="empty">No news items were found in this collection.</p>')

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AI News Digest — {date_str}</title>
<style>
  :root{{
    --bg:#f4f6f9; --card:#ffffff; --ink:#141a22; --muted:#5c6879;
    --line:#e6eaf0; --accent:#3457d5; --accent-ink:#1e3aad;
    --accent-soft:#eef2ff; --chip:#eef1f6;
    --high:#12805c; --high-bg:#e5f6ef; --mid:#a15c00; --mid-bg:#fdf1df;
  }}
  *{{box-sizing:border-box}}
  body{{margin:0;background:var(--bg);color:var(--ink);
    font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;}}
  .wrap{{max-width:820px;margin:0 auto;padding:40px 20px 72px}}
  header.hero{{background:linear-gradient(135deg,#1b2440,#3457d5);color:#fff;
    border-radius:18px;padding:34px 34px 30px;margin-bottom:6px;
    box-shadow:0 10px 30px rgba(25,45,110,.22)}}
  .kicker{{font-size:12px;font-weight:700;letter-spacing:.18em;opacity:.85;margin-bottom:8px}}
  header.hero h1{{margin:0;font-size:30px;letter-spacing:.2px}}
  header.hero .meta{{margin:10px 0 0;opacity:.9;font-size:14px}}
  nav.tabs{{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;gap:8px;
    background:var(--bg);padding:14px 0;margin-bottom:6px;border-bottom:1px solid var(--line)}}
  .tab{{border:1px solid var(--line);background:var(--card);color:var(--ink);
    border-radius:999px;padding:8px 15px;font-size:13.5px;font-weight:600;cursor:pointer;
    display:inline-flex;align-items:center;gap:7px;transition:background .12s,border-color .12s}}
  .tab:hover{{border-color:var(--accent)}}
  .tab.active{{background:var(--accent);color:#fff;border-color:var(--accent)}}
  .tab .n{{font-size:11.5px;background:rgba(20,30,50,.09);border-radius:999px;padding:1px 8px}}
  .tab.active .n{{background:rgba(255,255,255,.25)}}
  .cat-section{{margin-top:26px}}
  .cat-section h2{{font-size:21px;margin:0 0 2px;display:flex;flex-wrap:wrap;align-items:baseline;gap:10px}}
  .cat-section h2 .aud{{font-size:13px;font-weight:500;color:var(--muted)}}
  .cat-section .cnt{{color:var(--muted);font-size:13px;margin:0 0 14px}}
  .card{{position:relative;display:flex;gap:16px;background:var(--card);
    border:1px solid var(--line);border-left:4px solid var(--accent);
    border-radius:14px;padding:20px 22px;margin-bottom:16px;
    box-shadow:0 1px 3px rgba(20,30,50,.05);transition:box-shadow .15s,transform .15s}}
  .card:hover{{box-shadow:0 8px 24px rgba(20,30,50,.12);transform:translateY(-2px)}}
  .card.t-high{{border-left-color:var(--high)}}
  .card.t-mid{{border-left-color:var(--mid)}}
  .rank{{flex:0 0 auto;width:30px;height:30px;border-radius:8px;background:var(--accent-soft);
    color:var(--accent-ink);font-size:14px;font-weight:700;display:grid;place-items:center}}
  .content{{flex:1;min-width:0}}
  a.title{{display:inline-block;font-size:18px;font-weight:700;line-height:1.35;
    color:var(--accent-ink);text-decoration:none}}
  a.title:hover{{text-decoration:underline}}
  .metarow{{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:9px 0 4px}}
  .src{{background:var(--chip);border:1px solid var(--line);border-radius:6px;
    padding:2px 9px;font-size:12.5px;font-weight:600;color:var(--ink)}}
  .date{{color:var(--muted);font-size:12.5px}}
  .score{{margin-left:auto;font-size:11.5px;font-weight:700;border-radius:999px;padding:3px 10px}}
  .score.t-high{{background:var(--high-bg);color:var(--high)}}
  .score.t-mid {{background:var(--mid-bg);color:var(--mid)}}
  .score.t-low{{background:var(--chip);color:var(--muted)}}
  .snippet{{margin:6px 0 12px;color:#37424f;font-size:14.5px}}
  a.read{{display:inline-block;font-size:13px;font-weight:600;color:#fff;
    background:var(--accent);border-radius:8px;padding:7px 14px;text-decoration:none}}
  a.read:hover{{background:var(--accent-ink)}}
  .empty{{background:var(--card);border:1px solid var(--line);border-radius:14px;
    padding:30px;text-align:center;color:var(--muted)}}
  footer{{color:var(--muted);font-size:12.5px;text-align:center;margin-top:26px}}
</style>
</head>
<body>
  <div class="wrap">
    <header class="hero">
      <div class="kicker">AI NEWS DIGEST</div>
      <h1>{date_str}</h1>
      <p class="meta">{total} stories across {len([c for c in order if grouped.get(c)])} categories · source: {provider} · generated {fetched}</p>
    </header>

    <nav class="tabs">
        {tabs_html}
    </nav>

    <main id="sections">
{body}
    </main>
    <footer>Generated automatically from {html.escape(collection.get("collection", "ai_news"))} · {total} items</footer>
  </div>

<script>
  var tabs = document.querySelectorAll('.tab');
  var sections = document.querySelectorAll('.cat-section');
  tabs.forEach(function(t){{
    t.addEventListener('click', function(){{
      tabs.forEach(function(x){{ x.classList.remove('active'); }});
      t.classList.add('active');
      var cat = t.getAttribute('data-cat');
      sections.forEach(function(s){{
        s.hidden = !(cat === '__all' || s.getAttribute('data-cat') === cat);
      }});
      window.scrollTo({{ top: 0, behavior: 'smooth' }});
    }});
  }});
</script>
</body>
</html>
"""


def process_data(object_name: str, raw_bytes: bytes) -> tuple[bytes, str]:
    """Route an input object to its output bytes + destination object name."""
    import json

    base = object_name.split("/")[-1]

    # News JSON -> categorised HTML digest.
    if base.lower().endswith(".json"):
        collection = json.loads(raw_bytes.decode("utf-8", errors="replace"))
        date_str = _digest_date(collection, object_name)
        page = render_news_html(collection, date_str)
        return page.encode("utf-8"), f"{PROCESSED_PREFIX}ai_news_{date_str}.html"

    # CSV demo: append a processed_at column.
    if base.lower().endswith(".csv"):
        processed_at = datetime.datetime.utcnow().isoformat() + "Z"
        reader = csv.reader(io.StringIO(raw_bytes.decode("utf-8", errors="replace")))
        out = io.StringIO()
        writer = csv.writer(out)
        for i, row in enumerate(reader):
            writer.writerow(row + (["processed_at"] if i == 0 else [processed_at]))
        return out.getvalue().encode("utf-8"), f"{PROCESSED_PREFIX}{base}"

    # Anything else: pass through.
    return raw_bytes, f"{PROCESSED_PREFIX}{base}"
