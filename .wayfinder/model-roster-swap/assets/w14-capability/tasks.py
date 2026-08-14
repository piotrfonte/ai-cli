"""W14 capability task set — the verbatim record.

Constraint 3 of the ticket: fixed prompts, recorded verbatim, so a re-run after a
quant or drafter change is comparable. This file IS that record. Do not reword a
prompt here without noting it on the ticket; a reworded prompt is a new task.

Every grader executes the model's own output. Nothing is graded by reading it.
"""

import json
import os
import re
import shutil
import subprocess

# ── Shared system prompt ──────────────────────────────────────────────────
# Deliberately close to what an agentic coder sees, and identical for every model
# and every task, so the cached prefix is shared and the comparison is fair.
SYSTEM = (
    "You are a coding agent working in a Bash and Node.js repository on macOS. "
    "You write correct, minimal code and you follow a specification exactly. "
    "When asked for code, reply with one fenced code block and no prose around it. "
    "When asked a question about the repository, use the tools provided rather than "
    "guessing, then answer in the exact format requested."
)

# ══════════════════════════════════════════════════════════════════════════
# T1 — tool chain over a simulated scripts/ tree
# ══════════════════════════════════════════════════════════════════════════
# The decoy is the point. `mergeSettings` is the name a model guesses; it lives in
# a different file and discards other models by object spread. The correct answer,
# `applyDesired`, is only visible to a model that opens the file.

T1_FILES = {
    "scripts/patch-omlx-mtp.mjs": '''#!/usr/bin/env node
// Merge per-model settings into oMLX's model_settings.json.
import { readFileSync, writeFileSync } from 'node:fs';

const DESIRED = {};

// Replace the whole settings file with `settings`. Callers must pass a complete
// object; anything absent from it is gone from disk.
function writeSettings(path, settings) {
  writeFileSync(path, JSON.stringify(settings, null, 2));
}

// Fold `desired` into `existing` one model at a time. Entries for models that do
// not appear in `desired` are copied through untouched, so a setting written by
// the oMLX admin panel survives a run of this script. Returns { settings, changed }.
function applyDesired(existing, desired) {
  const models = { ...(existing.models ?? {}) };
  let changed = false;
  for (const [id, want] of Object.entries(desired)) {
    for (const key of [id, id.split('/').pop()]) {
      const prev = models[key] ?? {};
      const next = { ...prev, ...want };
      if (JSON.stringify(prev) !== JSON.stringify(next)) changed = true;
      models[key] = next;
    }
  }
  return { settings: { version: existing.version ?? 1, models }, changed };
}

export { writeSettings, applyDesired };
''',
    "scripts/patch-opencode-mem-cap.mjs": '''#!/usr/bin/env node
// Cap the opencode-mem summarizer input so its prefill cannot saturate the guard.
import { readFileSync, writeFileSync } from 'node:fs';

// Combine two settings objects. The right-hand side wins outright: keys present
// only on the left are dropped. Never use this on a file that holds several
// models — it keeps only what `b` carries.
function mergeSettings(a, b) {
  return { ...b };
}

function capContext(text, maxChars) {
  if (text.length <= maxChars) return text;
  const head = text.slice(0, Math.floor(maxChars * 0.6));
  const tail = text.slice(-Math.floor(maxChars * 0.4));
  return head + '\\n...elided...\\n' + tail;
}

export { mergeSettings, capContext };
''',
    "scripts/patch-smart-coding-excludes.mjs": '''#!/usr/bin/env node
// Add virtualenv and tool-cache excludes the upstream RAG indexer lacks.
import { readFileSync, writeFileSync } from 'node:fs';

const BUILTIN = ['**/.venv/**', '**/site-packages/**', '**/__pycache__/**'];

function extraPatterns(env) {
  const raw = env.SMART_CODING_EXCLUDE_PATTERNS ?? '';
  return raw.split(':').filter(Boolean);
}

function finalPatterns(detected, env) {
  return [...detected, ...BUILTIN, ...extraPatterns(env)];
}

export { finalPatterns, extraPatterns };
''',
}

T1_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_dir",
            "description": "List the files in a directory of the repository.",
            "parameters": {
                "type": "object",
                "properties": {"path": {"type": "string", "description": "Directory path, e.g. 'scripts'"}},
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the full text of one file in the repository.",
            "parameters": {
                "type": "object",
                "properties": {"path": {"type": "string", "description": "File path, e.g. 'scripts/foo.mjs'"}},
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "grep",
            "description": "Search every file in the repository for a substring. Returns matching lines with their file and line number.",
            "parameters": {
                "type": "object",
                "properties": {"pattern": {"type": "string", "description": "Substring to search for"}},
                "required": ["pattern"],
            },
        },
    },
]

T1_PROMPT = (
    "The repository has a scripts/ directory. Exactly one function in it merges "
    "per-model settings into oMLX's model_settings.json **without discarding the "
    "entries of models it was not asked to change**.\n\n"
    "Find it. Then reply with exactly one line in this format, and nothing else:\n\n"
    "<functionName> in <path>"
)

T1_REPAIR = (
    "That is not the answer. Note that `mergeSettings` in "
    "scripts/patch-opencode-mem-cap.mjs returns `{ ...b }`, which drops every model "
    "that is not in `b` — so it is not the function being asked for. Read the files "
    "again and give the one line in the requested format."
)


def t1_run_tool(name, args):
    """Deterministic tool backend for T1."""
    if name == "list_dir":
        p = (args.get("path") or "").strip().strip("/")
        hits = sorted({f for f in T1_FILES if f.startswith(p)})
        if not hits:
            return f"No such directory: {args.get('path')!r}"
        return "\n".join(hits)
    if name == "read_file":
        p = (args.get("path") or "").strip().lstrip("./")
        if p in T1_FILES:
            return T1_FILES[p]
        for k in T1_FILES:
            if k.endswith(p) or os.path.basename(k) == os.path.basename(p):
                return T1_FILES[k]
        return f"No such file: {args.get('path')!r}"
    if name == "grep":
        pat = args.get("pattern") or ""
        out = []
        for path, body in sorted(T1_FILES.items()):
            for i, line in enumerate(body.splitlines(), 1):
                if pat in line:
                    out.append(f"{path}:{i}: {line.strip()}")
        return "\n".join(out) if out else f"No matches for {pat!r}"
    return f"No such tool: {name}"


def grade_t1(final_text, tool_calls_made, files_read):
    """Correct iff it used tools, opened the deciding file, and named applyDesired."""
    text = (final_text or "").strip()
    reasons = []
    if not tool_calls_made:
        reasons.append("answered without calling any tool")
    if not any("patch-omlx-mtp" in f for f in files_read):
        reasons.append("never read scripts/patch-omlx-mtp.mjs")
    if "applyDesired" not in text:
        reasons.append("final answer does not name applyDesired")
    if "mergeSettings" in text:
        reasons.append("final answer still names the decoy mergeSettings")
    if "patch-omlx-mtp.mjs" not in text:
        reasons.append("final answer does not name the file")
    return (not reasons), "; ".join(reasons)


# ══════════════════════════════════════════════════════════════════════════
# T2 — write the both-key-spellings idempotent merge, then run it
# ══════════════════════════════════════════════════════════════════════════

T2_PROMPT = """Write an ES module that exports one function:

  mergeModelSettings(existing, desired)

`existing` is the parsed contents of oMLX's model_settings.json, shaped:

  { version: 1, models: { "<id>": { ...settings } } }

`desired` maps a two-level model id ("org/repo") to the settings to apply to it.

Rules:
1. For every id in `desired`, write its settings under BOTH the two-level id
   ("org/repo") AND that id's directory leaf ("repo"). oMLX resolves a request to
   the leaf, so a two-level-only entry is silently never read.
2. Merge into whatever entry already exists for that key. Never drop a key that is
   already there.
3. Never remove or alter an entry for a model that does not appear in `desired`.
4. If `existing` has no `models` object, create one. Keep `existing.version` if it
   is present; otherwise use 1.
5. Return `{ settings, changed }`. `changed` is true only if some stored value
   actually differs from what was there before. Calling the function again with its
   own output must give `changed === false`.
6. Pure. No file, network or process access, and do not mutate `existing`.

Reply with a single ```javascript fenced block holding the whole module, and nothing else."""

T2_TEST_JS = r"""
import { mergeModelSettings } from './mod.mjs';
const fails = [];
const check = (name, cond, detail) => { if (!cond) fails.push(name + (detail ? ' -> ' + detail : '')); };

{ // fresh create, both spellings, version default
  const r = mergeModelSettings({}, { 'lmstudio-community/GLM-4.7-Flash-MLX-6bit': { enable_thinking: false } });
  check('A1 returns {settings,changed}', r && r.settings && typeof r.changed === 'boolean', JSON.stringify(r));
  const m = (r && r.settings && r.settings.models) || {};
  check('A2 two-level key written', m['lmstudio-community/GLM-4.7-Flash-MLX-6bit'] && m['lmstudio-community/GLM-4.7-Flash-MLX-6bit'].enable_thinking === false, JSON.stringify(m));
  check('A3 leaf key written', m['GLM-4.7-Flash-MLX-6bit'] && m['GLM-4.7-Flash-MLX-6bit'].enable_thinking === false, JSON.stringify(m));
  check('A4 changed is true on create', r && r.changed === true, JSON.stringify(r && r.changed));
  check('A5 version defaults to 1', r && r.settings && r.settings.version === 1, JSON.stringify(r && r.settings && r.settings.version));
}
{ // idempotent
  const d = { 'a/b': { x: 1 } };
  const r1 = mergeModelSettings({}, d);
  const r2 = mergeModelSettings(r1.settings, d);
  check('B1 re-run reports changed=false', r2.changed === false, JSON.stringify(r2.changed));
}
{ // unrelated models preserved
  const existing = { version: 1, models: { 'other/model': { mtp_enabled: true }, 'model': { mtp_enabled: true } } };
  const r = mergeModelSettings(existing, { 'a/b': { x: 1 } });
  check('C1 unrelated two-level entry preserved', r.settings.models['other/model'] && r.settings.models['other/model'].mtp_enabled === true, JSON.stringify(r.settings.models));
  check('C2 unrelated leaf entry preserved', r.settings.models['model'] && r.settings.models['model'].mtp_enabled === true, JSON.stringify(r.settings.models));
}
{ // merges into an existing entry, keeps siblings, both spellings
  const existing = { version: 1, models: { 'a/b': { keep: 'yes' }, 'b': { keep: 'yes' } } };
  const r = mergeModelSettings(existing, { 'a/b': { x: 1 } });
  check('D1 sibling key kept', r.settings.models['a/b'].keep === 'yes', JSON.stringify(r.settings.models['a/b']));
  check('D2 new key added', r.settings.models['a/b'].x === 1, JSON.stringify(r.settings.models['a/b']));
  check('D3 leaf merged too', r.settings.models['b'].keep === 'yes' && r.settings.models['b'].x === 1, JSON.stringify(r.settings.models['b']));
}
{ // does not mutate input
  const existing = { version: 1, models: { 'a/b': { keep: 'yes' } } };
  const before = JSON.stringify(existing);
  mergeModelSettings(existing, { 'a/b': { x: 1 } });
  check('E1 input not mutated', JSON.stringify(existing) === before, JSON.stringify(existing));
}
{ // changed true when a value differs
  const existing = { version: 1, models: { 'a/b': { x: 1 }, 'b': { x: 1 } } };
  const r = mergeModelSettings(existing, { 'a/b': { x: 2 } });
  check('F1 changed true on differing value', r.changed === true, JSON.stringify(r.changed));
}
{ // version preserved
  const r = mergeModelSettings({ version: 3, models: {} }, { 'a/b': { x: 1 } });
  check('G1 existing version preserved', r.settings.version === 3, JSON.stringify(r.settings.version));
}
{ // leaf derivation on a dashed name
  const r = mergeModelSettings({}, { 'org/name-with-dashes': { y: 2 } });
  check('H1 leaf derived from last path segment', r.settings.models['name-with-dashes'] && r.settings.models['name-with-dashes'].y === 2, JSON.stringify(r.settings.models));
}
if (fails.length) { console.log('FAIL'); for (const f of fails) console.log('  ' + f); process.exit(1); }
console.log('PASS');
"""


# ══════════════════════════════════════════════════════════════════════════
# T3 — repair a cache-pruning Bash function
# ══════════════════════════════════════════════════════════════════════════
# Three real defects: `ls -t` is newest-first when the contract says oldest-first;
# `for f in $(ls ...)` word-splits; and every expansion is unquoted, so a path with
# a space breaks it. All three are live defect classes in ai.sh.

T3_BUGGY = r"""_prune_cache() {
  local dir=$1
  local budget_kb=$2
  [[ -d $dir ]] || return 0
  local total
  total=$(du -sk $dir | cut -f1)
  for f in $(ls -t $dir); do
    (( total <= budget_kb )) && break
    local sz
    sz=$(du -sk $dir/$f | cut -f1)
    rm -rf $dir/$f
    total=$(( total - sz ))
  done
}"""

T3_PROMPT = f"""This Bash function is meant to prune an on-disk cache directory. Its contract:

- Delete cache blocks **oldest first** (oldest modification time goes first), stopping
  as soon as the directory's total size is at or below `budget_kb` kilobytes.
- Never delete more than it has to.
- Work correctly when the directory path contains a space, and when a block's own
  name contains a space.
- Return 0 and print nothing on success.

It is currently wrong. Fix it.

```bash
{T3_BUGGY}
```

Reply with a single ```bash fenced block holding the corrected function, and nothing else."""

# The generated function is executed. Anything reaching outside the throwaway
# directory is a protocol failure and is NOT run. See README, "Safety rule".
DANGEROUS = [
    "sudo", "$HOME", "${HOME}", "~/", "/Users", "/System", "/etc", "/var/",
    "curl", "wget", "nc ", "ssh ", "scp ", "npm ", "pip ", "rm -rf /",
    ":(){", "mkfs", "dd if=", "shutdown", "killall",
]


def scan_dangerous(code):
    """Return the first denylisted token found, else None."""
    for token in DANGEROUS:
        if token in code:
            return token
    return None


T3_TEST_SH = r"""#!/bin/bash
# Behaviour test for the model's _prune_cache. Runs only inside the throwaway dir.
set -u
source ./fn.sh

work="$PWD/cache dir"
mkdir -p "$work"
# Four 100 KB blocks, names carrying spaces, mtimes oldest -> newest.
i=1
for name in "block one" "block two" "block three" "block four"; do
  head -c 102400 /dev/zero > "$work/$name"
  touch -t "2026010${i}0000" "$work/$name"
  i=$((i+1))
done

before=$(du -sk "$work" | cut -f1)
_prune_cache "$work" 250
rc=$?

fails=()
[ "$rc" -eq 0 ] || fails+=("exit status was $rc, expected 0")
[ -e "$work/block one" ]   && fails+=("oldest block 'block one' survived")
[ -e "$work/block two" ]   && fails+=("second-oldest 'block two' survived")
[ -e "$work/block three" ] || fails+=("over-deleted: 'block three' is gone")
[ -e "$work/block four" ]  || fails+=("over-deleted: newest 'block four' is gone")
after=$(du -sk "$work" 2>/dev/null | cut -f1)
[ -n "$after" ] || fails+=("the cache directory itself was destroyed")
if [ -n "$after" ] && [ "$after" -gt 250 ]; then
  fails+=("directory is still ${after} KB, over the 250 KB budget")
fi

# A missing directory must be a silent no-op.
_prune_cache "$PWD/no such dir" 100
[ $? -eq 0 ] || fails+=("missing directory did not return 0")

if [ ${#fails[@]} -gt 0 ]; then
  echo "FAIL"
  for f in "${fails[@]}"; do echo "  $f"; done
  echo "  (started at ${before} KB with four 100 KB blocks; budget 250 KB)"
  exit 1
fi
echo "PASS"
"""


# ══════════════════════════════════════════════════════════════════════════
# T4 — write, then extend without regressing
# ══════════════════════════════════════════════════════════════════════════

T4_PROMPT_A = """Write an ES module that exports one function:

  blockingErrors(results, editedFiles)

`results` is ESLint output, shaped:

  [{ filePath: string, messages: [{ severity: number, ruleId: string|null, line: number, message: string }] }]

`editedFiles` is a Set of file paths edited during this session.

Return a flat array of `{ file, line, rule, message }` objects, one per message that
has `severity === 2`, but only for files present in `editedFiles`. `rule` is the
message's `ruleId`.

Sort the result by `file` ascending, then by `line` ascending.

Do not mutate the inputs. Pure — no file, network or process access.

Reply with a single ```javascript fenced block holding the whole module, and nothing else."""

T4_PROMPT_B = """New requirement. Everything specified before must keep working exactly as it does now.

A message whose `ruleId` is `null` is a parse error. Parse errors must be reported
even when their file is **not** in `editedFiles`, and within any one file every parse
error must sort **before** all of that file's other messages, whatever its line number.
Ordering between files is unchanged, and ordering among non-parse-error messages of the
same file is unchanged.

Reply with a single ```javascript fenced block holding the whole updated module, and nothing else."""

T4_TEST_JS = r"""
import { blockingErrors } from './mod.mjs';
const fails = [];
const check = (name, cond, detail) => { if (!cond) fails.push(name + (detail ? ' -> ' + detail : '')); };

const base = () => ([
  { filePath: 'b.js', messages: [
      { severity: 2, ruleId: 'no-undef', line: 9, message: 'undef b9' },
      { severity: 1, ruleId: 'quotes',   line: 2, message: 'warn only' },
      { severity: 2, ruleId: 'eqeqeq',   line: 3, message: 'eq b3' } ] },
  { filePath: 'a.js', messages: [
      { severity: 2, ruleId: 'no-undef', line: 5, message: 'undef a5' } ] },
  { filePath: 'skipped.js', messages: [
      { severity: 2, ruleId: 'no-undef', line: 1, message: 'not edited' } ] },
]);

{ // A: severity filter, editedFiles filter, ordering, shape
  const input = base();
  const snapshot = JSON.stringify(input);
  const out = blockingErrors(input, new Set(['a.js', 'b.js']));
  check('A1 returns an array', Array.isArray(out), typeof out);
  const got = (out || []).map(e => `${e.file}:${e.line}:${e.rule}`).join(',');
  check('A2 filters severity 1 and unedited files, sorted by file then line',
        got === 'a.js:5:no-undef,b.js:3:eqeqeq,b.js:9:no-undef', got);
  check('A3 message carried through', (out[0] || {}).message === 'undef a5', JSON.stringify(out[0]));
  check('A4 inputs not mutated', JSON.stringify(input) === snapshot);
}
{ // A: empty
  const out = blockingErrors([], new Set());
  check('A5 empty input gives empty array', Array.isArray(out) && out.length === 0, JSON.stringify(out));
}
{ // A: nothing edited
  const out = blockingErrors(base(), new Set());
  check('A6 nothing edited gives empty array', Array.isArray(out) && out.length === 0, JSON.stringify(out));
}
"""

T4_TEST_JS_B = r"""
{ // B: parse errors escape the editedFiles filter and sort first within their file
  const input = [
    { filePath: 'z.js', messages: [
        { severity: 2, ruleId: 'eqeqeq', line: 2, message: 'eq z2' },
        { severity: 2, ruleId: null,     line: 40, message: 'parse z40' } ] },
    { filePath: 'never-edited.js', messages: [
        { severity: 2, ruleId: null,     line: 7, message: 'parse ne7' },
        { severity: 2, ruleId: 'eqeqeq', line: 1, message: 'eq ne1' } ] },
  ];
  const snapshot = JSON.stringify(input);
  const out = blockingErrors(input, new Set(['z.js']));
  const got = (out || []).map(e => `${e.file}:${e.line}:${e.rule}`).join(',');
  check('B1 parse errors first within a file, unedited file contributes only its parse error',
        got === 'never-edited.js:7:null,z.js:40:null,z.js:2:eqeqeq', got);
  check('B2 inputs not mutated', JSON.stringify(input) === snapshot);
}
{ // B: a parse error must not drag in its file's ordinary messages
  const out = blockingErrors([
    { filePath: 'q.js', messages: [
        { severity: 2, ruleId: null,   line: 3, message: 'parse q3' },
        { severity: 2, ruleId: 'x',    line: 1, message: 'should not appear' },
        { severity: 1, ruleId: null,   line: 2, message: 'warning parse, excluded' } ] },
  ], new Set());
  const got = (out || []).map(e => `${e.file}:${e.line}:${e.rule}`).join(',');
  check('B3 only the severity-2 parse error appears for an unedited file', got === 'q.js:3:null', got);
}
"""

T4_TEST_TAIL = r"""
if (fails.length) { console.log('FAIL'); for (const f of fails) console.log('  ' + f); process.exit(1); }
console.log('PASS');
"""


# ══════════════════════════════════════════════════════════════════════════
# Execution helpers
# ══════════════════════════════════════════════════════════════════════════

FENCE = re.compile(r"```[ \t]*([A-Za-z0-9_+-]*)[ \t]*\r?\n(.*?)```", re.S)


def extract_code(text, prefer):
    """Last fenced block whose language matches `prefer`, else last block of any."""
    if not text:
        return None
    blocks = FENCE.findall(text)
    if not blocks:
        return None
    prefer = {p.lower() for p in prefer}
    matched = [body for lang, body in blocks if lang.lower() in prefer]
    return (matched[-1] if matched else blocks[-1][1]).strip()


def run_node_module(code, test_js, workdir):
    """Write the module and its test, run node, return (passed, output)."""
    os.makedirs(workdir, exist_ok=True)
    with open(os.path.join(workdir, "mod.mjs"), "w") as fh:
        fh.write(code)
    with open(os.path.join(workdir, "test.mjs"), "w") as fh:
        fh.write(test_js)
    try:
        proc = subprocess.run(
            ["node", "test.mjs"], cwd=workdir, capture_output=True, text=True, timeout=60
        )
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT: the module did not finish in 60s (infinite loop?)"
    out = (proc.stdout + proc.stderr).strip()
    return proc.returncode == 0 and "PASS" in proc.stdout, out


def run_bash_function(code, test_sh, workdir):
    """Syntax-check then behaviour-test the model's Bash function.

    The directory is wiped first. T3's test builds a directory tree, and a buggy
    attempt leaves junk in it — on the first run of this suite that junk inflated
    the next attempt's `du` baseline and added stray `ls` entries, failing repair
    code that was in fact correct. Every attempt must start from bare ground.
    """
    shutil.rmtree(workdir, ignore_errors=True)
    os.makedirs(workdir, exist_ok=True)
    fn_path = os.path.join(workdir, "fn.sh")
    with open(fn_path, "w") as fh:
        fh.write(code + "\n")
    syn = subprocess.run(["bash", "-n", fn_path], capture_output=True, text=True)
    if syn.returncode != 0:
        return False, "bash -n failed:\n" + (syn.stdout + syn.stderr).strip()
    test_path = os.path.join(workdir, "test.sh")
    with open(test_path, "w") as fh:
        fh.write(test_sh)
    try:
        proc = subprocess.run(
            ["bash", test_path], cwd=workdir, capture_output=True, text=True, timeout=120
        )
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT: the function did not finish in 120s"
    out = (proc.stdout + proc.stderr).strip()
    return proc.returncode == 0 and "PASS" in proc.stdout, out
