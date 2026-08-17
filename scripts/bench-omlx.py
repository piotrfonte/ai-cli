#!/usr/bin/env python3
"""Measure decode throughput (tok/s) of a model served by the local oMLX server.

Streams a chat completion and times it:
  - TTFT      — time to first token (prompt eval + first decode)
  - decode    — tokens/sec during generation (first→last token), the headline number
  - end-to-end— total tokens / total wall time

Usage:
  python scripts/bench-omlx.py [--model ID] [--base-url URL] [--max-tokens N]
                               [--prompt TEXT] [--runs N]

Defaults target the local mlx provider on port 10081. Run a few times — the
first request pays model-load + cold-prefill; later runs reflect warm decode.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request


def run_once(base_url: str, model: str, prompt: str, max_tokens: int) -> dict:
    url = base_url.rstrip("/") + "/chat/completions"
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": 0.0,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
    ).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json", "Authorization": "Bearer mlx"}
    )

    t0 = time.perf_counter()
    t_first = None
    t_last = None
    chunk_tokens = 0
    usage = None

    with urllib.request.urlopen(req, timeout=600) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[len("data:"):].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            if obj.get("usage"):
                usage = obj["usage"]
            for ch in obj.get("choices", []):
                delta = ch.get("delta", {})
                if delta.get("content"):
                    now = time.perf_counter()
                    if t_first is None:
                        t_first = now
                    t_last = now
                    chunk_tokens += 1

    t_end = time.perf_counter()
    if t_first is None:
        raise RuntimeError("no content tokens streamed")

    completion_tokens = (usage or {}).get("completion_tokens") or chunk_tokens
    prompt_tokens = (usage or {}).get("prompt_tokens")
    decode_span = max(t_last - t_first, 1e-9)
    # decode tok/s: tokens emitted after the first, over the time after the first
    decode_tps = (completion_tokens - 1) / decode_span if completion_tokens > 1 else 0.0
    return {
        "ttft_s": t_first - t0,
        "decode_tps": decode_tps,
        "e2e_tps": completion_tokens / max(t_end - t0, 1e-9),
        "completion_tokens": completion_tokens,
        "prompt_tokens": prompt_tokens,
        "stream_chunks": chunk_tokens,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:10081/v1")
    ap.add_argument("--model", default="lmstudio-community/GLM-4.7-Flash-MLX-6bit")
    ap.add_argument("--max-tokens", type=int, default=256)
    ap.add_argument(
        "--prompt",
        default="Write a TypeScript function `debounce<T>` that debounces an async "
        "function, with correct types and a cancel method. Explain the typing briefly.",
    )
    ap.add_argument("--runs", type=int, default=3)
    args = ap.parse_args()

    print(f"model     : {args.model}")
    print(f"endpoint  : {args.base_url}")
    print(f"max_tokens: {args.max_tokens}   runs: {args.runs}")
    print("-" * 64)

    best_decode = 0.0
    for i in range(1, args.runs + 1):
        try:
            r = run_once(args.base_url, args.model, args.prompt, args.max_tokens)
        except Exception as e:  # noqa: BLE001
            print(f"run {i}: ERROR {e}")
            return 1
        tag = "(cold)" if i == 1 else "(warm)"
        best_decode = max(best_decode, r["decode_tps"])
        print(
            f"run {i} {tag:6} | decode {r['decode_tps']:6.1f} tok/s | "
            f"TTFT {r['ttft_s']:5.2f}s | e2e {r['e2e_tps']:6.1f} tok/s | "
            f"out {r['completion_tokens']} tok"
        )
    print("-" * 64)
    print(f"best decode throughput: {best_decode:.1f} tok/s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
