#!/usr/bin/env python3
"""
parse_stage11_foundation_trace_summary.py

Parse Stage 11 foundation trace experiment summary logs and emit
CSV or pretty-printed tables.

Usage:
  python3 parse_stage11_foundation_trace_summary.py <summary-log>... [--csv|--pretty]
"""

import argparse
import csv
import glob
import os
import re
import sys


FIELD_NAMES = [
    ("case", "case"),
    ("tracepoints_available", "tracepoints_available"),
    ("trace_mode", "trace_mode"),
    ("duration", "duration"),
    ("decode_dispatches", "decode_dispatches"),
    ("prefetch_dispatches", "prefetch_dispatches"),
    ("normal_dispatches", "normal_dispatches"),
    ("starvation_escapes", "starvation_escapes"),
]


def parse_summary_log(path):
    """Extract fields from a Stage 11 summary.log."""
    fields = {
        "case": os.path.basename(os.path.dirname(path)),
        "tracepoints_available": "NA",
        "trace_mode": "NA",
        "duration": "NA",
        "decode_dispatches": "NA",
        "prefetch_dispatches": "NA",
        "normal_dispatches": "NA",
        "starvation_escapes": "NA",
    }

    try:
        with open(path) as f:
            text = f.read()
    except FileNotFoundError:
        return fields

    # Direct field extraction
    patterns = {
        "tracepoints_available": re.compile(r"tracepoints_available[= ]+(true|false)"),
        "trace_mode": re.compile(r"trace_mode[= ]+(\w+)"),
        "duration": re.compile(r"duration[= ]+(\d+)"),
    }
    for key, pat in patterns.items():
        m = pat.search(text)
        if m:
            fields[key] = m.group(1)

    # Try to get counter values from summary CSV if sidecar exists
    summary_csv = os.path.join(os.path.dirname(path), "summary.csv")
    if os.path.isfile(summary_csv):
        try:
            with open(summary_csv) as f:
                reader = csv.DictReader(f)
                for row in reader:
                    for native_name, label in [
                        ("decode_dispatches", "decode_dispatches"),
                        ("prefetch_dispatches", "prefetch_dispatches"),
                        ("normal_dispatches", "normal_dispatches"),
                        ("starvation_escapes", "starvation_escapes"),
                    ]:
                        val = row.get(native_name, "NA")
                        if val != "NA":
                            fields[label] = val
        except (csv.Error, OSError):
            pass

    return fields


def case_sort_key(case_name):
    m = re.match(r"(\d+)", case_name)
    if m:
        return (0, int(m.group(1)), case_name)
    return (1, 0, case_name)


def emit_csv(rows, outfile):
    writer = csv.DictWriter(outfile, fieldnames=[n for n, _ in FIELD_NAMES])
    writer.writeheader()
    writer.writerows(rows)


def emit_pretty(rows):
    col_widths = {}
    for row in rows:
        for _, native_name in FIELD_NAMES:
            val = str(row.get(native_name, ""))
            col_widths[native_name] = max(
                col_widths.get(native_name, len(native_name)), len(val)
            )
    sep = "+" + "+".join("-" * (w + 2) for w in col_widths.values()) + "+"
    header = (
        "| "
        + " | ".join(
            native_name.ljust(col_widths[native_name]) for _, native_name in FIELD_NAMES
        )
        + " |"
    )
    print(sep)
    print(header)
    print(sep.replace("-", "="))
    for row in rows:
        line = (
            "| "
            + " | ".join(
                str(row.get(native_name, "")).ljust(col_widths[native_name])
                for _, native_name in FIELD_NAMES
            )
            + " |"
        )
        print(line)
        print(sep)


def main():
    parser = argparse.ArgumentParser(
        description="Parse Stage 11 foundation trace summary logs"
    )
    parser.add_argument("summary_logs", nargs="+", help="Path(s) to summary.log")
    parser.add_argument("--csv", action="store_true", help="Output CSV (default)")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print table")
    args = parser.parse_args()

    paths = []
    for p in args.summary_logs:
        expanded = glob.glob(p)
        if expanded:
            paths.extend(expanded)
        else:
            paths.append(p)

    rows = []
    for path in paths:
        fields = parse_summary_log(path)
        row = {}
        for _, native_name in FIELD_NAMES:
            row[native_name] = fields.get(native_name, "NA")
        rows.append(row)

    if not rows:
        print("No summary logs found.", file=sys.stderr)
        sys.exit(1)

    rows.sort(key=lambda r: case_sort_key(r.get("case", "")))

    use_csv = not args.pretty

    if use_csv:
        emit_csv(rows, sys.stdout)
    else:
        emit_pretty(rows)


if __name__ == "__main__":
    main()
