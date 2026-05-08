#!/usr/bin/env python3
"""Report or enforce coverage for Cocxy critical modules.

The script reads one or more llvm-cov JSON exports and a small JSON config.
When the same source file appears in multiple coverage exports, the script uses
the highest observed covered-line count for that file. That is conservative:
it avoids double-counting overlapping XCTest and Swift Testing coverage.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        default="scripts/critical-coverage.json",
        help="Critical coverage config JSON path.",
    )
    parser.add_argument(
        "--coverage",
        action="append",
        required=True,
        help="llvm-cov export JSON path. Pass more than once to combine conservatively.",
    )
    parser.add_argument(
        "--root",
        default=None,
        help="Repository root. Defaults to this script's parent repository.",
    )
    parser.add_argument(
        "--enforce",
        action="store_true",
        help="Exit non-zero when any configured module is below its threshold.",
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def repository_root(args: argparse.Namespace) -> Path:
    if args.root:
        return Path(args.root).resolve()
    return Path(__file__).resolve().parents[1]


def relative_filename(filename: str, root: Path) -> str:
    path = Path(filename)
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def read_coverage(paths: list[Path], root: Path) -> dict[str, tuple[int, int]]:
    by_file: dict[str, tuple[int, int]] = {}
    for path in paths:
        payload = load_json(path)
        data_entries = payload.get("data", [])
        if not data_entries:
            raise ValueError(f"{path} does not contain llvm-cov data entries")
        for file_entry in data_entries[0].get("files", []):
            filename = relative_filename(file_entry.get("filename", ""), root)
            line_summary = file_entry.get("summary", {}).get("lines", {})
            count = int(line_summary.get("count", 0))
            covered = int(line_summary.get("covered", 0))
            if count <= 0:
                continue
            previous = by_file.get(filename)
            if previous is None:
                by_file[filename] = (count, covered)
            else:
                previous_count, previous_covered = previous
                by_file[filename] = (max(previous_count, count), max(previous_covered, covered))
    return by_file


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def module_rows(config: dict[str, Any], coverage: dict[str, tuple[int, int]]) -> list[dict[str, Any]]:
    threshold = float(config.get("threshold", 80.0))
    rows: list[dict[str, Any]] = []
    for module in config.get("modules", []):
        name = module["name"]
        includes = list(module.get("include", []))
        excludes = list(module.get("exclude", []))
        matched = [
            path
            for path in sorted(coverage)
            if matches_any(path, includes) and not matches_any(path, excludes)
        ]
        count = sum(coverage[path][0] for path in matched)
        covered = sum(coverage[path][1] for path in matched)
        percent = (100.0 * covered / count) if count else 0.0
        module_threshold = float(module.get("threshold", threshold))
        rows.append(
            {
                "name": name,
                "files": len(matched),
                "covered": covered,
                "count": count,
                "percent": percent,
                "threshold": module_threshold,
                "passed": bool(count and percent >= module_threshold),
            }
        )
    return rows


def print_report(rows: list[dict[str, Any]], enforce: bool) -> None:
    print("Critical coverage modules")
    print("module                          files   covered/lines   percent   threshold   status")
    for row in rows:
        status = "PASS" if row["passed"] else "FAIL"
        print(
            f"{row['name']:<31} "
            f"{row['files']:>5} "
            f"{row['covered']:>7}/{row['count']:<7} "
            f"{row['percent']:>7.2f}% "
            f"{row['threshold']:>8.2f}%   "
            f"{status}"
        )
    if enforce:
        print("Enforce mode: failing modules block the gate.")
    else:
        print("Report-only mode: pass --enforce to fail below-threshold modules.")


def main() -> int:
    args = parse_args()
    root = repository_root(args)
    config = load_json((root / args.config).resolve() if not Path(args.config).is_absolute() else Path(args.config))
    coverage_paths = [
        (root / path).resolve() if not Path(path).is_absolute() else Path(path)
        for path in args.coverage
    ]
    coverage = read_coverage(coverage_paths, root)
    rows = module_rows(config, coverage)
    print_report(rows, args.enforce)
    if any(row["count"] == 0 for row in rows):
        print("error: one or more critical modules matched zero executable coverage lines", file=sys.stderr)
        return 1
    if args.enforce and any(not row["passed"] for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
