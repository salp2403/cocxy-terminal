#!/usr/bin/env python3
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

"""Compare Cocxy performance benchmark outputs against approved baselines."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


LOG_PATTERNS: dict[str, str] = {
    "editor_scroll_frame_ms": r"Editor 5000-line average scroll frame time:\s*([0-9.]+)\s*ms",
    "editor_insert_frame_ms": r"Editor 50-cursor insertion frame time:\s*([0-9.]+)\s*ms",
    "editor_delete_frame_ms": r"Editor 50-cursor delete frame time:\s*([0-9.]+)\s*ms",
    "syntax_cold_parse_ms": r"Syntax 5000-line Swift cold parse time:\s*([0-9.]+)\s*ms",
    "syntax_viewport_capture_ms": r"Syntax 5000-line Swift viewport capture time:\s*([0-9.]+)\s*ms",
    "syntax_token_mapping_ms": r"Syntax 5000-line Swift viewport token mapping time:\s*([0-9.]+)\s*ms",
    "syntax_viewport_highlight_ms": r"Syntax 5000-line Swift viewport highlight time:\s*([0-9.]+)\s*ms",
    "syntax_incremental_parse_ms": r"Syntax 5000-line incremental Swift parse time:\s*([0-9.]+)\s*ms",
    "cocxycore_surface_creation_ms": r"CocxyCore surface creation time:\s*([0-9.]+)\s*ms",
    "cocxycore_echo_latency_ms": r"CocxyCore echo latency:\s*([0-9.]+)\s*ms",
    "cocxycore_output_throughput_mbps": r"CocxyCore output throughput:\s*([0-9.]+)\s*MB/s",
    "cocxycore_frame_average_ms": r"CocxyCore frame preparation average:\s*([0-9.]+)\s*ms",
    "cocxycore_frame_p99_ms": r"CocxyCore frame preparation p99:\s*([0-9.]+)\s*ms",
    "cocxycore_idle_rss_delta_mb": r"CocxyCore idle surface RSS delta:\s*([0-9.]+)\s*MB",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline",
        default="scripts/performance-baselines.json",
        help="Path to the approved baseline JSON.",
    )
    parser.add_argument(
        "--metric-file",
        action="append",
        default=[],
        help="JSON benchmark result file. Can be passed more than once.",
    )
    parser.add_argument(
        "--log-file",
        action="append",
        default=[],
        help="Benchmark log file to parse for printed metric lines.",
    )
    parser.add_argument(
        "--enforce",
        action="store_true",
        help="Exit non-zero when metrics are missing or regressed.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        raise SystemExit(f"Missing JSON file: {path}") from None
    except json.JSONDecodeError as error:
        raise SystemExit(f"Invalid JSON in {path}: {error}") from None


def number(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def collect_json_metrics(path: Path) -> dict[str, float]:
    payload = load_json(path)
    kind = payload.get("benchmark_kind")
    metrics: dict[str, float] = {}

    if kind == "app-readiness":
        for source_key, metric_name in [
            ("median_ms", "app_readiness_median_ms"),
            ("internal_critical_path_median_ms", "internal_critical_path_median_ms"),
        ]:
            value = number(payload.get(source_key))
            if value is not None:
                metrics[metric_name] = value
    elif kind == "memory-baseline":
        value = number(payload.get("physical_footprint_mb"))
        if value is not None:
            metrics["physical_footprint_mb"] = value
    else:
        raise SystemExit(f"Unsupported benchmark_kind in {path}: {kind!r}")

    return metrics


def collect_log_metrics(path: Path) -> dict[str, float]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        raise SystemExit(f"Missing log file: {path}") from None

    metrics: dict[str, float] = {}
    for metric_name, pattern in LOG_PATTERNS.items():
        matches = re.findall(pattern, text)
        if matches:
            metrics[metric_name] = float(matches[-1])
    return metrics


def load_baselines(path: Path) -> tuple[float, list[dict[str, Any]]]:
    payload = load_json(path)
    default_tolerance = number(payload.get("default_tolerance_ratio"))
    if default_tolerance is None:
        raise SystemExit("Baseline JSON must define numeric default_tolerance_ratio")

    metrics = payload.get("metrics")
    if not isinstance(metrics, list) or not metrics:
        raise SystemExit("Baseline JSON must define a non-empty metrics array")

    return default_tolerance, metrics


def allowed_threshold(
    baseline: float,
    direction: str,
    tolerance_ratio: float,
    absolute_tolerance: float,
) -> float:
    if direction == "lower":
        return max(baseline * (1 + tolerance_ratio), baseline + absolute_tolerance)
    if direction == "higher":
        return min(baseline * (1 - tolerance_ratio), baseline - absolute_tolerance)
    raise SystemExit(f"Unsupported metric direction: {direction!r}")


def metric_passes(actual: float, threshold: float, direction: str) -> bool:
    if direction == "lower":
        return actual <= threshold
    if direction == "higher":
        return actual >= threshold
    return False


def main() -> int:
    args = parse_args()
    default_tolerance, baselines = load_baselines(Path(args.baseline))

    actuals: dict[str, float] = {}
    for metric_file in args.metric_file:
        actuals.update(collect_json_metrics(Path(metric_file)))
    for log_file in args.log_file:
        actuals.update(collect_log_metrics(Path(log_file)))

    failures: list[str] = []
    rows: list[dict[str, Any]] = []
    for entry in baselines:
        name = entry.get("name")
        baseline = number(entry.get("baseline"))
        direction = entry.get("direction")
        if not isinstance(name, str) or baseline is None or not isinstance(direction, str):
            raise SystemExit(f"Invalid baseline metric entry: {entry!r}")

        tolerance = number(entry.get("tolerance_ratio"))
        if tolerance is None:
            tolerance = default_tolerance
        absolute_tolerance = number(entry.get("absolute_tolerance")) or 0.0

        if name not in actuals:
            failures.append(f"missing metric {name}")
            rows.append({
                "name": name,
                "status": "missing",
                "baseline": baseline,
                "actual": None,
            })
            continue

        actual = actuals[name]
        threshold = allowed_threshold(baseline, direction, tolerance, absolute_tolerance)
        passed = metric_passes(actual, threshold, direction)
        rows.append({
            "name": name,
            "status": "pass" if passed else "fail",
            "direction": direction,
            "baseline": baseline,
            "actual": actual,
            "threshold": threshold,
        })
        if not passed:
            failures.append(
                f"{name} actual {actual:.3f} breached {direction}-is-better threshold {threshold:.3f}"
            )

    print(json.dumps({"metrics": rows, "failures": failures}, indent=2, sort_keys=True))
    if failures:
        for failure in failures:
            print(f"Performance regression: {failure}", file=sys.stderr)
        return 1 if args.enforce else 0

    print("Performance regression gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
