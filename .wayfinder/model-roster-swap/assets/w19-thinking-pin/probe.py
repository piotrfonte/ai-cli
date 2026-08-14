#!/usr/bin/env python3
"""W19 — probe whether the enable_thinking pin actually engages on GLM.

Runs the SAME two prompts either side of the pin so the pin is the only variable:
  1. the short determinism probe run.py already uses
  2. the real T2 prompt, which W14 recorded GLM reasoning heavily on

Reports reasoning_content length, content length, finish_reason and tokens.
A pin that engages collapses reasoning_chars to 0 and leaves content non-empty.
"""

import json
import os
import sys
import time
import urllib.request

W14 = "/Users/p/Development/ai-cli/.wayfinder/model-roster-swap/assets/w14-capability"
sys.path.insert(0, W14)
import tasks as T  # noqa: E402

BASE = os.environ.get("W19_BASE", "http://127.0.0.1:10082/v1")
MODEL = "lmstudio-community/GLM-4.7-Flash-MLX-6bit"
LABEL = sys.argv[1] if len(sys.argv) > 1 else "unlabelled"

SHORT = (
    "In one sentence, say what a paged KV cache does for a coding agent. "
    "Do not add anything else."
)


def ask(prompt, max_tokens):
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": T.SYSTEM},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
        "stream": False,
    }
    req = urllib.request.Request(
        f"{BASE}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer mlx"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as resp:
        data = json.loads(resp.read())
    wall = time.time() - t0
    choice = (data.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    usage = data.get("usage") or {}
    return {
        "wall_s": round(wall, 2),
        "finish_reason": choice.get("finish_reason"),
        "reasoning_chars": len(msg.get("reasoning_content") or ""),
        "content_chars": len(msg.get("content") or ""),
        "completion_tokens": usage.get("completion_tokens", 0),
        "content_head": (msg.get("content") or "")[:220],
        "reasoning_head": (msg.get("reasoning_content") or "")[:220],
    }


out = {
    "label": LABEL,
    "short": ask(SHORT, 8192),
    "t2_real": ask(T.T2_PROMPT, 8192),
}
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), f"probe-{LABEL}.json")
with open(path, "w") as fh:
    json.dump(out, fh, indent=2)
print(json.dumps(out, indent=2))
