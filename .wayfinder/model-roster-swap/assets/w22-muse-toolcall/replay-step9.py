#!/usr/bin/env python3
"""Replay the turn that killed the /init run of 2026-08-13.

Rebuilds the tool history of a real opencode session straight from opencode's
own store, then asks the server for the next turn — the one that returned 56
tokens as nothing at all. Prints what comes back, and counts empty turns.

    ~/.omlx/venv/bin/python replay-step9.py [runs] [--session ID]

Against the unpatched adapter that turn produced no text, no reasoning and no
tool call, and opencode left the agent loop. Against the patched one it produces
`read(src/setupProxy.js)` every time — the call the model meant all along.

The session default below is the recorded failure. Any session id works: the
script takes every tool call and tool result in order and asks for one more
turn, so it replays any conversation opencode has stored.

Needs the server up on $AI_PORT (10081) with Muse Glimmer served.
"""
import json
import os
import sqlite3
import sys
import urllib.request

SESSION = "ses_003a2dc65ffeIEQaOQkHRXKhU1"
DB = os.path.expanduser("~/.local/share/opencode/opencode.db")
URL = f"http://127.0.0.1:{os.environ.get('AI_PORT', '10081')}/v1/chat/completions"
MODEL = "Muse-Glimmer-30B-4bit"

argv = sys.argv[1:]
if "--session" in argv:
    SESSION = argv[argv.index("--session") + 1]
RUNS = int(next((a for a in argv if a.isdigit()), 3))


def tool(name, props, required=()):
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": f"{name} tool.",
            "parameters": {
                "type": "object",
                "properties": {p: {"type": "string"} for p in props},
                "required": list(required),
            },
        },
    }


# The roster opencode advertised in that session.
TOOLS = [
    tool("bash", ["command", "description"], ["command"]),
    tool("edit", ["filePath", "oldString", "newString"], ["filePath"]),
    tool("glob", ["pattern", "path"], ["pattern"]),
    tool("grep", ["pattern", "path"], ["pattern"]),
    tool("invalid", ["tool", "error"]),
    tool("memory", ["action", "content"], ["action"]),
    tool("question", ["question"], ["question"]),
    tool("read", ["filePath", "offset", "limit"], ["filePath"]),
    tool("skill", ["skill", "args"], ["skill"]),
    tool("smart-coding_a_semantic_search", ["query", "limit"], ["query"]),
    tool("smart-coding_b_index_codebase", ["path"]),
    tool("smart-coding_c_clear_cache", []),
    tool("smart-coding_d_check_last_version", []),
    tool("smart-coding_e_set_workspace", ["path"], ["path"]),
    tool("smart-coding_f_get_status", []),
    tool("task", ["description", "prompt"], ["prompt"]),
    tool("todowrite", ["todos"], ["todos"]),
    tool("webfetch", ["url", "format"], ["url"]),
    tool("write", ["filePath", "content"], ["filePath", "content"]),
]

db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
rows = db.execute(
    """
    select json_extract(m.data,'$.role'), p.data
    from message m join part p on p.message_id = m.id
    where m.session_id = ?
    order by m.time_created, p.id
    """,
    (SESSION,),
).fetchall()
if not rows:
    sys.exit(f"no parts found for session {SESSION} in {DB}")

messages = []
for role, pdata in rows:
    part = json.loads(pdata)
    if part.get("type") == "text" and role == "user":
        messages.append({"role": "user", "content": part["text"]})
    elif part.get("type") == "tool":
        state = part.get("state", {})
        call_id = part.get("callID")
        messages.append(
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    {
                        "id": call_id,
                        "type": "function",
                        "function": {
                            "name": part.get("tool"),
                            "arguments": json.dumps(
                                state.get("input", {}), ensure_ascii=False
                            ),
                        },
                    }
                ],
            }
        )
        messages.append(
            {
                "role": "tool",
                "tool_call_id": call_id,
                "content": str(state.get("output", ""))[:20000],
            }
        )

print(f"session {SESSION}")
print(f"replaying {len(messages)} messages, {len(TOOLS)} tools, {RUNS} run(s)\n")

empty = 0
for run in range(1, RUNS + 1):
    body = json.dumps(
        {
            "model": MODEL,
            "messages": messages,
            "tools": TOOLS,
            "max_tokens": 8192,
            "stream": False,
        }
    ).encode()
    request = urllib.request.Request(
        URL, data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=900) as response:
        data = json.loads(response.read())
    choice = data["choices"][0]
    message = choice["message"]
    content = message.get("content") or ""
    reasoning = message.get("reasoning_content") or ""
    calls = message.get("tool_calls") or []
    usage = data.get("usage", {})
    dead = not content and not reasoning and not calls
    empty += dead
    print(
        f"run {run}: finish={choice['finish_reason']} "
        f"tokens={usage.get('completion_tokens')} calls={len(calls)} "
        f"content={len(content)} reasoning={len(reasoning)}"
        + ("   <-- EMPTY TURN" if dead else "")
    )
    for call in calls:
        print(f"    -> {call['function']['name']}({call['function']['arguments'][:120]})")
    if content:
        print(f"    content: {content[:400]!r}")

print(f"\n{empty}/{RUNS} empty turns")
sys.exit(1 if empty else 0)
