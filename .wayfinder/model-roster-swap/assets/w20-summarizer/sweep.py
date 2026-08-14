#!/usr/bin/env python3
"""W20 M1 — sweep the summarizer input cap against the 30 s abort.

Answers Gate 0: at what value of OPENCODE_MEM_MAX_CONTEXT_CHARS, if any, does a
capture complete inside autoCaptureIterationTimeout on a given model?

Two repeats per size, because the wall is dominated by how much the model
chooses to reason, which varies run to run.
"""
import argparse
import json
import time
from pathlib import Path

from summarizer import capture

SIZES = [24000, 12000, 6000, 2000]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--port", type=int, default=10082)
    ap.add_argument("--budget", type=float, default=30.0)
    ap.add_argument("--repeats", type=int, default=2)
    ap.add_argument("--sizes", type=int, nargs="*", default=SIZES)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    runs = []
    for size in args.sizes:
        for i in range(args.repeats):
            rec = capture(args.model, size, args.port, args.budget)
            rec["repeat"] = i + 1
            runs.append(rec)
            print(
                f"{args.tag:8s} chars={size:6d} r{i+1} "
                f"wall={rec.get('wall_s')!s:>7s}s "
                f"in={rec.get('prompt_tokens')} out={rec.get('completion_tokens')} "
                f"reason={rec.get('reasoning_chars')} "
                f"type={rec.get('memory_type')} gate0={rec.get('gate0')}",
                flush=True,
            )
            time.sleep(2)

    Path(args.out).write_text(json.dumps({"model": args.model, "runs": runs}, indent=2))
    print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
