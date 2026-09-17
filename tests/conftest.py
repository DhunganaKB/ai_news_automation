"""Make the two service packages importable in tests (they aren't installed)."""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
for rel in ("services/raw-file-processor", "services/news-fetcher"):
    sys.path.insert(0, str(ROOT / rel))
