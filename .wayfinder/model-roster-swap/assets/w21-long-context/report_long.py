#!/usr/bin/env python3
"""W21 Stage 2 — build the comparison tables against W14's 4k result.

  python3 report_long.py

Counting rule that is easy to get wrong, and is checked below: in T4 an
`attempts` list of length 2 is the phase A -> phase B structure, NOT a repair
turn. Only length 3 means a repair happened. Applying that rule to W14's stored
results reproduces its published recovery counts exactly (GLM 0, Muse 2,
Bonsai 3), which is why `--selftest` asserts it before any Stage 2 number is
printed.

A second distinction the tables keep separate: T1's repair turn carries a
HAND-WRITTEN hint, because a naming question has no execution output to show.
T2's and T4's carry the real failure output. W14's "GLM never recovered" finding
was measured only on the latter — in W14 no model ever needed a T1 repair — so a
T1 recovery must not be counted against it.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
W14 = os.path.join(HERE, "..", "w14-capability")

TAGS = [
    ("muse", "Muse Glimmer 30B 4-bit"),
    ("glm", "GLM 4.7 Flash 6-bit"),
    ("bonsai", "Ternary Bonsai 27B 2-bit"),
]
TRIMMED = ["T1_tool_chain", "T2_merge_module", "T4_extend_no_regress"]
SYM = {"pass@1": "1", "pass@2": "2", "fail": "F", "protocol_fail": "P"}


def had_repair(run):
    """True when a repair turn actually happened."""
    n = len(run.get("attempts") or [])
    return n >= 3 if run["task"].startswith("T4") else n >= 2


def recoveries(runs, real_output_only=True):
    out = 0
    for r in runs:
        if not had_repair(r):
            continue
        if real_output_only and r["task"].startswith("T1"):
            continue
        if r["verdict"] == "pass@2":
            out += 1
    return out


def repairs(runs, real_output_only=True):
    return sum(
        1
        for r in runs
        if had_repair(r) and not (real_output_only and r["task"].startswith("T1"))
    )


def load(path):
    with open(path) as fh:
        return json.load(fh)


def selftest():
    """W14's published recovery counts must fall out of the rule above."""
    expected = {"glm": 0, "muse": 2, "bonsai": 3}
    ok = True
    for tag, want in expected.items():
        runs = load(os.path.join(W14, f"results-{tag}.json"))["runs"]
        got = recoveries(runs)
        flag = "ok " if got == want else "BAD"
        if got != want:
            ok = False
        print(f"  {flag} W14 {tag}: recoveries from real output = {got} (published {want})")
    return ok


def row(runs, tasks):
    cells = []
    for t in tasks:
        rs = sorted((r for r in runs if r["task"] == t), key=lambda r: r["repeat"])
        cells.append(" ".join(SYM.get(r["verdict"], "?") for r in rs))
    p1 = sum(1 for r in runs if r["verdict"] == "pass@1")
    p2 = sum(1 for r in runs if r["verdict"] in ("pass@1", "pass@2"))
    return cells, p1, p2, len(runs)


def main():
    print("selftest — W14 recovery counts reproduced from the stored runs:")
    if not selftest():
        print("\nSELFTEST FAILED — counting rule is wrong; not printing Stage 2 tables.")
        return 1
    print()

    print("## pass@1 / pass@≤2 — trimmed suite (T1, T2, T4), 4k vs ~17.6k\n")
    print("| Model | Context | T1 | T2 | T4 | pass@1 | pass@≤2 |")
    print("|---|---|---|---|---|---|---|")
    summary = {}
    for tag, label in TAGS:
        w14 = [r for r in load(os.path.join(W14, f"results-{tag}.json"))["runs"] if r["task"] in TRIMMED]
        c, p1, p2, n = row(w14, TRIMMED)
        print(f"| {label} | W14 ~4k | {c[0]} | {c[1]} | {c[2]} | {p1}/{n} | {p2}/{n} |")
        summary[tag] = {"w14": (p1, p2, n)}

        path = os.path.join(HERE, f"results-long-{tag}.json")
        if not os.path.exists(path):
            print(f"| {label} | **W21 ~17.6k** | — | — | — | *pending* | *pending* |")
            continue
        d = load(path)
        c, p1, p2, n = row(d["runs"], TRIMMED)
        print(f"| **{label}** | **W21 ~17.6k** | {c[0]} | {c[1]} | {c[2]} | **{p1}/{n}** | **{p2}/{n}** |")
        summary[tag]["w21"] = (p1, p2, n)
        summary[tag]["d"] = d

    print("\n## Repair behaviour, real failure output only (T1's hint excluded)\n")
    print("| Model | Context | Repair turns | Recovered | Runaways |")
    print("|---|---|---|---|---|")
    for tag, label in TAGS:
        w14 = [r for r in load(os.path.join(W14, f"results-{tag}.json"))["runs"] if r["task"] in TRIMMED]
        print(
            f"| {label} | ~4k | {repairs(w14)} | {recoveries(w14)} | "
            f"{sum(1 for r in w14 if r['verdict'] == 'protocol_fail')} |"
        )
        if "d" in summary.get(tag, {}):
            rs = summary[tag]["d"]["runs"]
            print(
                f"| **{label}** | **~17.6k** | {repairs(rs)} | {recoveries(rs)} | "
                f"{sum(1 for r in rs if r['verdict'] == 'protocol_fail')} |"
            )

    print("\n## Cost\n")
    print("| Model | Wall | Peak prompt | Within 24,576 budget | min / solved |")
    print("|---|---|---|---|---|")
    for tag, label in TAGS:
        d = summary.get(tag, {}).get("d")
        if not d:
            continue
        p1, p2, n = summary[tag]["w21"]
        mps = (d["total_wall_s"] / 60 / p2) if p2 else float("inf")
        print(
            f"| {label} | {d['total_wall_s'] / 60:.1f} min | {d['peak_prompt_tokens']} | "
            f"{'yes' if d['within_budget'] else '**NO**'} | {mps:.2f} |"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
