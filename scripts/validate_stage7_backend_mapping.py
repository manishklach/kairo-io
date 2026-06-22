#!/usr/bin/env python3
"""
Stage 7.5: Validate the 0008 backend mapping patch, documentation, and
benchmark for required symbols, sections, and patterns.

Checks performed:
  1. 0008 patch sections A-H: each required symbol present
  2. docs/stage7_generic_nvme_backend_mapping.md: required documentation patterns
  3. docs/stage7_5_nvme_hook_audit.md: audit document exists with required sections
  4. bench/kairo_bench.c: backend-mode helpers and compute_backend_model
  5. Experiment script and parser exist and contain required patterns

Exit code: 0 if all checks pass, 1 if any check fails.
"""

import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def fail(msg):
    print(f"[FAIL] {msg}", file=sys.stderr)
    return False


def check_file(path):
    full = os.path.join(REPO_ROOT, path)
    if not os.path.isfile(full):
        return fail(f"missing file: {path}")
    return True


def check_pattern(path, pattern, label):
    full = os.path.join(REPO_ROOT, path)
    if not os.path.isfile(full):
        return fail(f"missing file: {path} ({label})")
    with open(full, "r", encoding="utf-8", errors="replace") as f:
        if re.search(pattern, f.read()):
            return True
    return fail(f"pattern '{pattern}' not found in {path} ({label})")


def run_checks():
    ok = True

    # ---- 0008 patch sections ----
    p8 = "kernel/patches/0008-rfc-kairo-nvme-zns-fdp-mapping.patch"

    # Section A: blk_types.h — enum, struct, flags
    ok &= check_pattern(p8, r"enum kairo_backend_class", "A: backend class enum")
    ok &= check_pattern(p8, r"struct kairo_backend_hint", "A: backend hint struct")
    ok &= check_pattern(p8, r"KAIRO_BACKEND_F_STREAMS_CAPABLE", "A: STREAMS_CAPABLE flag")
    ok &= check_pattern(p8, r"KAIRO_BACKEND_F_NOOP_FALLBACK", "A: NOOP_FALLBACK flag")

    # Section B: blk_types.h — kairo_backend_caps
    ok &= check_pattern(p8, r"struct kairo_backend_caps", "B: backend caps struct")
    ok &= check_pattern(p8, r"bool streams\s*:\s*1", "B: caps.streams bitfield")

    # Section C: blk-mq.h — generic helpers
    ok &= check_pattern(p8, r"kairo_backend_class_from_request", "C: class_from_request")
    ok &= check_pattern(p8, r"kairo_backend_hint_from_request", "C: hint_from_request")
    ok &= check_pattern(p8, r"kairo_backend_is_noop", "C: is_noop")
    ok &= check_pattern(p8, r"kairo_backend_is_recomputable", "C: is_recomputable")

    # Section D: blk-mq.h — apply_caps
    ok &= check_pattern(p8, r"kairo_backend_hint_apply_caps", "D: hint_apply_caps")

    # Section E: include/linux/nvme.h — legacy mapping
    ok &= check_pattern(p8, r"struct nvme_kairo_mapping", "E: legacy mapping struct")

    # Section F: drivers/nvme/host/nvme.h — get_backend_caps
    ok &= check_pattern(p8, r"nvme_kairo_get_backend_caps", "F: get_backend_caps")

    # Section G: drivers/nvme/host/core.c — prepare/apply
    ok &= check_pattern(p8, r"nvme_kairo_prepare_backend_hint", "G: prepare_backend_hint")
    ok &= check_pattern(p8, r"nvme_kairo_apply_backend_hint", "G: apply_backend_hint")

    # Section H: drivers/nvme/host/zns.c — zone reset candidate
    ok &= check_pattern(p8, r"nvme_kairo_zone_reset_candidate", "H: zone_reset_candidate")

    # Compile-risk annotations
    ok &= check_pattern(p8, r"COMPILE-TARGET", "0008: COMPILE-TARGET annotation")
    ok &= check_pattern(p8, r"CONCEPTUAL-HOOK", "0008: CONCEPTUAL-HOOK annotation")

    # ---- docs/stage7_generic_nvme_backend_mapping.md ----
    d7 = "docs/stage7_generic_nvme_backend_mapping.md"
    ok &= check_pattern(d7, r"backend class", "doc7: backend class term")
    ok &= check_pattern(d7, r"KAIRO_BACKEND_NONE", "doc7: KAIRO_BACKEND_NONE reference")
    ok &= check_pattern(d7, r"backend_mode", "doc7: backend_mode reference")
    ok &= check_pattern(d7, r"stream_id", "doc7: stream_id reference")

    # ---- docs/stage7_5_nvme_hook_audit.md ----
    d75 = "docs/stage7_5_nvme_hook_audit.md"
    ok &= check_file(d75)
    ok &= check_pattern(d75, r"COMPILE-TARGET CANDIDATE", "audit: compile-target classification")
    ok &= check_pattern(d75, r"CONCEPTUAL HOOK", "audit: conceptual hook classification")
    ok &= check_pattern(d75, r"kairo_backend_caps", "audit: caps abstraction discussed")
    ok &= check_pattern(d75, r"Section", "audit: section references")
    ok &= check_pattern(d75, r"Compile-Risk Annotation", "audit: compile-risk annotation convention")

    # ---- bench/kairo_bench.c ----
    kb = "bench/kairo_bench.c"
    ok &= check_pattern(kb, r"backend-mode", "bench: --backend-mode option")
    ok &= check_pattern(kb, r"backend_mode=", "bench: backend_mode= output")
    ok &= check_pattern(kb, r"backend_class=", "bench: backend_class= output")
    ok &= check_pattern(kb, r"kairo_compute_backend_model", "bench: compute_backend_model helper")
    ok &= check_pattern(kb, r"struct kairo_backend_model", "bench: backend_model struct")
    ok &= check_pattern(kb, r"kairo_backend_mode_name", "bench: backend_mode_name")

    # ---- experiment script ----
    r7se = "scripts/run_stage7_backend_mapping_experiment.sh"
    ok &= check_file(r7se)
    ok &= check_pattern(r7se, r"results/stage7", "experiment: results/stage7 path")
    ok &= check_pattern(r7se, r"block-device", "experiment: block-device arg")

    # ---- parser ----
    p7sp = "scripts/parse_stage7_backend_summary.py"
    ok &= check_file(p7sp)
    ok &= check_pattern(p7sp, r"--csv", "parser: --csv option")
    ok &= check_pattern(p7sp, r"--pretty", "parser: --pretty option")

    return ok


def main():
    ok = run_checks()
    if ok:
        print("[OK] All Stage 7.5 validation checks passed.")
        sys.exit(0)
    else:
        print("[FAIL] Some Stage 7.5 validation checks failed.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
