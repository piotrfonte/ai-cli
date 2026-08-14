#!/usr/bin/env python3
"""W19 — grade GLM-with-thinking-pinned-off against its own stored control.

  python3 compare-w19.py results-glm.json results-glm-nothink.json

The bar was fixed by W18 BEFORE this measurement ran, and is applied here
unchanged:

  1. capability floor — at least 9 of 12 solved at pass@<=2
  2. then minutes per solved task decides, against Muse's 3.46

min/solved is each run's OWN recorded wall divided by what it actually solved —
the same arithmetic W18 used to build its table (Muse 38.1/11 = 3.46,
GLM 23.0/6 = 3.83, Bonsai 32.7/8 = 4.09). Recovery is reported, never gated:
the solved count already counts a failed repair as a failure.
"""

import json
import sys

TASKS = ["T1_tool_chain", "T2_merge_module", "T3_bash_prune", "T4_extend_no_regress"]
SHORT = {"pass@1": "1", "pass@2": "2", "fail": "F", "protocol_fail": "P"}

# W18's table, for the roster comparison. Wall and solved as recorded by W14.
ROSTER = {"Muse Glimmer": (38.1, 11), "Bonsai": (32.7, 8)}
BAR_FLOOR = 9
MUSE_MIN_PER_SOLVED = 38.1 / 11


def load(p):
    with open(p) as fh:
        return json.load(fh)


def runaways(d):
    return sum(
        1 for r in d["runs"] if "length" in [f for f in (r.get("finish_reasons") or []) if f]
    )


def recoveries(d):
    return sum(1 for r in d["runs"] if r["verdict"] == "pass@2")


def wall_min(d):
    return d.get("total_wall_s", sum(r.get("elapsed_s", 0) for r in d["runs"])) / 60.0


def cell(d, task):
    return " ".join(SHORT.get(r["verdict"], "?") for r in d["runs"] if r["task"] == task)


def main():
    ctrl, pin = load(sys.argv[1]), load(sys.argv[2])
    names = ("GLM control (thinking on)", "GLM pinned (thinking off)")

    print("## GLM, thinking on vs off\n")
    print("| Run | T1 tool chain | T2 merge | T3 bash | T4 extend | pass@1 | pass@<=2 |")
    print("|---|---|---|---|---|---|---|")
    for name, d in zip(names, (ctrl, pin)):
        cells = " | ".join(cell(d, t) for t in TASKS)
        print(
            f"| {name} | {cells} | **{d['pass_at_1']}/{d['total_runs']}** "
            f"| **{d['pass_at_2_or_better']}/{d['total_runs']}** |"
        )

    print("\n## Cost\n")
    print("| Run | Wall | Completion tokens | Reasoning chars | Runaways | Recoveries | min/solved |")
    print("|---|---|---|---|---|---|---|")
    for name, d in zip(names, (ctrl, pin)):
        comp = sum(r.get("completion_tokens", 0) for r in d["runs"])
        rch = sum(r.get("reasoning_chars", 0) for r in d["runs"])
        solved = d["pass_at_2_or_better"]
        mps = wall_min(d) / solved if solved else float("inf")
        print(
            f"| {name} | {wall_min(d):.1f} min | {comp:,} | {rch:,} "
            f"| {runaways(d)}/{d['total_runs']} | {recoveries(d)}/{d['total_runs']} | **{mps:.2f}** |"
        )

    print("\n## Against the pre-registered bar\n")
    solved = pin["pass_at_2_or_better"]
    mps = wall_min(pin) / solved if solved else float("inf")
    floor_ok = solved >= BAR_FLOOR
    speed_ok = mps <= MUSE_MIN_PER_SOLVED
    print(f"- **Floor** — needs >= {BAR_FLOOR}/12 solved: got **{solved}/12** -> "
          f"{'PASS' if floor_ok else 'FAIL'}")
    print(f"- **Speed** — needs <= {MUSE_MIN_PER_SOLVED:.2f} min/solved: got **{mps:.2f}** -> "
          f"{'PASS' if speed_ok else 'FAIL'}")
    print(f"\n**Verdict: GLM {'TAKES' if (floor_ok and speed_ok) else 'DOES NOT TAKE'} the default back.**")
    if not floor_ok:
        print("\nThe floor is checked first and it is the binding one: the speed number "
              "is not reached unless the capability floor is cleared.")

    print("\n## Roster, min/solved\n")
    table = [("Muse Glimmer (default)", *ROSTER["Muse Glimmer"]),
             ("Bonsai", *ROSTER["Bonsai"]),
             ("GLM, thinking on", wall_min(ctrl), ctrl["pass_at_2_or_better"]),
             ("GLM, thinking off", wall_min(pin), solved)]
    print("| Model | Wall | Solved | min/solved |")
    print("|---|---|---|---|")
    for label, w, s in sorted(table, key=lambda r: (r[1] / r[2]) if r[2] else float("inf")):
        print(f"| {label} | {w:.1f} min | {s}/12 | **{w/s:.2f}** |" if s else
              f"| {label} | {w:.1f} min | 0/12 | — |")

    print("\n## Verdict changes, task by task\n")
    for t in TASKS:
        c = [r["verdict"] for r in ctrl["runs"] if r["task"] == t]
        p = [r["verdict"] for r in pin["runs"] if r["task"] == t]
        print(f"- **{t}** — on: `{' '.join(SHORT.get(v,'?') for v in c)}` "
              f"-> off: `{' '.join(SHORT.get(v,'?') for v in p)}`")

    print("\n## Failure detail, pinned run\n")
    bad = [r for r in pin["runs"] if r["verdict"] != "pass@1"]
    if not bad:
        print("Clean sweep, nothing to report.")
    for r in bad:
        last = (r.get("attempts") or [{}])[-1]
        why = " ".join(str(last.get("detail") or last.get("protocol") or "").split())[:260]
        print(f"- `{r['task']}`[{r['repeat']}] -> **{r['verdict']}** — {why}")


if __name__ == "__main__":
    main()
