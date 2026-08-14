#!/usr/bin/env python3
"""W13: does a *growing* agentic conversation re-pay Bonsai's cold prefill?

Turn 1 of a folder visit is a cold ~12.8k-token prompt. Turn 2 appends the
assistant reply plus tool output, so its prompt is a strict EXTENSION of turn 1's.
If oMLX's paged prefix cache hits on that extension, the 66 s is paid once at the
door; if it misses, it is paid every turn.

Every request uses max_tokens=1, so the wall time is prefill alone (never subtract
decode from the log line -- builds report tok/s differently).
"""
import json, time, urllib.request, os, sys

URL = "http://127.0.0.1:10081/v1/chat/completions"
MODEL = "prism-ml/Ternary-Bonsai-27B-mlx-2bit"
NONCE = sys.argv[1] if len(sys.argv) > 1 else "w13-default"

# Realistic agentic context: this repo's own CLAUDE.md, the kind of payload a
# coding turn carries. The nonce guarantees a cold prefix (no block from an
# earlier session can match).
with open("/Users/p/Development/ai-cli/CLAUDE.md") as f:
    doc = f.read()

SYSTEM = "You are a coding assistant working in a repository. Answer briefly."
USER1 = (
    f"Session {NONCE}. Here is the project documentation:\n\n"
    f"{doc}\n\n"
    "Question: which environment variable caps the KV cache on disk?"
)

# ~2k tokens of appended tool output, as turn 2 of a real session would carry.
TOOL_OUT = "\n".join(
    f"{i:4d}\t  omlx_cache_prune_gb=$((i)) # line {i} of the launcher listing "
    f"showing cache budget resolution and flag parsing for profile dispatch"
    for i in range(1, 260)
)


def ask(messages, label):
    body = json.dumps({
        "model": MODEL, "messages": messages,
        "max_tokens": 1, "stream": False,
    }).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=900) as r:
        out = json.load(r)
    dt = time.time() - t0
    u = out.get("usage", {})
    pt = u.get("prompt_tokens", 0)
    details = u.get("prompt_tokens_details") or {}
    cached = details.get("cached_tokens", u.get("cached_tokens", "n/a"))
    rate = pt / dt if dt else 0
    print(f"{label:<34} prompt={pt:>7,}  cached={cached!s:>7}  "
          f"{dt:7.2f}s  {rate:8.0f} tok/s", flush=True)
    return {"label": label, "prompt_tokens": pt, "cached": cached,
            "seconds": round(dt, 2), "tok_s": round(rate)}


results = []
a1 = [{"role": "system", "content": SYSTEM},
      {"role": "user", "content": USER1}]
results.append(ask(a1, "A  turn 1 (cold, ~12.8k)"))

b = a1 + [
    {"role": "assistant", "content": "OMLX_SSD_CACHE_MAX caps it. Let me check the launcher."},
    {"role": "user", "content": f"Tool result (read ai.sh):\n{TOOL_OUT}\n\nNow: what prunes it?"},
]
results.append(ask(b, "B  turn 2 (extends A by ~2k)"))

c = b + [
    {"role": "assistant", "content": "_prune_cache enforces it at each server start."},
    {"role": "user", "content": f"Tool result (read ai.sh again):\n{TOOL_OUT}\n\nAnd the default?"},
]
results.append(ask(c, "C  turn 3 (extends B by ~2k)"))

results.append(ask(a1, "D  repeat of A (pure warm)"))

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "w13-results.json")
with open(out_path, "w") as f:
    json.dump(results, f, indent=2)
print(f"\nwrote {out_path}")
