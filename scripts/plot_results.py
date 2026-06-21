#!/usr/bin/env python3
"""Minimal plotting helper for Kairo fio JSON outputs."""

import json
import sys
from pathlib import Path


def summarize(path: Path) -> None:
    data = json.loads(path.read_text())
    print(f"file: {path}")
    for job in data.get("jobs", []):
        name = job.get("jobname", "unknown")
        read = job.get("read", {})
        write = job.get("write", {})
        print(
            f"  {name}: read_bw={read.get('bw', 0)} KiB/s "
            f"read_clat_ns_p99={read.get('clat_ns', {}).get('percentile', {}).get('99.000000', 'n/a')} "
            f"write_bw={write.get('bw', 0)} KiB/s"
        )


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(f"usage: {argv[0]} <fio-json> [fio-json...]", file=sys.stderr)
        return 1

    for arg in argv[1:]:
        summarize(Path(arg))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
