#!/usr/bin/env python3
"""
parse_stage6_placement_summary.py

Parses Stage 6 benchmark summary.log files and emits CSV or pretty-printed
tables suitable for analysis and comparison.

Usage:
    python3 parse_stage6_placement_summary.py results/stage6/*/summary.log --csv
    python3 parse_stage6_placement_summary.py results/stage6/*/summary.log --pretty
    cat summary.log | python3 parse_stage6_placement_summary.py --csv
"""

import csv
import re
import sys
from pathlib import Path

CSV_COLUMNS = [
    "case",
    "models",
    "sessions",
    "cache_pools",
    "placement_groups",
    "lifetime",
    "recompute_ok",
    "semantic_mode",
    "hint_mode",
    "decode_p99_us",
    "decode_p95_us",
    "decode_avg_us",
    "write_MBps",
    "decode_read_MBps",
    "prefetch_read_MBps",
    "total_evictions",
    "kairo_model_tagged_requests_delta",
    "kairo_session_tagged_requests_delta",
    "kairo_cache_pool_tagged_requests_delta",
    "kairo_recompute_ok_requests_delta",
    "kairo_placement_hints_delta",
    "kairo_has_model_id_count_delta",
    "kairo_has_session_id_count_delta",
    "kairo_has_cache_pool_count_delta",
    "kairo_lifetime_short_count_delta",
    "kairo_lifetime_session_count_delta",
    "kairo_lifetime_model_count_delta",
    "kairo_lifetime_persistent_count_delta",
]

RE_KEY_VAL = re.compile(r"^(\w[\w_]*)=(.*)$")


def parse_summary(text: str) -> dict:
    """Parse a summary.log text into a key-value dict."""
    result = {}
    for line in text.splitlines():
        m = RE_KEY_VAL.match(line)
        if m:
            result[m.group(1)] = m.group(2).strip()
    return result


def parse_summary_file(path: Path) -> dict:
    return parse_summary(path.read_text())


def parse_stdin() -> list[dict]:
    """Parse concatenated summary.log content from stdin (header-separated)."""
    return [parse_summary(sys.stdin.read())]


def make_row(summary: dict) -> dict:
    """Build a CSV row dict from a parsed summary, with blank for missing keys."""
    row = {}
    for col in CSV_COLUMNS:
        row[col] = summary.get(col, "")
    return row


def write_csv(rows: list[dict], out):
    writer = csv.DictWriter(out, fieldnames=CSV_COLUMNS)
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


def write_pretty(rows: list[dict], out):
    if not rows:
        print("(no data)", file=out)
        return

    col_widths = {col: len(col) for col in CSV_COLUMNS}
    for row in rows:
        for col in CSV_COLUMNS:
            col_widths[col] = max(col_widths[col], len(str(row.get(col, ""))))

    header = " | ".join(h.rjust(col_widths[h]) for h in CSV_COLUMNS)
    sep = "-+-".join("-" * col_widths[h] for h in CSV_COLUMNS)

    print(header, file=out)
    print(sep, file=out)
    for row in rows:
        line = " | ".join(str(row.get(h, "")).rjust(col_widths[h]) for h in CSV_COLUMNS)
        print(line, file=out)


def main():
    args = sys.argv[1:]
    fmt = "pretty"
    paths = []

    i = 0
    while i < len(args):
        if args[i] == "--csv":
            fmt = "csv"
        elif args[i] == "--pretty":
            fmt = "pretty"
        elif args[i].startswith("--"):
            print(f"unknown option: {args[i]}", file=sys.stderr)
            return 1
        else:
            paths.append(args[i])
        i += 1

    rows = []
    if paths:
        for p in paths:
            pp = Path(p)
            if pp.exists():
                rows.append(make_row(parse_summary_file(pp)))
            else:
                print(f"warning: not found: {p}", file=sys.stderr)
    else:
        rows = [make_row(r) for r in parse_stdin()]

    if fmt == "csv":
        write_csv(rows, sys.stdout)
    else:
        write_pretty(rows, sys.stdout)

    return 0


if __name__ == "__main__":
    sys.exit(main())
