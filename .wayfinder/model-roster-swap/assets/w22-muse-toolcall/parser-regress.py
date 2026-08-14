#!/usr/bin/env python3
"""Regression suite for oMLX's Muse Glimmer output parser.

Covers every defect scripts/patch-omlx-muse-toolcall.mjs repairs, plus the
well-formed cases the repairs must not touch. Runs in milliseconds against the
installed adapter: no server, no model, no weights.

    ~/.omlx/venv/bin/python parser-regress.py

Which cases were red before the patch:

  1  stray <|message|> in the tag   red (W22) — name 'bash<|message|>', XML leak
  2  dotted invoke name             red      — name 'read.filePath', call lost
  3  token before `to=` in header   red      — 0 calls, whole turn silent
  4  tool body with no invoke tag   red      — client receives NOTHING
  5  a real tool name with a dot    green    — must stay green
  6  unknown name, unknown prefix   green    — must stay green (no guessing)
  7  well-formed call, think, text  green    — must stay green

Case 3 is the one that ended the /init run of 2026-08-13 at step 9, and case 4
is the rail that makes such a turn visible if it ever happens again.
"""
import sys

sys.path.insert(0, "/Users/p/.omlx/src")

from omlx.adapter.muse_glimmer import (  # noqa: E402
    _MuseChannelSplitter,
    _extract_tool_calls,
    MuseGlimmerOutputParserSession,
)


def tool(name, params=("command",)):
    return {
        "type": "function",
        "function": {
            "name": name,
            "parameters": {
                "type": "object",
                "properties": {p: {"type": "string"} for p in params},
            },
        },
    }


TOOLS = [
    tool("bash"),
    tool("read", ("filePath",)),
    tool("webfetch", ("url", "format")),
    tool("a.b", ("x",)),  # a tool genuinely named with a dot
]


def stream(raw, chunk_size=7):
    """Feed raw text through the splitter in small chunks, as decoding does."""
    splitter = _MuseChannelSplitter()
    visible = ""
    for i in range(0, len(raw), chunk_size):
        _, v = splitter.feed(raw[i : i + chunk_size])
        visible += v
    _, v = splitter.finish()
    return visible + v, splitter


def finalize(raw, tools=TOOLS):
    """Run raw text through a parser session, exactly as the scheduler does."""
    session = MuseGlimmerOutputParserSession.__new__(MuseGlimmerOutputParserSession)
    session._tokenizer = None
    session._tools = tools
    session._raw_text = raw
    session._detokenizer = None
    _, session._splitter = stream(raw)
    return session.finalize()


failures = []


def check(case, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {case}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(case)


# ── 1. W22: the header pattern repeated inside the invoke tag ────────────────
# The model emits name="bash<|message|>". Unpatched: the tool name carries the
# special token AND the stray <|message|> re-classifies the open tool body, so
# the rest of the XML streams to the user as visible text.
CALLS = ["git status", "git diff", "git diff --cached", "git log --oneline -5"]
raw = " to=self<|message|>Run them in parallel.<|eom|>"
for cmd in CALLS:
    raw += (
        "<|start|>assistant to=bash<|message|>"
        '<atem:function_calls>\n<atem:invoke name="bash<|message|>">\n'
        f'<atem:parameter name="command">{cmd}</atem:parameter>\n'
        "</atem:invoke>\n</atem:function_calls><|eom|>"
    )
visible, _ = stream(raw)
calls = _extract_tool_calls(raw, TOOLS)
leak = visible.split("</think>", 1)[-1]
check("1 stray <|message|> — names clean", [c["name"] for c in calls] == ["bash"] * 4,
      f"got {[c['name'] for c in calls]}")
check("1 stray <|message|> — no XML leak", leak == "", f"{len(leak)} chars leaked")

# ── 2. The dotted invoke name ────────────────────────────────────────────────
# The model's own template teaches to=tool_name.function_name, so it pairs the
# tool with one of its parameters: name="read.filePath".
raw = (
    " to=read<|message|><atem:function_calls>\n"
    '<atem:invoke name="read.filePath">\n'
    '<atem:parameter name="filePath">/tmp/x.md</atem:parameter>\n'
    "</atem:invoke>\n</atem:function_calls><|eom|>"
)
calls = _extract_tool_calls(raw, TOOLS)
check("2 dotted name repaired to the real tool",
      len(calls) == 1 and calls[0]["name"] == "read", f"got {calls}")
check("2 dotted name — arguments survive",
      calls and calls[0]["arguments"] == '{"filePath":"/tmp/x.md"}', f"got {calls}")

# ── 3. A token before `to=` in the header ────────────────────────────────────
# The splitter searches for `to=` anywhere; the extractor used to demand it
# first. Every such turn was suppressed as a tool channel and then matched
# nothing — no text, no tool call, no error.
raw = (
    " json to=bash<|message|><atem:function_calls>\n"
    '<atem:invoke name="bash">\n'
    '<atem:parameter name="command">ls</atem:parameter>\n'
    "</atem:invoke>\n</atem:function_calls><|eom|>"
)
visible, splitter = stream(raw)
calls = _extract_tool_calls(raw, TOOLS)
check("3 offset `to=` — splitter still suppresses the body", visible == "",
      f"leaked {visible!r}")
check("3 offset `to=` — extractor agrees with the splitter",
      len(calls) == 1 and calls[0]["name"] == "bash", f"got {calls}")

# The shape that actually killed the /init run: the model opened its FIRST
# message with no space after the generation prompt's `<|start|>assistant`, so
# the old `assistant\s+to=` needed a whitespace character that was never there.
# Replayed against the live server, the same 56 tokens now yield this call three
# times out of three.
raw = (
    'to=read<|message|><atem:function_calls>\n<atem:invoke name="read">\n'
    "<atem:parameter name=\"filePath\">/x/setupProxy.js</atem:parameter>\n"
    "</atem:invoke>\n</atem:function_calls><|eom|>"
)
visible, _ = stream(raw)
calls = _extract_tool_calls(raw, TOOLS)
check("3b no space after `assistant` — call recovered",
      len(calls) == 1 and calls[0]["name"] == "read", f"got {calls}")
check("3b no space after `assistant` — nothing leaked", visible == "",
      f"leaked {visible!r}")

# ── 4. A tool body carrying no invoke tag at all ─────────────────────────────
# The turn is lost either way — no call can be built from this — but it must
# not reach the client as an empty answer, which kills the agent loop silently.
raw = ' to=read<|message|>{"filePath": "/tmp/x.md"}<|eot|>'
visible, splitter = stream(raw)
result = finalize(raw)
check("4 unparsable tool body — nothing streamed",
      visible == "" and not splitter.answered)
check("4 unparsable tool body — no invented call", result.tool_calls == [],
      f"got {result.tool_calls}")
check("4 unparsable tool body — suppressed text surfaced, not dropped",
      '{"filePath": "/tmp/x.md"}' in result.visible_text,
      f"visible_text={result.visible_text!r}")

# ── 4b. Reasoning, then a tool message that does not parse ───────────────────
# The shape of the second failure: opencode shows "Thought: 6.0s" and nothing
# else. Reasoning DOES reach the client, so it must not count as an answer —
# counting it would call this turn healthy and leave the user with silence.
REASONED = " to=self<|message|>Let's webfetch.<|eom|>"

# A body with no invoke tag in any spelling: nothing can be built from it.
raw = (
    REASONED + "<|start|>assistant to=webfetch<|message|>"
    '{"url": "https://opencode.ai"}<|eot|>'
)
visible, splitter = stream(raw)
result = finalize(raw)
check("4b reasoning is not an answer", splitter.answered is False)
check("4b reasoning still streams", visible == "<think>Let's webfetch.</think>",
      f"got {visible!r}")
check("4b lost tool message surfaced", "https://opencode.ai" in result.visible_text,
      f"visible_text={result.visible_text!r}")
check("4b the recipient is recorded with it", "to=webfetch" in splitter.suppressed,
      f"suppressed={splitter.suppressed!r}")

# The same shape with a loosely written tag is no longer lost at all — it
# becomes the call the model meant, and the rail stays quiet.
raw = (
    REASONED + "<|start|>assistant to=webfetch<|message|>"
    '<invoke name="webfetch"><parameter name="url">https://opencode.ai</parameter></invoke>'
    "<|eot|>"
)
result = finalize(raw)
check("4b loose tag after reasoning — call recovered",
      len(result.tool_calls) == 1 and result.tool_calls[0]["name"] == "webfetch"
      and "opencode.ai" in result.tool_calls[0]["arguments"], f"got {result.tool_calls}")
check("4b loose tag after reasoning — nothing surfaced", result.visible_text == "",
      f"visible_text={result.visible_text!r}")

# ── 4c. A real answer plus a broken tool message ─────────────────────────────
# The tool call is still lost and still logged, but the answer stands on its
# own, so nothing is appended to it.
raw = (
    " to=user<|message|>Here is the answer.<|eom|>"
    '<|start|>assistant to=bash<|message|><invoke name="bash">ls</invoke><|eot|>'
)
visible, splitter = stream(raw)
result = finalize(raw)
check("4c answer recognised", splitter.answered is True)
check("4c answer not polluted by the lost call", result.visible_text == "",
      f"visible_text={result.visible_text!r}")

# ── 4d. Loose tags — no namespace prefix, single quotes, bare name ───────────
# The model is told its payload "is not expected to be valid XML and is parsed
# with regular expressions", so it writes it loosely. Each of these was a lost
# turn before: suppressed as a tool channel, then matching nothing.
for label, invoke, param in [
    ("no prefix", '<invoke name="bash">', '<parameter name="command">'),
    ("single quotes", "<atem:invoke name='bash'>", "<atem:parameter name='command'>"),
    ("unquoted name", "<atem:invoke name=bash>", "<atem:parameter name=command>"),
    ("mixed", "<invoke name='bash'>", '<atem:parameter name="command">'),
]:
    raw = (
        f" to=bash<|message|>{invoke}\n{param}ls</atem:parameter>\n"
        "</atem:invoke><|eom|>"
    )
    calls = _extract_tool_calls(raw, TOOLS)
    check(f"4d loose tags ({label}) — call recovered",
          len(calls) == 1 and calls[0]["name"] == "bash"
          and calls[0]["arguments"] == '{"command":"ls"}', f"got {calls}")

# ── 5. A tool genuinely named with a dot is never rewritten ──────────────────
raw = (
    ' to=a.b<|message|><atem:function_calls>\n<atem:invoke name="a.b">\n'
    '<atem:parameter name="x">1</atem:parameter>\n'
    "</atem:invoke>\n</atem:function_calls><|eom|>"
)
calls = _extract_tool_calls(raw, TOOLS)
check("5 real dotted tool name kept",
      len(calls) == 1 and calls[0]["name"] == "a.b", f"got {calls}")

# ── 6. An unknown name whose prefix is also unknown stays unknown ────────────
# The repair fires only on evidence. Reporting an unknown tool beats calling the
# wrong one.
raw = (
    ' to=nope<|message|><atem:function_calls>\n<atem:invoke name="nope.thing">\n'
    '<atem:parameter name="x">1</atem:parameter>\n'
    "</atem:invoke>\n</atem:function_calls><|eom|>"
)
calls = _extract_tool_calls(raw, TOOLS)
check("6 unknown name with unknown prefix untouched",
      len(calls) == 1 and calls[0]["name"] == "nope.thing", f"got {calls}")

# ── 7. Well-formed output is unchanged ───────────────────────────────────────
raw = (
    " to=self<|message|>Think first.<|eom|>"
    "<|start|>assistant to=bash<|message|><atem:function_calls>\n"
    '<atem:invoke name="bash">\n'
    '<atem:parameter name="command">ls</atem:parameter>\n'
    "</atem:invoke>\n</atem:function_calls><|eom|>"
    "<|start|>assistant to=user<|message|>Done.<|eot|>"
)
visible, splitter = stream(raw)
result = finalize(raw)
calls = _extract_tool_calls(raw, TOOLS)
check("7 well-formed — one clean call",
      len(calls) == 1 and calls[0]["name"] == "bash" and calls[0]["arguments"] == '{"command":"ls"}',
      f"got {calls}")
check("7 well-formed — thinking wrapped, answer visible",
      visible == "<think>Think first.</think>Done.", f"got {visible!r}")
check("7 well-formed — no never-drop flush", result.visible_text == "",
      f"got {result.visible_text!r}")
check("7 well-formed — finish_reason is tool_calls",
      result.finish_reason == "tool_calls", f"got {result.finish_reason}")

print("\n=== verdict ===")
if failures:
    for f in failures:
        print(f"FAIL - {f}")
    sys.exit(1)
print("PASS - all cases green")
