#!/usr/bin/env python3
import argparse
import csv
import glob
import re
import sys
from pathlib import Path

FIELDS = [
    "case",
    "decode_p99_us",
    "decode_p95_us",
    "decode_avg_us",
    "decode_latency_samples",
    "decode_latency_max_us",
    "decode_lat_0_10us",
    "decode_lat_10_25us",
    "decode_lat_25_50us",
    "decode_lat_50_100us",
    "decode_lat_100_250us",
    "decode_lat_250_500us",
    "decode_lat_500_1000us",
    "decode_lat_1ms_2ms",
    "decode_lat_2ms_5ms",
    "decode_lat_gt_5ms",
    "write_MBps",
    "prefetch_read_MBps",
]


def parse_summary_log(path: Path) -> dict[str, str]:
    data = {field: "NA" for field in FIELDS}
    text = path.read_text(encoding="utf-8")
    for line in text.splitlines():
        m = re.match(r'^(\w[\w_]*)=(.+)$', line.strip())
        if m:
            key = m.group(1)
            value = m.group(2).strip()
            if key in data:
                data[key] = value
    return data


def render_pretty(rows: list[dict[str, str]]) -> str:
    if not rows:
        return ""
    headers = FIELDS
    col_widths = {h: len(h) for h in headers}
    for row in rows:
        for h in headers:
            col_widths[h] = max(col_widths[h], len(row.get(h, "NA")))
    sep = " | ".join(h.ljust(col_widths[h]) for h in headers)
    out = [sep, "-|-".join("-" * col_widths[h] for h in headers)]
    for row in rows:
        out.append(" | ".join(row.get(h, "NA").ljust(col_widths[h]) for h in headers))
    return "\n".join(out) + "\n"


def expand_patterns(patterns: list[str]) -> list[Path]:
    logs: list[Path] = []
    for pattern in patterns:
        expanded = [Path(match) for match in glob.glob(pattern)]
        if expanded:
            logs.extend(expanded)
            continue
        p = Path(pattern)
        if p.exists():
            logs.append(p)
    return logs


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Parse Stage 13 decode latency histogram summary logs"
    )
    parser.add_argument("summary_logs", nargs="+",
                        help="Paths to summary.log files or glob patterns")
    parser.add_argument("--csv", action="store_true",
                        help="Output CSV")
    parser.add_argument("--pretty", action="store_true",
                        help="Output pretty-printed table")
    args = parser.parse_args()

    if not args.csv and not args.pretty:
        args.pretty = True

    logs = expand_patterns(args.summary_logs)

    rows = []
    for log in sorted(set(logs)):
        data = parse_summary_log(log)
        rows.append(data)

    if args.csv:
        writer = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow({f: row.get(f, "NA") for f in FIELDS})
        return 0

    if args.pretty:
        sys.stdout.write(render_pretty(rows))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
