#!/usr/bin/env python3
"""Tight, deterministic repro of the Muse Glimmer tool-call defect.

Feeds oMLX's own adapter the raw output the model produced (reconstructed from
the opencode session record) and asserts the two halves of the user's symptom:

  1. the extracted tool name is 'bash<|message|>', not 'bash'
  2. the tool-call XML leaks into visible text, starting at '">'

Runs in milliseconds, no server, no model.  Red now; green when the adapter is
fixed.
"""
import sys

sys.path.insert(0, "/Users/p/.omlx/src")

from omlx.adapter.muse_glimmer import (  # noqa: E402
    _MuseChannelSplitter,
    _extract_tool_calls,
)

# The model repeats the training pattern `to=<name><|message|>` inside the
# invoke tag, emitting name="bash<|message|>" instead of name="bash".
# Everything else is well-formed.  The first message carries no leading
# <|start|>assistant -- the generation prompt supplied it.
CALLS = ["git status", "git diff", "git diff --cached", "git log --oneline -5"]

RAW = " to=self<|message|>Run the commands in parallel.<|eom|>"
for cmd in CALLS:
    RAW += (
        "<|start|>assistant to=bash<|message|>"
        '<atem:function_calls>\n<atem:invoke name="bash<|message|>">\n'
        f'<atem:parameter name="command">{cmd}</atem:parameter>\n'
        "</atem:invoke>\n</atem:function_calls><|eom|>"
    )

# What opencode actually recorded, from the session DB.
EXPECTED_LEAK = "".join(
    f'">\n<atem:parameter name="command">{cmd}</atem:parameter>\n'
    "</atem:invoke>\n</atem:function_calls>"
    for cmd in CALLS
)

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "bash",
            "description": "Executes a bash command.",
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"],
            },
        },
    }
]


def run(chunk_size=7):
    """Stream RAW through the splitter in small chunks, as decoding does."""
    sp = _MuseChannelSplitter()
    visible = ""
    for i in range(0, len(RAW), chunk_size):
        _, v = sp.feed(RAW[i : i + chunk_size])
        visible += v
    _, v = sp.finish()
    visible += v
    return visible, _extract_tool_calls(RAW, TOOLS)


visible, calls = run()

problems = []
names = [c["name"] for c in calls]
if any(n != "bash" for n in names):
    problems.append(f"tool names are {names!r}, expected all 'bash'")
if len(calls) != 4:
    problems.append(f"got {len(calls)} tool calls, expected 4")
# strip the <think> wrapper the splitter adds around the reasoning channel
body = visible.split("</think>", 1)[-1]
if body:
    problems.append(f"tool XML leaked into visible text ({len(body)} chars)")

print("=== extracted tool calls ===")
for c in calls:
    print(f"   name={c['name']!r}  arguments={c['arguments']}")
print("\n=== visible text after the reasoning channel ===")
print(repr(body[:220]) + (" ..." if len(body) > 220 else ""))
print(f"\nleak matches what opencode recorded: {body == EXPECTED_LEAK}")

print("\n=== verdict ===")
if problems:
    for p in problems:
        print(f"FAIL - {p}")
    sys.exit(1)
print("PASS - names clean, no leak")
