#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${COCXY_VISUAL_GOLDEN_ARTIFACTS:-${ROOT_DIR}/build/visual-screenshot-golden/$(date +%Y%m%d-%H%M%S)}"
SOURCE_ROOT="${COCXY_VISUAL_GOLDEN_SOURCE:-}"

latest_directory() {
  local directory="$1"
  if [ ! -d "$directory" ]; then
    return 1
  fi
  find "$directory" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r | head -1
}

fail() {
  local reason="$1"
  {
    echo "status=failed"
    echo "reason=${reason}"
    echo "artifactRoot=${ARTIFACT_ROOT}"
  } | tee "${ARTIFACT_ROOT}/summary.txt"
  exit 1
}

mkdir -p "$ARTIFACT_ROOT"

if [ -z "$SOURCE_ROOT" ]; then
  SOURCE_ROOT="$(latest_directory "${ROOT_DIR}/build/browser-automation-matrix" || true)"
fi

if [ -z "$SOURCE_ROOT" ] || [ ! -d "$SOURCE_ROOT" ]; then
  fail "missing browser automation artifact directory"
fi

MATRIX_TSV="${SOURCE_ROOT}/matrix.tsv"
MANIFEST_TSV="${ARTIFACT_ROOT}/approved-goldens.tsv"
if [ ! -s "$MATRIX_TSV" ]; then
  fail "missing browser automation matrix.tsv"
fi

if ! VALIDATION_OUTPUT="$(/usr/bin/python3 - "$ROOT_DIR" "$SOURCE_ROOT" "$MATRIX_TSV" "$MANIFEST_TSV" <<'PY'
import csv
import hashlib
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1]).resolve()
source_root = pathlib.Path(sys.argv[2]).resolve()
matrix_tsv = pathlib.Path(sys.argv[3]).resolve()
manifest_tsv = pathlib.Path(sys.argv[4]).resolve()

required = [
    "focus",
    "fill",
    "type",
    "fill-editable",
    "type-page",
    "press",
    "keydown",
    "keyup",
    "hover",
    "click",
    "dblclick",
    "check",
    "uncheck",
    "check-radio",
    "upload",
    "select",
    "select-label",
    "select-index",
    "scroll",
    "scroll-into-view",
]

def rel(path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)

def png_dimensions(path: pathlib.Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    chunk_len = struct.unpack(">I", data[8:12])[0]
    chunk_type = data[12:16]
    if chunk_len != 13 or chunk_type != b"IHDR":
        raise ValueError("missing PNG IHDR")
    width, height = struct.unpack(">II", data[16:24])
    return width, height

rows: dict[str, dict[str, str]] = {}
with matrix_tsv.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    for row in reader:
        rows[row.get("scenario", "")] = row

approved: list[dict[str, str]] = []
errors: list[str] = []
for scenario in required:
    row = rows.get(scenario)
    if not row:
        errors.append(f"{scenario}: missing matrix row")
        continue
    if row.get("screenshotStatus") != "captured":
        errors.append(f"{scenario}: screenshotStatus={row.get('screenshotStatus')!r}")
        continue
    raw_path = row.get("screenshotPath", "")
    if not raw_path:
        errors.append(f"{scenario}: missing screenshotPath")
        continue
    path = pathlib.Path(raw_path)
    if not path.is_absolute():
        path = (source_root / path).resolve()
    if not path.is_file():
        errors.append(f"{scenario}: screenshot file missing at {path}")
        continue
    size = path.stat().st_size
    if size < 4096:
        errors.append(f"{scenario}: screenshot too small ({size} bytes)")
        continue
    try:
        width, height = png_dimensions(path)
    except ValueError as exc:
        errors.append(f"{scenario}: {exc}")
        continue
    if width < 640 or height < 480:
        errors.append(f"{scenario}: screenshot dimensions too small ({width}x{height})")
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    approved.append({
        "scenario": scenario,
        "sourcePath": rel(path),
        "width": str(width),
        "height": str(height),
        "bytes": str(size),
        "sha256": digest,
        "approval": "approved",
    })

if errors:
    raise SystemExit("\n".join(errors))

manifest_tsv.parent.mkdir(parents=True, exist_ok=True)
with manifest_tsv.open("w", encoding="utf-8", newline="") as handle:
    fieldnames = ["scenario", "sourcePath", "width", "height", "bytes", "sha256", "approval"]
    writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(approved)

print(f"checkedScreenshots={len(approved)}")
print(f"requiredScreenshots={len(required)}")
print(f"sourceMatrix={rel(matrix_tsv)}")
print(f"approvedManifest={rel(manifest_tsv)}")
PY
)"; then
  fail "visual golden validation failed"
fi

{
  echo "status=ok"
  echo "result=visual-screenshot-golden-ok"
  printf '%s\n' "$VALIDATION_OUTPUT"
  echo "artifactRoot=${ARTIFACT_ROOT}"
} | tee "${ARTIFACT_ROOT}/summary.txt"
