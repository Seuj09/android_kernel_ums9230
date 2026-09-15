#!/usr/bin/env bash
# Rebuild AnyKernel3-ums9230-cgroup2-early-ba98de94.zip
# Usage: ./pack.sh /path/to/Image   OR   ./pack.sh /path/to/Image.xz
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
IMG_IN=${1:?Image or Image.xz}
if [[ "$IMG_IN" == *.xz ]]; then
  python3 - <<PY
import lzma, shutil
from pathlib import Path
src=Path("$IMG_IN"); dst=Path("$ROOT/Image")
with lzma.open(src) as f, open(dst,"wb") as o: shutil.copyfileobj(f,o)
print("decompressed", dst, dst.stat().st_size)
PY
else
  cp -f "$IMG_IN" "$ROOT/Image"
fi
python3 - <<PY
import zipfile
from pathlib import Path
root = Path("$ROOT")
out = root / "AnyKernel3-ums9230-cgroup2-early-ba98de94.zip"
with zipfile.ZipFile(out, "w", allowZip64=True) as z:
  for path in root.rglob("*"):
    if not path.is_file():
      continue
    rel = path.relative_to(root).as_posix()
    if rel.endswith(".zip") or rel == "pack.sh":
      continue
    zi = zipfile.ZipInfo.from_file(path, rel)
    zi.compress_type = zipfile.ZIP_STORED if path.name == "Image" else zipfile.ZIP_DEFLATED
    z.write(path, rel)
print("wrote", out, out.stat().st_size)
PY
