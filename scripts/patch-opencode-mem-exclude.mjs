#!/usr/bin/env node
// patch-opencode-mem-exclude.mjs — never let opencode-mem touch sensitive directories.
//
// opencode-mem gates auto-capture/recall by *directory*, but offers no opt-out for a
// directory you don't want memory to see at all. For a sensitive client repo,
// capture/recall in those trees is unwanted: a session on a client's code would
// otherwise summarize that work into the local memory store, and recall would surface
// other projects' memories into it.
//
// This patches the compiled plugin entry (dist/index.js) to short-circuit all three
// memory touch-points — auto-capture (session.idle), recall injection (chat.message),
// and post-compaction restore (session.compacted) — when the session `directory` is
// under any prefix in OPENCODE_MEM_EXCLUDE_DIRS (colon-separated, like PATH). Empty/
// unset list = no change in behavior.
//
// Idempotent via a sentinel; re-applied by ai.sh on every launch so an `npm update` /
// plugin re-download that reverts the package is auto-re-patched. Mirrors
// patch-opencode-mem-cap.mjs.
//
// Usage: node patch-opencode-mem-exclude.mjs <opencode-mem-package-dir>

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

const SENTINEL = "__OMLX_MEM_EXCLUDE_PATCHED__";

const pkgDir = process.argv[2];
if (!pkgDir) {
  console.error("usage: patch-opencode-mem-exclude.mjs <opencode-mem-package-dir>");
  process.exit(2);
}

// Helper injected after the import block. `directory` is the plugin's closure-scoped
// session dir (const { directory } = ctx). A path is excluded if it equals, or is
// nested under, any configured prefix.
const INJECT = `
// ${SENTINEL} — skip memory in excluded dirs (injected by ai.sh)
const __OMLX_MEM_EXCLUDE_DIRS = (process.env.OPENCODE_MEM_EXCLUDE_DIRS || "")
  .split(":").map((s) => s.trim()).filter(Boolean);
function __omlxMemExcluded(dir) {
  if (!dir || __OMLX_MEM_EXCLUDE_DIRS.length === 0) return false;
  const d = String(dir).replace(/\\/+$/, "");
  return __OMLX_MEM_EXCLUDE_DIRS.some((p) => {
    const q = String(p).replace(/\\/+$/, "");
    return d === q || d.startsWith(q + "/");
  });
}
`;

const REPLACEMENTS = [
  // recall injection (chat.message)
  [
    "if (!isConfigured() || !CONFIG.chatMessage.enabled)",
    "if (!isConfigured() || !CONFIG.chatMessage.enabled || __omlxMemExcluded(directory))",
  ],
  // post-compaction restore
  [
    "if (!isConfigured() || !CONFIG.compaction.enabled)",
    "if (!isConfigured() || !CONFIG.compaction.enabled || __omlxMemExcluded(directory))",
  ],
  // auto-capture (session.idle)
  [
    "await performAutoCapture(ctx, sessionID, directory);",
    "if (__omlxMemExcluded(directory)) return;\n                        await performAutoCapture(ctx, sessionID, directory);",
  ],
];

function patchFile(file) {
  const path = join(pkgDir, file);
  if (!existsSync(path)) return false;
  let src = readFileSync(path, "utf8");
  if (src.includes(SENTINEL)) return "already";

  for (const [from] of REPLACEMENTS) {
    if (!src.includes(from)) {
      console.error(`[patch] skip (anchor not found): ${from.slice(0, 48)}…`);
      return false;
    }
  }
  for (const [from, to] of REPLACEMENTS) src = src.replace(from, to);

  const lastImport = src.lastIndexOf("\nimport ");
  const insertAt = src.indexOf("\n", lastImport) + 1;
  src = src.slice(0, insertAt) + INJECT + src.slice(insertAt);

  writeFileSync(path, src);
  return true;
}

const r = patchFile("dist/index.js");
if (r === true) console.error("[patch] opencode-mem directory-exclude applied");
process.exit(0);
