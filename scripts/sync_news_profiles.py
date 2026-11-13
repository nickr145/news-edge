"""Keep the curated news profiles identical across the three places that load them.

    python3 scripts/sync_news_profiles.py          # copy data/news_profiles.json to the clients
    python3 scripts/sync_news_profiles.py --check  # exit 1 if any copy differs (for CI / pre-commit)

data/news_profiles.json is the single source of truth. Edit it, run this script, commit all three.
"""
import filecmp
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / "data/news_profiles.json"
copies = [root / "frontend/src/data/newsProfiles.json", root / "ios/NewsEdge/NewsEdge/Resources/NewsProfiles.json"]

stale = [c for c in copies if not c.exists() or not filecmp.cmp(src, c, shallow=False)]
if "--check" in sys.argv:
    for c in stale:
        print(f"out of sync: {c.relative_to(root)}")
    sys.exit(1 if stale else 0)
for c in copies:
    shutil.copy(src, c)
print(f"synced {len(copies)} copies" + (f" ({len(stale)} were stale)" if stale else ""))
