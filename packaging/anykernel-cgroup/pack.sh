#!/usr/bin/env bash
# Pack AnyKernel3 zip with Image (or Image.xz).
# Usage: ./pack.sh <Image|Image.xz> [output.zip]
#   output.zip may be a bare filename (written under this dir), an absolute
#   path, or a path relative to the repo root.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$ROOT/../.." && pwd)
IMG_IN=${1:?Image or Image.xz}
OUT_ZIP=${2:-}

if [[ "$IMG_IN" == *.xz ]]; then
  python3 - <<PY
import lzma, shutil
from pathlib import Path
src=Path("$IMG_IN"); dst=Path("$ROOT/Image")
with lzma.open(src) as f, open(dst,"wb") as o: shutil.copyfileobj(f,o)
print("decompressed", dst.stat().st_size)
PY
else
  cp -f "$IMG_IN" "$ROOT/Image.tmp" && mv -f "$ROOT/Image.tmp" "$ROOT/Image"
fi

SHORT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
if [[ -z "$OUT_ZIP" ]]; then
  OUT_ZIP="$ROOT/AnyKernel3-ums9230-cgroup2-ion-${SHORT}.zip"
elif [[ "$OUT_ZIP" == /* ]]; then
  :
elif [[ "$OUT_ZIP" == */* ]]; then
  # path relative to repo root (CI passes packaging/anykernel-cgroup/foo.zip)
  OUT_ZIP="$REPO/$OUT_ZIP"
else
  # bare filename → under packaging dir
  OUT_ZIP="$ROOT/$OUT_ZIP"
fi

mkdir -p "$(dirname "$OUT_ZIP")"

python3 - <<PY
import zipfile
from pathlib import Path
root = Path("$ROOT")
out = Path("$OUT_ZIP")
with zipfile.ZipFile(out, "w", allowZip64=True) as z:
  for path in sorted(root.rglob("*")):
    if not path.is_file():
      continue
    rel = path.relative_to(root).as_posix()
    if rel.endswith(".zip") or rel == "pack.sh" or rel == "Image.tmp":
      continue
    zi = zipfile.ZipInfo.from_file(path, rel)
    zi.compress_type = zipfile.ZIP_STORED if path.name == "Image" else zipfile.ZIP_DEFLATED
    with open(path, "rb") as f:
      z.writestr(zi, f.read())
print("wrote", out, out.stat().st_size)
PY
