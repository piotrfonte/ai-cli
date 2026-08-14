#!/usr/bin/env python3
"""W14 — run the capability task set against one model on the local oMLX server.

  python3 run.py --model <two-level-id> --out results-<name>.json [--repeats N]

Sends no `temperature`, mirroring opencode.json's "temperature": false, so each
model falls back to its own generation_config.json. See README.md for the rubric;
it was written before the first request was sent.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tasks as T  # noqa: E402

# Constraint 9 sets 4096 as the FLOOR. Production is higher: every model
# opencode.json declares gets `"output": 8192`, and W9 will declare the same for
# this roster. A first pass at 4096 made GLM hit the cap mid-module — a failure
# manufactured by the harness, not by the model, so it was discarded. Measure the
# budget the models actually get.
MAX_TOKENS = 8192
TOOL_ITER_CAP = 6          # a tool loop that will not stop is a protocol failure
REQUEST_TIMEOUT = 1800


def post(url, payload):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json", "Authorization": "Bearer mlx"}
    )
    with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
        return json.loads(resp.read())


class Session:
    """One conversation with one model. Accumulates timing and token counts."""

    def __init__(self, base, model, system):
        self.base, self.model = base, model
        self.messages = [{"role": "system", "content": system}]
        self.wall = 0.0
        self.prompt_tokens = 0
        self.completion_tokens = 0
        self.reasoning_chars = 0
        self.finish_reasons = []
        self.error = None

    def say(self, content, tools=None):
        self.messages.append({"role": "user", "content": content})
        return self._complete(tools)

    def _complete(self, tools=None):
        payload = {
            "model": self.model,
            "messages": self.messages,
            "max_tokens": MAX_TOKENS,
            "stream": False,
        }
        if tools:
            payload["tools"] = tools
        t0 = time.time()
        try:
            data = post(f"{self.base}/chat/completions", payload)
        except urllib.error.HTTPError as e:
            self.error = f"HTTP {e.code}: {e.read().decode()[:400]}"
            self.wall += time.time() - t0
            return None
        except Exception as e:  # noqa: BLE001 - record and move on
            self.error = f"{type(e).__name__}: {e}"
            self.wall += time.time() - t0
            return None
        self.wall += time.time() - t0
        usage = data.get("usage") or {}
        self.prompt_tokens += usage.get("prompt_tokens", 0) or 0
        self.completion_tokens += usage.get("completion_tokens", 0) or 0
        choice = (data.get("choices") or [{}])[0]
        msg = choice.get("message") or {}
        self.finish_reasons.append(choice.get("finish_reason"))
        self.reasoning_chars += len(msg.get("reasoning_content") or "")
        self.messages.append(
            {
                "role": "assistant",
                "content": msg.get("content") or "",
                **({"tool_calls": msg["tool_calls"]} if msg.get("tool_calls") else {}),
            }
        )
        return msg

    def add_tool_result(self, call_id, text):
        self.messages.append({"role": "tool", "tool_call_id": call_id, "content": text})

    def resume(self, tools=None):
        return self._complete(tools)

    def stats(self):
        return {
            "wall_s": round(self.wall, 2),
            "prompt_tokens": self.prompt_tokens,
            "completion_tokens": self.completion_tokens,
            "reasoning_chars": self.reasoning_chars,
            "finish_reasons": self.finish_reasons,
            "error": self.error,
        }


def hit_length_cap(sess):
    return "length" in [f for f in sess.finish_reasons if f]


# ── T1 ────────────────────────────────────────────────────────────────────
def drive_tool_loop(sess, first_prompt, files_read, calls_made):
    """Run the tool loop until the model answers or the cap is hit."""
    msg = sess.say(first_prompt, tools=T.T1_TOOLS) if first_prompt else sess.resume(tools=T.T1_TOOLS)
    for _ in range(TOOL_ITER_CAP):
        if msg is None:
            return None, "request failed"
        calls = msg.get("tool_calls") or []
        if not calls:
            return msg.get("content") or "", None
        for call in calls:
            fn = (call.get("function") or {})
            name = fn.get("name") or ""
            raw = fn.get("arguments")
            try:
                args = json.loads(raw) if isinstance(raw, str) and raw.strip() else (raw or {})
                if not isinstance(args, dict):
                    raise ValueError("arguments were not a JSON object")
            except Exception as e:  # noqa: BLE001
                return None, f"unparsable tool arguments for {name!r}: {e}"
            calls_made.append(name)
            if name == "read_file":
                files_read.append(args.get("path") or "")
            result = T.t1_run_tool(name, args)
            if result.startswith("No such tool"):
                return None, f"called a tool that does not exist: {name!r}"
            sess.add_tool_result(call.get("id") or "0", result)
        msg = sess.resume(tools=T.T1_TOOLS)
    return None, f"did not stop calling tools within {TOOL_ITER_CAP} rounds"


def task_t1(base, model, workdir):
    sess = Session(base, model, T.SYSTEM)
    files_read, calls_made = [], []
    text, proto = drive_tool_loop(sess, T.T1_PROMPT, files_read, calls_made)
    attempts = []
    if proto is None and not hit_length_cap(sess):
        ok, why = T.grade_t1(text, calls_made, files_read)
        attempts.append({"ok": ok, "detail": why, "answer": (text or "")[:400]})
        if ok:
            return verdict("pass@1", sess, attempts, files_read=files_read, calls=calls_made)
    else:
        attempts.append({"ok": False, "protocol": proto or "hit max_tokens", "answer": (text or "")[:400]})
        return verdict("protocol_fail", sess, attempts, files_read=files_read, calls=calls_made)

    text2, proto2 = drive_tool_loop(sess, T.T1_REPAIR, files_read, calls_made)
    if proto2 is not None or hit_length_cap(sess):
        attempts.append({"ok": False, "protocol": proto2 or "hit max_tokens"})
        return verdict("protocol_fail", sess, attempts, files_read=files_read, calls=calls_made)
    ok2, why2 = T.grade_t1(text2, calls_made, files_read)
    attempts.append({"ok": ok2, "detail": why2, "answer": (text2 or "")[:400]})
    return verdict("pass@2" if ok2 else "fail", sess, attempts, files_read=files_read, calls=calls_made)


# ── code tasks (T2, T3, T4) ───────────────────────────────────────────────
def attempt_code(sess, prompt, lang, runner, test_body, workdir, resume=False):
    """One generate-and-execute round. Returns (state, detail, output)."""
    msg = sess.resume() if resume else sess.say(prompt)
    if msg is None:
        return "protocol_fail", f"request failed: {sess.error}", ""
    if hit_length_cap(sess):
        return "protocol_fail", "hit max_tokens before finishing", ""
    text = msg.get("content") or ""
    if not text.strip():
        return "protocol_fail", "empty content", ""
    code = T.extract_code(text, lang)
    if not code:
        return "protocol_fail", "no fenced code block in the reply", text[:400]
    bad = T.scan_dangerous(code)
    if bad:
        return "protocol_fail", f"generated code touches {bad!r}; not executed", code[:400]
    ok, out = runner(code, test_body, workdir)
    return ("ok" if ok else "failed"), out, code


def task_code(base, model, workdir, prompt, lang, runner, test_body, repair_lead):
    """Generate, execute, and allow exactly one repair turn carrying the real output."""
    sess = Session(base, model, T.SYSTEM)
    attempts = []
    state, detail, code = attempt_code(sess, prompt, lang, runner, test_body, workdir)
    attempts.append({"state": state, "detail": detail[:1500], "code": (code or "")[:2000]})
    if state == "protocol_fail":
        return verdict("protocol_fail", sess, attempts)
    if state == "ok":
        return verdict("pass@1", sess, attempts)

    repair = f"{repair_lead}\n\n{detail}\n\nFix it. Reply with a single ```{lang[0]} fenced block holding the whole corrected version, and nothing else."
    state2, detail2, code2 = attempt_code(sess, repair, lang, runner, test_body, workdir)
    attempts.append({"state": state2, "detail": detail2[:1500], "code": (code2 or "")[:2000]})
    if state2 == "protocol_fail":
        return verdict("protocol_fail", sess, attempts)
    return verdict("pass@2" if state2 == "ok" else "fail", sess, attempts)


def task_t4(base, model, workdir):
    """Write it, then extend it. Scored on the extension holding both requirement sets."""
    sess = Session(base, model, T.SYSTEM)
    attempts = []
    test_a = T.T4_TEST_JS + T.T4_TEST_TAIL
    test_ab = T.T4_TEST_JS + T.T4_TEST_JS_B + T.T4_TEST_TAIL

    state, detail, code = attempt_code(
        sess, T.T4_PROMPT_A, ["javascript", "js"], T.run_node_module, test_a, workdir
    )
    attempts.append({"phase": "A", "state": state, "detail": detail[:1500], "code": (code or "")[:2000]})
    if state == "protocol_fail":
        return verdict("protocol_fail", sess, attempts)
    # Phase A failing is recorded but does not end the task: the extension is what
    # is scored, and a model may still get the whole thing right on the next turn.

    state_b, detail_b, code_b = attempt_code(
        sess, T.T4_PROMPT_B, ["javascript", "js"], T.run_node_module, test_ab, workdir
    )
    attempts.append({"phase": "B", "state": state_b, "detail": detail_b[:1500], "code": (code_b or "")[:2000]})
    if state_b == "protocol_fail":
        return verdict("protocol_fail", sess, attempts)
    if state_b == "ok":
        return verdict("pass@1", sess, attempts)

    repair = (
        "The module does not satisfy the tests. This is the real output of running them:\n\n"
        f"{detail_b}\n\nFix it, keeping every earlier requirement working. Reply with a "
        "single ```javascript fenced block holding the whole module, and nothing else."
    )
    state_c, detail_c, code_c = attempt_code(
        sess, repair, ["javascript", "js"], T.run_node_module, test_ab, workdir
    )
    attempts.append({"phase": "repair", "state": state_c, "detail": detail_c[:1500], "code": (code_c or "")[:2000]})
    if state_c == "protocol_fail":
        return verdict("protocol_fail", sess, attempts)
    return verdict("pass@2" if state_c == "ok" else "fail", sess, attempts)


def verdict(state, sess, attempts, **extra):
    return {"verdict": state, "attempts": attempts, **sess.stats(), **extra}


# ── determinism probe ─────────────────────────────────────────────────────
PROBE = (
    "In one sentence, say what a paged KV cache does for a coding agent. "
    "Do not add anything else."
)


def probe_determinism(base, model):
    """Same prompt twice, fresh conversation each time, compared byte for byte."""
    outs = []
    for _ in range(2):
        s = Session(base, model, T.SYSTEM)
        m = s.say(PROBE)
        outs.append((m or {}).get("content") or "")
    return {
        "deterministic": outs[0] == outs[1] and bool(outs[0].strip()),
        "sample_a": outs[0][:300],
        "sample_b": outs[1][:300],
    }


# ── main ──────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default="http://127.0.0.1:10082/v1")
    ap.add_argument("--repeats", type=int, default=0, help="0 = decide from the determinism probe")
    ap.add_argument("--scratch", default="/private/tmp/claude-501/-Users-p-Development-ai-cli/36b70a77-d1ee-46fa-b432-d80eab0661ef/scratchpad/w14")
    args = ap.parse_args()

    started = time.time()
    print(f"[{args.model}] determinism probe...", flush=True)
    probe = probe_determinism(args.base, args.model)
    repeats = args.repeats or (1 if probe["deterministic"] else 3)
    print(f"[{args.model}] deterministic={probe['deterministic']} -> {repeats} repeat(s)", flush=True)

    suite = [
        ("T1_tool_chain", lambda wd: task_t1(args.base, args.model, wd)),
        ("T2_merge_module", lambda wd: task_code(
            args.base, args.model, wd, T.T2_PROMPT, ["javascript", "js"],
            T.run_node_module, T.T2_TEST_JS,
            "The module does not satisfy the tests. This is the real output of running them:")),
        ("T3_bash_prune", lambda wd: task_code(
            args.base, args.model, wd, T.T3_PROMPT, ["bash", "sh"],
            T.run_bash_function, T.T3_TEST_SH,
            "The function does not satisfy its contract. This is the real output of testing it:")),
        ("T4_extend_no_regress", lambda wd: task_t4(args.base, args.model, wd)),
    ]

    runs = []
    for name, fn in suite:
        for i in range(repeats):
            wd = os.path.join(args.scratch, args.model.replace("/", "_"), f"{name}-{i}")
            t0 = time.time()
            try:
                rec = fn(wd)
            except Exception as e:  # noqa: BLE001 - never lose the rest of the suite
                rec = {"verdict": "protocol_fail", "attempts": [], "error": f"harness: {type(e).__name__}: {e}"}
            rec.update({"task": name, "repeat": i, "elapsed_s": round(time.time() - t0, 2)})
            runs.append(rec)
            print(f"  {name}[{i}] -> {rec['verdict']} ({rec['elapsed_s']}s)", flush=True)
            with open(args.out, "w") as fh:
                json.dump({"model": args.model, "probe": probe, "repeats": repeats, "runs": runs}, fh, indent=2)

    counts = {}
    for r in runs:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    summary = {
        "model": args.model,
        "probe": probe,
        "repeats": repeats,
        "counts": counts,
        "pass_at_1": sum(1 for r in runs if r["verdict"] == "pass@1"),
        "pass_at_2_or_better": sum(1 for r in runs if r["verdict"] in ("pass@1", "pass@2")),
        "total_runs": len(runs),
        "total_wall_s": round(time.time() - started, 1),
        "runs": runs,
    }
    with open(args.out, "w") as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps({k: v for k, v in summary.items() if k != "runs"}, indent=2), flush=True)


if __name__ == "__main__":
    main()
