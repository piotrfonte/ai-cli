#!/usr/bin/env python3
"""W15: the six measurements, run identically against a DFlash-off and a DFlash-on server.

Usage: measure.py <tag> [port]

Writes results-<tag>.json next to this file. Every number here is wall-clock from the
client. Prefill is always isolated with max_tokens=1; decode is never inferred by
subtracting the server log's tok/s line, which builds report differently.
"""
import json
import os
import sys
import threading
import time
import urllib.request

TAG = sys.argv[1] if len(sys.argv) > 1 else "untagged"
PORT = sys.argv[2] if len(sys.argv) > 2 else "10082"
BASE = f"http://127.0.0.1:{PORT}"
URL = f"{BASE}/v1/chat/completions"
MODEL = "mlx-community/Muse-Glimmer-30B-4bit"
MAX_TOKENS = 8192  # constraint 9 as W14 raised it; matches opencode.json's output cap
HERE = os.path.dirname(os.path.abspath(__file__))
REPO_DOC = "/Users/p/Development/ai-cli/CLAUDE.md"

SYSTEM = "You are a coding assistant working in a repository. Answer briefly."
CODING_Q = (
    "Write a Python function slugify(s) that lowercases the string, replaces every run "
    "of non-alphanumeric characters with a single hyphen, and strips leading and "
    "trailing hyphens. Answer with the function only."
)


def ask(messages, *, max_tokens, timeout=1800):
    body = json.dumps({"model": MODEL, "messages": messages,
                       "max_tokens": max_tokens, "stream": False}).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.load(r)
    dt = time.time() - t0
    choice = (out.get("choices") or [{}])[0]
    msg = choice.get("message") or {}
    usage = out.get("usage") or {}
    details = usage.get("prompt_tokens_details") or {}
    return {
        "seconds": round(dt, 3),
        "finish_reason": choice.get("finish_reason"),
        "content": msg.get("content") or "",
        "reasoning_chars": len(msg.get("reasoning_content") or ""),
        "prompt_tokens": usage.get("prompt_tokens", 0),
        "completion_tokens": usage.get("completion_tokens", 0),
        "cached_tokens": details.get("cached_tokens", 0),
    }


def admin(path):
    try:
        with urllib.request.urlopen(f"{BASE}{path}", timeout=15) as r:
            return json.load(r)
    except Exception as exc:  # admin may require a key; the log is the fallback proof
        return {"error": f"{type(exc).__name__}: {exc}"}


def short_msgs():
    return [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": CODING_Q}]


def long_msgs(nonce):
    with open(REPO_DOC) as f:
        doc = f.read()
    return [{"role": "system", "content": SYSTEM},
            {"role": "user", "content": (
                f"Session {nonce}. Here is the project documentation:\n\n{doc}\n\n"
                "Question: which environment variable caps the KV cache on disk?")}]


def main():
    nonce = f"w15-{TAG}-{int(time.time())}"
    res = {"tag": TAG, "nonce": nonce, "model": MODEL, "max_tokens": MAX_TOKENS}

    # 1. Functional gate. This is also the cold model load, so it is timed separately
    #    and never used as a rate.
    print("1. gate (cold load included) ...", flush=True)
    gate = ask(short_msgs(), max_tokens=MAX_TOKENS)
    gate_ok = gate["finish_reason"] == "stop" and len(gate["content"].strip()) > 0
    res["gate"] = {**gate, "content": gate["content"][:400], "passed": gate_ok}
    print(f"   finish_reason={gate['finish_reason']} content={len(gate['content'])}ch "
          f"reasoning={gate['reasoning_chars']}ch {gate['seconds']}s -> "
          f"{'PASS' if gate_ok else 'FAIL'}", flush=True)

    # 2. Prefill of the short prompt, isolated, so step 3 can subtract it honestly.
    print("2. short-prompt prefill (max_tokens=1) ...", flush=True)
    p_short = ask(short_msgs(), max_tokens=1)
    res["short_prefill"] = p_short
    print(f"   {p_short['prompt_tokens']} tok in {p_short['seconds']}s", flush=True)

    # 3. Decode, three runs.
    print("3. decode x3 ...", flush=True)
    decodes = []
    for i in range(3):
        run = ask(short_msgs(), max_tokens=MAX_TOKENS)
        gen_s = max(1e-6, run["seconds"] - p_short["seconds"])
        rate = run["completion_tokens"] / gen_s
        decodes.append({**run, "content": run["content"][:200],
                        "decode_seconds": round(gen_s, 3), "tok_per_s": round(rate, 2)})
        print(f"   run {i + 1}: {run['completion_tokens']} tok in {gen_s:.2f}s "
              f"=> {rate:.2f} tok/s (finish={run['finish_reason']})", flush=True)
    res["decode"] = decodes

    # 4. Cold prefill of a ~12.8k prompt. Unique nonce, so no prefix cache can serve it.
    print("4. cold 12.8k prefill (max_tokens=1) ...", flush=True)
    cold = ask(long_msgs(nonce), max_tokens=1)
    res["cold_prefill"] = cold
    print(f"   {cold['prompt_tokens']} tok cached={cold['cached_tokens']} "
          f"{cold['seconds']}s => {cold['prompt_tokens'] / cold['seconds']:.0f} tok/s",
          flush=True)

    # 5. The same prompt again. Does anything cache it?
    print("5. warm repeat ...", flush=True)
    warm = ask(long_msgs(nonce), max_tokens=1)
    res["warm_repeat"] = warm
    print(f"   {warm['prompt_tokens']} tok cached={warm['cached_tokens']} "
          f"{warm['seconds']}s", flush=True)

    # 6. Concurrency: two identical decode requests fired together. Serial baseline is
    #    step 3's mean, measured on this same server minutes earlier.
    print("6. concurrency (2 requests together) ...", flush=True)
    out = {}

    def fire(idx):
        out[idx] = ask(short_msgs(), max_tokens=MAX_TOKENS)

    threads = [threading.Thread(target=fire, args=(i,)) for i in (0, 1)]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    wall = time.time() - t0
    pair = [out[i] for i in sorted(out)]
    res["concurrency"] = {"wall_seconds": round(wall, 3),
                          "requests": [{**r, "content": r["content"][:120]} for r in pair]}
    serial_mean = sum(d["seconds"] for d in decodes) / len(decodes)
    print(f"   wall {wall:.2f}s for 2; single-request mean was {serial_mean:.2f}s "
          f"(perfect overlap would be ~{serial_mean:.2f}s, full serialization ~"
          f"{2 * serial_mean:.2f}s)", flush=True)

    # 7. Engagement and memory, from oMLX itself.
    res["admin_activity"] = admin("/admin/api/activity")
    res["admin_stats"] = admin("/admin/api/stats")

    path = os.path.join(HERE, f"results-{TAG}.json")
    with open(path, "w") as f:
        json.dump(res, f, indent=2)
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()
