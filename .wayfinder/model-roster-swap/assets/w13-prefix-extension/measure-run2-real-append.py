#!/usr/bin/env python3
"""W13 run 2: marginal cost of a turn, with realistically-sized tool results.

Run 1 proved the prefix cache hits on extension but used a 9k-token append.
This run appends ~500 and ~2000 tokens -- the size a real tool result carries --
to read the per-turn cost a folder visit actually pays after the door charge.
"""
import json, time, urllib.request, os, sys

URL = "http://127.0.0.1:10081/v1/chat/completions"
MODEL = "prism-ml/Ternary-Bonsai-27B-mlx-2bit"
NONCE = sys.argv[1] if len(sys.argv) > 1 else "w13b-default"

with open("/Users/p/Development/ai-cli/CLAUDE.md") as f:
    doc = f.read()

SYSTEM = "You are a coding assistant working in a repository. Answer briefly."
USER1 = (
    f"Session {NONCE}. Here is the project documentation:\n\n"
    f"{doc}\n\n"
    "Question: which environment variable caps the KV cache on disk?"
)


def tool_out(lines):
    return "\n".join(
        f"{i:4d}\t  omlx_cache_prune_gb=$((i)) # launcher line {i}"
        for i in range(1, lines + 1)
    )


def ask(messages, label):
    body = json.dumps({"model": MODEL, "messages": messages,
                       "max_tokens": 1, "stream": False}).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=900) as r:
        out = json.load(r)
    dt = time.time() - t0
    u = out.get("usage", {})
    pt = u.get("prompt_tokens", 0)
    d = u.get("prompt_tokens_details") or {}
    cached = d.get("cached_tokens", 0)
    fresh = pt - (cached or 0)
    print(f"{label:<32} prompt={pt:>7,} cached={cached:>7,} fresh={fresh:>6,} "
          f"{dt:7.2f}s  ({fresh/dt if dt else 0:>5.0f} tok/s on fresh)", flush=True)
    return {"label": label, "prompt_tokens": pt, "cached": cached,
            "fresh": fresh, "seconds": round(dt, 2)}


msgs = [{"role": "system", "content": SYSTEM},
        {"role": "user", "content": USER1}]
res = [ask(msgs, "turn 1 (cold, ~12.8k)")]

for n, lines in enumerate([40, 160, 160, 40], start=2):
    msgs = msgs + [
        {"role": "assistant", "content": "Checking the launcher now."},
        {"role": "user", "content": f"Tool result:\n{tool_out(lines)}\n\nContinue."},
    ]
    res.append(ask(msgs, f"turn {n} (+~{lines * 12} tok tool out)"))

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "w13-results2.json")
with open(out_path, "w") as f:
    json.dump(res, f, indent=2)
print(f"\nwrote {out_path}")
