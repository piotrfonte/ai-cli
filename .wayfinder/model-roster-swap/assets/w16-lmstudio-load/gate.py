#!/usr/bin/env python3
"""W16 — the map's standard serve gate, aimed at LM Studio instead of oMLX.

Constraint 9, as sharpened by W1, W6 and W14:
  * finish_reason must be "stop"
  * content must be non-empty
  * max_tokens must be 8192 (W14's working figure; 4096 is the floor)

A short cap has fooled this map twice: it returns the whole reasoning inline in
`content` with no `reasoning_content` key, so a bare non-empty test passes a dead
answer. Hence the cap, and hence the reasoning field is reported separately.

Usage:  python3 gate.py <model-key> <out.json> [base-url]
"""
import json
import sys
import time
import urllib.error
import urllib.request

PROMPT = (
    "Write a Python function that reverses a singly linked list in place. "
    "The node class is `class Node: __init__(self, val, next=None)`. "
    "Return only the function."
)
MAX_TOKENS = 8192


def main() -> int:
    key = sys.argv[1]
    out_path = sys.argv[2]
    base = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:1234/v1"

    body = json.dumps(
        {
            "model": key,
            "messages": [{"role": "user", "content": PROMPT}],
            "max_tokens": MAX_TOKENS,
            "stream": False,
        }
    ).encode()

    req = urllib.request.Request(
        f"{base}/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
    )

    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            payload = json.load(r)
        err = None
    except urllib.error.HTTPError as e:
        payload, err = None, f"HTTP {e.code}: {e.read().decode()[:500]}"
    except Exception as e:  # noqa: BLE001 - the failure itself is the result
        payload, err = None, f"{type(e).__name__}: {e}"
    elapsed = time.time() - t0

    result = {"model_key": key, "max_tokens": MAX_TOKENS, "elapsed_s": round(elapsed, 2)}

    if err:
        result |= {"gate": "FAIL", "error": err}
    else:
        choice = payload["choices"][0]
        msg = choice["message"]
        content = msg.get("content") or ""
        reasoning = msg.get("reasoning_content") or msg.get("reasoning") or ""
        usage = payload.get("usage", {})
        result |= {
            "finish_reason": choice.get("finish_reason"),
            "content_chars": len(content),
            "content_head": content[:400],
            "reasoning_chars": len(reasoning),
            "reasoning_split_out": bool(reasoning),
            "usage": usage,
            "served_model": payload.get("model"),
        }
        ok = choice.get("finish_reason") == "stop" and len(content.strip()) > 0
        result["gate"] = "PASS" if ok else "FAIL"
        if usage.get("completion_tokens"):
            result["decode_tok_s"] = round(usage["completion_tokens"] / elapsed, 1)

    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)

    print(json.dumps({k: v for k, v in result.items() if k != "content_head"}, indent=2))
    return 0 if result["gate"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
