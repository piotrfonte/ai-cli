#!/usr/bin/env python3
"""Prove the W14 graders are passable and that they reject wrong answers.

A grader nobody has validated is worse than no grader: if an assertion is
impossible, every model fails and the result reads as "they are all bad". This
runs a reference solution through each grader (must PASS) and a deliberately
wrong one (must FAIL). No model and no server involved.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tasks as T

SCRATCH = "/private/tmp/claude-501/-Users-p-Development-ai-cli/36b70a77-d1ee-46fa-b432-d80eab0661ef/scratchpad/w14-selftest"

T2_GOOD = """
export function mergeModelSettings(existing, desired) {
  const src = existing && typeof existing === 'object' ? existing : {};
  const models = { ...(src.models || {}) };
  let changed = false;
  for (const [id, want] of Object.entries(desired || {})) {
    const keys = [id, id.split('/').pop()];
    for (const key of keys) {
      const prev = models[key] || {};
      const next = { ...prev, ...want };
      if (JSON.stringify(prev) !== JSON.stringify(next)) changed = true;
      models[key] = next;
    }
  }
  const version = Object.prototype.hasOwnProperty.call(src, 'version') ? src.version : 1;
  return { settings: { version, models }, changed };
}
"""

T2_BAD = """
export function mergeModelSettings(existing, desired) {
  const models = { ...(existing.models || {}) };
  for (const [id, want] of Object.entries(desired || {})) models[id] = want;   // leaf missing
  return { settings: { version: 1, models }, changed: true };                  // never idempotent
}
"""

T3_GOOD = r"""_prune_cache() {
  local dir=$1
  local budget_kb=$2
  [[ -d "$dir" ]] || return 0
  local total
  total=$(du -sk "$dir" | cut -f1)
  local f sz
  while IFS= read -r f; do
    (( total <= budget_kb )) && break
    sz=$(du -sk "$f" | cut -f1)
    rm -rf "$f"
    total=$(( total - sz ))
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 \
           | xargs -0 stat -f '%m %N' 2>/dev/null | sort -n | cut -d' ' -f2-)
  return 0
}"""

T3_BAD = T.T3_BUGGY   # the original defect, must fail

T4_GOOD = """
export function blockingErrors(results, editedFiles) {
  const out = [];
  for (const r of results || []) {
    const edited = editedFiles && editedFiles.has(r.filePath);
    for (const m of r.messages || []) {
      if (m.severity !== 2) continue;
      const isParse = m.ruleId === null;
      if (!edited && !isParse) continue;
      out.push({ file: r.filePath, line: m.line, rule: m.ruleId, message: m.message, _p: isParse ? 0 : 1 });
    }
  }
  out.sort((a, b) =>
    a.file < b.file ? -1 : a.file > b.file ? 1 :
    a._p !== b._p ? a._p - b._p : a.line - b.line);
  return out.map(({ _p, ...rest }) => rest);
}
"""

T4_GOOD_A_ONLY = """
export function blockingErrors(results, editedFiles) {
  const out = [];
  for (const r of results || []) {
    if (!(editedFiles && editedFiles.has(r.filePath))) continue;
    for (const m of r.messages || []) {
      if (m.severity !== 2) continue;
      out.push({ file: r.filePath, line: m.line, rule: m.ruleId, message: m.message });
    }
  }
  out.sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line));
  return out;
}
"""

results = []


def expect(label, got, want):
    ok = got == want
    results.append(ok)
    print(f"{'ok  ' if ok else 'FAIL'}  {label}: got {got}, want {want}")


# ── T1 ────────────────────────────────────────────────────────────────────
ok, why = T.grade_t1("applyDesired in scripts/patch-omlx-mtp.mjs", ["read_file"], ["scripts/patch-omlx-mtp.mjs"])
expect("T1 correct answer accepted", ok, True)

ok, _ = T.grade_t1("mergeSettings in scripts/patch-opencode-mem-cap.mjs", ["read_file"], ["scripts/patch-opencode-mem-cap.mjs"])
expect("T1 decoy rejected", ok, False)

ok, _ = T.grade_t1("applyDesired in scripts/patch-omlx-mtp.mjs", [], [])
expect("T1 guess without tools rejected", ok, False)

expect("T1 grep tool finds the decoy", "patch-opencode-mem-cap.mjs" in T.t1_run_tool("grep", {"pattern": "mergeSettings"}), True)
expect("T1 read_file returns the deciding file", "applyDesired" in T.t1_run_tool("read_file", {"path": "scripts/patch-omlx-mtp.mjs"}), True)
expect("T1 list_dir lists three scripts", len(T.t1_run_tool("list_dir", {"path": "scripts"}).splitlines()), 3)

# ── T2 ────────────────────────────────────────────────────────────────────
ok, out = T.run_node_module(T2_GOOD, T.T2_TEST_JS, os.path.join(SCRATCH, "t2good"))
expect("T2 reference solution passes", ok, True)
if not ok:
    print("  ---\n" + out + "\n  ---")
ok, _ = T.run_node_module(T2_BAD, T.T2_TEST_JS, os.path.join(SCRATCH, "t2bad"))
expect("T2 wrong solution rejected", ok, False)

# ── T3 ────────────────────────────────────────────────────────────────────
ok, out = T.run_bash_function(T3_GOOD, T.T3_TEST_SH, os.path.join(SCRATCH, "t3good"))
expect("T3 reference solution passes", ok, True)
if not ok:
    print("  ---\n" + out + "\n  ---")
ok, out = T.run_bash_function(T3_BAD, T.T3_TEST_SH, os.path.join(SCRATCH, "t3bad"))
expect("T3 original buggy function rejected", ok, False)

# ── T4 ────────────────────────────────────────────────────────────────────
test_a = T.T4_TEST_JS + T.T4_TEST_TAIL
test_ab = T.T4_TEST_JS + T.T4_TEST_JS_B + T.T4_TEST_TAIL
ok, out = T.run_node_module(T4_GOOD_A_ONLY, test_a, os.path.join(SCRATCH, "t4a"))
expect("T4 phase-A reference passes phase-A tests", ok, True)
if not ok:
    print("  ---\n" + out + "\n  ---")
ok, _ = T.run_node_module(T4_GOOD_A_ONLY, test_ab, os.path.join(SCRATCH, "t4a_on_ab"))
expect("T4 un-extended solution fails the extended tests", ok, False)
ok, out = T.run_node_module(T4_GOOD, test_ab, os.path.join(SCRATCH, "t4ab"))
expect("T4 extended reference passes both sets", ok, True)
if not ok:
    print("  ---\n" + out + "\n  ---")

# ── safety scan ───────────────────────────────────────────────────────────
expect("safety scan catches sudo", T.scan_dangerous("sudo rm -rf x") is not None, True)
expect("safety scan catches $HOME", T.scan_dangerous('rm -rf "$HOME/x"') is not None, True)
expect("safety scan passes clean code", T.scan_dangerous(T3_GOOD), None)

# ── extraction ────────────────────────────────────────────────────────────
expect("extract prefers the requested language",
       T.extract_code("blah\n```text\nno\n```\n```javascript\nyes\n```", ["javascript", "js"]), "yes")
expect("extract falls back to the last block",
       T.extract_code("```\nfallback\n```", ["javascript"]), "fallback")

print()
print(f"{sum(results)}/{len(results)} grader checks passed")
sys.exit(0 if all(results) else 1)
