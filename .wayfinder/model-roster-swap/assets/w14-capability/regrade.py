#!/usr/bin/env python3
"""Re-grade T3 from the stored code, in a clean directory per attempt.

Why this exists: the first run of the suite reused ONE working directory for both
attempts of a task. Only T3 builds a directory tree, so only T3 was affected — a
failing first attempt left junk in `cache dir`, which inflated the second attempt's
`du` baseline and added stray `ls` entries. Correct repair code was then graded as
a failure. `run_bash_function` now wipes the directory; this script re-applies the
fixed grader to the code that was already generated, so no model has to run again.

The models' inputs were never corrupted: attempt 1 always ran on bare ground, so
the failure output each model saw was real. Only the grading of attempt 2 was wrong.

Every original verdict is preserved as `verdict_original`.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tasks as T  # noqa: E402

SCRATCH = "/private/tmp/claude-501/-Users-p-Development-ai-cli/36b70a77-d1ee-46fa-b432-d80eab0661ef/scratchpad/w14-regrade"


def regrade_run(rec, tag):
    """Replay a T3 run's attempts through the fixed grader."""
    outcomes = []
    for i, a in enumerate(rec.get("attempts", [])):
        code = a.get("code")
        if a.get("state") == "protocol_fail" or not code:
            outcomes.append(("protocol_fail", a.get("detail", "")))
            continue
        wd = os.path.join(SCRATCH, tag, f"{rec['task']}-{rec['repeat']}-a{i}")
        ok, out = T.run_bash_function(code, T.T3_TEST_SH, wd)
        outcomes.append((("ok" if ok else "failed"), out))
        a["state_regraded"] = "ok" if ok else "failed"
        a["detail_regraded"] = out[:1500]

    if not outcomes:
        return rec["verdict"]
    if outcomes[0][0] == "protocol_fail":
        return "protocol_fail"
    if outcomes[0][0] == "ok":
        return "pass@1"
    if len(outcomes) < 2:
        return "fail"
    if outcomes[1][0] == "protocol_fail":
        return "protocol_fail"
    return "pass@2" if outcomes[1][0] == "ok" else "fail"


def main():
    for path in sys.argv[1:]:
        with open(path) as fh:
            d = json.load(fh)
        tag = d["model"].replace("/", "_")
        changed = []
        for rec in d["runs"]:
            if rec["task"] != "T3_bash_prune":
                continue
            before = rec["verdict"]
            after = regrade_run(rec, tag)
            rec["verdict_original"] = before
            rec["verdict"] = after
            rec["regraded"] = True
            if before != after:
                changed.append(f"{rec['task']}[{rec['repeat']}] {before} -> {after}")

        runs = d["runs"]
        counts = {}
        for r in runs:
            counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
        d["counts"] = counts
        d["pass_at_1"] = sum(1 for r in runs if r["verdict"] == "pass@1")
        d["pass_at_2_or_better"] = sum(1 for r in runs if r["verdict"] in ("pass@1", "pass@2"))
        d["regrade_note"] = (
            "T3 re-graded in a clean directory per attempt. The first run reused one "
            "directory for both attempts, so a failing attempt 1 polluted the state "
            "attempt 2 was tested in. Only T3 builds a directory tree; T1, T2 and T4 "
            "are unaffected. Original verdicts kept as verdict_original."
        )
        with open(path, "w") as fh:
            json.dump(d, fh, indent=2)
        print(f"{path}: {len(changed)} verdict(s) changed")
        for c in changed:
            print(f"   {c}")
        print(f"   pass@1 {d['pass_at_1']}/{d['total_runs']}  pass<=2 {d['pass_at_2_or_better']}/{d['total_runs']}")


if __name__ == "__main__":
    main()
