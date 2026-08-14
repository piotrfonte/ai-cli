#!/usr/bin/env python3
"""W12: does GLM 4.7 Flash admit a full 65,536-token prompt once the MLA KV
estimate is corrected?

W5 measured the unpatched server rejecting a 65,000-token prompt in 5.1 s with the
model alone in memory, because oMLX sized this model's MLA KV with the uniform MHA
formula (~362 KB/token against a real 52.9). scripts/patch-omlx-mla-kv.mjs corrects
the layer count in estimate_mla_kv_bytes_per_token. This re-runs W5's check.

Every request uses max_tokens=1, so wall time is prefill alone -- never subtract
decode from the server log line, because oMLX builds report tok/s differently.

Prompt sizes are cut with the model's OWN tokenizer, so prompt_tokens lands on the
target rather than near it. Each run carries a nonce, so turn 1 is genuinely cold.

Usage: python3 measure-context-ceiling.py [nonce]
"""
import json, os, subprocess, sys, time, urllib.error, urllib.request

URL = "http://127.0.0.1:10081/v1/chat/completions"
MODEL = "lmstudio-community/GLM-4.7-Flash-MLX-6bit"
MODEL_DIR = "/Users/p/.cache/huggingface/hub/lmstudio-community/GLM-4.7-Flash-MLX-6bit"
NONCE = sys.argv[1] if len(sys.argv) > 1 else "w12-default"

SYSTEM = "You are a coding assistant working in a repository. Answer briefly."
# The question sits at the END of the prompt, after the filler, so the model must
# actually carry the whole window to answer it.
TAIL = "\n\nQuestion: reply with exactly the two words SERVE OK and nothing else."

from transformers import AutoTokenizer  # noqa: E402

tok = AutoTokenizer.from_pretrained(MODEL_DIR)

with open("/Users/p/Development/ai-cli/CLAUDE.md") as f:
    corpus = f.read()
# Repeat to a comfortable surplus, varying each copy so it is not trivially
# compressible and so no two runs share a prefix.
blocks = [f"\n\n<!-- {NONCE} block {i} -->\n{corpus}" for i in range(40)]
big_ids = tok(("".join(blocks)), add_special_tokens=False)["input_ids"]

HEAD_TOK = len(tok(f"Session {NONCE}. Project documentation follows.\n\n",
                   add_special_tokens=False)["input_ids"])
TAIL_TOK = len(tok(TAIL, add_special_tokens=False)["input_ids"])
# Chat-template + system overhead, measured once below and folded in.
OVERHEAD = len(tok.apply_chat_template(
    [{"role": "system", "content": SYSTEM}, {"role": "user", "content": ""}],
    tokenize=True, add_generation_prompt=True))


def prompt_of(target_tokens):
    """Build a user message whose rendered prompt lands on target_tokens."""
    body_tokens = target_tokens - OVERHEAD - HEAD_TOK - TAIL_TOK
    body = tok.decode(big_ids[:max(body_tokens, 1)])
    return f"Session {NONCE}. Project documentation follows.\n\n{body}{TAIL}"


def omlx_rss_gb():
    try:
        out = subprocess.run(["pgrep", "-f", "omlx-server"], capture_output=True,
                             text=True).stdout.split()
        if not out:
            return None
        rss = subprocess.run(["ps", "-o", "rss=", "-p", out[0]],
                             capture_output=True, text=True).stdout.strip()
        return round(int(rss) / 1024 / 1024, 2)
    except Exception:
        return None


def ask(target, label, max_tokens=1):
    messages = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt_of(target)}]
    body = json.dumps({"model": MODEL, "messages": messages,
                       "max_tokens": max_tokens, "stream": False}).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        dt = time.time() - t0
        detail = e.read().decode()[:400]
        print(f"{label:<30} target={target:>7,}  REJECTED after {dt:6.2f}s  "
              f"HTTP {e.code}\n    {detail}", flush=True)
        return {"label": label, "target": target, "ok": False,
                "seconds": round(dt, 2), "http": e.code, "detail": detail}
    dt = time.time() - t0
    u = out.get("usage", {})
    pt = u.get("prompt_tokens", 0)
    cached = (u.get("prompt_tokens_details") or {}).get("cached_tokens", 0) or 0
    fresh = pt - cached
    ch = out["choices"][0]
    msg = ch.get("message", {})
    content = (msg.get("content") or "").strip()
    reasoning = (msg.get("reasoning_content") or "")
    rss = omlx_rss_gb()
    print(f"{label:<30} prompt={pt:>7,} cached={cached:>7,} fresh={fresh:>7,} "
          f"{dt:7.2f}s ({fresh/dt if dt else 0:>5.0f} tok/s)  "
          f"finish={ch.get('finish_reason')!r} rss={rss}GB", flush=True)
    if max_tokens > 1:
        print(f"    content={content[:80]!r}  reasoning_chars={len(reasoning)}",
              flush=True)
    return {"label": label, "target": target, "ok": True, "prompt_tokens": pt,
            "cached": cached, "fresh": fresh, "seconds": round(dt, 2),
            "finish_reason": ch.get("finish_reason"), "rss_gb": rss,
            "content": content if max_tokens > 1 else None,
            "reasoning_chars": len(reasoning) if max_tokens > 1 else None}


def swap_used_gb():
    out = subprocess.run(["sysctl", "-n", "vm.swapusage"], capture_output=True,
                         text=True).stdout
    for part in out.split():
        if part.endswith("M") and "used" in out.split(part)[0][-8:]:
            return round(float(part[:-1]) / 1024, 2)
    return None


res = []
print(f"=== W12 context ceiling, nonce={NONCE} ===", flush=True)
print(f"chat-template overhead={OVERHEAD} head={HEAD_TOK} tail={TAIL_TOK}", flush=True)
print(f"swap used at start: {swap_used_gb()} GB\n", flush=True)

# Warm-up. W5 measured the FIRST large prefill after a model load costing about
# twice the steady rate, so a cold ladder reads the warm-up as the model's rate.
# This request is not reported.
ask(10240, "warm-up (not reported)")
print(flush=True)

# W5's ladder: 20k answered, 45k was rejected after 145 s, 65k was rejected in 5.1 s.
for target, label in [(20480, "20,480 (W5: answered)"),
                      (45056, "45,056 (W5: rejected)"),
                      (65536, "65,536 (W5: rejected 5.1s)")]:
    res.append(ask(target, label))

# Mid-session repeat: W5 found ~37.5k passing on a fresh server and failing once
# memory was already occupied. The cap has to hold HERE, not only when cold.
print("\n--- mid-session repeat (memory now occupied) ---", flush=True)
res.append(ask(65536, "65,536 mid-session"))

# The serve gate at full window: constraint 9 wants max_tokens >= 4096, a non-empty
# content and finish_reason stop.
print("\n--- serve gate at 65,536 (max_tokens=4096) ---", flush=True)
res.append(ask(65536, "65,536 serve gate", max_tokens=4096))

print(f"\nswap used at end: {swap_used_gb()} GB", flush=True)

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results.json")
with open(out_path, "w") as f:
    json.dump(res, f, indent=2)
print(f"wrote {out_path}")
