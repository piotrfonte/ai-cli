#!/usr/bin/env python3
"""Prove the request's tool list reaches oMLX's output parser on the VLM lane.

oMLX builds its parser session from `request.tools`, but VLMBatchedEngine never
set it: `chat`/`stream_chat` take `tools` as an explicit parameter and call
`generate`/`stream_generate` without it. The parser was therefore blind to the
tool list, which silently disabled the dotted-invoke-name repair — a lost turn
per occurrence, seen live as `tool=webfetch.webfetch`.

The blindness is invisible from outside EXCEPT through parameter coercion, and
that is what this probe reads. `_coerce_param_value` keeps a value as a string
when the schema says `"type": "string"`, and otherwise JSON-decodes it. So a
string-typed parameter holding `5` comes back as:

    "5"   schemas present  -> the tool list reached the parser   PASS
    5     no schemas       -> it did not                         FAIL

Needs the server up with a VLM-lane model (Muse Glimmer or Ternary Bonsai).

    ~/.omlx/venv/bin/python tools-reach-parser.py [model] [--stream]
"""
import json
import os
import sys
import urllib.request

argv = sys.argv[1:]
MODEL = next((a for a in argv if not a.startswith("--")), "Muse-Glimmer-30B-4bit")
STREAM = "--stream" in argv
URL = f"http://127.0.0.1:{os.environ.get('AI_PORT', '10081')}/v1/chat/completions"

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "set_retries",
            "description": "Set the retry count for a job.",
            "parameters": {
                "type": "object",
                # Deliberately a STRING that will hold digits. This is the whole
                # experiment: only a schema can keep it one.
                "properties": {"count": {"type": "string"}},
                "required": ["count"],
            },
        },
    }
]

body = json.dumps(
    {
        "model": MODEL,
        "messages": [
            {
                "role": "user",
                "content": "Call set_retries with count 5. Call the tool, do not explain.",
            }
        ],
        "tools": TOOLS,
        "max_tokens": 4096,
        "stream": STREAM,
    }
).encode()

request = urllib.request.Request(
    URL, data=body, headers={"Content-Type": "application/json"}
)
with urllib.request.urlopen(request, timeout=900) as response:
    raw = response.read().decode()

if STREAM:
    calls = {}
    for line in raw.splitlines():
        if not line.startswith("data: ") or line == "data: [DONE]":
            continue
        delta = json.loads(line[6:])["choices"][0].get("delta", {})
        for call in delta.get("tool_calls") or []:
            slot = calls.setdefault(call.get("index", 0), {"name": "", "arguments": ""})
            fn = call.get("function") or {}
            slot["name"] += fn.get("name") or ""
            slot["arguments"] += fn.get("arguments") or ""
    tool_calls = list(calls.values())
else:
    message = json.loads(raw)["choices"][0]["message"]
    tool_calls = [
        {"name": c["function"]["name"], "arguments": c["function"]["arguments"]}
        for c in (message.get("tool_calls") or [])
    ]

print(f"model={MODEL} stream={STREAM}")
for call in tool_calls:
    print(f"  {call['name']}({call['arguments']})")

if not tool_calls:
    print("\nINCONCLUSIVE - the model called no tool; re-run")
    sys.exit(2)

argument = json.loads(tool_calls[0]["arguments"]).get("count")
print(f"\ncount = {argument!r}  ({type(argument).__name__})")
if isinstance(argument, str):
    print("PASS - the schema was applied, so request.tools reached the parser")
    sys.exit(0)
print("FAIL - the value was JSON-decoded, so the parser had no tool list")
sys.exit(1)
