#!/usr/bin/env python3
"""Close the one confound in the W15 run: did the prefix cache stay empty because
every long prompt was measured at max_tokens=1?

measure.py's long prompts (steps 4 and 5) generate a single token, and dflash publishes
its snapshot from the generation loop. Its short prompts DID generate hundreds of tokens
and still inserted nothing, but short and long were never tested under the same
max_tokens, so the two explanations are not separated.

This does: cold 12.2k prompt with a REAL generation, then the same prompt again. If
cached_tokens is still 0 on the repeat, the cache does not insert, full stop.

Usage: confirm-cache.py [port]
"""
import json
import sys
import time
import urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "10082"
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"
MODEL = "mlx-community/Muse-Glimmer-30B-4bit"
NONCE = f"w15-confirm-{int(time.time())}"

with open("/Users/p/Development/ai-cli/CLAUDE.md") as f:
    DOC = f.read()

MSGS = [
    {"role": "system", "content": "You are a coding assistant working in a repository. Answer briefly."},
    {"role": "user", "content": (f"Session {NONCE}. Here is the project documentation:\n\n{DOC}\n\n"
                                 "Question: which environment variable caps the KV cache on disk?")},
]


def ask(label, max_tokens):
    body = json.dumps({"model": MODEL, "messages": MSGS,
                       "max_tokens": max_tokens, "stream": False}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        out = json.load(r)
    dt = time.time() - t0
    u = out.get("usage", {})
    cached = (u.get("prompt_tokens_details") or {}).get("cached_tokens", 0)
    print(f"{label:<38} prompt={u.get('prompt_tokens'):>6,} cached={cached:>6,} "
          f"completion={u.get('completion_tokens'):>5,} {dt:7.2f}s", flush=True)
    return {"label": label, "prompt_tokens": u.get("prompt_tokens"), "cached": cached,
            "completion_tokens": u.get("completion_tokens"), "seconds": round(dt, 2)}


res = [ask("turn 1 (cold, real generation)", 1024),
       ask("turn 2 (same prompt, max_tokens=1)", 1)]
with open(__file__.replace("confirm-cache.py", "results-confirm-cache.json"), "w") as f:
    json.dump(res, f, indent=2)
print("\ncache inserts" if res[1]["cached"] else "\ncache does NOT insert")
