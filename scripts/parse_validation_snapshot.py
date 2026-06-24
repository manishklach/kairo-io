#!/usr/bin/env python3
import argparse
import csv
import sys
from pathlib import Path

FIELDS = [
    "timestamp",
    "is_wsl",
    "kernel_release",
    "validate_patch_stack",
    "make",
    "fallback_gcc_build",
    "benchmark_exists",
    "benchmark_binary",
    "stage6_dryrun",
    "stage7_dryrun",
    "stage8_dryrun",
    "stage13_dryrun",
    "user_bench_baseline",
    "user_bench_mixed",
    "results_dir",
    "notes",
]

TABLE_FIELDS = [
    "validate_patch_stack",
    "make",
    "fallback_gcc_build",
    "benchmark_exists",
    "stage6_dryrun",
    "stage7_dryrun",
    "stage8_dryrun",
    "stage13_dryrun",
    "user_bench_baseline",
    "user_bench_mixed",
]


def parse_summary(path: Path) -> dict[str, str]:
    data = {field: "" for field in FIELDS}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in data:
            data[key] = value
    return data


def render_markdown(data: dict[str, str]) -> str:
    lines = [
        "# Kairo Validation Snapshot",
        "",
        f"Date: {data['timestamp'] or 'unknown'}",
        f"Environment: {'WSL' if data['is_wsl'] == 'true' else 'non-WSL or unknown'}",
        f"Kernel: {data['kernel_release'] or 'unknown'}",
        f"WSL: {data['is_wsl'] or 'unknown'}",
        "",
        "## Summary",
        "",
        "| Check | Result |",
        "|---|---|",
    ]
    for field in TABLE_FIELDS:
        lines.append(f"| {field} | {data.get(field, '')} |")
    lines.extend(
        [
            "",
            "## What This Validates",
            "",
            "- repository consistency",
            "- benchmark build",
            "- experiment harness dry-run path",
            "- WSL user-space benchmark smoke path",
            "",
            "## What This Does Not Validate",
            "",
            "- custom kernel boot",
            "- Kairo sysfs counters",
            "- mq-deadline patched-kernel behavior",
            "- physical NVMe placement",
            "- tracepoint availability on patched kernel",
            "",
            "## Artifacts",
            "",
            "- environment.log",
            "- validate_patch_stack.log",
            "- make.log",
            "- stage6_dryrun.log",
            "- stage7_dryrun.log",
            "- stage8_dryrun.log",
            "- stage13_dryrun.log",
            "- user_bench_baseline.log",
            "- user_bench_mixed.log",
        ]
    )
    if data.get("results_dir"):
        lines.extend(["", f"Results directory: `{data['results_dir']}`"])
    if data.get("notes"):
        lines.extend(["", f"Notes: {data['notes']}"])
    return "\n".join(lines) + "\n"


def render_csv(data: dict[str, str]) -> str:
    out = []
    writer = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
    writer.writeheader()
    writer.writerow({field: data.get(field, "") for field in FIELDS})
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse a Kairo validation snapshot summary.log")
    parser.add_argument("summary_log", nargs="?", help="Path to results/validation/<timestamp>/summary.log")
    parser.add_argument("--markdown", action="store_true", help="Render Markdown snapshot output")
    parser.add_argument("--csv", action="store_true", help="Render CSV output")
    args = parser.parse_args()

    if not args.summary_log:
      parser.print_help()
      return 0

    path = Path(args.summary_log)
    data = parse_summary(path)

    if args.csv:
        writer = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerow({field: data.get(field, "") for field in FIELDS})
        return 0

    if args.markdown or not args.csv:
        sys.stdout.write(render_markdown(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
