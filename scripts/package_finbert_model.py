"""Package the compiled FinBERT model as flat release assets + a hash manifest.

    xcrun coremlcompiler compile ios/NewsEdge/NewsEdge/Resources/FinBERT.mlpackage /tmp/compiled
    python3 scripts/package_finbert_model.py /tmp/compiled/FinBERT.mlmodelc /tmp/release
    gh release create finbert-coreml-v1 /tmp/release/* --title "FinBERT Core ML v1" --notes "..."

GitHub release assets can't contain '/', so paths are flattened with '__'. The app
(FinBERTModelStore) downloads manifest.json, then each asset, verifies size + SHA-256,
and rebuilds the .mlmodelc directory in Application Support.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
assert src.suffix == ".mlmodelc" and src.is_dir(), "pass the compiled .mlmodelc directory"
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)

files = []
for f in sorted(p for p in src.rglob("*") if p.is_file()):
    rel = f.relative_to(src).as_posix()
    asset = rel.replace("/", "__")
    shutil.copy(f, out / asset)
    files.append({"asset": asset, "path": rel, "size": f.stat().st_size,
                  "sha256": hashlib.sha256(f.read_bytes()).hexdigest()})
(out / "manifest.json").write_text(json.dumps({"version": 1, "files": files}, indent=2))
print(f"{len(files)} files, {sum(f['size'] for f in files) / 1e6:.1f} MB -> {out}")
