#!/usr/bin/env python3
"""W21 Stage 2 — the W14 coding suite, re-run with a long corpus in context.

  python3 run_long.py --model <two-level-id> --out results-long-<tag>.json

This is a WRAPPER, not a fork. It imports W14's own tasks, graders and task
drivers unchanged, and alters exactly one thing: the shared system prompt now
carries ~17k tokens of real repository source ahead of the task. Same prompts,
same execution grading, same rubric — so the only difference against W14's
result is context length, which is what W21 asks about.

Three deliberate differences from W14's run.py, each recorded:

1. **T3 is dropped.** The pre-registration commits Stage 2 to the trimmed suite
   T1, T2, T4 after Stage 1 found no retrieval fault. T3 scored 0/9 first-shot at
   4k, so it is floored and carries no pass@1 signal.
2. **The determinism probe is skipped and repeats are pinned to 3.** W14 already
   proved all three models sample whatever their generation_config.json claims;
   re-deriving it would cost 2 requests per model to reach the same 3.
3. **Peak prompt tokens are tracked**, not just the per-run sum W14 recorded. The
   corpus plus a growing multi-turn conversation must stay inside GLM's real
   client budget of 32,768 with 8,192 reserved for output, and a sum cannot show
   that. If `peak_prompt_tokens` approaches 24,576 the run is not production
   faithful and the result must say so.
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
W14 = os.path.join(HERE, "..", "w14-capability")
sys.path.insert(0, os.path.abspath(W14))

import run as R  # noqa: E402  — W14's drivers, imported unchanged
import tasks as T  # noqa: E402  — W14's prompts and graders, imported unchanged

BUDGET_PROMPT_TOKENS = 24576  # 32768 client context - 8192 reserved output


class LongSession(R.Session):
    """W14's Session, plus the peak-prompt tracking Stage 2 needs."""

    # Class-level on purpose: the peak that matters is the largest single prompt
    # anywhere in the suite, not per-conversation.
    peak = 0

    def say(self, content, tools=None):
        before = self.prompt_tokens
        msg = super().say(content, tools)
        LongSession.peak = max(LongSession.peak, self.prompt_tokens - before)
        return msg

    def resume(self, tools=None):
        before = self.prompt_tokens
        msg = super().resume(tools)
        LongSession.peak = max(LongSession.peak, self.prompt_tokens - before)
        return msg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default="http://127.0.0.1:10082/v1")
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--scratch", required=True)
    args = ap.parse_args()

    with open(os.path.join(HERE, "corpus-s2.txt"), encoding="utf-8") as fh:
        corpus = fh.read()

    # The one change. Instruction first, then the repository context, so the
    # constant head is byte-identical on every request of the whole suite and the
    # door charge is paid once per model (Stage 1 measured this on all three).
    base_system = T.SYSTEM
    T.SYSTEM = (
        base_system
        + "\n\nThe following files from this repository are already open in your "
        "context. Use them when they are relevant.\n\n"
        + corpus
    )
    R.Session = LongSession

    suite = [
        ("T1_tool_chain", lambda wd: R.task_t1(args.base, args.model, wd)),
        (
            "T2_merge_module",
            lambda wd: R.task_code(
                args.base, args.model, wd, T.T2_PROMPT, ["javascript", "js"],
                T.run_node_module, T.T2_TEST_JS,
                "The module does not satisfy the tests. This is the real output of running them:",
            ),
        ),
        ("T4_extend_no_regress", lambda wd: R.task_t4(args.base, args.model, wd)),
    ]

    started = time.time()
    runs = []
    for name, fn in suite:
        for i in range(args.repeats):
            wd = os.path.join(args.scratch, args.model.replace("/", "_"), f"{name}-{i}")
            t0 = time.time()
            try:
                rec = fn(wd)
            except Exception as e:  # noqa: BLE001 — never lose the rest of the suite
                rec = {
                    "verdict": "protocol_fail",
                    "attempts": [],
                    "error": f"harness: {type(e).__name__}: {e}",
                }
            rec.update({"task": name, "repeat": i, "elapsed_s": round(time.time() - t0, 2)})
            runs.append(rec)
            print(
                f"  {name}[{i}] -> {rec['verdict']} ({rec['elapsed_s']}s) "
                f"peak_prompt={LongSession.peak}",
                flush=True,
            )
            with open(os.path.join(HERE, args.out), "w") as fh:
                json.dump({"model": args.model, "runs": runs}, fh, indent=2)

    counts = {}
    for r in runs:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    summary = {
        "model": args.model,
        "stage": 2,
        "suite": [n for n, _ in suite],
        "repeats": args.repeats,
        "corpus_chars": len(corpus),
        "peak_prompt_tokens": LongSession.peak,
        "budget_prompt_tokens": BUDGET_PROMPT_TOKENS,
        "within_budget": LongSession.peak <= BUDGET_PROMPT_TOKENS,
        "counts": counts,
        "pass_at_1": sum(1 for r in runs if r["verdict"] == "pass@1"),
        "pass_at_2_or_better": sum(1 for r in runs if r["verdict"] in ("pass@1", "pass@2")),
        "total_runs": len(runs),
        "total_wall_s": round(time.time() - started, 1),
        "runs": runs,
    }
    with open(os.path.join(HERE, args.out), "w") as fh:
        json.dump(summary, fh, indent=2)
    print(
        json.dumps({k: v for k, v in summary.items() if k != "runs"}, indent=2),
        flush=True,
    )


if __name__ == "__main__":
    main()
