#!/usr/bin/env python3
"""W20 M2 — Gate 1: what a capture in flight costs the turn that lands on it.

The plugin fires a capture on session.idle + a 10 s debounce, so it never
overlaps the turn that produced it. It overlaps the NEXT one. This measures that:

  control   a coding turn alone
  test      the same coding turn, started 2 s after a capture begins

Gate 1 is >= 75% of the control's decode rate (the user's 25% ceiling, fixed
before the run).

Both requests go to one oMLX server running --max-concurrent-requests 2, so the
two share continuous batching exactly as they would in a live session.
"""
import argparse
import json
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

from summarizer import build_context, capture

REPO = Path(__file__).resolve().parents[4]

CODING_INSTRUCTION = """

---

You are the coding agent for the repository above.

Task: `_prune_cache` in `ai.sh` deletes KV-cache blocks oldest-first at every
server start. Write a short review of that function covering: what breaks if the
server is still running when it prunes, whether mtime is a sound stand-in for
LRU, and what happens when a pruned block is looked up later. Then give the
concrete edit you would make, as a diff.

Be specific and cite the contract the file states.
"""


def _coding_prompt(target_chars: int) -> str:
    """A realistic ~12.8k-token agentic prompt built from this repo's own files."""
    parts = []
    for rel in ("CLAUDE.md", "ai.sh"):
        p = REPO / rel
        if p.exists():
            parts.append(f"===== {rel} =====\n{p.read_text(encoding='utf-8', errors='replace')}")
    body = "\n\n".join(parts)
    return body[:target_chars] + CODING_INSTRUCTION


def coding_turn(model: str, port: int, chars: int, max_tokens: int = 2048) -> dict:
    body = {
        "model": model,
        "messages": [{"role": "user", "content": _coding_prompt(chars)}],
        "max_tokens": max_tokens,
    }
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer mlx"},
    )
    rec = {"role": "coding", "model": model}
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            data = json.loads(r.read())
        rec["wall_s"] = round(time.time() - t0, 2)
        rec["ok"] = True
        choice = (data.get("choices") or [{}])[0]
        usage = data.get("usage") or {}
        rec["finish_reason"] = choice.get("finish_reason")
        rec["prompt_tokens"] = usage.get("prompt_tokens")
        rec["completion_tokens"] = usage.get("completion_tokens")
        rec["cached_tokens"] = (usage.get("prompt_tokens_details") or {}).get("cached_tokens")
        rec["model_load_duration"] = usage.get("model_load_duration")
        rec["total_time"] = usage.get("total_time")
    except urllib.error.HTTPError as e:
        rec["wall_s"] = round(time.time() - t0, 2)
        rec["ok"] = False
        rec["http_status"] = e.code
        rec["error"] = e.read().decode(errors="replace")[:400]
    except Exception as e:  # noqa: BLE001
        rec["wall_s"] = round(time.time() - t0, 2)
        rec["ok"] = False
        rec["error"] = f"{type(e).__name__}: {e}"
    return rec


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--coding-model", required=True)
    ap.add_argument("--summarizer-model", required=True)
    ap.add_argument("--port", type=int, default=10082)
    ap.add_argument("--coding-chars", type=int, default=48000)
    ap.add_argument("--capture-chars", type=int, default=24000)
    ap.add_argument("--max-tokens", type=int, default=2048)
    ap.add_argument("--lead-s", type=float, default=2.0)
    ap.add_argument("--mode", choices=["control", "contended", "both"], default="both")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    out = {
        "coding_model": args.coding_model,
        "summarizer_model": args.summarizer_model,
        "coding_chars": args.coding_chars,
        "capture_chars": args.capture_chars,
    }

    if args.mode in ("control", "both"):
        print("control: coding turn alone ...", flush=True)
        c = coding_turn(args.coding_model, args.port, args.coding_chars, args.max_tokens)
        out["control"] = c
        print(f"  {json.dumps(c)}", flush=True)
        time.sleep(5)

    if args.mode in ("contended", "both"):
        print(f"contended: capture starts, coding turn {args.lead_s}s later ...", flush=True)
        cap_rec: dict = {}

        def _cap() -> None:
            # budget=1e9: measure the true wall; the abort is judged afterwards.
            cap_rec.update(capture(args.summarizer_model, args.capture_chars, args.port, 1e9))

        t = threading.Thread(target=_cap)
        t0 = time.time()
        t.start()
        time.sleep(args.lead_s)
        cod = coding_turn(args.coding_model, args.port, args.coding_chars, args.max_tokens)
        cod["started_at_s"] = round(args.lead_s, 2)
        t.join()
        out["contended"] = {
            "coding": cod,
            "capture": cap_rec,
            "overlap_wall_s": round(time.time() - t0, 2),
        }
        print(f"  coding : {json.dumps(cod)}", flush=True)
        print(f"  capture: {json.dumps(cap_rec)}", flush=True)

    # Gate 1: decode rate held, computed from the log-comparable tok/s.
    if "control" in out and "contended" in out:
        ctl, tst = out["control"], out["contended"]["coding"]
        if ctl.get("ok") and tst.get("ok"):
            r_ctl = ctl["completion_tokens"] / ctl["wall_s"]
            r_tst = tst["completion_tokens"] / tst["wall_s"]
            out["gate1"] = {
                "control_tok_s_endtoend": round(r_ctl, 2),
                "contended_tok_s_endtoend": round(r_tst, 2),
                "retained_pct": round(100 * r_tst / r_ctl, 1),
                "passes": (r_tst / r_ctl) >= 0.75,
            }
            print(f"\nGate 1: {json.dumps(out['gate1'], indent=2)}")

    Path(args.out).write_text(json.dumps(out, indent=2))
    print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
