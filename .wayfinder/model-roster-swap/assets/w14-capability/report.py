#!/usr/bin/env python3
"""Render the W14 results JSON into the tables the ticket resolution carries.

  python3 report.py results-glm.json results-bonsai.json results-muse.json
"""

import json
import sys

TASKS = ["T1_tool_chain", "T2_merge_module", "T3_bash_prune", "T4_extend_no_regress"]
LABEL = {
    "T1_tool_chain": "T1 tool chain",
    "T2_merge_module": "T2 merge module",
    "T3_bash_prune": "T3 bash repair",
    "T4_extend_no_regress": "T4 extend, no regress",
}
SHORT = {"pass@1": "1", "pass@2": "2", "fail": "F", "protocol_fail": "P"}


def load(paths):
    out = []
    for p in paths:
        with open(p) as fh:
            out.append(json.load(fh))
    return out


def cell(runs):
    """Compact per-task verdict string, e.g. '1 1 2' or 'F P F'."""
    return " ".join(SHORT.get(r["verdict"], "?") for r in runs)


def main():
    data = load(sys.argv[1:])

    print("## Per-task verdicts\n")
    print("`1` = pass@1  ·  `2` = pass@2 (one repair)  ·  `F` = fail  ·  `P` = protocol failure\n")
    head = "| Model | " + " | ".join(LABEL[t] for t in TASKS) + " | pass@1 | pass@≤2 |"
    print(head)
    print("|" + "---|" * (len(TASKS) + 3))
    for d in data:
        row = [d["model"].split("/")[-1]]
        for t in TASKS:
            row.append(cell([r for r in d["runs"] if r["task"] == t]))
        n = d["total_runs"]
        row.append(f"**{d['pass_at_1']}/{n}**")
        row.append(f"**{d['pass_at_2_or_better']}/{n}**")
        print("| " + " | ".join(row) + " |")

    print("\n## Cost, recorded but not scored\n")
    # Reasoning is reported in CHARACTERS, not as a share of completion tokens. A
    # chars/token ratio differs per tokenizer, and dividing one by the other gave a
    # nonsensical >100% for Muse. Characters are what was actually measured.
    print("| Model | Samples? | Runs | Wall | Completion tokens | Reasoning chars | Runaways |")
    print("|---|---|---|---|---|---|---|")
    for d in data:
        runs = d["runs"]
        comp = sum(r.get("completion_tokens", 0) for r in runs)
        rchars = sum(r.get("reasoning_chars", 0) for r in runs)
        runaway = sum(1 for r in runs if "length" in [f for f in (r.get("finish_reasons") or []) if f])
        wall = d.get("total_wall_s", sum(r.get("elapsed_s", 0) for r in runs))
        print(
            f"| {d['model'].split('/')[-1]} | "
            f"{'no (greedy)' if d['probe']['deterministic'] else 'yes'} | "
            f"{d['total_runs']} | {wall/60:.1f} min | {comp:,} | {rchars:,} | {runaway}/{len(runs)} |"
        )

    print("\n## Failure detail\n")
    for d in data:
        bad = [r for r in d["runs"] if r["verdict"] != "pass@1"]
        if not bad:
            print(f"**{d['model'].split('/')[-1]}** — clean sweep, nothing to report.\n")
            continue
        print(f"**{d['model'].split('/')[-1]}**\n")
        for r in bad:
            # The DECIDING attempt is the last one, not the first. T4 runs phase A
            # before the scored phase B, so attempts[0] reported "PASS" on runs that
            # actually failed — misleading exactly where the detail matters most.
            last = (r.get("attempts") or [{}])[-1]
            why = last.get("detail") or last.get("protocol") or ""
            why = " ".join(str(why).split())[:240]
            print(f"- `{r['task']}`[{r['repeat']}] → **{r['verdict']}** — {why}")
        print()


if __name__ == "__main__":
    main()
