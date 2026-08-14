#!/usr/bin/env python3
"""W20 — a faithful replay of opencode-mem's auto-capture summarizer request.

Every field here is copied from the installed plugin, not invented:

  system prompt   services/auto-capture.js  (generateSummary, manual-config path)
  user prompt     `${context}\n\nAnalyze this conversation. ...`
  tools           the save_memory schema, tool_choice "auto"
  temperature     0.3  (memoryTemperature default; NOT false)
  max_tokens      absent — the provider never sends one
  abort           AbortController at autoCaptureIterationTimeout (default 30000 ms)

NOTE on the abort. The plugin's AbortController is a TOTAL deadline: setTimeout
fires 30 s after the request starts and kills the fetch whatever it is doing.
urllib's `timeout=` is a per-socket-read timeout, which is NOT the same thing —
a 72 s request that dribbles bytes passes a 30 s socket timeout and would have
been scored a pass. So this harness measures the true wall with a generous
socket timeout and evaluates the deadline itself: wall > budget means the plugin
aborts, and Gate 0 fails.

The context itself is built by buildMarkdownContext and then capped by ai.sh's
patch (__omlxCapContext) to OPENCODE_MEM_MAX_CONTEXT_CHARS, head 55% / tail 45%.
build_context() reproduces that shape from real repo text, so the prompt is
technical enough that the model actually has something to summarize.

Usage:
  summarizer.py --model <id> --chars 24000 [--timeout 30] [--out f.json]
"""
import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

# .../ai-cli/.wayfinder/model-roster-swap/assets/w20-summarizer/summarizer.py
REPO = Path(__file__).resolve().parents[4]

SYSTEM_PROMPT = """You are a technical memory recorder for a software development project.

RULES:
1. ONLY capture technical work (code, bugs, features, architecture, config)
2. SKIP non-technical by returning type="skip"
3. NO meta-commentary or behavior analysis
4. Include specific file names, functions, technical details
5. Generate 2-4 technical tags (e.g., "react", "auth", "bug-fix")
6. You MUST write the summary in English.

FORMAT:
## Request
[1-2 sentences: what was requested, in English]

## Outcome
[1-2 sentences: what was done, include files/functions, in English]

SKIP if: greetings, casual chat, no code/decisions made
CAPTURE if: code changed, bug fixed, feature added, decision made"""

ANALYZE_TAIL = (
    "\n\nAnalyze this conversation. If it contains technical work (code, bugs, "
    "features, decisions), create a concise summary and relevant tags. If it's "
    "non-technical (greetings, casual chat, incomplete requests), return "
    'type="skip" with empty summary.'
)

TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "save_memory",
        "description": "Save the conversation summary as a memory",
        "parameters": {
            "type": "object",
            "properties": {
                "summary": {
                    "type": "string",
                    "description": "Markdown-formatted summary of the conversation",
                },
                "type": {
                    "type": "string",
                    "description": (
                        "Type of memory: 'skip' for non-technical conversations, "
                        "or technical type (feature, bug-fix, refactor, analysis, "
                        "configuration, discussion, other)"
                    ),
                },
                "tags": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "List of 2-4 technical tags related to the memory",
                },
            },
            "required": ["summary", "type", "tags"],
        },
    },
}

USER_REQUEST = (
    "The auto-capture summarizer keeps timing out. Work out where the 30 s "
    "abort comes from, whether the input cap is what decides it, and what the "
    "cheapest lever is. Do not change the default model."
)


def _source_text() -> str:
    """Real technical prose + code from this repo, so the summary is not vacuous."""
    parts = []
    for rel in ("CLAUDE.md", "ai.sh", "scripts/patch-omlx-mtp.mjs", "opencode.json"):
        p = REPO / rel
        if p.exists():
            parts.append(p.read_text(encoding="utf-8", errors="replace"))
    return "\n\n".join(parts)


def build_context(max_chars: int) -> str:
    """Reproduce buildMarkdownContext + __omlxCapContext for a given cap."""
    body = _source_text()
    sections = [
        "## User Request",
        "---",
        USER_REQUEST,
        "---\n",
        "## AI Response",
        "---",
        body,
        "---\n",
        "## Tools Used",
        "---",
        "- read(services/auto-capture.js)",
        "- read(services/ai/providers/openai-chat-completion.js)",
        "- grep(autoCaptureIterationTimeout)",
        "- bash(node --check scripts/patch-omlx-mtp.mjs)",
        "---\n",
    ]
    s = "\n".join(sections)
    if len(s) <= max_chars:
        return s
    head = int(max_chars * 0.55)
    tail = max_chars - head
    dropped = len(s) - max_chars
    return (
        s[:head]
        + "\n\n... [omlx: truncated "
        + str(dropped)
        + " chars of summarizer context to protect oMLX memory] ...\n\n"
        + s[len(s) - tail :]
    )


def capture(
    model: str, chars: int, port: int, budget: float, max_tokens: int | None = None
) -> dict:
    """budget = the plugin's per-iteration abort, evaluated as a wall deadline.

    max_tokens mirrors `memoryExtraParams: {"max_tokens": N}`. applySafeExtraParams
    spreads that object into the body and max_tokens is not in PROTECTED_KEYS, so
    passing it here is faithful to what the configured plugin sends.
    """
    context = build_context(chars)
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": context + ANALYZE_TAIL},
        ],
        "tools": [TOOL_SCHEMA],
        "tool_choice": "auto",
        "temperature": 0.3,
    }
    if max_tokens is not None:
        body["max_tokens"] = max_tokens
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer mlx"},
    )
    rec = {
        "model": model,
        "context_chars": len(context),
        "request_chars": len(json.dumps(body)),
        "abort_budget_s": budget,
    }
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            data = json.loads(r.read())
        rec["wall_s"] = round(time.time() - t0, 2)
        rec["ok"] = True
        choice = (data.get("choices") or [{}])[0]
        msg = choice.get("message") or {}
        rec["finish_reason"] = choice.get("finish_reason")
        usage = data.get("usage") or {}
        rec["prompt_tokens"] = usage.get("prompt_tokens")
        rec["completion_tokens"] = usage.get("completion_tokens")
        details = usage.get("prompt_tokens_details") or {}
        rec["cached_tokens"] = details.get("cached_tokens")
        calls = msg.get("tool_calls") or []
        rec["tool_calls"] = len(calls)
        rec["reasoning_chars"] = len(msg.get("reasoning_content") or "")
        rec["content_chars"] = len(msg.get("content") or "")
        if calls:
            fn = calls[0].get("function") or {}
            rec["tool_name"] = fn.get("name")
            try:
                args = json.loads(fn.get("arguments") or "{}")
                rec["tool_args_parse"] = True
                rec["memory_type"] = args.get("type")
                rec["summary_chars"] = len(args.get("summary") or "")
                rec["tags"] = args.get("tags")
            except Exception as e:  # noqa: BLE001
                rec["tool_args_parse"] = False
                rec["tool_args_error"] = str(e)
        # Gate 0 as the plugin sees it: a parsed save_memory call, inside the
        # AbortController's total deadline. Both halves are required.
        rec["answered"] = bool(
            calls
            and rec.get("tool_name") == "save_memory"
            and rec.get("tool_args_parse")
        )
        rec["within_budget"] = rec["wall_s"] <= budget
        rec["gate0"] = rec["answered"] and rec["within_budget"]
    except urllib.error.HTTPError as e:
        rec["wall_s"] = round(time.time() - t0, 2)
        rec["ok"] = False
        rec["http_status"] = e.code
        rec["error"] = e.read().decode(errors="replace")[:400]
        rec["gate0"] = False
    except Exception as e:  # timeout lands here — the plugin's abort
        rec["wall_s"] = round(time.time() - t0, 2)
        rec["ok"] = False
        rec["error"] = f"{type(e).__name__}: {e}"
        rec["aborted"] = True
        rec["gate0"] = False
    return rec


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--chars", type=int, default=24000)
    ap.add_argument("--port", type=int, default=10082)
    ap.add_argument(
        "--budget",
        type=float,
        default=30.0,
        help="autoCaptureIterationTimeout in seconds, as a wall deadline",
    )
    ap.add_argument(
        "--max-tokens",
        type=int,
        default=None,
        help='mirrors memoryExtraParams {"max_tokens": N}',
    )
    ap.add_argument("--out")
    args = ap.parse_args()

    rec = capture(args.model, args.chars, args.port, args.budget, args.max_tokens)
    print(json.dumps(rec, indent=2))
    if args.out:
        Path(args.out).write_text(json.dumps(rec, indent=2))


if __name__ == "__main__":
    main()
