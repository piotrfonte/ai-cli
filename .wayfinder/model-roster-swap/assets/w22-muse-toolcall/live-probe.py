#!/usr/bin/env python3
"""Red-capable loop v2 -- adds the variables opencode actually uses.

  --stream       stream the response (opencode always does)
  --many-tools   send the full 16-tool opencode set, not just bash
  --multi        prompt that demands several tool calls in one turn

Asserts a clean tool call: name is a declared tool exactly, arguments parse as
JSON, no <atem:...> or <|...|> leaking into content.
"""
import json
import sys
import urllib.request

URL = "http://127.0.0.1:10081/v1/chat/completions"
args_cli = sys.argv[1:]
MODEL = next((a for a in args_cli if not a.startswith("--")), "Muse-Glimmer-30B-4bit")
STREAM = "--stream" in args_cli
MANY = "--many-tools" in args_cli
MULTI = "--multi" in args_cli
REPEAT = int(args_cli[args_cli.index("--repeat") + 1]) if "--repeat" in args_cli else 1


def tool(name, desc, props, required):
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": desc,
            "parameters": {"type": "object", "properties": props, "required": required},
        },
    }


BASH = tool(
    "bash",
    "Executes a bash command and returns its output.",
    {
        "command": {"type": "string", "description": "The command to execute"},
        "description": {"type": "string", "description": "What the command does"},
    },
    ["command"],
)

# The exact roster opencode advertises, per the error message the user pasted.
OPENCODE_TOOLS = [
    BASH,
    tool("edit", "Edit a file.", {"filePath": {"type": "string"}, "oldString": {"type": "string"}, "newString": {"type": "string"}}, ["filePath", "oldString", "newString"]),
    tool("glob", "Find files by glob pattern.", {"pattern": {"type": "string"}, "path": {"type": "string"}}, ["pattern"]),
    tool("grep", "Search file contents.", {"pattern": {"type": "string"}, "path": {"type": "string"}}, ["pattern"]),
    tool("invalid", "Internal.", {"tool": {"type": "string"}, "error": {"type": "string"}}, []),
    tool("memory", "Persistent memory.", {"action": {"type": "string"}, "content": {"type": "string"}}, ["action"]),
    tool("question", "Ask the user a question.", {"question": {"type": "string"}}, ["question"]),
    tool("read", "Read a file.", {"filePath": {"type": "string"}, "offset": {"type": "number"}, "limit": {"type": "number"}}, ["filePath"]),
    tool("skill", "Invoke a skill.", {"skill": {"type": "string"}, "args": {"type": "string"}}, ["skill"]),
    tool("smart-coding_a_semantic_search", "Semantic code search.", {"query": {"type": "string"}, "limit": {"type": "number"}}, ["query"]),
    tool("smart-coding_b_index_codebase", "Index the codebase.", {"path": {"type": "string"}}, []),
    tool("smart-coding_c_clear_cache", "Clear the RAG cache.", {}, []),
    tool("smart-coding_d_check_last_version", "Check version.", {}, []),
    tool("smart-coding_e_set_workspace", "Set workspace.", {"path": {"type": "string"}}, ["path"]),
    tool("smart-coding_f_get_status", "Get status.", {}, []),
    tool("task", "Launch a subagent.", {"description": {"type": "string"}, "prompt": {"type": "string"}}, ["description", "prompt"]),
    tool("todowrite", "Write todos.", {"todos": {"type": "array", "items": {"type": "object"}}}, ["todos"]),
    tool("webfetch", "Fetch a URL.", {"url": {"type": "string"}}, ["url"]),
    tool("write", "Write a file.", {"filePath": {"type": "string"}, "content": {"type": "string"}}, ["filePath", "content"]),
]

TOOLS = OPENCODE_TOOLS if MANY else [BASH]
NAMES = {t["function"]["name"] for t in TOOLS}

PROMPT_ONE = "Show me the git status of this repository. Call the tool."
# Wording taken from the session that failed: the git-review-commit skill's
# "Gather state" step, which tells the model to run the four commands in parallel.
PROMPT_MULTI = (
    "Step 1: Gather state. Run these commands in parallel, in one response, "
    "as four separate tool calls: `git status`, `git diff`, `git diff --cached`, "
    "`git log --oneline -5`."
)

BODY = {
    "model": MODEL,
    "messages": [
        {"role": "system", "content": "You are a coding agent. Use the tools you are given."},
        {"role": "user", "content": PROMPT_MULTI if MULTI else PROMPT_ONE},
    ],
    "tools": TOOLS,
    "tool_choice": "auto",
    "max_tokens": 4096,
    "stream": STREAM,
}


def probe_batch():
    req = urllib.request.Request(
        URL, data=json.dumps(BODY).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"})
    with urllib.request.urlopen(req, timeout=900) as r:
        resp = json.load(r)
    m = resp["choices"][0]["message"]
    return (resp["choices"][0].get("finish_reason"), m.get("content") or "",
            m.get("reasoning_content") or "", m.get("tool_calls") or [])


def probe_stream():
    """Reassemble a streamed response the way an OpenAI client does."""
    req = urllib.request.Request(
        URL, data=json.dumps(BODY).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"})
    content, reasoning, finish = "", "", None
    calls = {}
    with urllib.request.urlopen(req, timeout=900) as r:
        for raw in r:
            line = raw.decode("utf-8").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            chunk = json.loads(payload)
            ch = chunk["choices"][0]
            if ch.get("finish_reason"):
                finish = ch["finish_reason"]
            d = ch.get("delta") or {}
            content += d.get("content") or ""
            reasoning += d.get("reasoning_content") or ""
            for tc in d.get("tool_calls") or []:
                i = tc.get("index", 0)
                slot = calls.setdefault(i, {"name": "", "arguments": ""})
                fn = tc.get("function") or {}
                if fn.get("name"):
                    slot["name"] += fn["name"]
                if fn.get("arguments"):
                    slot["arguments"] += fn["arguments"]
    ordered = [{"function": calls[i]} for i in sorted(calls)]
    return finish, content, reasoning, ordered


def check(finish, content, reasoning, calls):
    problems = []
    if not calls:
        problems.append(f"no tool_calls (finish_reason={finish})")
    for c in calls:
        name = c.get("function", {}).get("name", "")
        if name not in NAMES:
            problems.append(f"tool name {name!r} is not a declared tool")
        raw = c.get("function", {}).get("arguments", "")
        try:
            parsed = json.loads(raw) if isinstance(raw, str) else raw
            if not isinstance(parsed, dict):
                problems.append(f"arguments are not an object: {parsed!r}")
        except Exception as e:
            problems.append(f"arguments are not JSON ({e}): {raw[:200]!r}")
    if "atem:" in content:
        problems.append("raw <atem:...> XML leaked into content")
    if "<|" in content:
        problems.append("special token leaked into content")
    detail = {
        "finish_reason": finish,
        "n_tool_calls": len(calls),
        "names": [c.get("function", {}).get("name") for c in calls],
        "args_head": [str(c.get("function", {}).get("arguments"))[:120] for c in calls],
        "content_head": content[:600],
        "reasoning_chars": len(reasoning),
    }
    return problems, detail


flags = f"stream={STREAM} many_tools={MANY} multi={MULTI}"
print(f"=== {MODEL} :: {flags} ===")
fails = 0
for i in range(REPEAT):
    try:
        result = probe_stream() if STREAM else probe_batch()
    except Exception as e:
        print(f"run {i+1}: ERROR {e}")
        fails += 1
        continue
    problems, detail = check(*result)
    if problems:
        fails += 1
    print(f"run {i+1}: {'FAIL' if problems else 'PASS'}")
    for p in problems:
        print(f"   - {p}")
    print("   " + json.dumps(detail, indent=2)[:1500].replace("\n", "\n   "))

print(f"\n=== {REPEAT - fails}/{REPEAT} PASS, {fails}/{REPEAT} FAIL :: {flags} ===")
sys.exit(1 if fails else 0)
