"""Keep the curated news data (profiles + background vocabulary) identical across the places that load it.

    python3 scripts/sync_news_profiles.py          # copy data/news_profiles.json to the clients
    python3 scripts/sync_news_profiles.py --check  # exit 1 if any copy differs (for CI / pre-commit)

data/news_profiles.json and data/news_background.json are the sources of truth (the latter is rebuilt by
scripts/build_background_tokens.mjs). Edit, run this script, commit all copies.
"""
import filecmp
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
pairs = [  # (source of truth, copy)
    (root / "data/news_profiles.json", root / "frontend/src/data/newsProfiles.json"),
    (root / "data/news_profiles.json", root / "ios/NewsEdge/NewsEdge/Resources/NewsProfiles.json"),
    (root / "data/news_background.json", root / "frontend/src/data/newsBackground.json"),
    (root / "data/news_background.json", root / "ios/NewsEdge/NewsEdge/Resources/NewsBackground.json"),
]

stale = [c for src, c in pairs if not c.exists() or not filecmp.cmp(src, c, shallow=False)]
if "--check" in sys.argv:
    for c in stale:
        print(f"out of sync: {c.relative_to(root)}")
    sys.exit(1 if stale else 0)
for src, c in pairs:
    shutil.copy(src, c)
print(f"synced {len(pairs)} copies" + (f" ({len(stale)} were stale)" if stale else ""))
