#!/usr/bin/env python3
"""W12 part 2: find GLM 4.7 Flash's real cold-prefill ceiling.

Part 1 (measure-context-ceiling.py) showed the corrected MLA KV estimate lets the
guard ADMIT a 45,072-token prompt -- it prices KV+SDPA at 1.55 GB, correctly -- and
then real process memory reaches 48-50 GB during prefill, hits the physical Metal
cap, and oMLX force-stops the prefill and unloads the model.

So the binding constraint was never KV. It is the prefill ACTIVATION transient. The
7x KV over-count was wrong about the reason and accidentally right about the answer.

This finds the real ceiling. Each rung uses its OWN nonce, so nothing is served from
the prefix cache and every rung is a genuine cold door charge -- the worst case, and
the one that decides a declared context cap.

Adaptive: probes the optimistic end first, then bisects toward a number that holds.

Usage: python3 find-real-ceiling.py [nonce-prefix]
"""
import json, subprocess, sys, threading, time, urllib.error, urllib.request

URL = "http://127.0.0.1:10081/v1/chat/completions"
MODEL = "lmstudio-community/GLM-4.7-Flash-MLX-6bit"
MODEL_DIR = "/Users/p/.cache/huggingface/hub/lmstudio-community/GLM-4.7-Flash-MLX-6bit"
PREFIX = sys.argv[1] if len(sys.argv) > 1 else "w12c"

SYSTEM = "You are a coding assistant working in a repository. Answer briefly."
TAIL = "\n\nQuestion: reply with exactly the two words SERVE OK and nothing else."

from transformers import AutoTokenizer  # noqa: E402

tok = AutoTokenizer.from_pretrained(MODEL_DIR)
with open("/Users/p/Development/ai-cli/CLAUDE.md") as f:
    corpus = f.read()

OVERHEAD = len(tok.apply_chat_template(
    [{"role": "system", "content": SYSTEM}, {"role": "user", "content": ""}],
    tokenize=True, add_generation_prompt=True))


def build(target, nonce):
    head = f"Session {nonce}. Project documentation follows.\n\n"
    n_head = len(tok(head, add_special_tokens=False)["input_ids"])
    n_tail = len(tok(TAIL, add_special_tokens=False)["input_ids"])
    blocks = "".join(f"\n\n<!-- {nonce} block {i} -->\n{corpus}" for i in range(40))
    ids = tok(blocks, add_special_tokens=False)["input_ids"]
    body = tok.decode(ids[:max(target - OVERHEAD - n_head - n_tail, 1)])
    return head + body + TAIL


def omlx_pid():
    out = subprocess.run(["pgrep", "-f", "omlx-server"], capture_output=True,
                         text=True).stdout.split()
    return out[0] if out else None


class PeakSampler(threading.Thread):
    """Sample the server's RSS so the real transient is observed, not inferred."""

    def __init__(self):
        super().__init__(daemon=True)
        self.peak = 0.0
        self.stop = False

    def run(self):
        pid = omlx_pid()
        while not self.stop and pid:
            try:
                rss = subprocess.run(["ps", "-o", "rss=", "-p", pid],
                                     capture_output=True, text=True).stdout.strip()
                if rss:
                    self.peak = max(self.peak, int(rss) / 1024 / 1024)
            except Exception:
                pass
            time.sleep(0.5)


def probe(target, nonce, max_tokens=1):
    body = json.dumps({"model": MODEL, "max_tokens": max_tokens, "stream": False,
                       "messages": [{"role": "system", "content": SYSTEM},
                                    {"role": "user", "content": build(target, nonce)}]
                       }).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    s = PeakSampler()
    s.start()
    t0 = time.time()
    verdict, detail, pt, content, finish = "OK", "", 0, None, None
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            out = json.load(r)
        if "choices" not in out:
            verdict = "NO-CHOICES"
            detail = json.dumps(out)[:300]
        else:
            ch = out["choices"][0]
            finish = ch.get("finish_reason")
            content = (ch.get("message", {}).get("content") or "").strip()
            pt = out.get("usage", {}).get("prompt_tokens", 0)
    except urllib.error.HTTPError as e:
        verdict, detail = f"HTTP {e.code}", e.read().decode()[:300]
    except Exception as e:  # noqa: BLE001
        verdict, detail = type(e).__name__, str(e)[:300]
    dt = time.time() - t0
    s.stop = True
    s.join(timeout=2)
    print(f"{target:>7,} -> {verdict:<12} {dt:7.2f}s  prompt={pt:>7,} "
          f"peak_rss={s.peak:5.1f}GB finish={finish!r}", flush=True)
    if detail:
        print(f"          {detail[:220]}", flush=True)
    if content is not None and max_tokens > 1:
        print(f"          content={content[:60]!r}", flush=True)
    return {"target": target, "verdict": verdict, "seconds": round(dt, 2),
            "prompt_tokens": pt, "peak_rss_gb": round(s.peak, 2),
            "finish_reason": finish, "content": content, "detail": detail}


results = []
print("=== W12 part 2: real cold-prefill ceiling (each rung is a fresh prefix) ===",
      flush=True)

# Probe downward from the ticket's optimistic end until one holds.
for target in (40960, 32768, 24576, 20480):
    r = probe(target, f"{PREFIX}-{target}-{int(time.time())}")
    results.append(r)
    if r["verdict"] == "OK":
        print(f"\n>>> highest passing cold prefill: {target:,}", flush=True)
        # Prove it also serves a real answer at that size, per constraint 9.
        print("--- serve gate at that size (max_tokens=4096) ---", flush=True)
        results.append(probe(target, f"{PREFIX}-gate-{int(time.time())}",
                             max_tokens=4096))
        break

with open(__file__.replace("find-real-ceiling.py", "results-ceiling.json"), "w") as f:
    json.dump(results, f, indent=2)
print("\nwrote results-ceiling.json", flush=True)
