#!/usr/bin/env python3
"""
parse_stage6_placement_summary.py

Parses kairo_bench Stage 6 placement/lifetime summary output and prints
a formatted comparison table.

Usage:
    python3 parse_stage6_placement_summary.py < log.txt
    python3 parse_stage6_placement_summary.py file1.log file2.log ...
"""

import re
import sys
from pathlib import Path

RE_FIELDS = {
    "file": re.compile(r"^file=(.+)$"),
    "mode": re.compile(r"^mode=(.+)$"),
    "hint_mode": re.compile(r"^hint_mode=(.+)$"),
    "semantic_mode": re.compile(r"^semantic_mode=(.+)$"),
    "access_pattern": re.compile(r"^access_pattern=(.+)$"),
    "block_size_bytes": re.compile(r"^block_size_bytes=(\d+)$"),
    "sessions": re.compile(r"^sessions=(\d+)$"),
    "models": re.compile(r"^models=(\d+)$"),
    "cache_pools": re.compile(r"^cache_pools=(\d+)$"),
    "placement_groups": re.compile(r"^placement_groups=(\d+)$"),
    "lifetime": re.compile(r"^lifetime=(.+)$"),
    "recompute_ok": re.compile(r"^recompute_ok=(\d+)$"),
    "fixed_model_id": re.compile(r"^fixed_model_id=(\d+)$"),
    "fixed_session_id": re.compile(r"^fixed_session_id=(\d+)$"),
    "fixed_cache_pool_id": re.compile(r"^fixed_cache_pool_id=(\d+)$"),
    "fixed_placement_group": re.compile(r"^fixed_placement_group=(\d+)$"),
    "decode_threads": re.compile(r"^decode_threads=(\d+)$"),
    "prefetch_threads": re.compile(r"^prefetch_threads=(\d+)$"),
    "write_threads": re.compile(r"^write_threads=(\d+)$"),
    "evict_threads": re.compile(r"^evict_threads=(\d+)$"),
    "decode_total_reads": re.compile(r"^decode_total_reads=(\d+)$"),
    "prefetch_total_reads": re.compile(r"^prefetch_total_reads=(\d+)$"),
    "write_total_ops": re.compile(r"^write_total_ops=(\d+)$"),
    "evict_total_ops": re.compile(r"^evict_total_ops=(\d+)$"),
    "decode_avg_us": re.compile(r"^decode_avg_us=([0-9.]+)$"),
    "decode_p50_us": re.compile(r"^decode_p50_us=([0-9.]+)$"),
    "decode_p95_us": re.compile(r"^decode_p95_us=([0-9.]+)$"),
    "decode_p99_us": re.compile(r"^decode_p99_us=([0-9.]+)$"),
    "decode_read_MBps": re.compile(r"^decode_read_MBps=([0-9.]+)$"),
    "prefetch_read_MBps": re.compile(r"^prefetch_read_MBps=([0-9.]+)$"),
    "write_MBps": re.compile(r"^write_MBps=([0-9.]+)$"),
}

HEADER_LINE = re.compile(r"^=== Run: (.+) ===")


def parse_log(text: str) -> list[dict]:
    """Parse concatenated kairo_bench outputs, returning a list of run dicts."""
    runs = []
    current = None

    for line in text.splitlines():
        m = HEADER_LINE.match(line)
        if m:
            if current is not None:
                runs.append(current)
            current = {"_label": m.group(1)}
            continue

        if current is None:
            continue

        for key, regex in RE_FIELDS.items():
            m2 = regex.match(line)
            if m2:
                current[key] = m2.group(1)
                break

    if current is not None:
        runs.append(current)

    return runs


def fmt(val: str | None, default: str = "-") -> str:
    return val if val else default


def print_table(runs: list[dict]) -> None:
    """Print a formatted comparison table of all runs."""
    if not runs:
        print("(no runs parsed)")
        return

    columns = [
        ("Label", "_label"),
        ("Lifetime", "lifetime"),
        ("Recompute", "recompute_ok"),
        ("FixModel", "fixed_model_id"),
        ("FixSession", "fixed_session_id"),
        ("FixCache", "fixed_cache_pool_id"),
        ("FixPlace", "fixed_placement_group"),
        ("CachePools", "cache_pools"),
        ("PlaceGrps", "placement_groups"),
        ("DecodeRd", "decode_total_reads"),
        ("DecAvgUs", "decode_avg_us"),
        ("DecP95Us", "decode_p95_us"),
        ("DecMBps", "decode_read_MBps"),
        ("WrMBps", "write_MBps"),
    ]

    col_widths = {}
    for header, key in columns:
        max_w = len(header)
        for run in runs:
            v = fmt(run.get(key, ""))
            if len(v) > max_w:
                max_w = len(v)
        col_widths[key] = max(max_w, len(header))

    # header
    parts = []
    for header, key in columns:
        parts.append(header.rjust(col_widths[key]))
    print(" | ".join(parts))
    print("-+-".join("-" * w for _, (_, key) in zip(columns, [(c, c) for c in columns]) if (w := col_widths.get(key if isinstance(key, str) else "", 1))))

    # Actually just print simple separator
    total_w = sum(col_widths.values()) + 3 * (len(columns) - 1)
    print("-" * total_w)

    # rows
    for run in runs:
        parts = []
        for header, key in columns:
            v = fmt(run.get(key, ""))
            parts.append(v.rjust(col_widths[key]))
        print(" | ".join(parts))


def main() -> None:
    if len(sys.argv) > 1:
        for path in sys.argv[1:]:
            text = Path(path).read_text()
            runs = parse_log(text)
            print(f"\n=== {path} ===")
            print_table(runs)
    else:
        text = sys.stdin.read()
        runs = parse_log(text)
        print_table(runs)


if __name__ == "__main__":
    main()
