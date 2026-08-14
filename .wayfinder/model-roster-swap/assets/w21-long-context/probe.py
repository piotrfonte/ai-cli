#!/usr/bin/env python3
"""W21 Stage 1 — long-context retrieval probe against one model on local oMLX.

  python3 probe.py --model <two-level-id> --out probe-<tag>.json [--repeats 2]

The rubric is in README.md and was written before the first request was sent.

The system message is byte-identical on every request: instruction, then corpus.
Only the short user question differs. That is deliberate — W13 measured a repeated
prefix restoring in ~3 s against ~59 s cold, so a constant head makes the door
charge a once-per-model cost. Every request records its own wall and usage, so the
claim is visible in the data instead of assumed.

Sends no `temperature`, mirroring opencode.json's "temperature": false.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))

MAX_TOKENS = 8192          # production-faithful; see README, and W14's amendment
REQUEST_TIMEOUT = 1800

INSTRUCTION = (
    "You are given the complete source of four files from one repository, verbatim.\n"
    "Read them. The user asks one question about their contents.\n\n"
    "Answer with the exact value only. No explanation, no code fence, no units.\n"
    "If the answer is not in the files, answer exactly: UNKNOWN\n\n"
    "=== BEGIN REPOSITORY FILES ===\n"
)

# Six facts, each occurring exactly once in the corpus (verified by string count).
# `depth` is where the fact sits in the corpus; `accept` grades the response's
# `content`, lowercased. Word boundaries on the numeric answers, so "14" cannot be
# matched by "1440".
NEEDLES = [
    {
        "id": "D1",
        "depth_pct": 2.6,
        "question": (
            "The files include this repository's opencode.json. "
            "What value does its top-level `model` key hold?"
        ),
        "expected": "zai/glm-5.2",
        "accept": r"zai/glm-5\.2",
    },
    {
        "id": "D2",
        "depth_pct": 10.1,
        "question": (
            "The files include scripts/patch-omlx-mtp.mjs. Its comments list the native "
            "context window oMLX resolves for each model when no pin exists. "
            "Which native window do those comments give for Bonsai?"
        ),
        "expected": "262,144",
        "accept": r"\b262[,_ ]?144\b",
    },
    {
        "id": "D3",
        "depth_pct": 29.8,
        "question": (
            "The files include ai.sh. Its comment about the Ternary Bonsai profile names "
            "one config key that is False, which is why the vision tower loads either way. "
            "What is that key called?"
        ),
        "expected": "language_model_only",
        "accept": r"\blanguage_model_only\b",
    },
    {
        "id": "D4",
        "depth_pct": 53.4,
        "question": (
            "The files include ai.sh. It reaps a leftover opencode-mem web UI listener "
            "that stayed bound after opencode died. Which TCP port does it check for "
            "that listener?"
        ),
        "expected": "4747",
        "accept": r"\b4747\b",
    },
    {
        "id": "D5",
        "depth_pct": 70.6,
        "question": (
            "The files include ai.sh. What numeric value does its local variable "
            "`glm_degraded_context` hold?"
        ),
        "expected": "24576",
        "accept": r"\b24[,_ ]?576\b",
    },
    {
        "id": "D6",
        "depth_pct": 95.3,
        "question": (
            "The files include plugins/post-edit-check.js. It generates a wrapper tsconfig "
            "instead of using the project's own. What filename does it give that generated "
            "file?"
        ),
        "expected": "opencode-tsc-check.json",
        "accept": r"opencode-tsc-check\.json",
    },
]

DEEP = {"D1", "D2", "D3", "D4", "D5"}   # outside Muse's 2048-token sliding window
NEAR = {"D6"}                            # inside it — the control


def post(url, payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer mlx"},
    )
    with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
        return json.loads(resp.read())


def ask(base, model, system, question):
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": question},
        ],
        "max_tokens": MAX_TOKENS,
        "stream": False,
    }
    t0 = time.time()
    try:
        data = post(f"{base}/chat/completions", payload)
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.read().decode()[:500]}", "wall": time.time() - t0}
    except Exception as e:  # noqa: BLE001 — record and move on
        return {"error": f"{type(e).__name__}: {e}", "wall": time.time() - t0}

    wall = time.time() - t0
    choice = (data.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    return {
        "wall": wall,
        "content": msg.get("content") or "",
        "reasoning": msg.get("reasoning_content") or "",
        "finish_reason": choice.get("finish_reason"),
        "usage": data.get("usage") or {},
    }


def grade(needle, res):
    """Loose match decides. Strict match is recorded so a long, waffly pass is visible."""
    if res.get("error"):
        return "error", False
    if res.get("finish_reason") == "length":
        return "runaway", False
    content = (res.get("content") or "").lower()
    loose = bool(re.search(needle["accept"], content))
    norm = lambda s: re.sub(r"[\s`'\"*,]|\.$", "", s)  # noqa: E731
    strict = norm(content) == norm(needle["expected"].lower())
    return ("pass" if loose else "fail"), strict


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default="http://127.0.0.1:10082/v1")
    ap.add_argument("--repeats", type=int, default=2)
    args = ap.parse_args()

    with open(os.path.join(HERE, "corpus.txt"), encoding="utf-8") as fh:
        corpus = fh.read()
    system = INSTRUCTION + corpus + "\n=== END REPOSITORY FILES ===\n"

    runs = []
    t_start = time.time()
    for rep in range(args.repeats):
        for needle in NEEDLES:
            res = ask(args.base, args.model, system, needle["question"])
            verdict, strict = grade(needle, res)
            usage = res.get("usage") or {}
            cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens")
            runs.append(
                {
                    "needle": needle["id"],
                    "depth_pct": needle["depth_pct"],
                    "set": "deep" if needle["id"] in DEEP else "near",
                    "repeat": rep,
                    "verdict": verdict,
                    "strict": strict,
                    "expected": needle["expected"],
                    "content": res.get("content", "")[:2000],
                    "reasoning_chars": len(res.get("reasoning") or ""),
                    "answer_in_reasoning": bool(
                        re.search(needle["accept"], (res.get("reasoning") or "").lower())
                    ),
                    "finish_reason": res.get("finish_reason"),
                    "wall": round(res.get("wall", 0.0), 2),
                    "prompt_tokens": usage.get("prompt_tokens"),
                    "completion_tokens": usage.get("completion_tokens"),
                    "cached_tokens": cached,
                    "error": res.get("error"),
                }
            )
            r = runs[-1]
            print(
                f"  {r['needle']} rep{rep} {r['set']:4} {r['verdict']:7} "
                f"{r['wall']:7.1f}s  prompt={r['prompt_tokens']} cached={r['cached_tokens']} "
                f"reason_chars={r['reasoning_chars']}",
                flush=True,
            )

    deep = [r for r in runs if r["set"] == "deep"]
    near = [r for r in runs if r["set"] == "near"]
    out = {
        "model": args.model,
        "max_tokens": MAX_TOKENS,
        "repeats": args.repeats,
        "wall_total": round(time.time() - t_start, 1),
        "deep_pass": sum(r["verdict"] == "pass" for r in deep),
        "deep_total": len(deep),
        "near_pass": sum(r["verdict"] == "pass" for r in near),
        "near_total": len(near),
        "runaways": sum(r["verdict"] == "runaway" for r in runs),
        "errors": sum(r["verdict"] == "error" for r in runs),
        "runs": runs,
    }
    with open(os.path.join(HERE, args.out), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    print(
        f"\n{args.model}: deep {out['deep_pass']}/{out['deep_total']}  "
        f"near {out['near_pass']}/{out['near_total']}  "
        f"runaways {out['runaways']}  errors {out['errors']}  "
        f"wall {out['wall_total']}s"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
